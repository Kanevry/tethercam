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
#    (contains Contents/Library/SystemExtensions/TetherCamCamera.systemextension)
cd Core && swift test
```

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

- `--headless`: no interaction, state changes are printed to stderr (used by
  `tools/vcam-test.sh`).
- `--debug-tcp HOST:PORT`: connect to a plain TCP source (`usbcam-sim`) instead of
  usbmuxd.

## License

MIT (see the repository root). The camera extension and the host contain no OBS code.
