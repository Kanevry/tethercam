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
                    OrientationSensor.swift  Lage aus der Schwerkraft (CoreMotion)
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

## Bildlage

Die Drehung wird an der Video-Data-Output-Verbindung gesetzt, also **vor** dem
Encoder. Ein Hochformat-Halter liefert deshalb ehrlich einen 1080x1920-Strom;
der Encoder bemerkt die geaenderte Geometrie und schickt ein frisches CONFIG.

**Automatik (Standard) misst die Schwerkraft**, nicht den Horizont. CoreMotion
liefert alle 100 ms den Gravitationsvektor; aus seinem Anteil in der
Bildschirmebene ergibt sich der Rollwinkel:

| Lage (physisch)                  | Winkel |
|----------------------------------|--------|
| Hochformat, aufrecht             | 90     |
| Querformat, Ladebuchse rechts    | 0      |
| Querformat, Ladebuchse links     | 180    |
| Hochformat, ueber Kopf           | 270    |

Das ist die Konvention vor dem iPhone 17, die das iPhone 15 Pro Max benutzt
(`videoRotationAngle` 0 = landscapeRight, 90 = portrait, 180 = landscapeLeft,
270 = portraitUpsideDown).

- **Steile Neigung funktioniert.** `AVCaptureDevice.RotationCoordinator` leitet
  seinen Winkel aus dem Horizont ab; zeigt das Stativ steil nach oben oder unten,
  ist kein Horizont im Bild und der Wert friert ein - genau der gemeldete Fehler
  ("manchmal richtig herum"). Die Schwerkraft hat diese Luecke nicht.
- **Flach-Rueckfall.** Erst wenn der Betrag in der Bildebene
  `m = sqrt(gx^2 + gy^2)` unter 0,12 faellt (Kamera praktisch senkrecht nach
  unten oder oben), ist der Rollwinkel numerisch bedeutungslos; dann bleibt der
  zuletzt bekannte Winkel stehen.
- **Hysterese.** Gewechselt wird erst, wenn der stufenlose Winkel die
  45-Grad-Sektorgrenze um mehr als 15 Grad ueberschreitet **und** der neue
  Sektor 300 ms stabil ist. Ein Schwenk ueber die Grenze schaltet also nicht hin
  und her.
- **Diagnose am Stativ.** Die Seitenleiste zeigt `Lage: 90 Grad (m=0.85)` plus
  den rohen stufenlosen Winkel. Im Log steht dieselbe Information samt Quelle
  und dem Vergleichswert des Coordinators:
  `[usbcam] rotation angle=90 source=sensor m=0.85 cont=88 coordinator=90 auto=1`.
  Bei normaler Haltung muessen `angle` und `coordinator` uebereinstimmen; sie
  laufen genau im Steilfall auseinander.
- **Manuell.** "Auto-Rotation" aus, dann gilt der fest gewaehlte Winkel
  0/90/180/270. Der Vorschau-Layer folgt weiterhin dem Coordinator, das ist rein
  kosmetisch.

Eine stufenlose Horizontbegradigung (Pixelpuffer per CoreImage um den exakten
Winkel drehen) ist bewusst **nicht** eingebaut: sie kostet pro Bild einen
GPU-Umweg und einen zweiten NV12-Pool. Der TODO steht in
`Sources/Capture/OrientationSensor.swift`.

## Lizenz

MIT, siehe `LICENSE`. Das OBS-Plugin unter `../obs-plugin/` steht getrennt davon
unter GPL-2.0-or-later.
