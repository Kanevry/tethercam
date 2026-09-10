# SEO and GEO runbook

Goal: be the answer for *"use iPhone as webcam on Mac via USB"*, *"iPhone camera in Zoom /
Meet / Teams / FaceTime"*, *"iPhone webcam OBS USB no wifi"* and *"Continuity Camera
alternative"* ; both in classic search (Google, Bing) and in generative engines (ChatGPT,
Perplexity, Claude, Google AI Overviews), which may cite retrieved pages.

Write useful, factual answers on a fast page that can be read without JavaScript.
Relevant headings and clear requirements help readers and retrieval systems understand
the product. Markup and llms.txt are supporting files; their presence does not prove
indexing, rankings, AI citations or conversion.

Last full pass: 2026-09-10.

---

## 1. What is in place

### Website (`web/`, static HTML on Vercel, no framework)

| Item | Where |
|---|---|
| Intent-first `<title>`, meta description, OG and Twitter cards per page | `index.html`, `de/index.html`, `install.html`, `changelog.html`, `privacy.html` |
| One `<h1>` per page; homepage use case and Mac compatibility are clear in the hero | same |
| Concise hero naming Zoom, Teams and Meet, with both app downloads and a separate OBS route | `index.html`, `de/index.html` |
| `#compare` section: video-call instructions plus a neutral comparison table against Continuity Camera, Camo, EpocCam, Iriun | same |
| FAQ with matching `FAQPage` JSON-LD in each language (USB vs Wi-Fi, Continuity Camera, Zoom/Meet/Teams/FaceTime, without OBS, latency, audio, price, requirements, Windows/Linux, competitors) | same |
| `SoftwareApplication` JSON-LD with `featureList`, `offers` price 0, licences, requirements | same |
| `Organization`, `WebSite`, `VideoObject` graph; `BreadcrumbList`, `WebPage` and a troubleshooting `FAQPage` on `/install` | same |
| Canonical URL and `hreflang` en / de / x-default on every page | all pages |
| `sitemap.xml` (5 URLs, homepage and guides updated 2026-09-10), `robots.txt` allowing GPTBot, OAI-SearchBot, ChatGPT-User, ClaudeBot, PerplexityBot, Google-Extended, Applebot-Extended | `web/sitemap.xml`, `web/robots.txt` |
| `llms.txt`: concise answers covering downloads, setup, audio, requirements and verified compatibility | `web/llms.txt`, linked from every page via `<link rel="alternate" type="text/plain">` |

### GitHub (`README.md`)

The first fifteen lines answer what / for whom / how to install, in that order, with concise copy and both app downloads before the first product illustration.
Detailed compatibility and setup information lives in the relevant sections below.

### App Store (`docs/app-store/`)

Subtitle, keywords, promotional text and the first lines of the description are aligned
with the same intents. Rationale and the A/B backlog: `docs/app-store/KEYWORDS-RATIONALE.md`.

---

## 2. Truthfulness rules, non-negotiable

Every claim on the site must survive a reader with an iPhone and a Mac. Retrieval systems
can repeat outdated claims, so keep requirements and release states explicit.

### Positioning, decided 2026-09-10

TetherCam turns the iPhone into a **wired webcam for the Mac**, over the USB cable.

- **The Mac app is the default path** and comes first everywhere: titles, meta
  descriptions, the hero, the quick start, the FAQ order, `llms.txt`. The menu bar app
  plus its camera extension makes the phone show up as the camera "TetherCam" in Zoom,
  Teams, Google Meet, FaceTime, QuickTime Player, Safari, Chrome and every other Mac app.
- **The OBS plugin is the pro path**: its own source in OBS Studio, with the phone's audio,
  no detour through a virtual camera. It stays first class and equally visible, but it is
  no longer the headline and no longer step 1. Keep "OBS" in the title, last.
- Acceptance after a homepage edit: at 1280x720, 390x844 and a narrow 320px viewport,
  a new visitor can identify the iPhone-to-Mac use case and find both app downloads
  in the first view. The OBS alternative must be easy to find without obscuring them.
- Follow the links: the Mac button resolves to the published Mac artifact, the iPhone
  button to the correct App Store listing, and the OBS route to its separate installer.
- Read one answer in isolation: its requirements, audio behavior and available version
  must stay correct when extracted by a search engine or assistant. Compare visible FAQ,
  JSON-LD, README and llms.txt. Counts of keywords or named apps are not quality gates.
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
  lists system cameras", and every place that names them states that they have not been individually tested. The
  same wording rule applies to `llms.txt` and the README. Everything else in the earlier
  positioning section still bounds the copy: no audio on the Mac-app path, iPhone app in the
  foreground, one receiver at a time (BUSY), macOS 14+ plus a one-time approval, no Wi-Fi,
  no cloud, no pairing code.
- **Review update, 2026-09-10:** replaced the earlier keyword-count comparison with
  user-task checks. Repeating app names to balance the number of OBS mentions made the
  page longer without proving that a visitor could choose the right installation.
  Check hierarchy, working links, mobile readability and factual agreement instead.

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
  Zoom 7.1.5 and Microsoft Teams were also verified on 2026-09-10. Do not generalize
  this into an individual test of every app that can select a system camera.
