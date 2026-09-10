# IUCM: iPhone USB Camera Message Protocol, Version 1.2

Stand: 2026-09-10 (1.2: CLIENT_INFO, siehe 4.11; 1.1: Audio, siehe 4.2, 4.9 und 4.10). Normativ fuer `shared/frame_parser.c`, die iOS-App und jeden weiteren
Empfaenger. Wer sich an dieses Dokument haelt, kann eine Swift- und eine C-Implementierung
unabhaengig voneinander schreiben und sie sprechen miteinander.

Konventionen in diesem Dokument:

- Alle Mehrbyte-Felder sind **little-endian**, mit genau **einer** Ausnahme: die
  NAL-Laengenpraefixe in der VIDEO-Nutzlast sind **big-endian** (HVCC-Vorgabe, siehe §4.6).
- `u8`, `u16`, `u32`, `u64` sind vorzeichenlose Ganzzahlen der jeweiligen Bitbreite.
- Offsets sind Byte-Offsets **innerhalb der Nutzlast** (payload), nicht innerhalb des Rahmens.
- Zeichenketten sind UTF-8, **ohne** abschliessendes NUL. Die Laenge steht immer davor.
- Es gibt kein Padding und keine Ausrichtungsanforderung. Alle Strukturen sind dicht gepackt.

## 1. Transport

Das iPhone ist TCP-Server auf Port **7878**. Der Mac erreicht diesen Port ueber den
System-USB-Multiplexer (`/var/run/usbmuxd`, §6). Nach erfolgreichem `Connect` ist der
usbmuxd-Socket ein roher, bidirektionaler Byte-Strom zur App; ab diesem Punkt gilt
ausschliesslich die Rahmung aus §2. Fuer Tests ohne Telefon spricht dasselbe Protokoll
ueber eine gewoehnliche TCP-Verbindung (`--tcp host:port`).

Genau ein Empfaenger pro Geraet. Eine zweite Verbindung beantwortet die App mit
`ERROR` Code 1 (BUSY) und schliesst.

## 2. Rahmung

Jede Nachricht besteht aus einem 12-Byte-Kopf und einer Nutzlast variabler Laenge.

| Offset | Groesse | Feld     | Inhalt                                              |
|--------|---------|----------|-----------------------------------------------------|
| 0      | 4       | magic    | ASCII `IUCM` = `0x49 0x55 0x43 0x4D`                |
| 4      | 1       | type     | Nachrichtentyp (§3)                                 |
| 5      | 1       | flags    | Bit 0 = Keyframe (nur VIDEO), Bits 1-7 = 0          |
| 6      | 2       | reserved | u16, MUSS 0 sein; Empfaenger ignorieren den Wert    |
| 8      | 4       | length   | u32 LE, Laenge der Nutzlast in Byte                 |
| 12     | length  | payload  | Nutzlast                                            |

- **Maximale Nutzlast: 8 MiB (8388608 Byte).** Ein groesseres `length` ist ein Protokollfehler:
  Verbindung schliessen und neu verbinden (Spec §8). Der C-Parser meldet
  `IUCM_ERR_OVERSIZE`.
- `flags` Bit 0 ist nur bei `VIDEO` definiert. Bei allen anderen Typen sendet der Sender 0;
  der Empfaenger wertet das Feld dort nicht aus.
- Unbekannte `type`-Werte werden **uebersprungen**, nicht als Fehler behandelt: Kopf lesen,
  `length` Byte verwerfen, weitermachen. So bleibt Version 1.x vorwaerts-tolerant.
- **Resynchronisation:** Steht am Anfang des Puffers nicht `IUCM`, sucht der Empfaenger
  vorwaerts nach dem naechsten `I` und verwirft alles davor. Das ist die Erholung nach
  einem verlorenen Byte; ein Neuverbinden ist erst noetig, wenn `length` die Obergrenze
  reisst oder der Rahmen semantisch unplausibel ist.

## 3. Nachrichtentypen

| Wert   | Name    | Richtung  | Nutzlast                            |
|--------|---------|-----------|-------------------------------------|
| `0x01` | HELLO   | App → Mac | §4.1, sofort nach Verbindungsaufbau |
| `0x02` | START   | Mac → App | §4.2                                |
| `0x03` | STOP    | Mac → App | leer (length = 0)                   |
| `0x04` | CLIENT_INFO | Mac → App | §4.11, optional, nach HELLO und vor START |
| `0x12` | STATS   | App → Mac | §4.8, 1x pro Sekunde solange verbunden |
| `0x10` | CONFIG  | App → Mac | §4.5                                |
| `0x11` | VIDEO   | App → Mac | §4.6                                |
| `0x13` | AUDIO_CONFIG | App → Mac | §4.9, vor dem ersten AUDIO     |
| `0x14` | AUDIO   | App → Mac | §4.10                               |
| `0x20` | PING    | Mac → App | §4.3, u64 Zeitstempel               |
| `0x21` | PONG    | App → Mac | §4.3, derselbe u64 Zeitstempel      |
| `0x30` | ERROR   | beide     | §4.7                                |

