# Architecture

This document explains how the pieces fit together and why. The normative wire format is
[../protocol/PROTOCOL.md](../protocol/PROTOCOL.md); where the two disagree, the protocol
document wins. The original design spec is
[superpowers/specs/2026-09-05-obs-iphone-usb-cam-design.md](superpowers/specs/2026-09-05-obs-iphone-usb-cam-design.md).

![Data path from the iPhone app through usbmuxd to the OBS plugin](images/architecture.svg)

## 1. Components

| Component | Language | License | Role |
|---|---|---|---|
| `ios-app/` TetherCam | Swift 6, SwiftUI | MIT | Capture, hardware HEVC encode, TCP listener on port 7878 |
| `shared/frame_parser.c` | C11 | MIT | Stateful IUCM framer and message codec, no I/O, no Apple frameworks |
| `shared/usbmux.c` | C11 | MIT | usbmuxd client with a hand written plist codec, builds on Linux too |
| `obs-plugin/` | C and Objective-C++ | GPL-2.0-or-later | OBS source, VideoToolbox decode, reconnect logic |
| `tools/usbcam-sim` | Swift | MIT | Sender simulator: moving test pattern, real HEVC, real protocol |
| `tools/usbcam-recv` | Swift | MIT | CLI receiver over TCP or usbmuxd, emits a JSON summary |

The split is deliberate. Everything that can be pure C without Apple frameworks is pure C
in `shared/`, so it compiles and runs under CI on Linux and under sanitizers. Everything
that needs VideoToolbox or libobs stays in the platform layer. `tools/` includes
`shared/usbmux.c` through a one line `#include` shim rather than copying it, so there is
exactly one source of truth for the tunnel client.

The plugin is GPL because it links libobs. Keeping the reusable core in a separate MIT
tree means a future CMIO extension, a Windows receiver or a third party app can use it
without inheriting the plugin's license.

## 2. Threads and ownership

**iPhone side.** AVCaptureSession delivers sample buffers on its own dispatch queue, the
encoder callback fires on a VideoToolbox queue, and NWListener runs its connection
handlers on a Network.framework queue. `ServerStateMachine` is deliberately pure: events
in, actions out, no I/O and no timers. That is what makes the handshake testable without a
device, a camera or a socket.

**Mac side.** One receive thread per OBS source. It connects, reads HELLO, sends START,
then loops: read bytes, feed the framer, decode, hand the frame to OBS. The decode
callback is synchronous enough that no extra queue is needed. OBS calls
`obs_source_output_video2` from that thread. Deleting the source signals the thread and
joins it, so there is no window where a dead source still emits frames.

There is no frame queue anywhere in the path. A queue would add latency to hide jitter
that a 1 ms cable does not produce.

## 3. Protocol summary

A 12 byte header (`IUCM` magic, type, flags, reserved, u32 little endian length) followed
by the payload. Maximum payload 8 MiB. Unknown message types are skipped by length, so
version 1.x stays forward tolerant. If the buffer does not start with `IUCM`, the parser
scans forward for the next `I` and discards what came before, which recovers from a lost
byte without a reconnect.

Message flow: the app sends HELLO on connect (protocol version, device name, camera list).
The Mac answers START (camera id, width, height, fps, bitrate). The app replies CONFIG
with the format it actually selected plus the `hvcC` record, then VIDEO frames. PING goes
out from the Mac every 2 s and comes back as PONG with the same u64 timestamp, which gives
both the round trip time and a dead link signal.

Two byte order traps are worth repeating here because both cost real debugging time:

- Inside a VIDEO payload the NAL length prefixes are **big endian**, per the hvcC
  convention, while every other multi byte field in the protocol is little endian.
- usbmuxd's `PortNumber` is in network byte order. A port in host order is rejected with
  the exact same `Result Number 3` as a closed port, with no distinguishing signal.
  Therefore `htons()` lives inside `usbmux_connect()` and is never a parameter.

The `hvcC` record is never built by hand. It is read out of the `CMFormatDescription` of
the first keyframe and passed through unchanged, and the receiver rebuilds its decoder
format description from it. Parameter sets never travel in band.

## 4. Reconnect logic

The failure modes and their handling:

| Event | Behaviour |
|---|---|
| No device, usbmuxd unreachable, connection refused | Retry with backoff, 1 s growing to 5 s, no crash and no log flood |
| Device attach event for the selected phone | Connect immediately, ignoring the backoff |
| Broken framing, or a length above 8 MiB | Close and reconnect |
| Three missed PONGs (about 6 s) | Close and reconnect |
| No PING seen by the app for 6 s | The app drops the connection and frees the listener |
| Decoder error | Drop the frame. After three in a row, rebuild the session and wait for the next keyframe |
| Connection lost | `obs_source_output_video2(source, NULL)` clears the last picture instead of freezing it |

