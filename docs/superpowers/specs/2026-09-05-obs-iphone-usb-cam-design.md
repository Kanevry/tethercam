# obs-iphone-usb-cam: Design

Datum: 2026-09-05. Status: Entwurf, freigegeben vom Owner fuer die Prototyp-Phase.

## 1. Problem

Continuity Camera liefert nach dem iOS-Update 26.6 auf einem Mac mit macOS 26.5.2 nur
Schwarzbild (Handshake ok, Videostream kommt nie zustande; Log:
`invalid stream for ContinuityCaptureControl`). Aufnahmen mit dem iPhone auf dem Tripod
in OBS sind damit blockiert. Bestehende Drittanbieter-Loesungen (Camo, Camera for OBS
Studio) sind bezahlt, closed source und ausserhalb unserer Kontrolle.

Ziel: Ein eigenes, offenes Werkzeug, das das iPhone-Kamerabild per USB-Kabel in OBS
bringt, unabhaengig von Continuity Camera, WLAN, VPN und Firewall.

## 2. Scope

**Drin (Prototyp):**
- iOS-App, die die Kamera aufnimmt, per Hardware HEVC kodiert und ueber USB ausliefert.
- OBS-Quell-Plugin fuer macOS, das den Stream ueber den System-USB-Multiplexer
  (`/var/run/usbmuxd`) empfaengt, dekodiert und als Quelle "iPhone USB Camera" liefert.
- Dokumentiertes Drahtprotokoll, damit andere Empfaenger andocken koennen.
- CLI-Empfaenger und Sender-Simulator fuer Tests ohne OBS bzw. ohne Telefon.

**Draussen (spaeter, eigene Specs):**
- Virtuelle Kamera als macOS Camera Extension (CMIO), damit das Bild auch in Zoom,
  FaceTime, Safari erscheint. Nutzt denselben Empfangskern.
- Audio vom iPhone (Shure haengt direkt am Mac).
- WLAN-Transport, Windows/Linux-Plugin, App-Store-Release, TestFlight.
- Steuerung von Fokus, Belichtung, Zoom aus OBS heraus.

## 3. Architektur

```
iPhone (Swift)                          Mac
+----------------------+                +------------------------------+
| AVCaptureSession     |   USB-Kabel    | OBS-Plugin (ObjC++)          |
| VTCompressionSession | -------------> |  UsbmuxClient (C)            |
| HEVC, realtime       |   usbmuxd      |  FrameParser (C)             |
| NWListener TCP :7878 |                |  VTDecompressionSession      |
+----------------------+                |  obs_source_output_video     |
                                        +------------------------------+
```

- Das iPhone ist TCP-Server auf Port 7878 (nur lokal, kein WLAN-Interface noetig; der
  Multiplexer tunnelt USB-Verbindungen zu Geraeteports).
- Der Mac verbindet sich ueber den usbmuxd-Unix-Socket mit dem Plist-Protokoll:
  `ListDevices` / `Listen` fuer Geraete-Erkennung, `Connect` (DeviceID, Port 7878 in
  Netzwerk-Byte-Order) fuer den Tunnel. Danach ist der Socket ein roher Byte-Strom zur
  App. Voraussetzung: das iPhone ist mit dem Mac vertraut (Finder-Trust), was bei jedem
  Entwickler-iPhone ohnehin gilt. Keine libimobiledevice-Abhaengigkeit.
- Ein Empfaenger pro Geraet. Verbindet sich ein zweiter Empfaenger, lehnt die App ab
  (Antwort `BUSY`).

## 4. Drahtprotokoll (protocol/PROTOCOL.md)

Little-endian, alle Nachrichten gleich gerahmt:

| Feld    | Groesse | Inhalt                                      |
|---------|---------|---------------------------------------------|
| magic   | 4       | ASCII `IUCM`                                |
| type    | 1       | Nachrichtentyp                              |
| flags   | 1       | Bit 0: Keyframe (nur VIDEO)                 |
| reserved| 2       | 0                                           |
| length  | 4       | Laenge der Nutzlast                         |
| payload | length  |                                             |

Typen:
- `0x01 HELLO` (App -> Mac, sofort nach Verbindung): Protokollversion (u16), App-Version
  (UTF-8), Geraetename (UTF-8), Liste der Kameras (id, Name, Position).
- `0x02 START` (Mac -> App): Kamera-ID, Breite, Hoehe, fps, Bitrate kbit/s.
- `0x03 STOP` (Mac -> App).
- `0x10 CONFIG` (App -> Mac): tatsaechlich aktives Format nach START (Breite, Hoehe, fps),
  plus HEVC-Parametersaetze (VPS/SPS/PPS) als `hvcC`-Record.