## 4. Nutzlasten

### 4.1 HELLO (`0x01`), App → Mac

| Offset            | Groesse   | Feld            | Inhalt                                    |
|-------------------|-----------|-----------------|-------------------------------------------|
| 0                 | 2         | version         | u16, `major << 8 \| minor`. 1.0 = `0x0100` |
| 2                 | 1         | name_len        | u8, Laenge des Geraetenamens in Byte      |
| 3                 | name_len  | name            | UTF-8, z. B. `iPhone von Bernhard`        |
| 3+name_len        | 1         | app_version_len | u8                                        |
| 4+name_len        | app_v_len | app_version     | UTF-8, z. B. `1.0.0`                      |
| …                 | 1         | camera_count    | u8, Anzahl der folgenden Kamera-Eintraege |

Danach `camera_count` mal, dicht gepackt:

| Groesse  | Feld       | Inhalt                                     |
|----------|------------|--------------------------------------------|
| 1        | id         | u8, Kamera-ID, im START zu wiederholen      |
| 1        | position   | u8: `0` = Rueckseite, `1` = Frontseite      |
| 1        | name_len   | u8                                          |
| name_len | name       | UTF-8, z. B. `Back Wide`             |

Andere `position`-Werte sind reserviert und werden wie `0` behandelt.

**Versionsregel:** Der Mac vergleicht nur das High-Byte (Major). Ist es ungleich 1, sendet
er `ERROR` Code 5 (VERSION_UNSUPPORTED) und schliesst. Ein hoeheres Minor-Byte ist kein
Fehler; unbekannte Zusatzfelder am Ende der Nutzlast werden ignoriert.

**Minor-Semantik von `version`:**

| Wert     | Bedeutung                                                              |
|----------|------------------------------------------------------------------------|
| `0x0100` | 1.0: Grundprotokoll. Kein Audio, kein CLIENT_INFO.                     |
| `0x0101` | 1.1: Audio (§4.2 Bit 0, §4.9, §4.10).                                  |
| `0x0102` | 1.2: zusaetzlich CLIENT_INFO (§4.11). Die App wertet `0x04` aus.       |

Eine App der Version 1.2 meldet `0x0102` in HELLO und akzeptiert weiterhin jeden Empfaenger
der Versionen 1.0 und 1.1: CLIENT_INFO ist optional, sein Ausbleiben ist kein Fehler.
Umgekehrt gilt fuer den Empfaenger: Merkmale werden **ab** einem Minor freigeschaltet, nie
**genau bei** einem. Wer Audio an 1.1 knuepft, prueft `minor >= 1`, damit ein 1.2-HELLO den
Audiowunsch nicht verliert.

### 4.2 START (`0x02`), Mac → App

| Offset | Groesse | Feld         | Inhalt                             |
|--------|---------|--------------|------------------------------------|
| 0      | 1       | camera_id    | u8, aus HELLO                      |
| 1      | 2       | width        | u16, Wunschbreite in Pixel         |
| 3      | 2       | height       | u16, Wunschhoehe in Pixel          |
| 5      | 2       | fps          | u16, Wunsch-Bildrate               |
| 7      | 4       | bitrate_kbps | u32, Ziel-Bitrate in kbit/s        |
| 11     | 1       | flags        | u8, optional (ab 1.1), siehe unten |

**Zwei gueltige Laengen: 11 und 12 Byte.** Bis Version 1.0 war START 11 Byte lang; ab 1.1
haengt der Empfaenger ein `flags`-Byte an. Beide Laengen sind gueltig und muessen von jedem
Empfaenger akzeptiert werden: **wer nur 11 Byte erhaelt, behandelt `flags` als 0.** Eine
Laenge groesser als 12 ist kein Fehler, die Zusatzbytes werden ignoriert (§4.1, Versionsregel).

| Bit | Name  | Bedeutung                                                      |
|-----|-------|-----------------------------------------------------------------|
| 0   | audio | Der Empfaenger wuenscht Audio (AUDIO_CONFIG und AUDIO, §4.9/4.10) |

Bits 1-7 sind reserviert und werden als 0 gesendet.

Ein Sender darf die kurze Form (11 Byte) verwenden, solange `flags == 0` ist; genau das tun
die beiden Swift-Implementierungen. So versteht auch eine App der Version 1.0, die
ueberzaehlige Bytes als Rahmenfehler wertet, ein START ohne Audiowunsch.

