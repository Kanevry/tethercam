# tools: Werkzeuge fuer TetherCam (Repo obs-iphone-usb-cam)

Swift-Paket (macOS 13+, swift-tools-version 5.9) mit dem Protokoll-Codec und dem
Sender-Simulator. Damit laesst sich der Empfaenger und spaeter das OBS-Plugin ohne
iPhone testen.

## Inhalt

| Target | Art | Zweck |
|---|---|---|
| `IucmProtocol` | Library | Codec + zustandsbehafteter Frame-Parser fuer das Drahtprotokoll (`protocol/PROTOCOL.md`) |
| `usbcam-sim` | Executable | Sender-Simulator: bewegtes Testbild, HEVC per VideoToolbox, TCP-Server |
| `CUsbmux` | C-Target | Bindet `shared/usbmux.c` ein (usbmuxd-Tunnel) |
| `usbcam-recv` | Executable | CLI-Empfaenger ueber TCP oder usbmuxd |

**Zu `CUsbmux`:** SwiftPM verlangt alle Quellen eines Targets unterhalb des
Paketverzeichnisses, `shared/` liegt aber daneben. Statt Symlinks (deren
Aufloesung SwiftPM je nach Version unterschiedlich handhabt) enthaelt
`Sources/CUsbmux/shim.c` nur ein `#include "../../../shared/usbmux.c"`, der
oeffentliche Header `Sources/CUsbmux/include/CUsbmux.h` analog ein
`#include` von `shared/usbmux.h`. Es gibt also keine Kopie: der Wahrheitsort
bleibt `shared/`, gebaut wird per CMake (C-Tests) und per SwiftPM (dieses Paket).

## Bauen und testen

```sh
swift build -c release --package-path tools
swift test --package-path tools
```

## usbcam-sim

```sh
usbcam-sim [--bind HOST] [--port PORT] [--dump FILE] [--no-audio]
```

- `--bind` lokale Adresse, Vorgabe `127.0.0.1`
- `--port` TCP-Port, Vorgabe `7878`
- `--dump` schreibt den kodierten Strom zusaetzlich als Annex-B-HEVC (mit
  Parametersaetzen vor jedem Keyframe), damit `ffplay`/`ffmpeg` ihn unabhaengig
  pruefen koennen
- `--no-audio` haelt den Sinuston auch dann zurueck, wenn das START-Flags-Byte
  Bit 0 (Audio) setzt

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
Matrix, am Pixelpuffer und am Encoder gesetzt.

Sendet zusaetzlich einen 440-Hz-Sinuston als AAC-LC (48 kHz, mono, 96 kbps), sobald
das START-Flags-Byte Bit 0 setzt: erst `AUDIO_CONFIG`, danach `AUDIO`-Frames im
1024-Sample-Takt, auf derselben Uhr wie VIDEO (PROTOCOL.md 4.9/4.10).

**Totlink:** Die 6-Sekunden-Regel wird erst scharf, nachdem der Empfaenger den
ersten PING geschickt hat. Ein Empfaenger, der noch gar nicht pingt, wird also
nicht mitten im Handshake abgeraeumt.

## usbcam-recv

```sh
usbcam-recv [--tcp HOST:PORT | --serial UDID] [--port N] [--camera N]
            [--size WxH] [--fps N] [--bitrate KBPS]
            [--dump FILE] [--dump-audio FILE] [--no-audio]
            [--seconds N] [--json] [--hello-timeout S]
```

- `--tcp HOST:PORT` gewoehnliches TCP, also gegen `usbcam-sim`. Ohne diese Option
  laeuft die Verbindung durch `/var/run/usbmuxd`.
- `--serial UDID` waehlt das iPhone per Seriennummer; ohne Angabe das erste
  USB-Geraet aus `usbmux_list_devices()`. Die `DeviceID` wechselt nach jedem
  Neustart des Telefons, die Seriennummer nicht, deshalb ist `--serial` der
  stabile Weg. Netzwerkgeraete werden nie ausgewaehlt (PROTOCOL.md 6.5).
