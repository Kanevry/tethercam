# SEO and GEO runbook

Goal: be the answer for *"use iPhone as webcam on Mac via USB"*, *"iPhone camera in Zoom /
Meet / Teams / FaceTime"*, *"iPhone webcam OBS USB no wifi"* and *"Continuity Camera
alternative"* — both in classic search (Google, Bing) and in generative engines (ChatGPT,
Perplexity, Claude, Google AI Overviews), which cite pages rather than rank them.

GEO and SEO want the same thing here: short, factual, self-contained answers under a
question-shaped heading, with numbers and dates, on a fast static page a crawler can read
without JavaScript. Everything below follows from that.

Last full pass: 2026-09-10.

---

## 1. What is in place

### Website (`web/`, static HTML on Vercel, no framework)

| Item | Where |
|---|---|
| Intent-first `<title>`, meta description, OG and Twitter cards per page | `index.html`, `de/index.html`, `install.html`, `changelog.html`, `privacy.html` |
| One `<h1>` per page carrying the core intent ("Your iPhone as a Mac webcam, over the USB cable") | same |
| "Works with" line in the hero, naming OBS, Zoom, Meet, Teams, FaceTime, QuickTime, Photo Booth, Safari, Chrome, with the OBS-virtual-camera caveat | `index.html`, `de/index.html` |
| `#compare` section: video-call instructions plus a neutral comparison table against Continuity Camera, Camo, EpocCam, Iriun | same |
| FAQ with `FAQPage` JSON-LD (15 questions en, 13 de) (USB vs Wi-Fi, Continuity Camera, Zoom/Meet/Teams/FaceTime, without OBS, latency, audio, price, requirements, Windows/Linux, competitors) | same |
| `SoftwareApplication` JSON-LD with `featureList`, `offers` price 0, licences, requirements | same |
| `Organization`, `WebSite`, `VideoObject` graph; `BreadcrumbList`, `WebPage` and a troubleshooting `FAQPage` on `/install` | same |
| Canonical URL and `hreflang` en / de / x-default on every page | all pages |
| `sitemap.xml` (5 URLs, `lastmod` 2026-09-09), `robots.txt` allowing GPTBot, OAI-SearchBot, ChatGPT-User, ClaudeBot, PerplexityBot, Google-Extended, Applebot-Extended | `web/sitemap.xml`, `web/robots.txt` |
| `llms.txt` for GEO: plain-text answers to the four head questions plus the comparison and the virtual-camera status | `web/llms.txt`, linked from every page via `<link rel="alternate" type="text/plain">` |

### GitHub (`README.md`)

The first fifteen lines answer what / for whom / how to install, in that order, with the
same keywords, followed by a "Works with" line. This matters for GEO more than for SEO:
model crawlers read READMEs, and the first screen is what gets summarised.

### App Store (`docs/app-store/`)

Subtitle, keywords, promotional text and the first lines of the description are aligned
with the same intents. Rationale and the A/B backlog: `docs/app-store/KEYWORDS-RATIONALE.md`.

---

## 2. Truthfulness rules, non-negotiable

Every claim on the site must survive a reader with an iPhone and a Mac. GEO amplifies
mistakes: once a model has been trained or grounded on a wrong claim, it repeats it.

### Positioning, decided 2026-09-10

TetherCam turns the iPhone into a **wired webcam for the Mac**, over the USB cable.

- **The Mac app is the default path** and comes first everywhere: titles, meta
  descriptions, the hero, the quick start, the FAQ order, `llms.txt`. The menu bar app
  plus its camera extension makes the phone show up as the camera "TetherCam" in Zoom,
  Teams, Google Meet, FaceTime, QuickTime Player, Safari, Chrome and every other Mac app.
- **The OBS plugin is the pro path**: its own source in OBS Studio, with the phone's audio,
  no detour through a virtual camera. It stays first class and equally visible, but it is
  no longer the headline and no longer step 1. Keep "OBS" in the title, last.
- Sanity check after any edit to `web/index.html`: `grep -oi 'obs' web/index.html | wc -l`
  should stay at or below `grep -oiE 'zoom|meet|teams|facetime' web/index.html | wc -l`.
- Facts that bound every sentence: the Mac app carries **no audio**; the iPhone app must
  stay in the **foreground**; the Mac app and the OBS plugin **cannot run at the same
  time** (the phone accepts one receiver, the second gets BUSY); the Mac app needs
  **macOS 14+** and a manual approval in System Settings.

### Messaging round 2026-09-10: iPhone instead of a webcam