**Nachtrag 2026-09-09 (Praxisbefund):** Die ausgelieferte App 1.0 (App Store 0.1.0)
verwirft ein 12-Byte-START nicht als Rahmenfehler, sondern still als Dekodierfehler: die
Verbindung bleibt offen, STATS kommen weiter im Sekundentakt, aber CONFIG und VIDEO
bleiben aus. Ein Sender darf das `flags`-Byte deshalb **nur anhaengen, wenn HELLO
mindestens 1.1 meldet**; gegenueber 1.0 wird der Audiowunsch fallengelassen und die kurze
Form geschickt. OBS-Plugin (ab 0.2.1) und `usbcam-recv` tun genau das; die Mac-App sendet
ohnehin `flags == 0`.

Die App waehlt das naechstliegende unterstuetzte Format und meldet das tatsaechlich aktive
per CONFIG. Standard fuer 1080p30: `bitrate_kbps = 12000`. **Audio wird ausschliesslich
gesendet, wenn Bit 0 im letzten START gesetzt war**; ohne das Bit sendet die App weder
AUDIO_CONFIG noch AUDIO.

### 4.3 PING (`0x20`) / PONG (`0x21`)

| Offset | Groesse | Feld         | Inhalt                        |
|--------|---------|--------------|-------------------------------|
| 0      | 8       | timestamp_us | u64, Mikrosekunden, monotone Uhr des Senders |

Gesamtlaenge 8 Byte. PONG traegt **denselben** Wert unveraendert zurueck; der Mac errechnet
daraus die Umlaufzeit.

**Takt und Totlink:**

- Der Mac sendet alle **2 s** PING.
- **3 fehlende PONG** (also ~6 s ohne Antwort) → Verbindung schliessen und neu verbinden.
- Die App verwirft eine Verbindung, die **6 s** lang kein PING gesehen hat, und gibt den
  Listener frei. Sonst bliebe ein toter Empfaenger fuer immer als BUSY stehen.

### 4.4 STOP (`0x03`), Mac → App

Nutzlast leer, `length = 0`. Die App stoppt die Aufnahme, haelt aber die Verbindung und den
Listener offen; ein neues START ist ohne Neuverbinden moeglich.

### 4.5 CONFIG (`0x10`), App → Mac

| Offset | Groesse  | Feld     | Inhalt                                     |
|--------|----------|----------|--------------------------------------------|
| 0      | 2        | width    | u16, tatsaechlich aktive Breite            |
| 2      | 2        | height   | u16, tatsaechlich aktive Hoehe             |
| 4      | 2        | fps      | u16, tatsaechlich aktive Bildrate          |
| 6      | 4        | hvcc_len | u32 LE, Laenge des hvcC-Records            |
| 10     | hvcc_len | hvcc     | hvcC-Record, unveraendert                  |

Der `hvcC`-Record wird **nicht** selbst gebaut, sondern aus der `CMFormatDescription` des
ersten Keyframes gelesen (`kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms`,
Schluessel `hvcC`). CONFIG kommt vor dem ersten VIDEO und erneut, sobald sich die
Format-Description aendert. Der Empfaenger baut daraus per `CMVideoFormatDescriptionCreate`
die Decoder-Format-Description neu und wartet dann auf den naechsten Keyframe.

### 4.6 VIDEO (`0x11`), App → Mac

| Offset | Groesse  | Feld   | Inhalt                                       |
|--------|----------|--------|----------------------------------------------|
| 0      | 8        | pts_us | u64 LE, Praesentationszeit in Mikrosekunden   |
| 8      | Rest     | nalus  | Folge laengenpraefixierter NAL-Einheiten      |

Ab Offset 8 folgen bis zum Ende der Nutzlast beliebig viele Eintraege der Form:

| Groesse | Feld       | Inhalt                                                       |
|---------|------------|--------------------------------------------------------------|
| 4       | nal_length | u32 **big-endian** (Netzwerk-Byte-Order, HVCC-Konvention)     |
| nal_len | nal_data   | NAL-Einheit ohne Startcode                                    |

- **Nur VCL-NALs.** Keine Parametersaetze in-band (VPS/SPS/PPS stehen im hvcC aus CONFIG),
  kein Annex-B, keine `00 00 00 01`-Startcodes.
- `flags` Bit 0 gesetzt = dieser Zugriffspunkt ist ein Keyframe (IDR).
- Der Empfaenger reicht die Bytes ab Offset 8 **unveraendert** an
  `VTDecompressionSessionDecodeFrame`.
