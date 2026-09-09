# TetherCam for macOS

Menu bar host app plus CoreMediaIO Camera Extension. The host receives the HEVC
stream from the iPhone over USB (usbmuxd, TCP 7878), decodes it with VideoToolbox
and feeds the frames into the extension's sink stream; the extension publishes the
iPhone as the camera "TetherCam" (1920x1080, NV12, 30 fps) to every app on the Mac
(Zoom, Teams, FaceTime, ffmpeg, ...). No OBS required.

Layout: `Core/` is the SwiftPM package (`TetherCamContract` = identifiers and the
published format, compiled into both targets; `TetherCamCore` = receiver, decoder,
sink bridge). `App/` is the host, `Extension/` the camera extension.

## Build

```bash
cd mac-app
xcodegen generate
xcodebuild -scheme TetherCam -configuration Release \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -derivedDataPath build build CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=G3QZ66475M
# -> build/Build/Products/Release/TetherCam.app
#    (contains Contents/Library/SystemExtensions/at.gotzendorfer.tethercam.mac.camera.systemextension)
cd Core && swift test          # 15 tests incl. the pipeline against usbcam-sim
```

## Install locally (developer Mac)

```bash
swift build --package-path tools -c release --product usbcam-sim   # optional, for tests/headless
bash mac-app/scripts/install-local.sh
```

The script builds Release, copies the app to `/Applications` (replacing only a
bundle whose `CFBundleIdentifier` is `at.gotzendorfer.tethercam.mac`), launches it
once (which submits the extension activation request) and prints the
`systemextensionsctl list` line. `activated waiting for user` means: System
Settings > General > Login Items & Extensions > Camera Extensions > enable
TetherCam; the script opens that pane.

## Why /Applications and the System Settings approval

A camera extension is a macOS system extension. `systemextensionsctl` only
activates extensions that are embedded in an app located in `/Applications`
(`OSSystemExtensionErrorUnsupportedParentBundleLocation` otherwise), and the first
activation must be approved by the user under System Settings > General >
Login Items & Extensions > Camera Extensions. TetherCam submits the activation
request on every launch, shows the state in its menu and offers a button that opens
that settings pane. The extension runs sandboxed inside Apple's
`registerassistantservice`; the host is not sandboxed because it talks to
`/var/run/usbmuxd` and TCP sockets just like the OBS plugin does.

## Headless flags

- `--headless`: every pipeline status change is one stderr line:
  `tethercam: link=<state> camera=<status> res=<WxH@fps> fps=<n> pushed=<n> dropped=<n>`
  (`link`: no-device|waiting|starting|streaming|incompatible|busy;
  `camera`: missing|waiting-for-user|ready|error). Runs until SIGTERM.
- `--debug-tcp HOST:PORT`: connect to a plain TCP source (`usbcam-sim`) instead of
  usbmuxd.
- `--no-activate`: skip the system extension activation request.

```bash
tools/.build/release/usbcam-sim --bind 127.0.0.1 --port 7878 --no-audio &
/Applications/TetherCam.app/Contents/MacOS/TetherCam --debug-tcp 127.0.0.1:7878 --headless
```

`pushed` only grows once the extension is enabled; until then the host keeps
receiving and retries the sink every 2 s. Frame timestamps handed to the extension
are the host clock at push time (`CameraPipeline`), because camera clients expect
host-clock presentation times and the phone clock is unrelated.

## License

MIT (see the repository root). The camera extension and the host contain no OBS code.
