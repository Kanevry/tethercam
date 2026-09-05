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
Kabelkamera für OBS
```

## Keywords (limit 100)

```
usb,kabel,tether,webcam,stream,streaming,aufnahme,hevc,kamera,video,studio,live,cam,mac
```

Comma separated, no spaces after commas. "obs" bleibt bewusst draussen, siehe `en-US.md`.

## Promotional text (limit 170)

```
iPhone per Kabel an den Mac stecken und das Kamerabild landet in OBS. Kein WLAN, keine Cloud, keine Netzwerklatenz. Gratis, quelloffen, Vorschau ab dem Start.
```

## Description (limit 4000)

```
TetherCam macht aus dem iPhone eine kabelgebundene Kamera für Live-Produktionen am Mac.

Das Telefon wird mit dem vorhandenen USB-Kabel angeschlossen. TetherCam nimmt das Kamerabild auf, kodiert es in Hardware und übergibt es dem kostenlosen TetherCam-Plugin für OBS Studio am Mac. Nichts läuft über WLAN, nichts läuft über einen Server, nichts wird irgendwohin hochgeladen. Das Kabel ist der gesamte Weg, deshalb bleibt das Bild auch in einem vollen Raum stabil, in dem drahtlose Kameras zu stocken beginnen.

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