- Ein Rest von 1 bis 3 Byte nach der letzten vollstaendigen NAL ist ein Rahmenfehler
  (`IUCM_ERR_TRUNCATED`), ebenso ein `nal_length`, das ueber das Nutzlastende hinausreicht.
- **Einheiten:** Protokoll-pts sind Mikrosekunden, `obs_source_frame.timestamp` sind
  Nanosekunden. Faktor 1000, angewandt im Plugin.

**Farbkonvention (fix, in Version 1 nicht verhandelbar):** Pixelformat NV12 Video-Range
(`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`), Farbraum BT.709 fuer Primaries,
Transfer und Matrix (ITU-R BT.709-2). Die App setzt das am Capture-Output und am Encoder,
das Plugin setzt `video_format_get_parameters(VIDEO_CS_709, VIDEO_RANGE_PARTIAL, …)` und
`full_range = false`. Es gibt keine Aushandlung; wer davon abweicht, produziert Farbstiche,
die niemand im Protokoll bemerkt.

### 4.7 ERROR (`0x30`), beide Richtungen

| Offset | Groesse  | Feld     | Inhalt                          |
|--------|----------|----------|---------------------------------|
| 0      | 2        | code     | u16, siehe Tabelle              |
| 2      | 2        | text_len | u16, Laenge des Textes in Byte  |
| 4      | text_len | text     | UTF-8, menschenlesbar, optional |

| Code | Name                | Bedeutung                                                      |
|------|---------------------|----------------------------------------------------------------|
| 1    | BUSY                | Es ist bereits ein Empfaenger verbunden. Sender schliesst danach.|
| 2    | CAMERA_DENIED       | Kamerazugriff verweigert (Berechtigung fehlt).                  |
| 3    | FORMAT_UNSUPPORTED  | Kein Format nahe genug am START-Wunsch.                         |
| 4    | ENCODER_FAILED      | VTCompressionSession-Fehler. App baut neu auf und laeuft weiter.|
| 5    | VERSION_UNSUPPORTED | Major-Version aus HELLO unbekannt. Sender schliesst danach.     |
| 6    | MIC_DENIED          | Mikrofonzugriff verweigert. **Nicht fatal:** Video laeuft weiter, es kommt nur kein Audio. |

Codes 7 und hoeher sind reserviert. Ein Empfaenger, der einen unbekannten Code sieht,
protokolliert Code plus Text und behandelt ihn wie einen nicht-fatalen Fehler.

### 4.8 STATS (`0x12`), App → Mac

Ergaenzt 2026-09-05. Geraetetelemetrie, damit der Zustand des Telefons (Lage, Leveller,
Formate) im OBS-Log lesbar ist, ohne das Telefon in die Hand zu nehmen. Die App sendet
**jede Sekunde**, solange ein Empfaenger verbunden ist, auch **wenn nicht gestreamt wird**,
denn genau dann ist der Zustand sonst unsichtbar.

Gesamtlaenge **22 Byte**, dicht gepackt, little-endian:

| Offset | Groesse | Feld                | Inhalt                                            |
|--------|---------|---------------------|---------------------------------------------------|
| 0      | 2       | continuous_angle_x10 | i16, kontinuierlicher Rollwinkel in Grad × 10     |
| 2      | 2       | sector              | u16, quantisierter Sektor: 0, 90, 180 oder 270     |
| 4      | 2       | residual_x10        | i16, tatsaechlich angewandter Restwinkel × 10      |
| 6      | 2       | gravity_m_x1000     | u16, Betrag der Schwerkraft in der Bildebene × 1000 |
| 8      | 2       | leveler_ms_x10      | u16, mittlere Leveller-Zeit je Bild in ms × 10     |
| 10     | 2       | dropped_frames      | u16, seit Verbindungsbeginn verworfene Bilder      |
| 12     | 2       | source_width        | u16, Breite, die die Kamera liefert                |
| 14     | 2       | source_height       | u16                                                |
| 16     | 2       | output_width        | u16, Breite nach dem Leveller (was der Encoder sieht) |
| 18     | 2       | output_height       | u16                                                |
| 20     | 1       | flags               | u8, siehe unten                                    |
| 21     | 1       | camera_id           | u8, aktive Kamera aus HELLO                        |

| Bit | Bedeutung                                                                 |
|-----|---------------------------------------------------------------------------|
| 0   | autoRotation: die Schwerkraft bestimmt den Sektor                        |
| 1   | horizonLeveling: der Leveller ist eingeschaltet                          |
| 2   | oversampling: die Kamera laeuft groesser als die Ausgabe (4K → 1080p)     |
| 3   | flat_hold: das Telefon liegt flach, der Winkel wird gehalten             |
| 4   | audio_active: Audio wird gerade gesendet (ab 1.1)                          |
| 5   | audio_muted: der Nutzer hat das Mikrofon stummgeschaltet (ab 1.1)            |

