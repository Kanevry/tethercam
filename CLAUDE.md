# CLAUDE.md — obs-iphone-usb-cam

## Was das ist

Ein iPhone wird per **USB-Kabel** zur Kamera in OBS auf dem Mac. Die iOS-App nimmt auf,
encodiert HEVC in Hardware und sendet ueber einen TCP-Listener auf Port 7878; der Mac
erreicht diesen Port ueber den usbmux-Tunnel von `usbmuxd`, ohne WLAN. Das OBS-Plugin
verbindet sich, decodiert per VideoToolbox und liefert NV12-Frames als Async-Source.

## Layout

| Ordner | Inhalt | Lizenz |
|---|---|---|
| `protocol/PROTOCOL.md` | **Der Vertrag.** Framing, Nachrichtentypen, Fehlercodes | MIT |
| `shared/` | C-Bausteine beider Seiten: `frame_parser`, `usbmux` (+ ctest) | MIT |
| `ios-app/` | Swift/SwiftUI-App `UsbCam` (Capture, HEVC-Encoder, Server) | MIT |
| `obs-plugin/` | OBS-Source `iPhone USB Camera` (C/ObjC++, CMake) | GPL-2.0-or-later |
| `tools/` | Swift-Paket: `usbcam-sim`, `usbcam-recv`, `integration.sh` | MIT |
| `docs/superpowers/specs/` | Design-Spec; Korrekturen datiert anfuegen, nichts umschreiben | — |

## Build und Test

```bash
# shared (C-Unit-Tests)
cmake -S shared -B shared/build && cmake --build shared/build && ctest --test-dir shared/build

# tools (Simulator + Empfaenger)
swift test --package-path tools
bash tools/integration.sh            # End-zu-End ohne iPhone, braucht ffmpeg/ffprobe

# ios-app (xcodegen erzeugt das .xcodeproj aus project.yml)
cd ios-app && xcodegen generate
xcodebuild test -scheme UsbCam -destination 'platform=iOS Simulator,name=UsbCam-Test-iPhone17'
xcodebuild -scheme UsbCam -configuration Release \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE-ID> <pfad>/UsbCam.app
xcrun devicectl device process launch --terminate-existing --device <DEVICE-ID> at.gotzendorfer.usbcam

# obs-plugin
cd obs-plugin
CODESIGN_IDENT="Apple Development: ..." CODESIGN_TEAM=G3QZ66475M CI=1 cmake --preset macos
CODESIGN_IDENT="Apple Development: ..." CODESIGN_TEAM=G3QZ66475M CI=1 cmake --build --preset macos
```

`CI=1` ist Pflicht: ohne die Variable fragt das obs-Plugin-Template interaktiv nach
Signing-Angaben und bricht im Agent-Kontext ab. Installiert wird das Bundle nach
`~/Library/Application Support/obs-studio/plugins/obs-iphone-usb-cam.plugin`; OBS liest es
erst beim naechsten Start. **Nie einen laufenden OBS-Prozess beenden.**

## Konventionen

- **`protocol/PROTOCOL.md` ist der Vertrag.** Wer das Wire-Format aendert, aendert zuerst
  dort und danach beide Seiten. Empfaenger reichen alle NALs der VIDEO-Nutzlast durch
  (VideoToolbox stellt jedem VCL-NAL ein Prefix-SEI voran).
- **Rotation gehoert auf die Aufnahmeseite.** Die App richtet ueber
  `AVCaptureDevice.RotationCoordinator` am Horizont aus; aendert sich dadurch die Geometrie,
  wird die Encoder-Session neu gebaut und ein neues CONFIG gesendet. Die Rotation-Property
  im Plugin ist nur der manuelle Notausgang.
- VCS: GitLab primaer (`agents/obs-iphone-usb-cam` auf gitlab.gotzendorfer.at). Ein
  GitHub-Mirror wird nur gepflegt, wenn der Stand vorzeigbar ist.
- Lizenzen sind gemischt und bleiben es: das OBS-Plugin GPL-2.0-or-later (OBS-Header),
  alles uebrige MIT. Kein GPL-Code ausserhalb `obs-plugin/`.
- Conventional Commits.

## Session Config
- **session-types:** [housekeeping, feature, deep]
- **agents-per-wave:** 3
- **vcs:** gitlab
- **test-command:** bash tools/integration.sh
