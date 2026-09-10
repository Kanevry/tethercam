# TetherCam virtual camera for macOS (CoreMediaIO Camera Extension)

Date: 2026-09-09. Status: implemented, not released (GitLab issue #12). Corrections are
appended dated at the end, nothing above is rewritten. The wire format stays
[../../../protocol/PROTOCOL.md](../../../protocol/PROTOCOL.md); this spec only adds a
second receiver on the Mac. The original design is
[2026-09-05-obs-iphone-usb-cam-design.md](2026-09-05-obs-iphone-usb-cam-design.md).

## Goal

The iPhone picture that TetherCam already delivers to OBS should show up as a system
camera named "TetherCam" in every macOS app that consumes one: Zoom, Teams, Meet in a
browser, FaceTime, QuickTime, ffmpeg. Same cable, same iOS app, same protocol; no OBS
required on the Mac.

## Non-goals (v1)

- **Audio.** A CMIO Camera Extension carries video only. The Mac app sends START with
  flags 0, so the phone sends no AUDIO messages. The OBS plugin path keeps audio.
- **Mac App Store.** The host app is unsandboxed (it opens `/var/run/usbmuxd` and TCP
  sockets exactly like the OBS plugin). MAS would need a sandboxed host and a different
  usbmux story; that is its own issue.
- **Dynamic camera formats.** The extension publishes exactly one format. Whatever the
  phone sends is scaled or letterboxed into it (see Format policy).
- **Replacing the OBS plugin.** It stays as the direct, lowest-latency, audio-capable path.

## Architecture

### Process model

```
 iPhone (TetherCam.app)          Mac
 ┌──────────────────┐            ┌─────────────────────────────────────────────┐
 │ AVCapture → HEVC │  USB       │ usbmuxd ──► TetherCam.app (host, menu bar)  │
 │ NWListener :7878 │ ─────────► │            Receiver → HevcDecoder →         │
 └──────────────────┘  usbmux    │            FrameScaler → CMIOSink           │
                                 │                     │ CMSampleBuffer         │
                                 │                     ▼ (sink stream, XPC)     │
                                 │ registerassistantservice (Apple, sandboxed) │
                                 │   └─ at.gotzendorfer.tethercam.mac.camera   │
                                 │      .systemextension: sink ──► source      │
                                 │                     │                        │
                                 │                     ▼ AVFoundation client    │
                                 │ Zoom / Teams / FaceTime / ffmpeg / Chrome   │
                                 └─────────────────────────────────────────────┘
```

Three processes on the Mac, three trust levels:

| Piece | Process | Sandbox | Role |
|---|---|---|---|
| `mac-app/App` host `TetherCam.app` | own, `LSUIElement` menu bar app | no (hardened runtime, entitlements `system-extension.install` + app group) | receives, decodes, scales, pushes into the sink |
| `mac-app/Extension` | Apple's `registerassistantservice` | yes (app group only) | publishes device + source stream, owns the sink stream |
| `mac-app/Core` SwiftPM | linked into both | n/a | `TetherCamContract` (identifiers, format) and `TetherCamCore` (pipeline) |

The extension is embedded at `Contents/Library/SystemExtensions/` of the host and is
activated through `OSSystemExtensionRequest` on every host launch
(`ExtensionInstaller`). The two sides never share code paths at runtime; they share
`TetherCamContract` at compile time (bundle ids, app group = `CMIOExtensionMachServiceName`,
stable device and stream UUIDs, the one format, sink queue depth 4). That file is
contract-locked: change it in one commit with both sides.

### Data path

1. `Receiver` mirrors the OBS plugin state machine (`no-device → waiting → starting →
   streaming`, plus `incompatible` and `busy`) over TCP or usbmux. It reuses
   `tools`' `IucmProtocol` codec and `CUsbmux` over `shared/usbmux.c`, so there is still
   exactly one tunnel client and one framer in the repo.
2. `HevcDecoder` builds a VideoToolbox decompression session from CONFIG (VPS/SPS/PPS)
   and gates on the first keyframe after each CONFIG, like the plugin.
3. `FrameScaler` letterboxes or scales every decoded geometry (1920x1080, 1080x1920
   portrait, 1280x720) into 1920x1080 NV12 with `VTPixelTransferSession`.
4. `CMIOSink` finds the extension's sink stream by UID, copies its buffer queue
   (`CMIOStreamCopyBufferQueue`) and enqueues `CMSampleBuffer`s
   (`CMSimpleQueueEnqueue`). A full queue drops the newest frame instead of blocking the
   receiver.
5. In the extension, `StreamSink` consumes the queue and `StreamSource` republishes the
   buffers to clients. While no host is feeding it, the source emits placeholder frames
   at 30 fps so the device never goes dark in a client's picker.

`CameraPipeline` glues 1 to 4 together and retries the sink lookup every 2 s until the
extension is enabled, so the host can start before the user has approved the extension.

### Clocking

Camera clients expect host-clock presentation times. The phone's `pts_us` is unrelated
to the Mac's clock, so `CameraPipeline` stamps every pushed buffer with the host clock at
push time. The phone pts is still used inside the decoder for ordering. Audio would need
the phone clock (as the OBS plugin does); that is one more reason audio is out of scope.

### Format policy

One published format: 1920x1080, `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`
(NV12), 30 fps, defined once in `TetherCamContract`. Reasons: every client accepts it,
clients remember the format per device UID and misbehave when the list changes, and a
single format keeps the extension free of negotiation state. Portrait input is
letterboxed, not rotated: rotation is decided on the phone (see the ARCHITECTURE note on
`RotationCoordinator`).

## Single-receiver decision

The phone serves one receiver at a time (protocol: a second connection gets `BUSY`).
Options considered:

- **Extension as the receiver.** Impossible as-is: the extension is sandboxed and cannot
  open `/var/run/usbmuxd`.
- **OBS plugin feeds the extension.** Couples the virtual camera to OBS running; defeats
  the goal.
- **Host app as the receiver; OBS consumes the system camera.** Chosen. The host owns the
  phone, the extension publishes it, and OBS picks "TetherCam" up as a normal video
  capture device. Users who want the lowest latency and audio in OBS keep using the
  plugin, but then must not run the Mac app at the same time (the phone answers BUSY to
  whoever connects second, and both receivers show that state).

## Activation and approval UX, and its limits

- The host submits `OSSystemExtensionRequest.activationRequest` on every launch and shows
  the result in its menu (`missing`, `waiting-for-user`, `ready`, `error`).
- macOS requires the user to enable the extension once under **System Settings >
  General > Login Items & Extensions > Camera Extensions** and asks for the admin
  password. This cannot be automated or scripted; OBS's own virtual camera has the same
  gate. The host offers a button that opens the pane.
- `sysextd` only activates extensions embedded in an app under `/Applications`
  (`OSSystemExtensionErrorUnsupportedParentBundleLocation` otherwise). The DMG therefore
  ships the usual "drag to Applications" layout and the menu says so when the app runs
  from elsewhere.
- `sysextd` looks the bundle up as `<bundle-id>.systemextension`, so the extension's
  `PRODUCT_NAME` must equal its bundle id; any other name yields
  `OSSystemExtensionErrorExtensionNotFound`.
- Updating an already enabled extension can require a reboot before the new binary is
  the one running (see Open risks).

## Distribution plan

- Developer ID Application signature on host and extension, hardened runtime, notarized,
  stapled, shipped as a `.dmg` on the GitHub release next to the plugin `.pkg`. No
  embedded provisioning profile is needed for Developer ID system extensions (verified
  against OBS.app).
- Homebrew cask in `kanevry/tethercam` (`tethercam-mac` or similar) once the DMG exists.
- Local developer install: `mac-app/scripts/install-local.sh` (automatic Apple Development
  signing, `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` on first
  build, copies to `/Applications`, launches once, reports `systemextensionsctl list`).
- Mac App Store: separate issue, blocked on the sandbox question above.

## Test strategy

| Layer | What | How |
|---|---|---|
| Unit | contract constants, receiver state machine, decoder keyframe gate, scaler geometries, sink queue behaviour, pipeline status transitions | `swift test --package-path mac-app/Core` |
| Live sim | pipeline against `usbcam-sim` over `--debug-tcp` | part of the same test target (`PipelineTests`) |
| End to end | `bash tools/vcam-test.sh`: sim → `TetherCam.app --debug-tcp --headless` → ffmpeg avfoundation capture of "TetherCam" → ffprobe asserts 1920x1080 and ≥25 fps → PSNR of two frames proves motion → optional `VCAM_BROWSER=1` Chrome `getUserMedia` via `agent-browser` | exit 0 PASS, 1 FAIL, 3 extension waiting for approval, 4 not registered |
| Device matrix | iPhone 15 Pro Max (iOS 26.6) over usbmux; clients FaceTime, Zoom, Chrome, QuickTime; portrait and 720p lens switches trigger CONFIG and must not drop the camera in the client | manual, with the results appended here |

`vcam-test.sh` is repeatable, kills only the processes it started, and writes everything
under `/tmp/vcam-test/`.

## Open risks

1. **Sink/placeholder handover.** When the host starts pushing, the source switches from
   placeholder frames to sink frames; when the host stops, it switches back. A client
   that is mid-frame during that switch may see one duplicated or torn frame. Not observed
   yet because the full E2E has not run; watch the PSNR check.
2. **Reboot on extension update.** Measured 2026-09-09 (builds 1 → 2 → 3 → 4, same
   version 0.1.0): `OSSystemExtensionReplacementActionReplace` swapped the enabled
   extension without a reboot and without a second approval; the old build is listed as
   `terminated waiting to uninstall on reboot`. Scripts must therefore read the
   `[activated ...]` line, not the last line, of `systemextensionsctl list`. A new
   `CFBundleVersion` per build is what makes the replacement visible.
3. **Coexistence with the OBS plugin.** Both receivers want the same phone; the second one
   gets `BUSY`. Both show a clear state, but the user has to know which one to quit.
   Possible later improvement: the Mac app pauses its receiver while OBS's plugin source
   is active, signalled through a file in the app group.
4. **First-run friction.** Two manual gates (drag to Applications, approve in System
   Settings with the admin password) are more than the plugin ever asked for. The
   install guide has to carry this.
5. **Sink authorization.** Any local client may open the sink stream (OBS policy). A
   `signingID == host bundle id` gate was tried and locked the host out: on macOS 26.6
   `CMIOExtensionClient.signingID` is nil for the Apple Development-signed host. Revisit
   with a Developer ID build before shipping.
6. **Codesign drift.** Any identity or entitlement mismatch between host and extension
   silently ends in `waiting for user` or `not found`. `install-local.sh` prints the
   `systemextensionsctl` line and the last sysextd log lines for exactly this reason.

## Status 2026-09-09

- Implemented on `main` (commits `66e95f0`, `83cb747`, `18fce1a` and the finalization
  commit of this session), Mac app version 0.1.0 build 4, not released.
- macOS 26.6.2, Xcode 26.0.1: `swift test --package-path mac-app/Core` 16 tests, tools 36,
  iOS 118, shared ctest 3, `tools/integration.sh` PASS; mac-app Release build 0 warnings.
- The extension was approved on this Mac (owner entered the admin password), state
  `[activated enabled]`; `TetherCam` appears in `ffmpeg -f avfoundation -list_devices`.
- `VCAM_BROWSER=1 bash tools/vcam-test.sh`:
  `PASS listed_s=1 size=1920x1080 fps=30.31 frames=90 psnr_db=19.70 browser=ok`, host
  status `link=streaming camera=ready pushed=113 dropped=38`; the captured frame shows the
  simulator's colour bars, the moving box and the timestamp. Chrome's `enumerateDevices`
  lists `TetherCam`.
- Three defects found only by that run, all fixed the same day: (a) `CMIOStreamCopyBufferQueue`
  returns `noErr` and no queue when the altered proc is nil; (b) `kCMIOStreamPropertyDirection`
  is app-relative: the extension's `.source` reports 1 and its `.sink` reports 0, so the
  host must pick direction 0 (the earlier value 1 started the SOURCE stream and the test
  passed on the placeholder animation); (c) the placeholder also moves, so `vcam-test.sh`
  now requires `pushed > 0` in the host status line before it reports PASS.
- Follow-ups: `dropped` ≈ 25 % at 30 fps with the extension's queue of 10 (consume loop
  timing, see #12); sink authorization (risk 5); the real-device matrix is issue #13; the
  release pipeline #14; Mac App Store #15.
- Interim for users today: OBS → Start Virtual Camera already brings the TetherCam
  picture into Zoom, Teams, Meet and FaceTime (needs the OBS camera extension approved
  once in the same System Settings pane).

## Correction 2026-09-09 (evening): real-device run

- First run with a real iPhone 15 Pro Max (App Store build 0.1.0) over usbmux, no
  `--debug-tcp`: the camera "TetherCam" showed the phone picture in QuickTime Player,
  Photo Booth, FaceTime, Google Meet (Chrome), Safari, Chrome and ffmpeg; issue #13 has
  the checklist. Zoom and Teams remain untested (not installed). Reconnect after an
  iOS-app restart and the BUSY answer to a second usbmux client behaved as designed.
- Open risk 1 (sink/placeholder hand-over) was seen once: the very first capture after
  the first sink connect delivered a single frame in 4 s; every later capture, including
  one after 15 s idle, ran at 30 fps. Not reproduced.
- New: frame accounting is misleading when no app reads the camera. In the pass-through
  path (landscape) the queue fills and `dropped` climbs into the thousands; in the
  scaled path (portrait) the `FrameScaler` pool threshold silently discards frames
  (`droppedAtAllocationThreshold` is not surfaced) and `pushed` freezes at 7 with
  `dropped=0`. The UI should show "no app is using the camera" and count pool drops.
- `Logger.info` lines of the extension are not retrievable with `log show --info`;
  diagnostics need `.notice`/`.error` or a documented `log stream` recipe.
- The phone lying flat reported 1920x1080, then 1080x1920 after the first CONFIG and
  1920x1080 again after a restart; both geometries were letterboxed correctly, so the
  mid-stream CONFIG change is verified on a device.
- Distribution, same evening: `scripts/mac-app-release.sh` produces the Developer ID
  signed, notarized and stapled `TetherCam-mac.dmg` (0.2.1 build 6); installed from the
  dmg it replaced the enabled extension without a second approval and streamed the phone
  at 30 fps. Mac App Store is out for now: the sandbox profile denies the usbmuxd socket
  for the host and `cmioextension.sb` denies it for the extension, so the
  host-bridges-frames design is the only possible one under any distribution channel
  (docs/mac-app-store-feasibility.md, issue #15). One user-facing trap: a quarantined
  copy that was not dragged by Finder is run through App Translocation and the host
  reports "must be in /Applications" although it is; the install guide names the fix.

## Correction 2026-09-10: release status, sandbox verdict, honest counters

- **Status.** The header above says "implemented, not released". As of 2026-09-09 the
  Mac app **is released**: 0.2.1 (build 6) ships as the Developer-ID signed, notarized
  and stapled `TetherCam-mac.dmg` on the GitHub release plus the Homebrew cask
  `kanevry/tethercam`. Header line kept as written, this note supersedes it.
- **The host-bridged design is not a choice, it is the only option (#18).** The Mac App
  Store spike measured that the deny of `/var/run/usbmuxd` in Apple's
  `cmioextension.sb` is **unconditional** — no entitlement, no temporary exception and
  no distribution channel lifts it. A Camera Extension therefore can never open usbmux
  itself under ANY channel (Developer ID included), so "host receives + decodes, sink
  stream carries frames into the extension" is the only design that can work, not
  merely the one picked for convenience. The Non-goal "Mac App Store" above understates
  this: MAS is blocked for the same socket reason on the host side, where the App
  Sandbox denies the usbmuxd socket as well (docs/mac-app-store-feasibility.md, #15/#17).
- **Sandboxed host, second trap.** A sandboxed process may feed a CMIO sink stream only
  when it holds `com.apple.security.device.camera`. Without that entitlement the
  sandboxed app enumerates **no** camera devices at all, so `findDevice()` returns nil
  and the failure looks like "extension not installed" instead of "missing
  entitlement". Silent, and worth naming before anyone retries the sandbox route.
- **Counters are honest now (#16).** The misleading accounting named in the 2026-09-09
  evening correction is fixed:
  - `FrameScaler.droppedAtAllocationThreshold` is carried in `ReceiverStats.scalerDrops`
    and folded into `PipelineStatus.dropped` via `CameraPipeline.totalDropped(...)`, so
    the portrait path no longer reports `dropped=0` while losing every frame.
  - `PipelineStatus.noConsumer` derives the idle state with `SinkIdleDetector`: `pushed`
    unchanged for more than 1 s while `fps > 0`. The menu then reads "Camera ready — no
    app is reading it yet", and the raw counters move behind `--debug-tcp`/`--headless`.
  - The contract/observed queue mismatch is documented rather than papered over:
    `TetherCamContract.sinkQueueDepth = 4` is only what the extension REQUESTS through
    `CMIOExtensionStreamProperties.sinkBufferQueueSize`; CoreMediaIO handed the client a
    capacity of 10 on macOS 26.6. `CMIOSink.queueCapacity` reads the real value from
    `CMSimpleQueueGetCapacity` and it is surfaced as `sinkQueueCapacity`. Anything
    reasoning about back-pressure must use the measured value.
  - The status line gained the tokens `received=`, `no-consumer=`; it stays `key=value`,
    so `tools/vcam-test.sh` (greps `pushed=`) is unaffected.
- **Extension logging.** State changes in `DeviceSource`/`StreamSink`/`ProviderSource`
  moved from `Logger.info` (not persisted in the CMIO sandbox) to `.notice`; the
  `log stream ... --level notice` recipe is in `mac-app/README.md`.

## Decision 2026-09-10: Mac App Store is a No-Go (#15, #17)

- **Rule.** App Sandbox blocks foreign Unix domain sockets such as `/var/run/usbmuxd`
  (Apple DTS, forum thread 788364: temporary-exception entitlements "don't work for
  Unix domain sockets"; the non-sandboxed XPC helper is Developer-ID-only). Measured
  here on 2026-09-10: `CONNECT_FAIL errno=1` in a signed sandboxed app.
- **Only sandbox-legal wire.** The "iPhone USB" network link that Personal Hotspot
  creates over the same cable (spike #17: `en8` active, phone at 172.20.10.1, TCP 7878
  reachable with Wi-Fi off). It costs the user the hotspot switch, depends on the
  carrier plan and excludes Wi-Fi-only iPads, so it is not a drop-in replacement.
- **Market.** Camo, Iriun and EpocCam all ship the Mac receiver as a direct download;
  only their phone apps are in the stores.
- **Decision (owner, 2026-09-10).** Stay with Developer ID `.dmg` + Homebrew cask for
  the Mac app and the App Store for the iOS app. The stale macOS review submission in
  App Store Connect is to be deleted by the owner in the UI (the API reports
  "not in cancellable state"). Re-open only if Apple changes the sandbox rule.

## Measurement 2026-09-10: sink authorization stays open (Open Risk 5, #28)

Open Risk 5 asked to retry the `signingID` gate with a Developer ID build. Done, and
the answer is the same as on 2026-09-09 — the gate is not implementable on this OS.

- **Setup.** macOS 26.6.2 (build 25G83). Host archived and exported with
  `method: developer-id`, verified `Authority=Developer ID Application: Bernhard
  Goetzendorfer (G3QZ66475M)`, `Identifier=at.gotzendorfer.tethercam.mac`, hardened
  runtime on. The already installed extension (0.3.0/9, pid 43130) served both runs;
  it was not replaced, so the known launchd EALREADY race was never touched.
- **Run A, simulated stream.** `VCAM_APP=<devid export> bash tools/vcam-test.sh` →
  `PASS listed_s=1 size=1920x1080 fps=29.68 frames=89 psnr_db=20.86`. Log:
  `sink client pid 87954 signingID unknown`.
- **Run B, live iPhone stream over USB** (owner started the iOS app):
  `sink client pid 88424 signingID unknown`, followed by `sink started, client pid 88424`;
  host status `link=streaming camera=ready res=1920x1080@30 fps=31.0`.
- **What "unknown" means.** It is not a fallback string from our code: the extension
  binary contains `<nil>` and no `unknown` (`strings -a … | grep -i unknown` → empty),
  and `log show --style json` shows `formatString: "sink client pid %d signingID
  %{public}s"` with `eventMessage: "… signingID unknown"`. The unified log renders an
  unresolvable `%{public}s` argument that way — i.e. `CMIOExtensionClient.signingID`
  hands the extension no usable string, with a Developer ID host either.
- **Decision (2026-09-10).** Keep the open policy, same as the OBS camera extension.
  A `signingID` equality gate would return false for the legitimate host and brick the
  camera. The threat it would stop (a local process feeding frames into the sink)
  already requires local code execution with camera access.
- **Change made.** `StreamSink.authorizedToStartStream` now logs once per client pid
  instead of once per stream start, and logs `signingID present <bool>` next to the
  value, because "unknown" and a literal fallback string are indistinguishable in the
  log. Retries must read the boolean, not the rendered value.
- **Next retry, if any.** Only worth repeating when Apple documents a populated
  `signingID`; a blind retry costs a build, an install and the extension race.
