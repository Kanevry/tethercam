# tools — Werkzeuge fuer obs-iphone-usb-cam

Swift-Paket (macOS 13+, swift-tools-version 5.9) mit dem Protokoll-Codec und dem
Sender-Simulator. Damit laesst sich der Empfaenger und spaeter das OBS-Plugin ohne
iPhone testen.

## Inhalt

| Target | Art | Zweck |
|---|---|---|
| `IucmProtocol` | Library | Codec + zustandsbehafteter Frame-Parser fuer das Drahtprotokoll (`protocol/PROTOCOL.md`) |
| `usbcam-sim` | Executable | Sender-Simulator: bewegtes Testbild, HEVC per VideoToolbox, TCP-Server |

`usbcam-recv` (CLI-Empfaenger) kommt als weiteres Executable-Target in dieselbe
`Package.swift`.

## Bauen und testen

```sh
swift build -c release --package-path tools
swift test --package-path tools
```

## usbcam-sim

```sh
usbcam-sim [--bind HOST] [--port PORT] [--dump FILE]
```

- `--bind` lokale Adresse, Vorgabe `127.0.0.1`
- `--port` TCP-Port, Vorgabe `7878`
- `--dump` schreibt den kodierten Strom zusaetzlich als Annex-B-HEVC (mit
  Parametersaetzen vor jedem Keyframe), damit `ffplay`/`ffmpeg` ihn unabhaengig
  pruefen koennen

Beispiel:

```sh
./tools/.build/release/usbcam-sim --dump /tmp/out.hevc
ffplay /tmp/out.hevc
```

Verhalten: Nach `accept` geht sofort HELLO raus (eine Kamera, `id 0`, Name
`Simulator`). Nach START werden Renderer und Encoder aufgesetzt; CONFIG mit dem
`hvcC` aus der Format-Description des ersten Keyframes geht vor dem ersten
VIDEO-Frame raus und erneut, sobald sich die Format-Description aendert. VIDEO
traegt die von VideoToolbox erzeugten NAL-Einheiten unveraendert (4-Byte-BE-Laenge,
kein Annex-B). PING wird mit PONG beantwortet, eine zweite Verbindung bekommt
ERROR 1 BUSY, STOP beendet den Strom und laesst die Verbindung offen. Pro Sekunde
geht eine Statuszeile (fps, kbps, Keyframes) nach stderr.

Farbkonvention fix laut Spec: NV12 Video-Range, BT.709 in Primaries, Transfer und
Matrix — am Pixelpuffer und am Encoder gesetzt.

**Totlink:** Die 6-Sekunden-Regel wird erst scharf, nachdem der Empfaenger den
ersten PING geschickt hat. Ein Empfaenger, der noch gar nicht pingt, wird also
nicht mitten im Handshake abgeraeumt.

## Protokoll-Probe

`scripts/probe_sim.py` ist ein Smoke-Test ohne Abhaengigkeiten (nur Python-stdlib):
verbindet, liest HELLO, schickt START, liest CONFIG, zaehlt VIDEO-Frames, prueft
das PONG-Echo und schickt STOP. Exit-Code ungleich 0 bei jedem Protokollverstoss.

```sh
./tools/.build/release/usbcam-sim --port 7878 &
python3 tools/scripts/probe_sim.py --seconds 3
```

## Lizenz

MIT, siehe `LICENSE`.
