# Listing-Checkliste (Owner)

Die fertigen Texte pro Kanal liegen als eigene Datei in diesem Ordner (Englisch, wie
gepostet wird). Diese Datei ist die Checkliste dazu, auf Deutsch: Reihenfolge und ein
Satz pro Schritt, was du tust.

Stand 2026-09-06: v0.1.0 ist veröffentlicht, signiert und notarisiert
(https://github.com/Kanevry/tethercam/releases/tag/v0.1.0), TestFlight ist offen
(https://testflight.apple.com/join/wmT74Ry8), das App-Store-Listing ist noch in Review.
Alle Download-Links in den Draft-Texten sind damit scharf, keine 404 mehr.

## Reihenfolge

1. **Forum-Resource anlegen.** Öffne `obs-forum-resource.md`, kopiere Titel, Tagline,
   Beschreibung, Feature-Liste und Feldwerte 1:1 in "Add Resource" unter
   https://obsproject.com/forum/resources/, Kategorie **OBS Studio Plugins**. Direkt
   danach zeigt die Resource kurz Status "DELETED"; das ist die normale
   Moderationswarteschlange, kein Fehler und kein Grund zum Neu-Einreichen.
2. **r/obs posten.** Lies zuerst die Community-Regeln im eingeloggten Browser (Sidebar
   von r/obs; von hier aus nicht erreichbar, siehe Verifikationsnotiz in
   `reddit-r-obs.md`). Trage die Forum-URL aus Schritt 1 in `<FORUM_URL>` ein und poste
   Titel plus Body als Textpost unter https://www.reddit.com/r/obs/submit, danach die
   Forum-Resource verlinkt.
3. **GitHub Social Preview hochladen.** Lade `web/img/og.png` unter den
   Repo-Einstellungen (Settings, Abschnitt "Social preview") von
   https://github.com/Kanevry/tethercam hoch, damit geteilte Links ein Bild statt eines
   leeren Kastens zeigen.
4. **awesome-obs-PR beobachten.** Ein anderer Agent öffnet diese PR heute; sobald die
   PR-URL in `awesome-obs-pr.md` eingetragen ist, dort nur den Review-/Merge-Status
   verfolgen, kein eigener Aktionsschritt.
5. **Homebrew-Tap ist live.** `brew tap kanevry/tethercam` (ein anderer Agent hat den
   Tap heute angelegt und bestückt); nichts weiter zu tun, höchstens einmal selbst
   `brew install --cask tethercam` zur Probe laufen lassen.

## Nicht vergessen

- Reihenfolge einhalten: Forum vor Reddit, weil der Reddit-Post die Forum-Resource
  verlinkt.
- `homebrew-decision.md` ist kein Draft zum Posten, sondern das Entscheidungsmemo hinter
  Schritt 5; nur bei Rückfragen zum Tap-Aufbau lesen.
- Repo- und Bundle-Name tragen das Präfix `obs-` (`obs-iphone-usb-cam`), was die
  Forum-Richtlinie für Resource-*Namen* eigentlich meidet; das Präfix taucht aber nie im
  Produktnamen auf (überall "TetherCam"), nur im Repo-Pfad und in der Bundle-Id, blockiert
  also nichts.