Bits 6-7 sind reserviert und werden als 0 gesendet. Bits 4 und 5 werden ab 1.1 gesendet:
Bit 4 solange AUDIO-Rahmen ausgehen, Bit 5 solange der Nutzer stummgeschaltet hat. Ein
Empfaenger liest sie rein informativ und leitet daraus keine Zustandswechsel ab.

`residual_x10` ist der **angewandte** Restwinkel (geglaettet und geklemmt), nicht die
geometrische Differenz `continuous - sector`. Letztere ergibt sich aus den beiden
Nachbarfeldern ohnehin; der angewandte Wert macht dagegen sichtbar, wenn der Leveller die
Neigung *nicht* deckt. Faustregel beim Lesen des Logs: weicht `residual` deutlich von
`angle - sector` ab, greift die Klemme (±45°) oder der Sektor haengt hinterher.

Ein Empfaenger, der `0x12` nicht kennt, ueberspringt den Rahmen nach §2: STATS ist
rueckwaertskompatibel und darf ohne Aushandlung gesendet werden.

### 4.9 AUDIO_CONFIG (`0x13`), App → Mac

Ergaenzt in 1.1. Beschreibt den Audiostrom, bevor das erste AUDIO kommt, und erneut, sobald
sich Rate, Kanalzahl oder Codec aendern. Wird nur gesendet, wenn START Bit 0 gesetzt war (§4.2).

| Offset | Groesse | Feld        | Inhalt                                             |
|--------|---------|-------------|----------------------------------------------------|
| 0      | 4       | sample_rate | u32 LE, Abtastrate in Hz, in der Praxis 48000      |
| 4      | 1       | channels    | u8, 1 (mono) oder 2 (stereo)                       |
| 5      | 1       | codec       | u8, `1` = AAC-LC. Andere Werte sind reserviert      |
| 6      | 2       | asc_len     | u16 LE, Laenge des AudioSpecificConfig in Byte     |
| 8      | asc_len | asc         | AudioSpecificConfig, unveraendert                   |

Gesamtlaenge `8 + asc_len`. `asc` ist der Magic Cookie des AudioConverters
(`kAudioConverterCompressionMagicCookie`), typisch 2 Byte, und wird **nicht** selbst gebaut.
Der Empfaenger fuellt daraus seine `AudioStreamBasicDescription` (`mSampleRate` aus
`sample_rate`, `mChannelsPerFrame` aus `channels`, `mFormatID = kAudioFormatMPEG4AAC`,
`mFramesPerPacket = 1024`) und reicht `asc` unveraendert als Magic Cookie an den Decoder
weiter.

Der Codec-Wert wird **durchgereicht, nicht abgelehnt**: ein Empfaenger, der einen unbekannten
Codec sieht, protokolliert ihn und laesst Audio aus, statt die Verbindung zu beenden.
`asc_len = 0` ist auf der Leitung gueltig, fuer AAC-LC aber unbrauchbar: der Sender MUSS den
Cookie mitschicken, der Empfaenger startet ohne ihn keinen Audiopfad.

Ein Empfaenger, der `0x13` nicht kennt, ueberspringt den Rahmen nach §2.

### 4.10 AUDIO (`0x14`), App → Mac

| Offset | Groesse | Feld   | Inhalt                                              |
|--------|---------|--------|------------------------------------------------------|
| 0      | 8       | pts_us | u64 LE, Praesentationszeit in Mikrosekunden          |
| 8      | Rest    | frame  | genau **ein** rohes AAC-Frame (1024 Samples)         |

- `pts_us` laeuft auf **derselben Uhr wie VIDEO** (§4.6). Das ist die einzige Grundlage der
  A/V-Synchronisation; es gibt keinen getrennten Audiotakt und keinen Offset.
- Die Nutzlast ab Offset 8 ist ein einzelnes Access Unit **ohne ADTS-Header**, ohne
  Laengenpraefix und ohne Paketierung mehrerer Frames. Bei 48 kHz entspricht ein Frame
  21333 us.
- Header-`flags` sind bei AUDIO **0**. Bit 0 bedeutet nur bei VIDEO Keyframe (§2).
- Eine leere Nutzlast ab Offset 8 (`length == 8`) ist **kein Rahmenfehler**: der Parser
  liefert ein leeres Frame, der Empfaenger verwirft es. Der Sender darf so etwas nicht
  erzeugen. Diese Regel haelt Audio- und Videopfad im Parser gleich (§4.6 reicht die
  Restbytes ebenfalls unbesehen durch) und erspart der C-Seite einen Sonderfall.
