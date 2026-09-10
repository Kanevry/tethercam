# App Store metadata: German (de-DE), secondary localization

Version 0.3.0, build 6. Same fields as `en-US.md`, translated. The app already ships `de.lproj`, so a German
localization is cheap and consistent with the interface. Register the localization in App
Store Connect as **German** (de-DE); Austria is served by that localization, there is no
separate de-AT slot.

Wording rules used here: no direct address at all, neither "du" nor "Sie". Everything is
phrased with nouns, infinitives and impersonal constructions, which reads neutral in
Austria and in Germany alike. No Apple feature names, no "Continuity Camera". "OBS" appears
only as a factual compatibility statement, never in the keyword field.

---

## Name (limit 30)

```
TetherCam
```

Same in every localization; the name field is not translated.

## Subtitle (limit 30)

```
iPhone-Webcam per USB-Kabel
```

## Keywords (limit 100)

```
tether,camcorder,streaming,aufnahme,videoanruf,konferenz,meeting,video,live,cam,mikrofon,obs,mac
```

Comma separated, no spaces after commas, 96 von 100 Zeichen. `iphone`, `usb`, `webcam` und
`kabel` stehen im Untertitel und werden dadurch schon indexiert, deshalb stehen sie nicht
im Keyword-Feld. Weil der neue Untertitel die beiden Empfaenger nicht mehr nennt, sind
`obs` und `mac` zurueck im Keyword-Feld; bezahlt wird das mit `kabel` und mit
`kabelgebunden`, dem langen Kompositum, das `KEYWORDS-RATIONALE.md` ohnehin als
Streichkandidaten gefuehrt hat. Der Rest des Platzes geht an `mikrofon`, das Gegenstueck
zu `mic` im englischen Feld. Markennamen wie Zoom, Google Meet, Teams, FaceTime oder
Continuity Camera stehen nur in der Beschreibung als sachliche Kompatibilitaetsangabe;
`obs` und `mac` sind die zwei Ausnahmen und standen vorher im Untertitel. Begruendung:
`KEYWORDS-RATIONALE.md`.

## Promotional text (limit 170)

```
iPhone als USB-Webcam am Mac: in Zoom, Teams, Meet, FaceTime und jeder App über die kostenlose TetherCam-Mac-App, oder als eigene Quelle in OBS. Kein WLAN, keine Cloud.
```

Jederzeit ohne neue Version aenderbar, **dieser Text kann sofort eingespielt werden**,
also noch vor der Einreichung von 0.3.0. Untertitel, Beschreibung und Neuheiten wirken
dagegen erst mit der Version 0.3.0.

## Description (limit 4000)

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

## What's New (limit 4000)

Für 0.3.0 (Build 6):

```
Die TetherCam-Mac-App macht das iPhone zur Kamera für jede Mac-App. Die kostenlose Menüleisten-App von tethercam.app installieren, die Kameraerweiterung einmal freigeben, und das Telefon erscheint als Kamera „TetherCam“ in Zoom, Teams, Meet, FaceTime, QuickTime Player und Browsern. Es gibt sie seit 0.2.1, im Store stand sie bisher nur nirgends. Nur Bild, macOS 14 oder neuer.
Die App weiß jetzt, wer empfängt. Die Statuszeile sagt „Verbunden mit TetherCam für Mac“ oder „Verbunden mit OBS“ statt immer OBS zu nennen, und sie sagt „Warten auf den Mac“, solange nichts verbunden ist.
Die Einstellungen verlinken beide Downloads, Mac-App und OBS-Plugin, und der Mikrofonhinweis richtet sich nach dem Empfänger, statt Ton zu versprechen, den die Mac-App nicht übertragen kann.
Ein zweiter Empfänger, der sich verbindet, während schon einer überträgt, bekommt das jetzt am Telefon gesagt, statt vor einem schwarzen Bild zu sitzen.
„Automatische Drehung“ und der manuelle Winkel bleiben über einen Neustart erhalten, so wie die Horizontkorrektur es schon war.
Der deutsche Systemdialog für das Mikrofon fragt endlich auf Deutsch.
```

Text für 0.2.0:

```
Ton vom iPhone. Das Mikrofon geht über dasselbe USB-Kabel und erscheint im OBS-Audiomixer neben dem Bild. Braucht das OBS-Plugin 0.2.0.
Stummschalter in den Einstellungen, mit Hinweis in der Statuskapsel, solange stumm.
Doppeltippen auf die Vorschau wechselt zur nächsten Kamera. Ein kurzer Hinweis nennt das Objektiv.
Die Verbindung bleibt bei verweigertem Mikrofon und anderen nicht fatalen Fehlern bestehen, statt in einer Schleife neu zu verbinden.
```

Text für 0.1.0 (erste Veröffentlichung):

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