- `0x11 VIDEO` (App -> Mac): pts in Mikrosekunden (u64), dann HEVC-NAL-Einheiten mit
  4-Byte-Laengenpraefix (AVCC/HVCC-Stil, kein Annex-B). Keyframes tragen die
  Parametersaetze zusaetzlich in-band.
- `0x20 PING` / `0x21 PONG`: Mac sendet alle 2 s PING mit u64-Zeitstempel, App antwortet
  PONG mit demselben Wert. Dient Latenzmessung und Totlink-Erkennung (3 fehlende PONG =
  Verbindung schliessen und neu verbinden).
- `0x30 ERROR` (App -> Mac): u16 Code, UTF-8 Text. Codes: 1 BUSY, 2 CAMERA_DENIED,
  3 FORMAT_UNSUPPORTED, 4 ENCODER_FAILED.

Versionsregel: HELLO traegt die Protokollversion; der Mac lehnt unbekannte Major-Version
mit ERROR ab. Prototyp ist Version 1.

## 5. iOS-App (`ios-app/`)

- Swift 6, SwiftUI, iOS 17 Minimum (deckt alle Geraete mit HEVC-Hardware-Encoder ab).
- Ein `CaptureEngine`-Actor: AVCaptureSession mit `AVCaptureVideoDataOutput` (NV12),
  Formatwahl nach START-Wunsch, naechstliegendes unterstuetztes Format.
- Ein `HevcEncoder`: VTCompressionSession, `kVTProfileLevel_HEVC_Main_AutoLevel`,
  `RealTime=true`, `AllowFrameReordering=false` (keine B-Frames, niedrige Latenz),
  `MaxKeyFrameInterval=fps` (ein Keyframe pro Sekunde), `AverageBitRate` aus START,
  Standard 12 Mbit/s bei 1080p30.
- Ein `UsbServer`: NWListener auf Port 7878, nimmt genau eine Verbindung an, parst
  START/STOP/PING, sendet HELLO/CONFIG/VIDEO/PONG/ERROR. Zweite Verbindung: ERROR BUSY,
  schliessen.
- UI: Vorschau, Kamera-Wahl, Statuszeile (verbunden / streamt / fps / Bitrate),
  Schalter "Bildschirm an lassen" (Standard an). Querformat-Lock. Kein Login, keine
  Telemetrie, keine Netzwerkzugriffe ausser dem lokalen Listener.
- Info.plist: Kamera-Nutzungstext; kein Mikrofon-Zugriff im Prototyp.
- Signierung: Team `G3QZ66475M`, automatische Signierung, Installation per Xcode auf das
  Entwickler-iPhone. Community: Selbstbau aus dem Repo mit eigener Apple-ID.

## 6. OBS-Plugin (`obs-plugin/`)

- Basis: offizielle `obs-plugintemplate` (CMake, buildspec.json, laedt libobs und
  Abhaengigkeiten). Sprache: C fuer Kern, Objective-C++ fuer VideoToolbox.
- Module:
  - `usbmux.c/.h`: Unix-Socket-Client fuer `/var/run/usbmuxd`, Plist-Nachrichten
    (XML-Plist per CoreFoundation), `list_devices`, `connect(device_id, port)`,
    Ereignisse Attach/Detach ueber `Listen`. Keine externen Bibliotheken.
  - `frame_parser.c/.h`: zustandsbehafteter Parser fuer das Drahtprotokoll aus Abschnitt 4,
    liefert komplette Nachrichten aus einem Byte-Strom. Pure C, ohne I/O, testbar.
  - `hevc_decoder.mm/.h`: VTDecompressionSession aus dem `hvcC`-Record, Ausgabe NV12
    CVPixelBuffer, Reset bei neuem CONFIG.
  - `iphone_source.mm`: `obs_source_info` (Typ `OBS_SOURCE_VIDEO | OBS_SOURCE_ASYNC`),
    Eigenschaften: Geraet (Liste aus usbmux), Kamera, Aufloesung, fps, Bitrate. Ein
    Empfangs-Thread pro Quelle: verbinden, HELLO lesen, START senden, Frames dekodieren,
    `obs_source_output_video` mit `VIDEO_FORMAT_NV12` und pts aus dem Frame.
  - Wiederverbindung: bei Detach oder Totlink Quelle auf Schwarz, alle 1 s neuer Versuch,
    Backoff bis 5 s. Beim Attach des gleichen Geraets sofort.
- Latenz: Decoder ohne Reordering, `obs_source_frame` sofort weiterreichen; das Plugin
  puffert nicht. Zielwert Glas-zu-Glas unter 100 ms bei 1080p30.
- Auslieferung: `.plugin`-Bundle nach `~/Library/Application Support/obs-studio/plugins/`,
  signiert mit Developer ID, notarisiert. Prototyp: nur lokal installiert.

## 7. Werkzeuge (`tools/`)

