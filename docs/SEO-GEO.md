# SEO and GEO runbook

Goal: be the answer for *"use iPhone as webcam on Mac via USB"*, *"iPhone camera in Zoom /
Meet / Teams / FaceTime"*, *"iPhone webcam OBS USB no wifi"* and *"Continuity Camera
alternative"* — both in classic search (Google, Bing) and in generative engines (ChatGPT,
Perplexity, Claude, Google AI Overviews), which cite pages rather than rank them.

GEO and SEO want the same thing here: short, factual, self-contained answers under a
question-shaped heading, with numbers and dates, on a fast static page a crawler can read
without JavaScript. Everything below follows from that.

Last full pass: 2026-09-09.

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

- The **macOS virtual camera** (`mac-app/`) is **verified, not released**. Verified
  2026-09-09 with a real iPhone 15 Pro Max in QuickTime Player, Photo Booth, FaceTime,
  Google Meet in Chrome, Safari, Chrome and ffmpeg, portrait and landscape, with reconnect.
  Zoom and Teams were **not** tested. There is no signed `.dmg` (issue #14). Never write
  anything that implies it can be downloaded.
- **Audio** travels only on the OBS plugin path. A CoreMediaIO camera extension carries
  video only; that is a platform limit, not a to-do.
- **iOS app:** 0.1.0 is live on the App Store; 0.2.0 is submitted and not released. Update
  the site the day 0.2.0 goes live.
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
5. Check the release facts: is 0.2.0 live on the App Store yet, is the `.dmg` out, does the
   plugin version on the site match the latest GitHub release.

---

## 5. Backlog: not done, in priority order

1. **One how-to page per app** — `/obs`, `/zoom`, `/google-meet`, `/facetime`,
   `/continuity-camera-alternative`. Highest expected return of anything on this list: each
   page can win its own long tail and be cited on its own, which a single FAQ entry cannot.
   Blocked in part on the virtual camera shipping, since half the answer is "install the
   Mac app".
2. **Ship the signed `.dmg` for the virtual camera (issue #14).** This is a marketing item
   as much as an engineering one: "works in Zoom without OBS" is the sentence that converts,
   and today it cannot be written.
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
