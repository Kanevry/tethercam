# App Store metadata: German (de-DE), secondary localization

**0.4.0 / next submission.** Gleiche Felder wie `en-US.md`, uebersetzt. Die Bloecke im
oberen Abschnitt sind die naechste Einreichung; der Wortlaut von 0.3.0, der live ist oder
in Pruefung liegt, steht unveraendert weiter unten unter "Live/in review: 0.3.0". Die
Lokalisierung heisst in App Store Connect **German** (de-DE); Oesterreich wird davon
mitbedient, einen eigenen de-AT-Slot gibt es nicht.

Botschaft, vom Owner am 2026-09-10 nach dem Zoom/Teams-Pass festgelegt (Issue #31):
**"iPhone statt Webcam."** Zwei Apps — TetherCam fuer Mac (kostenlos, tethercam.app) und
TetherCam fuer iPhone (diese App). Beide laden, Kabel einstecken, fertig. Es funktioniert
in jeder Mac-App, die Systemkameras auflistet; OBS Studio ist ein Werkzeug von vielen, das
Plugin bleibt der Weg fuer Profis, erwaehnt, aber nie als Ueberschrift.

Fakten, die jeden Satz begrenzen: die Mac-App uebertraegt nur Bild, die iPhone-App bleibt
im Vordergrund, das Telefon bedient immer nur einen Empfaenger, kein WLAN, keine Cloud,
kein Kopplungscode, Zoom und Microsoft Teams am 2026-09-10 geprueft, iOS 17+, macOS 14+.

Sprachregeln wie bisher: keine direkte Anrede, weder "du" noch "Sie". Alles mit Substantiven,
Infinitiven und unpersoenlichen Konstruktionen, was in Oesterreich und in Deutschland gleich
neutral liest. Keine Apple-Feature-Namen, keine "Continuity Camera". Markennamen stehen nur
in der Beschreibung als sachliche Kompatibilitaetsangabe, nie im Keyword-Feld.

---

## Name (limit 30)

```
TetherCam
```

Same in every localization; the name field is not translated.

## Subtitle (limit 30)

```
iPhone statt Webcam
```

## Keywords (limit 100)

```
usb,kabel,tether,mac,obs,streaming,aufnahme,videoanruf,konferenz,meeting,video,live,cam,mikrofon
```

Comma separated, no spaces after commas, 96 von 100 Zeichen. Der neue Untertitel gibt seinen
Platz an die Botschaft statt an Suchbegriffe, deshalb kommen `usb`, `kabel`, `mac` und `obs`
zurueck ins Keyword-Feld; draussen bleiben nur `iphone` und `webcam`, die ueber Name und
Untertitel ohnehin indexiert werden. `camcorder` faellt dafuer weg: ein englisches Lehnwort
mit wenig deutschem Suchvolumen, das die noetigen zehn Zeichen bezahlt. Markennamen wie
Zoom, Microsoft Teams, Google Meet, FaceTime oder Continuity Camera stehen nur in der
Beschreibung; `obs` und `mac` sind die zwei Ausnahmen und sachliche Kompatibilitaetsangaben.
Begruendung: `KEYWORDS-RATIONALE.md`, Addendum 2026-09-10 (2).

## Promotional text (limit 170)

```
iPhone statt Webcam. Die kostenlose TetherCam-Mac-App installieren, Kabel einstecken, und das Telefon ist Kamera in Zoom, Teams, Meet, FaceTime und jeder Mac-App.
```

Jederzeit ohne neue Version aenderbar und **nicht an eine Version gebunden**; deshalb wurde
genau dieser Block am 2026-09-10 sowohl in die live stehende 0.2.0 als auch in die in
Pruefung liegende 0.3.0 eingespielt. Untertitel, Keywords, Beschreibung und Neuheiten
wirken erst mit der naechsten Einreichung.

## Description (limit 4000)

```
iPhone statt Webcam.

ZWEI APPS, EIN KABEL

TetherCam sind zwei kostenlose Apps. TetherCam für Mac kommt von tethercam.app, TetherCam für iPhone ist diese hier. Beide installieren, das Telefon mit dem vorhandenen USB-Kabel an den Mac stecken, und das iPhone erscheint am Mac als Kamera „TetherCam“, in derselben Kameraauswahl wie die eingebaute Kamera.

Das gilt für jede Mac-App, die Systemkameras auflistet: Zoom, Microsoft Teams, Google Meet, FaceTime, QuickTime Player, Safari, Chrome und alle anderen. Zoom und Microsoft Teams wurden am 10. September 2026 geprüft.

Nichts läuft über WLAN, nichts läuft über einen Server, nichts wird irgendwohin hochgeladen. Es gibt kein Konto, keinen Kopplungscode und keine Suche im Netzwerk. Das Kabel ist der gesamte Weg, deshalb bleibt das Bild auch in einem vollen Raum stabil, in dem drahtlose Kameras zu stocken beginnen.

WAS GEBRAUCHT WIRD

Ein iPhone mit iOS 17 oder neuer, ein Mac mit macOS 14 oder neuer und das USB-Kabel, das beim Telefon dabei war. Die kostenlose TetherCam-Mac-App fragt einmalig nach der Freigabe ihrer Kameraerweiterung in den Systemeinstellungen, danach ist die Kamera einfach da.

DIE EHRLICHEN GRENZEN

Die Mac-App überträgt nur das Bild. Eine Kameraerweiterung am Mac hat keine Tonspur, der Ton bleibt deshalb beim Mikrofon des Mac. Ton über das Kabel gibt es, aber nur auf dem OBS-Weg weiter unten.

Diese iPhone-App bleibt während der Übertragung im Vordergrund.

Das Telefon bedient immer nur einen Empfänger. Mac-App und OBS-Plugin laufen also nicht gleichzeitig; wer als Zweiter verbindet, bekommt die Auskunft, dass die Leitung belegt ist.

AM TELEFON

Live-Vorschau ab dem Moment, in dem die App geöffnet wird, also noch bevor etwas verbunden ist. Eine Kamera- und Objektivauswahl für Weitwinkel, Ultraweitwinkel und Tele oder die Frontkamera, die den Stream sofort umschaltet.

Automatische Drehung, die sich am Horizont orientiert und nicht an der Bedienoberfläche. Beim Drehen des Telefons bleibt das Bild waagrecht, weil die Ausrichtung schon auf der Aufnahmeseite aufgelöst wird. Ein manueller Winkel steht zur Verfügung, wenn die Entscheidung von Hand kommen soll.

HEVC-Kodierung in Hardware, was das Telefon kühl und die Latenz niedrig hält.

Ein Diagnosebereich, der zeigt, was tatsächlich passiert: Zustand des Listeners, Verbindung, Bilder pro Sekunde, Bitrate und die gemessene Restneigung der Horizontkorrektur.

FÜR STREAMING UND AUFNAHME: OBS STUDIO

Das TetherCam-Plugin für OBS Studio ist der Weg für Profis, ebenfalls kostenlos und ebenfalls auf tethercam.app. Es ergänzt eine Quelle namens TetherCam direkt in OBS, findet das Telefon über dasselbe Kabel und ist der einzige Weg, der auch das Mikrofon des Telefons mitbringt.

DATENSCHUTZ

Kein Konto, keine Analyse, keine Werbung, keine Käufe. Das Kamerabild geht an den eigenen Mac und sonst nirgendwohin. Es werden keine Daten erfasst.

TetherCam für iPhone ist kostenlos und quelloffen unter der MIT-Lizenz: github.com/Kanevry/tethercam.
```

## What's New (limit 4000)

Am 2026-09-10 ausgefuellt. Die erste Zeile ist die Botschaft und bleibt stehen; der Rest
ist der ehrliche Stand dieses Builds. **0.4.0 ist wegen der Mac-App eine Minor-Version**
(Update-Pruefung und Wiederherstellung der Kameraerweiterung). Die iPhone-App selbst hat
in diesem Build keine sichtbare Aenderung, deshalb steht das auch so da. Beleg und
englische Fassung: `en-US.md`, gleicher Abschnitt.

```
iPhone statt Webcam: die kostenlose TetherCam-Mac-App von tethercam.app installieren, Kabel einstecken, und das Telefon ist Kamera in Zoom, Teams, Meet, FaceTime und jeder anderen Mac-App, die Systemkameras auflistet.

An der iPhone-App aendert sich in dieser Version nichts. Die Arbeit dieser Version steckt auf der Mac-Seite: TetherCam fuer Mac prueft jetzt einmal taeglich auf Updates und kann seine Kameraerweiterung neu starten, wenn macOS die Kamera nach einem Update nicht startet. Details: tethercam.app/changelog
```

---

## Live/in review: 0.3.0

Unveraendert aufbewahrt. 0.2.0 (Build 4) ist live, 0.3.0 (Build 6) liegt in Pruefung; beide
tragen diese versionsgebundenen Felder, bis die naechste Einreichung sie ersetzt. Der
Promotional-Text beider Versionen wurde am 2026-09-10 auf den neuen Block oben gesetzt, was
erlaubt ist, weil dieses Feld nicht an eine Version gebunden ist.

### Subtitle — 0.3.0

```
iPhone-Webcam per USB-Kabel
```

### Keywords — 0.3.0

```
tether,camcorder,streaming,aufnahme,videoanruf,konferenz,meeting,video,live,cam,mikrofon,obs,mac
```

### Promotional text — 0.3.0, ersetzt 2026-09-10

```
iPhone als USB-Webcam am Mac: in Zoom, Teams, Meet, FaceTime und jeder App über die kostenlose TetherCam-Mac-App, oder als eigene Quelle in OBS. Kein WLAN, keine Cloud.
```

### Description — 0.3.0

```
TetherCam macht aus dem iPhone eine kabelgebundene USB-Webcam für den Mac.

Das Telefon wird mit dem vorhandenen USB-Kabel angeschlossen. TetherCam nimmt das Kamerabild auf, kodiert es in Hardware und übergibt es einem von zwei kostenlosen Empfängern am Mac: der TetherCam-Mac-App, die das Telefon zur normalen Kamera für jede Mac-App macht, oder dem TetherCam-Plugin für OBS Studio für Streaming und Aufnahme. Nichts läuft über WLAN, nichts läuft über einen Server, nichts wird irgendwohin hochgeladen. Das Kabel ist der gesamte Weg, deshalb bleibt das Bild auch in einem vollen Raum stabil, in dem drahtlose Kameras zu stocken beginnen.

AM TELEFON

Live-Vorschau ab dem Moment, in dem die App geöffnet wird, also noch bevor etwas verbunden ist. Eine Kamera- und Objektivauswahl für Weitwinkel, Ultraweitwinkel und Tele oder die Frontkamera, die den Stream sofort umschaltet.

Automatische Drehung, die sich am Horizont orientiert und nicht an der Bedienoberfläche. Beim Drehen des Telefons bleibt das Bild waagrecht, weil die Ausrichtung schon auf der Aufnahmeseite aufgelöst wird. Ein manueller Winkel steht zur Verfügung, wenn die Entscheidung von Hand kommen soll.

HEVC-Kodierung in Hardware, was das Telefon kühl und die Latenz niedrig hält.

Ein Diagnosebereich, der zeigt, was tatsächlich passiert: Zustand des Listeners, Verbindung, Bilder pro Sekunde, Bitrate und die gemessene Restneigung der Horizontkorrektur.

AM MAC

Zwei Empfänger, beide kostenlos und quelloffen auf tethercam.app. Einer davon genügt.

Die TetherCam-Mac-App ist der einfache Weg und braucht macOS 14 oder neuer. Sie ist eine Menüleisten-App mit Kameraerweiterung: nach einer einmaligen Freigabe in den Systemeinstellungen erscheint das iPhone als Kamera „TetherCam“ in Zoom, Microsoft Teams, Google Meet, FaceTime, QuickTime Player, Safari und Chrome, in derselben Kameraauswahl wie die eingebaute Kamera. Sie überträgt nur das Bild. Eine Kameraerweiterung am Mac hat keine Tonspur, der Ton bleibt deshalb beim Mikrofon des Mac.

Das TetherCam-Plugin für OBS Studio ist der Weg für Streaming und Aufnahme. Es ergänzt eine Quelle namens TetherCam direkt in OBS und findet das Telefon über das Kabel, und es ist der einzige Weg, der auch das Mikrofon des Telefons über dasselbe Kabel mitbringt.

Das Telefon bedient immer nur einen Empfänger, Mac-App und OBS-Plugin laufen also nicht gleichzeitig; wer als Zweiter verbindet, bekommt die Auskunft, dass die Leitung belegt ist. Die iPhone-App bleibt während der Übertragung im Vordergrund. Ganz ohne Empfänger bleibt die App eine Kamera mit Live-Vorschau, Objektivauswahl, Horizontkorrektur und Diagnose, sie hat dann nur kein Ziel für das Bild.

DATENSCHUTZ

Kein Konto, keine Analyse, keine Werbung, keine Käufe. Das Kamerabild geht an den eigenen Mac und sonst nirgendwohin. Es werden keine Daten erfasst.

TetherCam für iPhone ist kostenlos und quelloffen unter der MIT-Lizenz: github.com/Kanevry/tethercam.
```

### What's New — 0.3.0 (Build 6)

```
Die TetherCam-Mac-App macht das iPhone zur Kamera für jede Mac-App. Die kostenlose Menüleisten-App von tethercam.app installieren, die Kameraerweiterung einmal freigeben, und das Telefon erscheint als Kamera „TetherCam“ in Zoom, Teams, Meet, FaceTime, QuickTime Player und Browsern. Es gibt sie seit 0.2.1, im Store stand sie bisher nur nirgends. Nur Bild, macOS 14 oder neuer.
Die App weiß jetzt, wer empfängt. Die Statuszeile sagt „Verbunden mit TetherCam für Mac“ oder „Verbunden mit OBS“ statt immer OBS zu nennen, und sie sagt „Warten auf den Mac“, solange nichts verbunden ist.
Die Einstellungen verlinken beide Downloads, Mac-App und OBS-Plugin, und der Mikrofonhinweis richtet sich nach dem Empfänger, statt Ton zu versprechen, den die Mac-App nicht übertragen kann.
Ein zweiter Empfänger, der sich verbindet, während schon einer überträgt, bekommt das jetzt am Telefon gesagt, statt vor einem schwarzen Bild zu sitzen.
„Automatische Drehung“ und der manuelle Winkel bleiben über einen Neustart erhalten, so wie die Horizontkorrektur es schon war.
Der deutsche Systemdialog für das Mikrofon fragt endlich auf Deutsch.
```

### What's New — 0.2.0

```
Ton vom iPhone. Das Mikrofon geht über dasselbe USB-Kabel und erscheint im OBS-Audiomixer neben dem Bild. Braucht das OBS-Plugin 0.2.0.
Stummschalter in den Einstellungen, mit Hinweis in der Statuskapsel, solange stumm.
Doppeltippen auf die Vorschau wechselt zur nächsten Kamera. Ein kurzer Hinweis nennt das Objektiv.
Die Verbindung bleibt bei verweigertem Mikrofon und anderen nicht fatalen Fehlern bestehen, statt in einer Schleife neu zu verbinden.
```

### What's New — 0.1.0 (erste Veröffentlichung)

```
Erste öffentliche Veröffentlichung.

Live-Vorschau, während die App auf den Mac wartet, damit der Bildausschnitt schon vor der Verbindung mit OBS steht.
Kamera- und Objektivwechsel direkt in den Einstellungen.
Automatische Drehung mit Horizontkorrektur, dazu ein manueller Winkel.
HEVC-Kodierung in Hardware über das USB-Kabel.
Diagnosebereich mit Zustand des Listeners, Bildrate, Bitrate und Restneigung.
Deutsche und englische Bedienoberfläche.
```

---

## Fields that are not free text

Identical to `en-US.md`: Support URL `https://tethercam.app/#faq`, Marketing URL
`https://tethercam.app`, Privacy Policy URL `https://tethercam.app/privacy`, categories
Photo & Video plus Utilities, price Free, copyright `2026 Bernhard Goetzendorfer`.

Categories, age rating, App Privacy and export compliance are set once per app, not per
localization; there is nothing to translate there. The screenshots and the App Preview are
shared across localizations unless a German set is uploaded separately, which is not
planned for 0.1.0: the captions burned into the demo are English, and the interface shown
in the screenshots is English.