- Kommt AUDIO ohne vorheriges AUDIO_CONFIG, verwirft der Empfaenger den Rahmen und wartet
  auf das CONFIG. Ein Verbindungsabbruch ist das nicht.

Ein Empfaenger, der `0x14` nicht kennt, ueberspringt den Rahmen nach §2. AUDIO_CONFIG und
AUDIO sind damit ohne Aushandlung ueberspringbar, genau wie STATS.

### 4.11 CLIENT_INFO (`0x04`), Mac → App

Ergaenzt in 1.2. Sagt der App, **wer** sich verbunden hat: das OBS-Plugin, die Mac-App
(virtuelle Kamera) oder ein Werkzeug. Ohne diese Nachricht kann die App nur "verbunden"
anzeigen, nicht "verbunden mit ...".

| Offset          | Groesse     | Feld        | Inhalt                                        |
|-----------------|-------------|-------------|-----------------------------------------------|
| 0               | 1           | kind        | u8, siehe Tabelle                             |
| 1               | 1           | name_len    | u8, Laenge des Namens in Byte                 |
| 2               | name_len    | name        | UTF-8, englisch, z. B. `TetherCam for Mac`    |
| 2+name_len      | 1           | version_len | u8                                            |
| 3+name_len      | version_len | version     | UTF-8, z. B. `0.3.0`                          |

Gesamtlaenge `3 + name_len + version_len`. Die Zeichenkettenkodierung ist dieselbe wie in
HELLO (§4.1): u8-Laengenpraefix, UTF-8, **ohne** abschliessendes NUL.

| kind | Empfaenger                                        |
|------|---------------------------------------------------|
| 0    | unbekannt / anderes                               |
| 1    | OBS-Plugin (`TetherCam OBS plugin`)               |
| 2    | Mac-App / virtuelle Kamera (`TetherCam for Mac`)  |
| 3    | Werkzeug (`usbcam-recv`, `usbcam-sim`)            |

**Regeln:**

- `name` und `version` sind **englisch**. Uebersetzt wird ausschliesslich in der anzeigenden
  UI, nie auf der Leitung.
- Unbekannte `kind`-Werte behandelt die App wie `0`; `name` und `version` bleiben erhalten
  und werden angezeigt.
- **Zusatzbytes am Ende der Nutzlast werden ignoriert** (§4.1, Versionsregel). Spaetere
  Minor-Versionen duerfen hier Felder anhaengen.
- Der Empfaenger sendet CLIENT_INFO **einmal**, unmittelbar nachdem er HELLO gelesen hat und
  **vor** START. Ein spaeter eintreffendes CLIENT_INFO ist kein Fehler: die App latcht den
  neuen Inhalt einfach nach.
- Die Nachricht ist **optional**. Ein Empfaenger der Version 1.0/1.1 sendet sie nie, und die
  App verhaelt sich dann exakt wie zuvor (kein Empfaengername).
- Eine App, die `0x04` nicht kennt, ueberspringt den Rahmen nach §2. CLIENT_INFO ist damit
  ohne Aushandlung sendbar, genau wie STATS.
- *(Ergaenzt 2026-09-10, klarstellend, keine Semantikaenderung.)* `name_len` und
  `version_len` sind u8, also bis 255 Byte. Ein Empfaenger mit kuerzeren Puffern
  **kuerzt beim Lesen** und darf die Nachricht deswegen nicht verwerfen; `shared/frame_parser.c`
  behaelt hoechstens 63 Namens- und 31 Versionsbyte. Gekuerzt wird nur auf der Empfangsseite,
  auf der Leitung stehen immer alle Bytes.

## 5. Ablauf

```
App                                  Mac
 |<------------------ TCP/usbmux connect ----|
 |--- HELLO (version, name, cameras) ------->|
 |<-- CLIENT_INFO (kind, name, version) -----|   optional, ab 1.2
 |<-- START (camera_id, w, h, fps, bitrate,  |
 |          flags: Bit 0 = Audio) -----------|
 |--- CONFIG (aktives Format, hvcC) -------->|
 |--- AUDIO_CONFIG (48k, 1ch, AAC, asc) ---->|   nur wenn START Bit 0
 |--- VIDEO (pts, NALs) [flags=1 Keyframe] ->|
 |--- AUDIO (pts, AAC-Frame) --------------->|   nur wenn START Bit 0
 |--- VIDEO ... ---------------------------->|
 |<-- PING (t) --- alle 2 s -----------------|
 |--- PONG (t) ----------------------------->|
 |--- STATS (Lage, Leveller) --- alle 1 s -->|
 |<-- STOP ----------------------------------|
```