- `--port` ist der Geraeteport im Tunnel, Vorgabe 7878. `htons()` passiert in
  `usbmux_connect()`, nie hier (PROTOCOL.md 6.3).
- `--size/--fps/--bitrate/--camera` fuellen das START, Vorgaben `1920x1080`,
  `30`, `12000` kbps, Kamera `0`.
- `--dump FILE` schreibt Annex-B-HEVC: die Parametersaetze aus dem `hvcC` der
  CONFIG stehen vor jedem Keyframe, die NALs bekommen Startcodes. Die
  Wire-Nutzlast selbst bleibt unangetastet laengenpraefixiert.
- `--dump-audio FILE` schreibt den AAC-Strom als ADTS (mit Header vor jedem
  Access-Unit), damit `ffprobe`/`ffplay` ihn unabhaengig lesen koennen. Die
  Wire-Nutzlast selbst traegt kein ADTS (PROTOCOL.md 4.10).
- `--no-audio` loescht Bit 0 im START-Flags-Byte: die Gegenseite schickt dann
  weder `AUDIO_CONFIG` noch `AUDIO`. Ohne die Option fordert `usbcam-recv`
  Audio standardmaessig an.
- `--seconds N` sendet nach N Sekunden ab CONFIG ein STOP und endet mit 0.
- `--json` gibt am Ende eine Zeile auf stdout aus: `frames`, `fps_avg`,
  `kbps_avg`, `keyframes`, `ping_rtt_ms_avg`, `first_frame_ms`, `nals`,
  `width`, `height`, dazu die Audio-Felder `audio_frames`,
  `audio_decoded_samples`, `audio_sample_rate`, `audio_first_frame_ms` und
  `audio_video_pts_skew_ms` (erstes AUDIO-pts minus erstes VIDEO-pts, in ms).
  Alle Logzeilen gehen nach stderr, stdout bleibt sauber.

Waehrend des Laufs geht pro Sekunde eine Zeile nach stderr (fps, kbps,
Keyframes, NAL-Zahl, letzte PING-Umlaufzeit). PING geht alle 2 s raus, drei
ausgebliebene PONG (~6 s) beenden den Lauf.

Exit-Code ungleich 0 mit Klartext bei: falschem Magic beziehungsweise
uebergrossem `length`, VIDEO vor CONFIG, nicht monotoner `pts`, Major-Version
ungleich 1, ERROR der Gegenseite, ausbleibendem HELLO (`--hello-timeout`,
Vorgabe 3 s) und abgelehntem Tunnel.

```sh
# gegen den Simulator
./tools/.build/release/usbcam-sim --port 7979 &
./tools/.build/release/usbcam-recv --tcp 127.0.0.1:7979 --size 1280x720 \
    --seconds 5 --dump /tmp/out.hevc --json

# gegen das iPhone am Kabel
./tools/.build/release/usbcam-recv --serial 00008130-000C0DC40213803A --seconds 3
```

## integration.sh

`tools/integration.sh` ist die Abnahme ohne iPhone und wiederholbar: baut das
Paket in Release, startet `usbcam-sim` auf Port 7979 (per `IUCM_PORT`
umstellbar), laesst `usbcam-recv` 5 s in `/tmp/iucm-int.hevc` (Video) und
`/tmp/iucm-int-audio.aac` (Audio als ADTS) aufzeichnen und prueft die
JSON-Zusammenfassung gegen `fps_avg >= 25`, `keyframes >= 4`,
`first_frame_ms < 1500`, `ping_rtt_ms_avg < 50`, `audio_frames >= 100`,
`audio_sample_rate == 48000` und `|audio_video_pts_skew_ms| <= 50`. Danach
dekodiert `ffmpeg` einen Frame nach `/tmp/iucm-int.png` und `ffprobe` muss
`1280x720` melden; ein zweites `ffprobe` auf dem ADTS-Dump muss `aac,48000,1`
melden (Codec, Sample-Rate, Kanaele). Beendet wird nur der selbst gestartete
Simulator, per gemerkter PID, nie per `pkill`. Pfade zu ffmpeg/ffprobe ueber
`FFMPEG=`/`FFPROBE=` ueberschreibbar.

