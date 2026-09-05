# obs-plugin: OBS-Quelle "TetherCam (iPhone via USB)"

macOS-Plugin fuer OBS Studio. Empfaengt den HEVC-Strom der iOS-App ueber den
System-USB-Multiplexer (`/var/run/usbmuxd`), dekodiert ihn per VideoToolbox und
liefert ihn als asynchrone Videoquelle. Protokoll: `../protocol/PROTOCOL.md`.

- Quellen-ID: `iphone_usb_camera`
- Bundle-ID: `at.gotzendorfer.obs-iphone-usb-cam`
- Lizenz: GPL-2.0-or-later (`LICENSE`). Der C-Kern unter `../shared/` ist MIT und
  wird direkt mitkompiliert.

## Aufbau

| Datei | Zweck |
|---|---|
| `src/plugin-main.c` | Modul-Einstieg, registriert die Quelle |
| `src/hevc_decoder.h/.mm` | VTDecompressionSession aus dem `hvcC`-Record, Ausgabe NV12 Video-Range |
| `src/iphone_source.h/.mm` | `obs_source_info`, Eigenschaften, Empfangs-Thread, Wiederverbindung |
| `../shared/frame_parser.c` | IUCM-Rahmenparser (mitkompiliert) |
| `../shared/usbmux.c` | usbmuxd-Client (mitkompiliert) |

## Bauen

Erster Lauf laedt libobs-Quellen und obs-deps nach `.deps/` (rund 1 GB, gitignored).

```sh
cd obs-plugin
CODESIGN_IDENT="Apple Development: <Name> (<ID>)" \
CODESIGN_TEAM=<TEAM> \
CI=1 cmake --preset macos
cmake --build --preset macos
```

**`CI=1` ist noetig.** Ohne die Variable (oder ohne `-DPLUGIN_BUILD_NUMBER=1`) bricht
das erste `configure` in `cmake/common/buildnumber.cmake` ab, ein Fehler der Vorlage,
nicht dieses Repos. Der Xcode-Generator ist Pflicht; gebaut wird universal
(`arm64;x86_64`). Auf reines arm64 einschraenken: `-DCMAKE_OSX_ARCHITECTURES=arm64`.

Ergebnis: `build_macos/RelWithDebInfo/obs-iphone-usb-cam.plugin`.

## Installieren

```sh
cp -R build_macos/RelWithDebInfo/obs-iphone-usb-cam.plugin \
      ~/Library/Application\ Support/obs-studio/plugins/
```

Wirkt erst nach einem OBS-Neustart. Kontrolle im neuesten Log unter
`~/Library/Application Support/obs-studio/logs/`: `obs-iphone-usb-cam` muss unter
`Loaded Modules:` stehen.

## Eigenschaften der Quelle

| Feld | Schluessel | Bedeutung |
|---|---|---|
| iPhone (USB) | `device_serial` | Liste aus `usbmux_list_devices`, nur USB. Leer = erstes angestecktes Geraet. Beschriftet mit der Seriennummer, weil iOS den HELLO-Namen auf "iPhone" kuerzt |
| Kamera | `camera_id` | Vor dem ersten HELLO statische Liste (Back Wide, Back Ultra Wide, Back Telephoto, Front); danach die Namen aus dem HELLO des Geraets |
| Aufloesung | `resolution` | `1280x720` oder `1920x1080` |
| Bildrate | `fps` | 30 oder 60 |
| Bitrate | `bitrate_kbps` | Vorgabe 12000 |
| Debug-TCP | `debug_tcp` | `host:port`; gesetzt umgeht die Quelle usbmuxd und verbindet direkt per TCP |

Aenderungen an den Eigenschaften bauen die Verbindung sofort neu auf.

## Test ohne iPhone (Simulator)

```sh
swift build -c release --package-path ../tools
../tools/.build/release/usbcam-sim --port 7878
```

In OBS eine Quelle "TetherCam (iPhone via USB)" anlegen und im Feld **Debug-TCP**
`127.0.0.1:7878` eintragen. Das Log zeigt dann:

```
[iphone-cam] connected via debug_tcp 127.0.0.1:7878
[iphone-cam] HELLO from '...' (app 0.1.0, proto 1.0, 1 cameras)
[iphone-cam] START sent: cam 0, 1920x1080@30, 12000 kbps
[iphone-cam] CONFIG received: 1920x1080@30, hvcC 110 bytes
[iphone-cam] first frame decoded (pts ... us)
[iphone-cam] 30.2 frames/s
```

Ohne GUI-Klicks geht es ueber eine vorbereitete Szenensammlung: eine
`~/Library/Application Support/obs-studio/basic/scenes/<name>.json` mit einer Quelle
der ID `iphone_usb_camera` anlegen und OBS mit
`--multi --collection <name>` starten. `--multi` ist noetig, damit eine bereits
laufende OBS-Instanz unberuehrt bleibt.

## Verhalten bei Stoerungen

- Kein Geraet, usbmuxd nicht erreichbar, Verbindung abgelehnt: Wiederholung mit
  Backoff 1 s → 5 s, ohne Absturz und ohne Log-Flut.
- Kaputte Rahmung oder Nutzlast > 8 MiB: Verbindung schliessen, neu verbinden.
- 3 fehlende PONG (~6 s ohne Antwort): neu verbinden.
- Dekoderfehler: Frame verwerfen; nach 3 Fehlern in Folge Session neu aufbauen und
  auf den naechsten Keyframe warten.
- Verbindung weg: `obs_source_output_video2(source, NULL)` raeumt das letzte Bild ab.
- Beim Loeschen der Quelle wird der Empfangs-Thread beendet und gejoint.