Regeln: HELLO ist immer die erste Nachricht der App. START vor HELLO ist ein Protokollfehler.
CLIENT_INFO (§4.11) steht, wenn es ueberhaupt kommt, zwischen HELLO und dem ersten START.
CONFIG kommt immer vor dem ersten VIDEO nach einem START. Nach einem STOP darf ein neues
START folgen; darauf antwortet die App wieder mit CONFIG.

**Audio.** Audio haengt allein an Bit 0 des letzten START (§4.2). Ist es gesetzt, sendet die
App AUDIO_CONFIG vor dem ersten AUDIO und erneut bei jeder Formataenderung; Video und Audio
laufen danach als zwei unabhaengige Nachrichtenstroeme mit derselben Uhr, ohne feste
Reihenfolge zueinander. Ist das Bit nicht gesetzt, kommt weder AUDIO_CONFIG noch AUDIO.
Verweigert der Nutzer den Mikrofonzugriff, sendet die App einmalig `ERROR` Code 6
(MIC_DENIED) und streamt weiter, nur eben ohne Ton. Nach einem STOP mit anschliessendem
neuen START gilt der Audiowunsch des **neuen** START; die App sendet dann wieder ein
AUDIO_CONFIG.

## 6. usbmuxd-Seite

Der Mac spricht zuerst mit `/var/run/usbmuxd` (Unix-Domain-Stream-Socket), um an den
Geraeteport zu kommen. Erst danach gilt §2.

### 6.1 Rahmung

16-Byte-Kopf, alles **little-endian**:

| Offset | Groesse | Feld    | Inhalt                                              |
|--------|---------|---------|-----------------------------------------------------|
| 0      | 4       | length  | u32, Gesamtlaenge **inklusive** dieser 16 Byte      |
| 4      | 4       | version | u32, `1`                                            |
| 8      | 4       | message | u32, `8` = XML-Plist                                |
| 12     | 4       | tag     | u32, frei waehlbar, Antwort traegt denselben Wert   |

Nutzlast: XML-Plist, `length - 16` Byte, ohne abschliessendes NUL.

Belegt: `shared/tests/fixtures/listdevices-req.bin`, erste 16 Byte
`ad01 0000 0100 0000 0800 0000 0100 0000` = length 429, version 1, message 8, tag 1.

### 6.2 Nachrichten

Jede Anfrage traegt zusaetzlich zum `MessageType` die drei Identitaetsfelder
`ClientVersionString` (string), `ProgName` (string) und `kLibUSBMuxVersion` (integer, `3`).

- **ListDevices** → Antwort `DeviceList`: Array von `Attached`-Dicts mit `DeviceID` und
  `Properties` (`ConnectionType`, `SerialNumber`, `ProductID`, `LocationID`,
  `ConnectionSpeed`, bei Netzwerkgeraeten zusaetzlich `NetworkAddress` als `<data>` und
  `EscapedFullServiceName`).
- **Listen** → Antwort `Result`/`Number 0`, danach bleibt die Verbindung offen und liefert
  `Attached`/`Detached`-Ereignisse. **Diese Ereignisse tragen `tag = 0`**, nicht den Tag der
  Listen-Anfrage. Wer nach Tag filtert, sieht nie ein Ereignis.
- **Connect** (`DeviceID`, `PortNumber`) → `Result`/`Number 0`: ab dem naechsten Byte ist der
  Socket ein roher Tunnel. `Number 3`: abgelehnt.
- **Result** → `MessageType Result`, `Number` (integer).

### 6.3 PortNumber ist byte-vertauscht

`PortNumber` steht in **Netzwerk-Byte-Order**, also `htons(port)`, obwohl der Rest des
Protokolls little-endian ist. Auf einer Little-Endian-Maschine heisst das: der Wert im Plist
ist der bytevertauschte Port.

| Port  | korrekter PortNumber  | Fixture                             |
|-------|-----------------------|-------------------------------------|
| 7878  | 50718 (`0xC61E`)      | `connect-7878-req.plist`            |
| 62078 | 32498 (`0x7EE2`)      | `connect-62078-req.plist`           |

**Die Falle:** Ein Port in Host-Order wird mit **demselben** `Result` `Number 3` beantwortet
wie ein geschlossener Port. Es gibt kein eigenes Fehlersignal. `connect-62078-hostorder-req`
schickt `PortNumber 62078` an denselben lockdown-Port, der mit korrekter Byte-Order `Number 0`
liefert, und bekommt `Number 3`. Wer die Byte-Order falsch hat, sucht den Fehler in der App.
Deshalb wird `htons()` in dieser Codebasis **innerhalb** von `usbmux_connect()` angewandt und
ist nie ein Parameter: `usbmux_connect(device_id, 7878)`.

### 6.4 Result-Codes