- **Audio** from the phone reaches the OBS mixer for recordings and streams through
  the plugin. Both the TetherCam Mac camera and OBS Virtual Camera carry video only;
  video calls need a separately selected microphone. Do not imply that enabling OBS
  Virtual Camera routes the OBS audio mixer into Zoom or Teams.
- **Distribution states, verified 2026-09-10:** the iPhone App Store app is **0.2.0**;
  the Mac app and OBS plugin GitHub release is **0.3.0**. Verify the store separately
  from GitHub. Never infer App Review approval from a Git tag or a local build.
- **Measured numbers** (1 ms round trip, ~90 ms to first frame, ~1.3 s reconnect, 13 Mbit/s)
  are from one setup, and the pages say so. Ping and time to first frame are not
  end-to-end camera latency. The latter has not been measured here.
- **Competitor rows** in the comparison table are hedged ("free tier plus a paid version")
  on purpose, and carry a checked-on date. Do not add resolution or watermark claims about
  other products without a link to their own page.

---

## 3. How to verify

### After every change to `web/`

```bash
# Parse JSON-LD and sitemap, then check markup
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

- **Rich Results Test** ; https://search.google.com/test/rich-results, run against
  `https://tethercam.app/` and `https://tethercam.app/install`. Check the detected Software App, Video and
  Breadcrumb items. FAQ markup can be validated separately; do not expect this product
  site to qualify for a Google FAQ rich result or assume markup produces AI citations.
- **Schema validator** ; https://validator.schema.org/ for anything the Google test ignores
  (`Organization`, `WebSite`).
- **Live headers** ; `curl -sI https://tethercam.app/ | head` for the status and cache
  headers, and `curl -s https://tethercam.app/llms.txt | head -3` to confirm the deploy
  picked up the new file. `web/vercel.json` controls the extensionless routes; if `/install`
  404s, that is where to look.
- **PageSpeed / Lighthouse** ; https://pagespeed.web.dev/. The site is static with two
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
   title and description do not match the query ; fix the description first, it is free.
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

Record for each: is TetherCam named, is `tethercam.app` linked, and is what the model says
**true**. The downloadable Mac virtual camera is available. A claim that it carries the
iPhone microphone, or that the Mac app and OBS plugin can receive simultaneously, would
be wrong. Check whether the source page permits that reading and clarify it when needed.
Crawler access does not guarantee retrieval or citation; check `robots.txt` if a relevant
search engine cannot fetch the page.

After each deploy, fetch `https://tethercam.app/llms.txt` and verify its actual content.
Read it end to end once a quarter. It is a supporting facts file; do not assume that a
particular model reads it or uses it instead of the website.

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

1. **Validate demand before adding app-specific guides.** Review support questions and
   Search Console queries for `/obs`, `/zoom`, `/google-meet`, `/facetime` or a Continuity
   troubleshooting guide. Add a page when it can answer a distinct task with checked
   steps and screenshots. A renamed copy of the same installation text adds little value.
2. **Done 2026-09-09 (0.2.1): the signed `.dmg` for the virtual camera shipped (#14).**
   "Works in Zoom without OBS" is now a sentence the site is allowed to write, and it is
   the headline. What remains here is spending the reach on it: see items 4 and 5.
3. **A short YouTube video, 60 to 90 seconds, "iPhone as a webcam on Mac over USB".** Video
   results own this query on Google, and the existing `demo.mp4` is already cut for it. The
   `VideoObject` markup on the page would then point at a hosted video with a real
   `embedUrl`.
4. **Distribution status is separate from submission.** Homebrew is live. The
   awesome-obs PR is open, not merged (verified 2026-09-10). The OBS forum resource was
   still awaiting account 2FA in the last launch receipt; no public resource is confirmed.
   The existing SideProject post and macapps App-Pile comment were publicly verified on
   2026-09-09. Three other Reddit posts were filtered, with moderator review outstanding.
   Use `docs/listings/README.md` for exact links and recheck current visibility before
   acting. Do not create duplicate submissions.
5. **Product Hunt preparation.** First align the App Store text, website, product demo
   and release availability. Inspect existing launches and the current account before
   choosing a date. A listing does not establish meaningful traffic or activation.
6. **A "what broke in Continuity Camera" write-up** with the exact log line
   (`invalid stream for ContinuityCaptureControl`). People search that error string
   verbatim, and nothing else on the web answers it with a working alternative.
7. **`de/` sub-pages.** Only the German landing page exists; `/de/install` and
   `/de/changelog` do not, so German visitors are dropped into English. Low ceiling but
   cheap.
8. **Bing Webmaster Tools.** Bing's index feeds ChatGPT search; the site is submitted
   nowhere but Google today. Ten minutes of work.
9. **Structured `HowTo` markup on the front-page quick start.** Google demoted `HowTo` rich
   results, so this is now GEO-only value ; worth little on its own, cheap when the how-to
   pages in item 1 are written.
10. **Real measurement of AI citation share.** Tools exist for tracking brand mentions in
    LLM answers; none is worth a subscription at this traffic level. Revisit if the manual
    sampling in section 3 ever stops being enough.
