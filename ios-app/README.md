# UsbCam (iOS-App)

Nimmt das iPhone-Kamerabild auf, kodiert es per Hardware in HEVC und liefert es
ueber einen lokalen TCP-Listener auf Port **7878** aus. Der Mac erreicht diesen
Port ueber den USB-Multiplexer (`/var/run/usbmuxd`); es wird kein WLAN benoetigt.

Protokoll: siehe `../protocol/PROTOCOL.md`. Design: `../docs/superpowers/specs/`.

## Aufbau

```
Sources/Protocol/   IucmMessage.swift     Codec fuer alle Nachrichten (pur, testbar)
                    IucmFrameParser.swift Byte-Strom-Framer mit Resync
Sources/Capture/    CaptureEngine.swift   AVCaptureSession, Kameraliste, Formatwahl
                    HevcEncoder.swift     VTCompressionSession, CONFIG + VIDEO
Sources/Server/     ServerStateMachine.swift  reine Zustandslogik (Events -> Aktionen)
                    UsbServer.swift       NWListener, eine Verbindung, PING-Timeout
Sources/UI/         App.swift, ContentView.swift, CameraPreview.swift
Tests/              XCTest: Codec-Round-Trips, Parser, Zustandsautomat
```

Das Xcode-Projekt ist **generiert** und nicht eingecheckt.

## Projekt erzeugen

```sh
brew install xcodegen        # einmalig
cd ios-app
xcodegen generate            # erzeugt UsbCam.xcodeproj
```

## Bauen

```sh
# Geraete-Build (Signierung Team G3QZ66475M, automatisch)
xcodebuild -project UsbCam.xcodeproj -scheme UsbCam \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates -derivedDataPath build build

# Unit-Tests (kein Geraet, keine Kamera noetig)
xcodebuild test -project UsbCam.xcodeproj -scheme UsbCam \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Selbstbau ohne unser Team: in `project.yml` `DEVELOPMENT_TEAM` auf die eigene
Team-ID und `PRODUCT_BUNDLE_IDENTIFIER` auf eine eigene Bundle-ID aendern.

## Auf dem iPhone installieren

**Voraussetzung: Developer Mode am iPhone.**
`Einstellungen > Datenschutz & Sicherheit > Entwicklermodus` einschalten und das
Geraet neu starten. Ohne diesen Schritt schlaegt `devicectl` fehl, und zwar auch
dann, wenn der Build erfolgreich war.

```sh
# Geraete-UDID nachschlagen
xcrun devicectl list devices

# App installieren
xcrun devicectl device install app \
  --device 8CDB11B5-13E8-5735-ABD4-AF958AC112DB \
  build/Build/Products/Debug-iphoneos/UsbCam.app

# App starten
xcrun devicectl device process launch \
  --device 8CDB11B5-13E8-5735-ABD4-AF958AC112DB \
  at.gotzendorfer.usbcam
```

## Betrieb

- Querformat, Vollbild, "Bildschirm an lassen" ist standardmaessig aktiv.
  iOS pausiert den Listener, sobald die App in den Hintergrund geht -- die App
  bleibt deshalb waehrend der Aufnahme im Vordergrund.
- Genau **ein** Empfaenger gleichzeitig. Eine zweite Verbindung bekommt
  `ERROR 1 BUSY` und wird geschlossen.
- Bleibt der PING des Mac laenger als 6 Sekunden aus, verwirft die App die
  Verbindung und gibt den Listener frei.
- Farbkonvention fest: NV12 Video-Range, BT.709 (Primaries, Transfer, Matrix).

## Lizenz

MIT, siehe `LICENSE`. Das OBS-Plugin unter `../obs-plugin/` steht getrennt davon
unter GPL-2.0-or-later.