| Number | Bedeutung                                                     |
|--------|---------------------------------------------------------------|
| 0      | OK                                                            |
| 2      | Geraet unbekannt (Bad Device)                                 |
| 3      | Verbindung abgelehnt: Port zu, App laeuft nicht, **oder** Port in falscher Byte-Order |
| 6      | Bad Version: `version` im Kopf ist nicht 1                   |

### 6.5 Ein Telefon erscheint zweimal

Ein per Kabel angestecktes iPhone mit aktivierter WLAN-Synchronisation steht **zweimal** in
`DeviceList`: einmal mit `ConnectionType "USB"` und einmal mit `"Network"`, mit
**derselben** `SerialNumber` und **unterschiedlicher** `DeviceID`. Der Netzwerkeintrag hat
kein `ProductID` und keine `ConnectionSpeed`, dafuer `NetworkAddress` und
`EscapedFullServiceName`.

Ein `Connect` auf die Netzwerk-DeviceID laeuft ueber WLAN und ist damit genau das, was dieses
Projekt vermeiden will. Deshalb filtert jede Geraeteliste und jedes Attach-Ereignis hart auf
`ConnectionType == "USB"`. `usbmux_list_devices()` liefert Netzwerkgeraete nicht aus.

### 6.6 Zwei Verbindungen

`Connect` verbraucht seine Verbindung (danach roher Tunnel), `Listen` belegt seine dauerhaft.
Das Plugin haelt deshalb **zwei** Sockets: eine Ereignis-Verbindung (Listen) und pro aktivem
Geraet eine Tunnel-Verbindung.

## 7. Aufgezeichnete Fixtures

`shared/tests/fixtures/` enthaelt echte Mitschnitte gegen `/var/run/usbmuxd` auf dem M4-Pro
(2026-09-05, iPhone `00008130-000C0DC40213803A` am Kabel). Jede Datei existiert zweimal:
`.bin` mit 16-Byte-Kopf, `.plist` nur die Nutzlast.

| Datei                            | Inhalt                                                                    |
|----------------------------------|---------------------------------------------------------------------------|
| `listdevices-req`                | ListDevices-Anfrage, tag 1                                                |
| `listdevices-resp`              | zwei Geraete: DeviceID 623 USB und 622 Network, gleiche SerialNumber       |
| `listen-req`                     | Listen-Anfrage, tag 2                                                     |
| `listen-resp-1`                  | Result Number 0 auf Listen, tag 2                                         |
| `listen-resp-1-2`                | Attached-Ereignis DeviceID 623 (USB), **tag 0**                           |
| `listen-resp-1-3`                | Attached-Ereignis DeviceID 622 (Network), tag 0: wird gefiltert           |
| `connect-7878-req` / `-resp`     | Connect auf App-Port 7878 (PortNumber 50718) → **Number 3**, App lief nicht |
| `connect-62078-req` / `-resp`    | Connect auf lockdown 62078 (PortNumber 32498) → **Number 0**              |
| `connect-62078-hostorder-req`/`-resp` | derselbe Port in Host-Order (62078) → **Number 3**, der Beleg fuer §6.3 |
| `badversion-0-resp`, `badversion-2-resp` | Antwort auf Kopf-`version` 0 bzw. 2 → **Number 6**, tag 9         |

Daneben liegt ein handgeschriebener Goldwert der IUCM-Rahmung selbst — kein Mitschnitt,
sondern der normative Bytevergleich fuer §4.11:

| Datei                  | Inhalt                                                                     |
|------------------------|----------------------------------------------------------------------------|
| `clientinfo-macapp.bin` | Ein vollstaendiger CLIENT_INFO-Rahmen: kind 2, name `TetherCam for Mac`, version `0.3.0` |

`connect-62078` ist der positive Beleg: der lockdown-Port ist immer offen, also trennt er
"Byte-Order richtig" von "App laeuft nicht". Ein Verbindungsproblem debuggt man mit 62078,
nicht mit 7878.

## 8. Referenzimplementierung

`shared/frame_parser.h/.c` (Rahmung, Codierung, Decodierung) und `shared/usbmux.h/.c`
(usbmuxd-Client plus handgeschriebener Plist-Codec). Pure C11, keine Apple-Frameworks,
baut und testet auf macOS und Linux:

```
cmake -S shared -B shared/build && cmake --build shared/build && ctest --test-dir shared/build --output-on-failure
```

`tools/usbcam-sim` und `tools/usbcam-recv` bilden den Audio-Teil (4.9/4.10) mit ab: der
Simulator sendet einen 440-Hz-AAC-Ton, der Empfaenger dekodiert ihn und meldet
`audio_frames`, `audio_sample_rate` und `audio_video_pts_skew_ms` in seiner
JSON-Zusammenfassung (`tools/README.md`).
