# TetherCam (iOS-App)

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
                    HorizonLeveler.swift  stufenlose Horizontbegradigung (CoreImage/Metal)
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
xcodegen generate            # erzeugt TetherCam.xcodeproj
```

## Bauen

```sh
# Geraete-Build (Signierung Team G3QZ66475M, automatisch)
xcodebuild -project TetherCam.xcodeproj -scheme TetherCam \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates -derivedDataPath build build

# Unit-Tests (kein Geraet, keine Kamera noetig)
xcodebuild test -project TetherCam.xcodeproj -scheme TetherCam \
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
  build/Build/Products/Debug-iphoneos/TetherCam.app

# App starten
xcrun devicectl device process launch \
  --device 8CDB11B5-13E8-5735-ABD4-AF958AC112DB \
  at.gotzendorfer.tethercam
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

## Horizont begradigen

Der Sektor kennt nur 0/90/180/270. Ein Stativkopf, der 8 Grad schief steht,
liefert also ein 8 Grad schiefes Bild - genau das, was in OBS zu sehen war.
Der Schalter **"Horizont begradigen"** (Standard **an**, gespeichert) dreht
diesen Rest stufenlos weg, so wie Continuity Camera es tut.

Ablauf pro Bild: Capture -> `HorizonLeveler` -> Encoder. Der Zeitstempel des
Originals wandert unveraendert mit.

- **Restwinkel.** `residual = continuous - sector`, kuerzester Weg, also
  `(-180, 180]`. Die Verbindung hat den Sektor schon angewandt; genau der Rest
  fehlt noch.
- **Vorzeichen.** `videoRotationAngle` zaehlt im Uhrzeigersinn, CoreImage rechnet
  in y-up-Koordinaten gegen den Uhrzeigersinn - deshalb dreht der Leveller um
  `-residual`. Gegenprobe im Test: 10 Grad gegen den Uhrzeigersinn gerollt gibt
  Schwerkraft `(-cos 10, sin 10)`, stufenlos 350 Grad, Rest -10 Grad.
- **Fuellzoom.** Nach der Drehung wuerden Ecken leer bleiben. Der Leveller
  skaliert deshalb um `s = cos d + sin d * max(W/H, H/W)` (minimal moeglicher
  Wert, im Test gegen die Eckgeometrie geprueft) und schneidet mittig auf die
  Zielgroesse. Bei 15 Grad sind das 1,43x.
- **Ueberabtastung.** Damit der Zuschnitt keine Aufloesung kostet, waehlt die
  Formatwahl bei aktiver Begradigung eine Stufe groesser, wenn das Geraet sie mit
  der geforderten Bildrate kann: 3840x2160 fuer 1080p, 1920x1080 fuer 720p.
  Kann es das nicht, bleibt die Quelle gleich gross und der Fuellzoom kostet
  Schaerfe (bei 15 Grad rund 30 Prozent der linearen Aufloesung). Was gewaehlt
  wurde, steht im Log: `capture format 3840x2160@30 oversampling=1 output=1920x1080`.
- **Glaettung.** Der gerenderte Winkel ist ein exponentiell geglaetteter Wert
  (Zeitkonstante 0,8 s) mit Totband 0,3 Grad. Unter `m < 0,12` (flach) friert er
  ein, genau wie der Sektor.
- **Deckel bei 25 Grad.** Die Sektor-Hysterese laesst den Rest waehrend eines
  Schwenks bis 60 Grad wachsen; das voll auszugleichen hiesse kurzzeitig 2x
  Zoom. Der Rest wird deshalb auf +/-25 Grad begrenzt: waehrend des Drehens
  bleibt eine sichtbare Schraege, danach steht das Bild gerade.
- **Nur im Automatikbetrieb.** Ein manuell gesetzter Winkel ist eine bewusste
  Entscheidung; dagegen dreht der Leveller nicht an.
- **Renderpfad.** CoreImage rendert mit einem Metal-`CIContext`
  (`workingColorSpace` nil, keine Zwischenpuffer) direkt in einen NV12-Puffer aus
  einem `CVPixelBufferPool`. Ob das geht, wird beim Start einmal geprueft
  (64x64-Graubild rein, Luma raus); scheitert es, faellt der Pfad auf BGRA
  zurueck und VideoToolbox konvertiert. Das Log sagt welcher:
  `[usbcam] leveler render path=nv12`. Die BT.709-Anhaenge des Quellpuffers
  werden auf den Ausgabepuffer uebertragen.
- **Kein Rueckstau.** Ist der Leveller noch beschaeftigt, wird das neue Bild
  verworfen, nicht eingereiht. Verworfene Bilder stehen in der Diagnose und im
  Log.
- **Diagnose.** Seitenleiste: `Rest +7.9 Grad  3.1 ms  drop 0`. Log alle 5 s:
  `[usbcam] leveler avg=3.10ms src=3840x2160 out=1920x1080 fps=30.0 dropped=0
  residual=7.9 path=nv12 leveling=1`.
- **Budgetwaechter.** Bleibt der Schnitt ueber 12 ms/Bild, waehrend
  ueberabgetastet wird, faellt die Quelle automatisch auf die angeforderte
  Groesse zurueck (`leveler over budget ... oversampling disabled`). Ziel ist
  1080p30 unter 8 ms/Bild.

## Lizenz

MIT, siehe `LICENSE`. Das OBS-Plugin unter `../obs-plugin/` steht getrennt davon
unter GPL-2.0-or-later.