The two sided dead link rule matters more than it looks. Without the app side timeout, a
receiver that died without closing its socket would leave the phone permanently BUSY, and
the only recovery would be to restart the app.

usbmuxd needs two sockets: `Connect` consumes its connection (it becomes a raw tunnel) and
`Listen` occupies its own for as long as you want attach and detach events. The plugin
therefore holds one event connection plus one tunnel connection per active device. Attach
and detach events carry `tag = 0`, not the tag of the Listen request, so filtering events
by tag silently yields nothing.

## 5. Color convention

Fixed in version 1, not negotiated: NV12 video range
(`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`), BT.709 for primaries, transfer and
matrix. The app sets it on the capture output and on the encoder, the plugin calls
`video_format_get_parameters(VIDEO_CS_709, VIDEO_RANGE_PARTIAL, ...)` with
`full_range = false`.

There is no negotiation on purpose. A mismatch here produces a mild color cast that no
part of the protocol can detect, and that a viewer will blame on the camera. One fixed
convention beats a field that both sides can fill in wrongly.

## 6. Known limitations

- **The app must stay in the foreground.** iOS suspends the network listener when the app
  is backgrounded, so streaming stops. The app keeps the screen awake while streaming.
  There is no supported way around this for a normal app.
- **One receiver per phone.** A second connection gets `ERROR 1 BUSY` and is closed. This
  is a design choice, not a limit of the transport: two receivers would mean two encoder
  configurations for one camera.
- **SEI NALs pass through untouched.** The receiver forwards everything after the pts
  field to `VTDecompressionSessionDecodeFrame` unchanged, so any non VCL NAL the encoder
  chooses to emit rides along. The decoder ignores what it does not need.
- **The hvcC length varies** between devices, iOS versions and encoder settings, roughly
  90 to 130 bytes in practice. Nothing may assume a fixed size. CONFIG carries an explicit
  `hvcc_len`.
- **Device names are useless.** iOS reports the device name to a sandboxed app as plain
  "iPhone", so the OBS device list is labelled with serial numbers instead. Serial numbers
  are also the stable identifier: the usbmuxd `DeviceID` changes after every reboot of the
  phone.
- **No audio, no orientation control, no exposure or focus control** in version 1.
- **Self built iOS apps expire** after 7 days when signed with a free Apple ID.

## 7. Future: CMIO extension

The obvious next step is a macOS Camera Extension (CMIO) so that the picture appears in
Zoom, FaceTime, Safari and anything else that consumes a system camera, not just OBS.

The receive path is already shaped for it. `shared/usbmux.c` and `shared/frame_parser.c`
have no dependency on libobs and no dependency on the plugin; the platform specific part
is the decoder plus the output call. A CMIO extension would reuse both C modules and the
VideoToolbox decoder, and replace `obs_source_output_video2` with a `CMIOExtensionStream`
sending `CMSampleBuffer`s.

Two constraints shape that work. First, a Camera Extension runs in its own sandboxed
process with its own entitlements and must be shipped inside a signed host application, so
distribution gets harder, not easier. Second, one receiver per phone still holds, which
means the OBS plugin and the virtual camera cannot both be connected to the same phone at
the same time. The likely resolution is that the CMIO extension becomes the single
receiver and the OBS plugin consumes the virtual camera like any other source. That is a
decision for its own spec, not something to prejudge here.

## Frontend integration (obs-frontend-api)

`src/tools_menu.c` is the only file that touches the OBS frontend. It is compiled
only when `ENABLE_FRONTEND_API` is ON, which is the default since the Tools menu
entry is the one-click setup path for a first-time user. `ENABLE_QT` stays OFF:
the plugin links `obs-frontend-api` for the menu registration and the
`FINISHED_LOADING` event, and nothing else. That is a deliberate ceiling, and it
has one visible consequence: the first-run hint is a log line, not a dialog,
because a dialog would require Qt and with it the whole Qt build and version
matrix.

The menu callback is the entire onboarding step that used to be manual: it takes
the current scene, refuses to add a second TetherCam source to it, creates the
source with the id `iphone_usb_camera` under the name `TetherCam iPhone`, and
sets bounds `OBS_BOUNDS_SCALE_INNER` to the canvas from `obs_get_video_info`, so
the first frame arrives framed rather than as a corner thumbnail.

The once-per-scene-collection flag for the hint lives in
`obs_module_config_path("first-run.json")`, keyed by the collection name. Per
collection rather than per install, because a user with a streaming collection
and a scratch collection has two setups, not one.
