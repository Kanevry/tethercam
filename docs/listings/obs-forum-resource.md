# OBS Resources draft: TetherCam

Venue: https://obsproject.com/forum/resources/ ("Add resource").
Category: Plugins. Platform: macOS. Version field: `0.1.0`.
Do not submit before the v0.1.0 GitHub release is published (see `README.md` in this folder).

---

## Title

TetherCam: iPhone as an OBS camera over USB (macOS)

## Tagline (one line)

Use your iPhone as a webcam for OBS over a plain USB cable, no Wi-Fi, no cloud, no pairing screen.

## Description

TetherCam brings the iPhone camera into OBS Studio on macOS through the USB cable. The
phone encodes HEVC in hardware and serves the stream on a local TCP port; the Mac reaches
that port through usbmuxd, the same system service that carries Xcode traffic over the
cable; the OBS plugin decodes with VideoToolbox and hands NV12 frames straight to OBS.
Nothing is buffered in the plugin and nothing leaves the cable.

It exists because Continuity Camera stopped working for me after an iOS and macOS version
mismatch (iOS 26.6 against macOS 26.5): the handshake succeeded, the picture stayed black.
The third party apps that fill this gap are paid and closed source. TetherCam is neither.

This is the first release, 0.1.0, and the iPhone app is in a public TestFlight beta.
Expect rough edges and please report them as GitHub issues.

Measured on one setup (iPhone 15 Pro Max, M4 Pro Mac, OBS 32.2.2): 1080p30 and 1080p60,
about 13 Mbit/s HEVC, about 1 ms ping round trip over USB, about 90 ms to the first frame,
about 1.3 s reconnect after a cable pull, 30.0 fps at about 6 percent CPU over a 3 minute
run. Your numbers will differ with phone, Mac and settings.

The plugin installs into your own home folder under the OBS plugins directory. No
administrator rights, no system extension, no daemon.

## Features

- Video over the USB cable only. No Wi-Fi, no cloud service, no account, no pairing code.
- 1280x720 or 1920x1080 at 30 or 60 fps, bitrate adjustable (default 12000 kbit/s).
- Hardware HEVC encoding on the phone, VideoToolbox decoding on the Mac.
- One menu entry: Tools, then "TetherCam: Add iPhone camera to current scene" creates the
  source and fits it to the canvas.
- Camera and lens picker in the app: Back Wide, Back Ultra Wide, Back Telephoto, Front.
- Auto rotation with horizon leveling on the phone, so OBS receives a picture that is
  already the right way up. Manual 0/90/180/270 override on either side.
- Status line at the top of the source properties that names the missing step when the
  picture is black; matching diagnostics sheet in the app.
- Reconnects on its own after a cable pull.
- Documented wire protocol (`protocol/PROTOCOL.md`) if you want to write your own receiver.
- Open source. Plugin GPL-2.0-or-later, everything else MIT.

## Requirements

- iPhone XR or newer with iOS 17 or later. Tested on iPhone 15 Pro Max, iOS 26.6.1.
- Mac with macOS 12 or later. Tested on macOS 26.5.2, Apple Silicon.
- OBS Studio 30 or later. Tested with 32.2.2.
- A data cable, not a charge-only one.

## Install

**Mac plugin**

1. Download `TetherCam-obs-plugin.pkg` from <RELEASE_URL> and open it, or run
   `curl -fsSL https://raw.githubusercontent.com/Kanevry/tethercam/main/scripts/install.sh | bash`.
   Read the script first; it downloads the release bundle and unpacks it into
   `~/Library/Application Support/obs-studio/plugins/`, nothing else.
2. If the `.pkg` is unsigned, macOS asks once: right-click, then Open.
3. Restart OBS.

**iPhone app**

1. Join the free public TestFlight beta: https://testflight.apple.com/join/wmT74Ry8
   (install TestFlight from the App Store first if you do not have it).
2. Or build it yourself with a free Apple ID and Xcode; steps in the README under
   "Install the iPhone app".

**Use it**

1. Connect the phone with a data cable and unlock it.
2. Open TetherCam on the phone and leave it in the foreground. The app keeps the screen
   on while streaming; iOS suspends the listener as soon as the app goes to the background.
3. In OBS: Tools, then "TetherCam: Add iPhone camera to current scene". The status line
   on the phone turns green and says "Streaming 1080p30".

## Known limitations

- First release. Beta on the iPhone side.
- macOS only. The shared C core builds on Linux, but no Windows or Linux receiver ships.
- Video only. Use a separate microphone in OBS.
- HEVC only. The phone encodes HEVC in hardware; there is no H.264 fallback.
- One receiver per phone. A second OBS source or the CLI receiver gets `ERROR 1 BUSY`.
- The app must stay in the foreground on an unlocked phone.
- Plugin only, no virtual camera: the picture shows up in OBS, not in Zoom or FaceTime.
  A CMIO Camera Extension is on the roadmap, not in this release.
- The `.pkg` is signed and notarized only if the signing secrets were configured when the
  release was built; otherwise macOS asks once before opening it.

## Support and issues

- Issues and bug reports: https://github.com/Kanevry/tethercam/issues
- Source and releases: https://github.com/Kanevry/tethercam
- Website: https://tethercam.app
- Privacy policy: https://tethercam.app/privacy (the app collects no data)

## License

- `obs-plugin/`: GPL-2.0-or-later, because it links against libobs.
- iPhone app, shared C core, tools, protocol spec, docs: MIT.

## Screenshots to attach

Upload in this order (repo paths; the `web/img/*.webp` twins are smaller if the forum
accepts WebP):

1. `docs/images/obs-iphone-live.png`: OBS showing live 1080p from the iPhone.
2. `docs/images/obs-tools-menu.png`: the Tools menu entry.
3. `docs/images/obs-plugin-properties.png`: source properties with the status line.
4. `docs/images/app-live.png`: the app streaming, status capsule "Streaming 1080p30".
5. `docs/images/app-settings-sheet.png`: camera and lens picker, resolution.
6. `docs/images/app-diagnostics.png`: diagnostics sheet on the phone.
7. `docs/images/architecture.svg`: data path diagram (convert to PNG if SVG is rejected).

Optional, the App Store frames: `web/img/store-01-hero-wired-into-obs.webp` through
`web/img/store-05-diagnostics.webp`. The camera picture in those is a generated studio
scene, say so if you use them.

Demo video, 54 seconds: https://tethercam.app (embedded), file `web/demo.mp4`.

## Placeholders

- `<RELEASE_URL>`: v0.1.0 release page.