Owner decision after the Zoom/Teams PASS (#13), filed as #31. It sharpens the positioning
above; it does not replace it.

- **Headline.** EN: *"Your iPhone, instead of a webcam."* DE: *"Dein iPhone statt Webcam."*
  Eyebrow: *"Two apps &middot; one cable"* / *"Zwei Apps &middot; ein Kabel"*. The headline
  is on `web/index.html`, `web/de/index.html`, the `<title>` first half, the OG and Twitter
  titles, the JSON-LD `description` fields, the first line of `README.md` and the first
  paragraph of `web/llms.txt`.
- **Two apps, not "plugin plus app".** The product is **TetherCam for Mac** (free `.dmg`
  from the GitHub release, or the Homebrew cask `tethercam`) and **TetherCam for iPhone**
  (App Store id6808997521). Download both, plug the cable in, done. The hero buttons are
  those two apps; the OBS plugin keeps its own section, its `#download` anchor and the full
  install path, but it is no longer a hero button, no longer in the first half of the title
  and no longer step 1.
- **App-list rule, verified vs. "any app".** Only these may be called verified, with the
  date: QuickTime Player, Photo Booth, FaceTime, Google Meet in Chrome, Safari, Chrome and
  ffmpeg (2026-09-09), Zoom 7.1.5 and Microsoft Teams (2026-09-10). **Webex, Slack and
  Discord are never called verified.** They are named only as examples of "any Mac app that
  lists system cameras", and every place that names them says we have not tested them. The
  same wording rule applies to `llms.txt` and the README. Everything else in the earlier
  positioning section still bounds the copy: no audio on the Mac-app path, iPhone app in the
  foreground, one receiver at a time (BUSY), macOS 14+ plus a one-time approval, no Wi-Fi,
  no cloud, no pairing code.
- **OBS-count sanity check, run after this round:** `web/index.html` 100 "obs" against 110
  call-app mentions (was 101 / 113); `web/de/index.html` 107 against 114 (was 108 / 117).
  Both pages stay inside the rule (`obs` <= call apps). "OBS" remains in both `<title>`
  tags, last in the app list.

### Release facts

- The **macOS virtual camera** (`mac-app/`) is **released since 0.2.1 (2026-09-09)**:
  Developer ID signed, notarized and stapled, downloadable as
  `TetherCam-mac.dmg` from the GitHub release
  (https://github.com/Kanevry/tethercam/releases/latest/download/TetherCam-mac.dmg) and via
  `brew tap kanevry/tethercam && brew install --cask tethercam`. It is not on the Mac App
  Store. Requires macOS 14 or newer plus a one-time approval in System Settings > General >
  Login Items & Extensions > Camera Extensions (administrator password). Verified
  2026-09-09 with a real iPhone 15 Pro Max in QuickTime Player, Photo Booth, FaceTime,
  Google Meet in Chrome, Safari, Chrome and ffmpeg, portrait and landscape, with reconnect.
  Zoom and Teams were **not** tested; say "should work, not verified" for those two and
  never claim more.
- **Audio** travels only on the OBS plugin path. A CoreMediaIO camera extension carries
  video only; that is a platform limit, not a to-do.
- **iOS app:** 0.1.0 is live on the App Store; 0.2.0 is submitted and still awaiting App
  Review, so it is not on the store yet. Update the site the day 0.2.0 goes live.
- **Measured numbers** (1 ms round trip, ~90 ms to first frame, ~1.3 s reconnect, 13 Mbit/s)
  are one setup, and the pages say so. Keep that qualifier.
- **Competitor rows** in the comparison table are hedged ("free tier plus a paid version")
  on purpose, and carry a checked-on date. Do not add resolution or watermark claims about
  other products without a link to their own page.

---

## 3. How to verify

### After every change to `web/`

```bash
# JSON-LD parses and tags balance (both are silent on success)
python3 - <<'PY'
import re, json
for f in ["web/index.html","web/de/index.html","web/install.html","web/changelog.html","web/privacy.html"]:
    s = open(f, encoding="utf-8").read()
    for block in re.findall(r'<script type="application/ld\+json">(.*?)</script>', s, re.S):
        json.loads(block)
    print(f, "ok")
PY
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('web/sitemap.xml'); print('sitemap ok')"
tidy -q -e web/index.html            # markup errors, warnings are noisy and mostly fine
```

Then, once deployed:

- **Rich Results Test** — https://search.google.com/test/rich-results, run against
  `https://tethercam.app/` and `https://tethercam.app/install`. Expect FAQ, Software App,
  Video and Breadcrumb items with no errors. Note that Google stopped showing FAQ rich
  results for most sites; the markup still feeds AI Overviews and other engines.
- **Schema validator** — https://validator.schema.org/ for anything the Google test ignores
  (`Organization`, `WebSite`).
- **Live headers** — `curl -sI https://tethercam.app/ | head` for the status and cache
  headers, and `curl -s https://tethercam.app/llms.txt | head -3` to confirm the deploy
  picked up the new file. `web/vercel.json` controls the extensionless routes; if `/install`
  404s, that is where to look.
- **PageSpeed / Lighthouse** — https://pagespeed.web.dev/. The site is static with two
  fonts and one 31 MB video that must stay lazy; a mobile score below 90 means something
  regressed, usually an image without dimensions.

### Google Search Console

1. Property is the domain `tethercam.app` (DNS TXT verification via the Vercel domain).
2. Submit `https://tethercam.app/sitemap.xml` once under *Sitemaps*; it is then re-read
   automatically.
3. After a content change, *URL inspection* → *Request indexing* for the changed page. One
   or two URLs, not the whole site.
4. Watch monthly: *Performance* → queries. The queries to look for are the qualified long
   tails, not "webcam": `iphone webcam usb mac`, `obs iphone camera`, `continuity camera
   alternative`, `iphone webcam ohne wlan`. Rising impressions with a low CTR means the
   title and description do not match the query — fix the description first, it is free.
5. *Pages* → excluded reasons. "Duplicate without user-selected canonical" on `/de/` would
   mean the hreflang pair broke.

### Are AI answers citing tethercam.app?

There is no console for this; it has to be sampled by hand. Once a month, in a fresh
session with no personalisation, in ChatGPT (search on), Perplexity, Claude with web
search, and Google (look at the AI Overview):

```
How do I use an iPhone as a webcam on a Mac over USB?
What is a good Continuity Camera alternative that works over the cable?
How do I get an iPhone camera into OBS on macOS without Wi-Fi?
Can I use my iPhone as a webcam in Google Meet on a Mac?
iPhone als Webcam am Mac über USB, ohne WLAN
```

Record for each: is TetherCam named, is `tethercam.app` linked, and — most important — is
what the model says **true**. A wrong claim (typically "TetherCam has a virtual camera you
can download") is a content bug: find the sentence on the site that allows the
misreading and tighten it. Bots that must stay allowed for any of this to work are already
listed in `robots.txt`; check that file has not been narrowed.

Also useful: `curl -s https://tethercam.app/llms.txt | wc -c` after each deploy, and read
it end to end once a quarter — it is the file a model reads instead of the site.

### App Store side

App Store Connect → *App Analytics* → *Impressions* and *Product Page Views*, source type
"App Store Search". A keyword change needs two to three weeks before the numbers mean
anything. Details: `docs/app-store/KEYWORDS-RATIONALE.md`.

---

## 4. Monthly routine, about 30 minutes

1. Search Console: queries, CTR, coverage errors. Fix titles or descriptions that
   underperform.
2. Run the five AI prompts above; log which engines cite the site and correct any false
   claim they repeat.
3. Re-read the comparison table. If a competitor changed its pricing or platforms, update
   the row and the "checked" date, or delete the row. A stale table is worse than none.
4. Update `sitemap.xml` `lastmod` for pages that actually changed, and `llms.txt` if a fact
   moved (release state above all).
5. Check the release facts: is 0.2.0 live on the App Store yet, does the `.dmg` version on
   the site match the latest GitHub release, does the
   plugin version on the site match the latest GitHub release.

---

## 5. Backlog: not done, in priority order

1. **One how-to page per app** — `/obs`, `/zoom`, `/google-meet`, `/facetime`,
   `/continuity-camera-alternative`. Highest expected return of anything on this list: each
   page can win its own long tail and be cited on its own, which a single FAQ entry cannot.
   No longer blocked: the virtual camera shipped in 0.2.1, so half of each answer is
   simply "install the Mac app".
2. **Done 2026-09-09 (0.2.1): the signed `.dmg` for the virtual camera shipped (#14).**
   "Works in Zoom without OBS" is now a sentence the site is allowed to write, and it is
   the headline. What remains here is spending the reach on it: see items 4 and 5.
3. **A short YouTube video, 60 to 90 seconds, "iPhone as a webcam on Mac over USB".** Video
   results own this query on Google, and the existing `demo.mp4` is already cut for it. The
   `VideoObject` markup on the page would then point at a hosted video with a real
   `embedUrl`.
4. **Backlinks from where the audience already is.** The OBS forum resource entry, an
   awesome-obs listing and the Homebrew tap already exist; missing are Reddit r/obs and
   r/macapps posts (drafts are in `docs/listings/`), and a Hacker News *Show HN*.
5. **Product Hunt launch.** One-shot, high-variance traffic and a durable do-follow link,
   but only worth spending once, and it should be spent on the virtual camera release, not
   on the current state.
6. **A "what broke in Continuity Camera" write-up** with the exact log line
   (`invalid stream for ContinuityCaptureControl`). People search that error string
   verbatim, and nothing else on the web answers it with a working alternative.
7. **`de/` sub-pages.** Only the German landing page exists; `/de/install` and
   `/de/changelog` do not, so German visitors are dropped into English. Low ceiling but
   cheap.
8. **Bing Webmaster Tools.** Bing's index feeds ChatGPT search; the site is submitted
   nowhere but Google today. Ten minutes of work.
9. **Structured `HowTo` markup on the front-page quick start.** Google demoted `HowTo` rich
   results, so this is now GEO-only value — worth little on its own, cheap when the how-to
   pages in item 1 are written.
10. **Real measurement of AI citation share.** Tools exist for tracking brand mentions in
    LLM answers; none is worth a subscription at this traffic level. Revisit if the manual
    sampling in section 3 ever stops being enough.