- `usbcam-recv` (Swift-Paket, macOS): verbindet sich wie das Plugin, schreibt Statistik
  (fps, Bitrate, PING-Latenz, Keyframe-Abstand) und optional den HEVC-Rohstrom in eine
  `.hevc`-Datei (mit `ffmpeg` abspielbar). Nutzt dieselben C-Module wie das Plugin
  (usbmux, frame_parser) ueber ein kleines C-Target.
- `usbcam-sim` (Swift-Paket, macOS): Sender-Simulator, der ein bewegtes Testbild mit
  eingeblendetem Zeitstempel kodiert und auf `127.0.0.1:7878` das Protokoll spricht.
  Ermoeglicht Plugin- und Empfaenger-Tests ohne Telefon; der Empfaenger bekommt dafuer
  eine Option `--tcp host:port`, die den usbmux-Tunnel umgeht. Das Plugin bekommt dieselbe
  Option als verstecktes Eigenschaftsfeld "Debug-TCP-Adresse".

## 8. Fehlerbehandlung

- App: Kamera verweigert -> ERROR CAMERA_DENIED plus Hinweis in der UI. Encoder-Fehler ->
  ERROR ENCODER_FAILED, Session neu aufbauen, weiterlaufen. Verbindung weg -> Aufnahme
  stoppen, Listener bleibt offen.
- Plugin: usbmuxd-Socket fehlt -> Quelle zeigt Fehler in den Eigenschaften, kein Absturz.
  Kaputte Rahmung (falsches Magic, Laenge > 8 MiB) -> Verbindung schliessen und neu
  verbinden, Log mit `blog(LOG_WARNING, ...)`. Decoder-Fehler -> Frame verwerfen, nach
  3 Fehlern in Folge Decoder neu aufbauen und naechsten Keyframe abwarten.
- Nie: Absturz von OBS durch das Plugin. Alle Threads werden beim Quelle-Loeschen sauber
  beendet (Join mit Timeout).

## 9. Tests

- `frame_parser`: Round-Trip aller Nachrichtentypen, Teilrahmen ueber mehrere Reads,
  Muell vor dem Magic, Ueberlaenge. C-Tests mit ctest.
- `usbmux`: Plist-Kodierung/-Dekodierung gegen aufgezeichnete Antworten (Fixtures), ohne
  echten Socket.
- App: Swift-Tests fuer den Protokoll-Codec (Spiegelbild des C-Parsers) und den
  Zustandsautomaten des Servers (HELLO vor START, BUSY bei zweiter Verbindung).
- Integration: `usbcam-sim` -> `usbcam-recv --tcp` im CI (macOS-Runner), prueft fps und
  Bildinhalt (Zeitstempel im Bild vs. pts).
- Manuell: Telefon am Kabel in OBS, Latenzmessung per Stoppuhr im Bild, Kabel ziehen und
  neu anstecken.

## 10. Fertig-Kriterium Prototyp

1. Rueckkamera 1080p30 per USB-Kabel in OBS sichtbar, 10 Minuten stabil.
2. Glas-zu-Glas-Latenz unter 100 ms (Stoppuhr-Methode).
3. Kabel ziehen und neu anstecken: Bild kommt ohne Zutun binnen 5 s zurueck.
4. Simulator-Integrationstest gruen im CI.
5. README mit Installationsweg fuer Mac-Plugin und Selbstbau der iOS-App.

## 11. Risiken

- Xcode 26.0.1 gegen iOS 26.6 auf dem Geraet: braucht evtl. Xcode-Update oder
  Geraete-Support-Download. Vor Welle 2 pruefen.
- usbmuxd-`Connect` auf einen App-Port erfordert, dass die App laeuft und lauscht;
  im Hintergrund pausiert iOS den Listener nach kurzer Zeit. Deshalb bleibt die App im
  Vordergrund und der Bildschirm an. Hintergrundbetrieb ist ausser Scope.
- obs-plugintemplate laedt vorgebaute Abhaengigkeiten aus GitHub; Netz noetig beim ersten
  Build.
- Lizenz: MIT fuer unseren Code; obs-plugintemplate ist ebenfalls MIT-lizenziert, libobs
  GPL-2.0 (Plugin-Verlinkung gegen libobs ist ueblich und vom OBS-Projekt gewollt).

## 12. Repo-Layout

```
obs-iphone-usb-cam/
  README.md  LICENSE (MIT)  CLAUDE.md
  protocol/PROTOCOL.md
  ios-app/            Xcode-Projekt (SwiftUI)
  obs-plugin/         obs-plugintemplate-basiert (CMake)
  tools/              Swift-Paket mit usbcam-recv, usbcam-sim, C-Target shared/
  docs/superpowers/specs/, docs/superpowers/plans/
```
