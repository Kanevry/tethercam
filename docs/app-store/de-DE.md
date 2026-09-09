# App Store metadata: German (de-DE), secondary localization

Same fields as `en-US.md`, translated. The app already ships `de.lproj`, so a German
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
USB-Webcam für Mac und OBS
```

## Keywords (limit 100)

```
kabel,tether,kabelgebunden,camcorder,streaming,aufnahme,videoanruf,konferenz,meeting,video,live,cam
```

Comma separated, no spaces after commas, 99 von 100 Zeichen. `usb`, `webcam` und `mac`
stehen jetzt im Untertitel und werden dadurch schon indexiert, deshalb sind sie aus dem
Keyword-Feld entfernt; der freigewordene Platz geht an die Videoanruf-Absicht
(`videoanruf`, `konferenz`, `meeting`). "obs" bleibt bewusst draussen, siehe `en-US.md`;
Markennamen wie Zoom, Google Meet, Teams, FaceTime oder Continuity Camera stehen nur in
der Beschreibung als sachliche Kompatibilitaetsangabe. Begruendung: `KEYWORDS-RATIONALE.md`.

## Promotional text (limit 170)

```
Das iPhone per USB-Kabel zur Webcam am Mac: in OBS Studio, und über die virtuelle OBS-Kamera in Videoanrufe. Kein WLAN, keine Cloud, keine Latenz. Gratis und quelloffen.
```

## Description (limit 4000)

```
TetherCam macht aus dem iPhone eine kabelgebundene USB-Webcam für den Mac.

Das Telefon wird mit dem vorhandenen USB-Kabel angeschlossen. TetherCam nimmt das Kamerabild auf, kodiert es in Hardware und übergibt es dem kostenlosen TetherCam-Plugin für OBS Studio am Mac; von OBS aus geht dasselbe Bild über die virtuelle OBS-Kamera weiter in einen Videoanruf, eine Bildschirmaufnahme oder einen Livestream. Nichts läuft über WLAN, nichts läuft über einen Server, nichts wird irgendwohin hochgeladen. Das Kabel ist der gesamte Weg, deshalb bleibt das Bild auch in einem vollen Raum stabil, in dem drahtlose Kameras zu stocken beginnen.

AM TELEFON

Live-Vorschau ab dem Moment, in dem die App geöffnet wird, also noch bevor etwas verbunden ist. Eine Kamera- und Objektivauswahl für Weitwinkel, Ultraweitwinkel und Tele oder die Frontkamera, die den Stream sofort umschaltet.

Automatische Drehung, die sich am Horizont orientiert und nicht an der Bedienoberfläche. Beim Drehen des Telefons bleibt das Bild waagrecht, weil die Ausrichtung schon auf der Aufnahmeseite aufgelöst wird. Ein manueller Winkel steht zur Verfügung, wenn die Entscheidung von Hand kommen soll.

HEVC-Kodierung in Hardware, was das Telefon kühl und die Latenz niedrig hält.

Ein Diagnosebereich, der zeigt, was tatsächlich passiert: Zustand des Listeners, Verbindung, Bilder pro Sekunde, Bitrate und die gemessene Restneigung der Horizontkorrektur.

AM MAC

Das TetherCam-Plugin für OBS Studio, ein kostenloser und quelloffener Download von tethercam.app. Es ergänzt eine Quelle namens TetherCam und findet das Telefon über das Kabel. Ohne das Plugin funktioniert die App weiterhin als Kamera mit Vorschau und Einstellungen, sie hat dann nur kein Ziel für das Bild.

DATENSCHUTZ

Kein Konto, keine Analyse, keine Werbung, keine Käufe. Das Kamerabild geht an den eigenen Mac und sonst nirgendwohin. Es werden keine Daten erfasst.

TetherCam für iPhone ist kostenlos und quelloffen unter der MIT-Lizenz: github.com/Kanevry/tethercam.
```

## What's New (limit 4000)

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
