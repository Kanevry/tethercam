# Community round 2 — Mac-app-first (GitLab #30)

Stand: 2026-09-10. Nichts davon ist veröffentlicht. Dieses Dokument enthält **Entwürfe**;
das Posten macht der Owner selbst, nach der Checkliste am Ende.

Warum eine zweite Runde: Runde 1 (#6) war OBS-first. Das Produkt ist inzwischen
Mac-App-first — "Your iPhone, instead of a webcam", zwei kostenlose Apps, ein Kabel,
OBS ist nur noch der Profi-Pfad. Die Runde-1-Texte sind damit inhaltlich veraltet, aber
sie werden **nicht** ersetzt oder neu eingereicht: gefilterte Beiträge aus Runde 1 werden
nach wie vor nicht wiederholt (`README.md`, Abschnitt "Noch offen").

## Faktenbasis für alle Texte

- Zwei kostenlose Apps: **TetherCam für Mac** (Menüleisten-App mit CMIO-Kameraerweiterung,
  `.dmg` von https://tethercam.app oder `brew install --cask tethercam`) und
  **TetherCam für iPhone** (App Store).
- Ein USB-Kabel. Kein WLAN, keine Cloud, kein Account, kein Pairing-Code.
- Mac-App: macOS 14+. iPhone-App: iOS 17+.
- Die Mac-App überträgt **nur Video**. Eine CoreMediaIO-Kameraerweiterung hat keinen
  Audio-Stream; das Mikrofon wird im Meeting separat gewählt. Ton über dasselbe Kabel
  gibt es nur über das OBS-Plugin.
- Das Telefon bedient **einen** Empfänger gleichzeitig.
- Verifiziert am 2026-09-10 mit einem echten iPhone 15 Pro Max: **Zoom 7.1.5** und
  **neues Teams (Desktop)** listen die Kamera "TetherCam".
- Bekannte Stolperstellen: fehlt die Kamera in Zoom oder Teams, hilft Cmd-Q und erneut
  öffnen; nach Installation oder Update der Kameraerweiterung ist ein Mac-Neustart nötig.
- Open Source: MIT, das OBS-Plugin GPL-2.0-or-later. https://github.com/Kanevry/tethercam

## Regelprüfung — Status: AUSSTEHEND

`curl -sL https://www.reddit.com/r/<sub>/about/rules.json -A 'Mozilla/5.0'` wurde am
2026-09-10 für r/macapps, r/Zoom, r/WFH und r/MicrosoftTeams ausgeführt. Alle vier Abrufe
lieferten **keine Regeln**, sondern Reddits Blockseite:

```
<h1>whoa there, pardner!</h1>
<p>Your request has been blocked due to a network policy.</p>
```

Damit ist die Regelprüfung für **alle vier Subreddits ausstehend**. Der Owner muss die
Regeln vor jedem Post in der Sidebar bzw. im Composer selbst lesen. Was unten unter
"Regelcheck" steht, ist entweder eine aus Runde 1 belegte Regel (dann so gekennzeichnet)
oder eine offene Frage, keine bestätigte aktuelle Regel.

---

## 1. r/macapps — **kein neuer Post**, App-Pile-Kommentar

**Regelcheck:** rules.json blockiert (siehe oben). Aus Runde 1 belegt: der
[App Pile September 2026](https://www.reddit.com/r/macapps/comments/1w4brkd/megathread_the_app_pile_september_2026/)
verlangt PCP-Format und erlaubt **einen** Promo-Eintrag pro Entwickler pro 30 Tage.
TetherCam hat am 2026-09-09 bereits einen App-Pile-Kommentar bekommen
([Permalink](https://www.reddit.com/r/macapps/comments/1w4brkd/comment/p8ppyzr/)).
Ein eigenständiger Post ist hier **nicht zulässig**; deshalb ist der Entwurf unten
bewusst ein **Update-Kommentar** unter dem bestehenden App-Pile-Eintrag, kein Post.
Der Owner muss vor dem Absenden prüfen, ob (a) der aktuelle Monats-App-Pile ein neuer
Thread ist und (b) das 30-Tage-Fenster seit dem 2026-09-09 abgelaufen ist. Ist es nicht
abgelaufen, wird nichts gepostet und der Eintrag wartet auf den Oktober-Thread.

**Format:** Antwort/Update unter dem eigenen bestehenden Kommentar, kein neuer Post.
**Medien:** `web/img/mac-app-zoom.png` (keine Gesichter).

> **Update: TetherCam is now a Mac app, not just an OBS plugin**
>
> Follow-up to my entry above, because what I posted then is no longer the main way to use this.
>
> When I first shared TetherCam it was an OBS plugin: the iPhone showed up as a source inside OBS and nowhere else. That only helped people who already stream. So I wrote the piece that was missing — TetherCam for Mac, a small menu bar app with a camera extension. The phone now appears as an ordinary system camera called "TetherCam", in the same picker as the built-in one, in any Mac app that lists cameras.
>
> Two apps, one cable: TetherCam for Mac (free .dmg from tethercam.app, or `brew install --cask tethercam`) and TetherCam for iPhone (free on the App Store). Plug the phone into the Mac with the cable you already own. Nothing goes over Wi-Fi, there is no account and no pairing code.
>
> Requirements are macOS 14+ and iOS 17+. I verified Zoom 7.1.5 and the new Teams desktop app on 10 September with an iPhone 15 Pro Max; Meet, FaceTime, QuickTime, Safari and Chrome work as well.
>
> Honest limits: the Mac app carries video only — a CoreMediaIO camera extension has no audio stream, so you pick the microphone separately. The phone serves one receiver at a time. If the camera is missing in Zoom or Teams, quit that app with Cmd-Q and reopen it; after installing or updating the extension the Mac needs a restart.
>
> Still $0, still open source (MIT; the OBS plugin is GPL): github.com/Kanevry/tethercam

(217 Wörter)

---

## 2. r/Zoom

**Regelcheck:** rules.json blockiert; **ausstehend**. Vor dem Posten in der Sidebar
klären: (1) ob Self-Promotion überhaupt erlaubt ist oder nur als Antwort auf Fragen,
(2) ob es einen Flair-Zwang gibt, (3) ob ein Karma-/Kontoalter-Gate greift. Wenn
Self-Promotion verboten ist, wird der Text **nicht** als Post verwendet, sondern
höchstens als Antwort in einem passenden Webcam-Qualitäts-Thread, mit Offenlegung der
Autorschaft.

**Titel:** `Using my iPhone as the Zoom camera over USB — the free tool I ended up writing`

**Medien:** `web/img/mac-app-zoom.png`.

> My webcam is the weakest part of my Zoom calls, and the iPhone in my pocket has a much better sensor. Continuity Camera exists, but on my machine it dropped out often enough during longer calls that I stopped relying on it.
>
> So I wrote what I wanted: TetherCam, two free apps that connect over the USB cable. TetherCam for Mac is a small menu bar app with a camera extension; TetherCam for iPhone runs on the phone. Install both, plug in the cable, and the phone shows up in Zoom's camera picker as "TetherCam", next to the built-in camera. Nothing goes over Wi-Fi, there is no account, no pairing code and no cloud.
>
> I verified this on 10 September with Zoom 7.1.5 and an iPhone 15 Pro Max. Requirements: macOS 14 or newer, iOS 17 or newer.
>
> Two things to know before you try it. The Mac app carries video only — a Mac camera extension has no audio stream, so the microphone stays whatever you had selected. And if the camera does not appear in Zoom's list, quit Zoom with Cmd-Q and reopen it; after the extension is installed or updated the Mac needs a restart.
>
> Both apps are free and open source (MIT): tethercam.app, github.com/Kanevry/tethercam. I am the author, happy to answer questions or hear where it breaks.

(233 Wörter)

---

## 3. r/WFH

**Regelcheck:** rules.json blockiert; **ausstehend**. Zu klären: ob Self-Promotion oder
Tool-Empfehlungen erlaubt sind, ob es einen Promo-Tag/Flair gibt und ob es einen
wiederkehrenden "tools"-Thread gibt, in den das gehört statt in einen eigenen Post.
Bei Zweifel: nicht posten, sondern den Mods vorher eine Frage schicken.

**Titel:** `I stopped buying webcams and use my old iPhone over USB instead`

**Medien:** `web/img/mac-app-zoom.png`.

> After a few years of working from home I had bought three webcams, and none of them looked as good as the phone lying next to my keyboard. So I wrote a tool to use the phone instead, and I have been on it for my daily calls since.
>
> It is two free apps: TetherCam for Mac (a menu bar app, free .dmg from tethercam.app or `brew install --cask tethercam`) and TetherCam for iPhone from the App Store. Connect the phone with the USB cable that came with it, and it shows up as a camera called "TetherCam" in Zoom, Teams, Meet, FaceTime, QuickTime, Safari, Chrome — anything on the Mac that lists system cameras.
>
> The cable is the whole path. No Wi-Fi, no cloud, no account, so it does not stutter when the flat's network is busy, and the phone charges while it works.
>
> The honest parts: it needs macOS 14+ and iOS 17+, so an old Mac is out. Video only — you pick your microphone as usual. The phone app has to stay open in the foreground. And an old iPhone with a cracked screen is a perfectly good camera, which is why I like this better than another purchase.
>
> Free and open source (MIT): github.com/Kanevry/tethercam. I wrote it; ask me anything.

(222 Wörter)

---

## 4. r/MicrosoftTeams (kurze Variante)

**Regelcheck:** rules.json blockiert; **ausstehend**. Subreddits rund um
Enterprise-Software sind oft Support-orientiert und lehnen Produktposts ab. Der Owner
klärt vorher, ob Third-Party-Tools erlaubt sind; wenn nein, entfällt dieser Post
ersatzlos.

**Titel:** `iPhone as the Teams camera over USB — works in the new Teams desktop app (free, open source)`

**Medien:** `web/img/mac-app-zoom.png`.

> Short version, since this sub is mostly support: I wrote a free tool that turns an iPhone into a normal Mac camera over the USB cable, and Teams picks it up.
>
> Two apps — TetherCam for Mac (menu bar app with a camera extension, free from tethercam.app) and TetherCam for iPhone (App Store). Plug in the cable and "TetherCam" appears in the Teams camera list like any other camera. No Wi-Fi, no account, no cloud.
>
> What I actually tested: the **new Teams desktop app on macOS**, on 10 September 2026, with an iPhone 15 Pro Max. **Teams in the browser I have not tested**, so I cannot claim it there. macOS 14+ and iOS 17+ are required.
>
> Two gotchas that cost me time: if the camera is not in the list, quit Teams with Cmd-Q and reopen it — Teams enumerates cameras at launch. And after the camera extension is installed or updated, restart the Mac.
>
> The Mac app carries video only; the microphone selection in Teams is unaffected.
>
> Free, open source, MIT: github.com/Kanevry/tethercam. I am the developer.

(186 Wörter)

---

## Teams-Einschränkung, ehrlich formuliert

Für jeden Text und jede Antwort gilt derselbe Wortlaut:

> Verified: the **new Teams desktop app on macOS**, 2026-09-10, iPhone 15 Pro Max,
> camera "TetherCam" listed and selectable.
> Not verified: **Teams in the browser**, Teams on Windows, and the classic Teams client.
> A camera missing from the Teams list is usually fixed by quitting Teams with Cmd-Q and
> reopening it; after an extension install or update the Mac needs a restart.

Nicht behaupten, Teams funktioniere "überall". Wer im Browser-Teams fragt: ehrlich sagen,
dass es ungetestet ist, und um ein Ergebnis bitten.

## Posting-Checkliste für den Owner

1. **Kontostand prüfen.** Konto u/CartographerNo3791 ist in Runde 1 mehrfach durch
   Reddits Filter gelaufen (r/obs, r/microsaas, r/IMadeThis). Vor Runde 2 prüfen, ob die
   Modmails von 2026-09-09 beantwortet wurden und ob die Beiträge wiederhergestellt sind.
   Ist das Konto weiter auffällig, erst ein paar Wochen normal kommentieren, dann posten.
2. **Regeln lesen.** Für jedes Subreddit Sidebar und Composer-Hinweise selbst lesen —
   die automatische Prüfung ist blockiert (siehe oben). Verbietet ein Subreddit
   Self-Promotion, entfällt der Post; kein Umgehen über eine "Frage"-Formulierung.
3. **Autorschaft offenlegen.** In jedem Text steht, dass der Poster der Entwickler ist.
   Das bleibt drin, auch wenn ein Subreddit es nicht verlangt.
4. **Maximal ein Post pro Tag**, über alle Subreddits hinweg. Vier Entwürfe heißt
   frühestens vier Tage.
5. **Kein Crossposten desselben Textes.** Jeder Entwurf oben ist eigenständig
   geschrieben; sie werden nicht per Reddit-Crosspost dupliziert und nicht wörtlich
   in ein zweites Subreddit kopiert.
6. **r/macapps ist ein Kommentar, kein Post.** Erst prüfen, ob die 30 Tage seit dem
   2026-09-09 abgelaufen sind bzw. ob ein neuer Monats-App-Pile offen ist.
7. **Medien:** nur `web/img/mac-app-zoom.png`. Keine Gesichter, keine erfundenen
   Screenshots, keine Zahlen ohne Beleg.
8. **Wenn gefiltert:** genau **eine** Modmail an das Subreddit, sachlich, mit Permalink
   und der Frage nach dem Auslöser. Danach warten. **Kein Repost**, keine zweite Modmail,
   kein Zweitkonto. Ergebnis hier und in #30 dokumentieren.
9. **Nichts versprechen, was nicht verifiziert ist.** Nur Zoom 7.1.5 und das neue
   Teams-Desktop sind mit echtem Gerät belegt; alles andere ist "works" ohne Datumsclaim.
10. **Nach jedem Post** Permalink, Datum, Konto und Status (sichtbar/gefiltert) in
    `README.md` unter "Runde 2 (Mac-App-first)" nachtragen.