```sh
bash tools/integration.sh
```

## vcam-test.sh

`tools/vcam-test.sh` ist die simulierte Abnahme der macOS-Virtual-Camera
(`mac-app/`, CoreMediaIO-Camera-Extension "TetherCam") ohne iPhone: startet
`usbcam-sim` (Port 7979, `IUCM_PORT`), laesst die Host-App headless mit
`--debug-tcp 127.0.0.1:PORT` den Strom in die Extension schieben, wartet bis
`ffmpeg -f avfoundation -list_devices` die Kamera "TetherCam" listet (max 20 s),
nimmt 3 s (`VCAM_SECONDS`) in `1920x1080` NV12 nach `/tmp/vcam-test/cam.mp4` auf
und prueft per `ffprobe` `1920x1080`, `fps >= 25`, `frames >= 50`; danach muessen
zwei Frames (0,3 s und 1,5 s) per PSNR unter 45 dB liegen (`inf` = Standbild =
FAIL). Mit `VCAM_BROWSER=1` zaehlt zusaetzlich `agent-browser` die Kamera per
`getUserMedia`/`enumerateDevices` auf. Bei jedem Fehler kommt der Schluss von
`/tmp/vcam-test/app.log`, bei PASS die letzte `tethercam:`-Statuszeile der App.

Vorbedingungen (einmalig): Extension per `bash mac-app/scripts/install-local.sh`
registrieren und unter System Settings > General > Login Items & Extensions >
Camera Extensions freigeben; das Terminal braucht Kamera-Zugriff (Privacy &
Security > Camera). App-Pfad: `/Applications/TetherCam.app`, sonst
`mac-app/build/Build/Products/Release/TetherCam.app`, per `VCAM_APP` uebersteuerbar.

Exit-Codes: `0` PASS, `1` FAIL (Klartext, App-Log-Tail), `3` Extension wartet auf
die Freigabe in den Systemeinstellungen (`BLOCKED: approve ...`), `4` Extension
nicht registriert (`BLOCKED: extension not registered ...`). Beendet werden nur
die selbst gestarteten Prozesse per PID. Weitere Variablen: `VCAM_NAME`,
`VCAM_EXT_ID`, `FFMPEG`, `FFPROBE`, `AGENT_BROWSER`.

```sh
bash tools/vcam-test.sh
VCAM_BROWSER=1 bash tools/vcam-test.sh
```

## Protokoll-Probe

`scripts/probe_sim.py` ist ein Smoke-Test ohne Abhaengigkeiten (nur Python-stdlib):
verbindet, liest HELLO, schickt START, liest CONFIG, zaehlt VIDEO-Frames, prueft
das PONG-Echo und schickt STOP. Exit-Code ungleich 0 bei jedem Protokollverstoss.

```sh
./tools/.build/release/usbcam-sim --port 7878 &
python3 tools/scripts/probe_sim.py --seconds 3
```

## usbmux_recv.py

`scripts/usbmux_recv.py` ist derselbe Empfaenger noch einmal, aber in reinem
Python-stdlib und direkt gegen `/var/run/usbmuxd`: ListDevices, Filter auf
`ConnectionType == "USB"`, Connect mit `htons(7878)`, danach der Handshake aus
`probe_sim.py`. Der Rueckfallweg fuer das echte Telefon, falls der Swift-Wrapper
um `shared/usbmux.c` sich seltsam verhaelt, beide Wege koennen so gegeneinander
gehalten werden, ohne dass ein Fehler in einer Schicht die andere verdeckt.

```sh
python3 tools/scripts/usbmux_recv.py --list
python3 tools/scripts/usbmux_recv.py --serial 00008130-000C0DC40213803A \
    --seconds 5 --size 1280x720 --dump /tmp/iphone.hevc
```

Optionen: `--serial`, `--port`, `--camera`, `--size`, `--fps`, `--bitrate`,
`--seconds`, `--dump`, `--timeout`, `--list`. `--dump` schreibt Annex-B mit den
Parametersaetzen aus dem `hvcC` vor jedem Keyframe.

## Lizenz

MIT, siehe `LICENSE`.
