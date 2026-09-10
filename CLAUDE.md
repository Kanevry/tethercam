# CLAUDE.md: TetherCam (Repo obs-iphone-usb-cam)

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
| `ios-app/` | Swift/SwiftUI-App `TetherCam` (Capture, HEVC-Encoder, Server) | MIT |
| `obs-plugin/` | OBS-Source `TetherCam (iPhone via USB)` (C/ObjC++, CMake) | GPL-2.0-or-later |
| `tools/` | Swift-Paket: `usbcam-sim`, `usbcam-recv`, `integration.sh`, `vcam-test.sh` | MIT |
| `mac-app/` | macOS-Menuleisten-App + CMIO Camera Extension (virtuelle Kamera, Preview, #12) | MIT |
| `docs/superpowers/specs/` | Design-Spec; Korrekturen datiert anfuegen, nichts umschreiben | n/a |
| `docs/app-store/` | Store-Metadaten (en-US, de-DE), Review Notes, Klickpfad, `validate.sh` | n/a |
| `tethercam.pen` + `images/` | Pen-Design-File der App-Store-Frames und Website-Galerie; KI-Szene, nie Gesichter | n/a |

## Build und Test

```bash
# shared (C-Unit-Tests)
cmake -S shared -B shared/build && cmake --build shared/build && ctest --test-dir shared/build

# tools (Simulator + Empfaenger)
swift test --package-path tools
bash tools/integration.sh            # End-zu-End ohne iPhone, braucht ffmpeg/ffprobe

# ios-app (xcodegen erzeugt das .xcodeproj aus project.yml)
cd ios-app && xcodegen generate
xcodebuild test -scheme TetherCam -destination 'platform=iOS Simulator,name=UsbCam-Test-iPhone17'
xcodebuild -scheme TetherCam -configuration Release \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE-ID> <pfad>/TetherCam.app
xcrun devicectl device process launch --terminate-existing --device <DEVICE-ID> at.gotzendorfer.tethercam

# mac-app (virtuelle Kamera; Spec docs/superpowers/specs/2026-09-09-virtual-camera-cmio.md)
swift test --package-path mac-app/Core
cd mac-app && xcodegen generate && xcodebuild -scheme TetherCam -configuration Release \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -derivedDataPath build build
bash mac-app/scripts/install-local.sh   # Release nach /Applications, startet, zeigt systemextensionsctl
bash tools/vcam-test.sh                 # Sim -> App headless -> ffmpeg-Aufnahme; Exit 3 = Freigabe fehlt

# obs-plugin
cd obs-plugin
CODESIGN_IDENT="Apple Development: ..." CODESIGN_TEAM=G3QZ66475M CI=1 cmake --preset macos
CODESIGN_IDENT="Apple Development: ..." CODESIGN_TEAM=G3QZ66475M CI=1 cmake --build --preset macos
```

`CI=1` ist Pflicht: ohne die Variable fragt das obs-Plugin-Template interaktiv nach
Signing-Angaben und bricht im Agent-Kontext ab. Installiert wird das Bundle nach
`~/Library/Application Support/obs-studio/plugins/obs-iphone-usb-cam.plugin`; OBS liest es
erst beim naechsten Start. **Nie einen laufenden OBS-Prozess beenden.**

### Distribution

`.claude/skills/distribute/SKILL.md` ist der Runbook fuer beide Artefakte. Kurzform:

```bash
scripts/appstore-upload.sh --dry-run   # iOS: archivieren + .ipa exportieren, kein Upload
scripts/appstore-upload.sh             # iOS: Upload nach App Store Connect / TestFlight
scripts/asc-api.sh apps                # App-Records/Bundle-Ids/Builds bei Apple abfragen
scripts/asc-listing.py --dry-run       # Listing aus docs/app-store/ nach App Store Connect
```

Der App-Store-Connect-Key liegt unter `~/.appstoreconnect/private_keys/` und niemals
im Repo; `.p8`-Inhalte und JWTs werden nie ausgegeben. Logs landen in
`build/appstore-*.log` (gitignored). Das `.pkg` des OBS-Plugins baut ausschliesslich
`release-plugin.yml` auf dem `v*`-Tag; danach muss der Draft-Release **veroeffentlicht**
werden, sonst liefert `releases/latest/download/...` 404 (docs/RELEASING.md, Teil 3).
Stand 2026-09-10: iOS 0.2.0 (Audio + Doppeltipp) ist im App Store
(https://apps.apple.com/us/app/tethercam/id6808997521); 0.3.0 (Protokoll 1.2, Build 6) ist
als Dev-Build am Geraet, TestFlight/Store steht aus (#24). Drei Artefakte: iOS-App, Mac-App
(.dmg, Mac-App-first) und OBS-Plugin (.pkg, signiert + notarisiert); Zoom und Teams am
2026-09-10 mit der virtuellen Kamera verifiziert (#13). Spendenlink ist
PayPal (paypal.me/Kanevry), nur Website/README/FUNDING.yml, nie in der App (3.1.1).


## Konventionen

- **`protocol/PROTOCOL.md` ist der Vertrag.** Wer das Wire-Format aendert, aendert zuerst
  dort und danach beide Seiten. Empfaenger reichen alle NALs der VIDEO-Nutzlast durch
  (VideoToolbox stellt jedem VCL-NAL ein Prefix-SEI voran).
- **Audio laeuft ueber denselben Draht** (Protokoll 1.1: AUDIO_CONFIG 0x13, AUDIO 0x14, START-Flag Bit 0).
  Audio-pts und Video-pts kommen von derselben Capture-Session-Uhr, beide Seiten rechnen nur
  `pts_us * 1000`, kein Offset. Der AAC-Decoder im Plugin fordert genau eine Access-Unit
  (1024 Frames) pro Aufruf an; mehr latcht den AudioConverter auf Stream-Ende.
- **Rotation gehoert auf die Aufnahmeseite.** Die App richtet ueber
  `AVCaptureDevice.RotationCoordinator` am Horizont aus; aendert sich dadurch die Geometrie,
  wird die Encoder-Session neu gebaut und ein neues CONFIG gesendet. Die Rotation-Property
  im Plugin ist nur der manuelle Notausgang.
- VCS: GitLab primaer (`agents/obs-iphone-usb-cam` auf gitlab.gotzendorfer.at) fuer die
  Entwicklung. `Kanevry/tethercam` auf GitHub ist der oeffentliche Mirror und der
  Release-Host (Actions, Release-Assets). Website: https://tethercam.app
- **Camera Extension:** `PRODUCT_NAME` der Extension = Bundle-Id (sysextd sucht
  `<bundle-id>.systemextension`), die App muss in `/Applications` liegen, die Freigabe in
  Systemeinstellungen > Anmeldeobjekte & Erweiterungen ist manuell (Admin-Passwort), nie automatisierbar.
- Lizenzen sind gemischt und bleiben es: das OBS-Plugin GPL-2.0-or-later (OBS-Header),
  alles uebrige MIT. Kein GPL-Code ausserhalb `obs-plugin/`.
- Conventional Commits.

## Session Config
- **session-types:** [housekeeping, feature, deep]
- **agents-per-wave:** 3
- **vcs:** gitlab
- **test-command:** bash tools/integration.sh

## Dispatcher Autonomy

> **Parity-exempt section.** This H2 is intentionally placed outside the `## Session Config` block so that the `claude-md-drift-check` Check-6 parity scanner (which extracts only column-0 keys inside the `## Session Config` block) does not flag repos that have not yet adopted this feature. Issue #679 / #681.

Opt-in configuration for the cross-repo free-repo dispatcher autonomy gate (Epic #673). The default is `off`, fail-closed. The effective `autonomy` resolves with host-local precedence `SO_DISPATCHER_AUTONOMY` env > `owner.yaml` `dispatcher.autonomy` > committed > `off` (#653 pattern).

```yaml
dispatcher-autonomy:
  autonomy: off            # off | advisory | autonomous-gated: default off (fail-closed)
  confidence-floor: 0.5    # float 0.0..1.0
```

Read by: `scripts/lib/config/dispatcher-autonomy.mjs` (parser + resolver), `skills/dispatcher/SKILL.md` (cross-repo dispatch flow). Issue: #681.
