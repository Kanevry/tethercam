# Keyword and subtitle rationale (App Store)

Written 2026-09-09. Companion to `en-US.md` and `de-DE.md`, which hold the fields that get
pasted into App Store Connect. Every change here was checked against
`docs/app-store/validate.sh`.

## What changed

| Field | Before | After |
|---|---|---|
| Subtitle (en) | `Wired camera for OBS` | `USB webcam for Mac and OBS` |
| Subtitle (de) | `Kabelkamera für OBS` | `USB-Webcam für Mac und OBS` |
| Keywords (en) | `usb,cable,tether,webcam,stream,broadcast,capture,hevc,camera,video,studio,live,wired,cam` | `cable,tether,wired,camcorder,streaming,capture,meeting,conference,call,video,live,studio,cam,mic` |
| Keywords (de) | `usb,kabel,tether,webcam,stream,streaming,aufnahme,hevc,kamera,video,studio,live,cam,mac` | `kabel,tether,kabelgebunden,camcorder,streaming,aufnahme,videoanruf,konferenz,meeting,video,live,cam` |

## Why

**The subtitle now carries the head terms.** Apple indexes the app name and the subtitle
along with the keyword field, so a term in the subtitle is wasted space in the keyword
field. Moving `USB`, `webcam` and `Mac` into the subtitle buys three high-volume words in
the most visible place on the product page and frees roughly 20 characters in the keyword
field. "webcam" is the word real people type; "camera" is not, because everything on an
iPhone is already a camera. The old subtitle described the mechanism ("wired camera"); the
new one describes the job ("USB webcam for Mac").

**The freed space went to the video-call intent.** The old list was purely a streaming
list. The searches this product should win are split in two: OBS and streaming on one side,
and "iPhone as webcam for Zoom / Meet / Teams / FaceTime" on the other. `meeting`,
`conference` and `call` (de: `videoanruf`, `konferenz`, `meeting`) cover the second half
without naming anyone's trademark.

**`mic` was added (en).** 0.2.0 sends the phone microphone over the same cable. That is a
differentiator against phone-as-webcam apps whose free tier is video only, and "webcam with
mic" is a real query.

**Terms that were dropped and why.** `usb`, `webcam`, `mac`, `obs` moved to the subtitle,
so they are already indexed. `hevc` is an engineering term almost nobody searches.
`broadcast` overlaps `streaming`. `stream` was dropped in favour of `streaming`, because
Apple stems within a language and the longer form reads better if it is ever shown.
`kamera` / `camera` was dropped: it competes with the entire camera category and never wins.

**No trademarks in the keyword field.** "Zoom", "Google Meet", "Teams", "FaceTime",
"Continuity Camera" and "Camo" all match genuine intent, but App Review guideline 2.3.7
warns against metadata stuffed with third-party terms, and Apple's own feature names are
the most likely to be rejected. They appear only in the long description as factual
compatibility statements, which is the accepted form. "OBS" is the single exception and
sits in the subtitle, as it did in 0.1.0; it is a factual compatibility statement about the
plugin this app ships with.

## What the competition ranks for

Observed positioning from the vendors' own store listings and product pages, checked
2026-09-09. Treat as orientation, not as scraped rank data; nothing here was measured with
a rank tracker.

| App | Positioning it leans on |
|---|---|
| Camo (Reincubate) | "webcam", "camera quality", pro features, Mac and Windows, USB and Wi-Fi |
| EpocCam (Elgato) | "webcam", streaming brand pull from Elgato, Zoom/Teams/OBS compatibility copy |
| Iriun Webcam | "webcam", free, Android and iOS, multi-platform desktop |
| Continuity Camera | not a store listing at all; it owns the query through Apple support pages |

The head term "webcam" is crowded and all three paid apps outrank a new free app on it.
The winnable niches are the qualified long tails: *iPhone webcam over USB*, *webcam without
Wi-Fi*, *Continuity Camera alternative*, *iPhone camera in OBS*. Those are exactly what the
website and `llms.txt` target; the store fields target the same intent with the words the
store allows.

## What to A/B later

Change one field at a time and give each variant at least two to three weeks, or the App
Store Connect impression data cannot separate the effect from ordinary release noise.

1. **Subtitle:** `USB webcam for Mac and OBS` versus `iPhone webcam over USB cable`. The
   second drops "OBS" (removing all trademark exposure) and buys "iPhone" and "cable".
2. **Keyword slot 1:** swap `camcorder` for `capture card`-adjacent terms (`capture` is
   already in; `card` on its own is noise) or for `podcast`, which is a large adjacent
   audience for a wired camera.
3. **`mic` versus `audio` (en) / `mikrofon` versus `ton` (de).** Only one fits; measure.
4. **Promotional text** is editable without a release, so it is the cheapest thing to test.
   Current text leads with the webcam job; a variant leading with "Continuity Camera not
   working?" would target the rescue query, but risks a trademark objection and should be
   submitted with review notes.
5. **de-DE `kabelgebunden`:** long and compound-heavy. If it shows no impressions after a
   cycle, replace it with `stativ` or `livestream`.

## Rules to keep

- Never repeat a word between the name, the subtitle and the keyword field.
- Comma separated, no spaces after commas: a space costs a character and buys nothing.
- Singular only; Apple stems plurals within a locale.
- Re-run `bash docs/app-store/validate.sh` after any edit. Umlauts count as one character,
  which is why the German fields fit at 99 and 169.

---

## Addendum 2026-09-10: the A/B candidate shipped, OBS moved back into keywords

Decided with the positioning in `docs/SEO-GEO.md` § "Positioning, decided 2026-09-10": the
free TetherCam Mac app is the default receiver and the OBS plugin is the pro path, so the
subtitle should describe the job, not one receiver.

| Field | Before (0.2.0) | After (0.3.0) |
|---|---|---|
| Subtitle (en) | `USB webcam for Mac and OBS` (26) | `iPhone webcam over USB cable` (28) |
| Subtitle (de) | `USB-Webcam für Mac und OBS` (26) | `iPhone-Webcam per USB-Kabel` (27) |
| Keywords (en) | `cable,tether,wired,camcorder,streaming,capture,meeting,conference,call,video,live,studio,cam,mic` (96) | `tether,wired,camcorder,streaming,capture,meeting,conference,call,video,live,studio,cam,mic,obs,mac` (98) |
| Keywords (de) | `kabel,tether,kabelgebunden,camcorder,streaming,aufnahme,videoanruf,konferenz,meeting,video,live,cam` (99) | `tether,camcorder,streaming,aufnahme,videoanruf,konferenz,meeting,video,live,cam,mikrofon,obs,mac` (96) |

This is A/B candidate 1 from the list above, taken deliberately rather than measured: the
listing was describing a receiver that is no longer step 1. The new subtitle buys `iPhone`
and `cable` in the indexed field and removes all trademark exposure from the most visible
line on the page.

**The keyword field pays for it.** Because the subtitle no longer carries `obs` and `mac`,
both go back into the keyword field, and `cable` leaves it (never repeat a word between
name, subtitle and keywords). In German that arithmetic does not close on its own, so
`kabelgebunden` was dropped as well; it was already the flagged streak candidate under
"What to A/B later" item 5, a long compound with no evidence behind it. The four freed
characters went to `mikrofon`, the counterpart to `mic` in the English list, which settles
item 3 in favour of the longer, more searched form on the German side.

**Trademark stance is unchanged**, with one honest note: `obs` and `mac` are factual
compatibility statements about software this app talks to, and both stood in the subtitle
of 0.1.0 and 0.2.0 without objection. If App Review ever queries the field, `mac` is the
first term to drop, `obs` the second.

**Promotional text** was rewritten Mac-app-first in both locales and can be pushed without
a release; it is the one field of this change that does not have to wait for 0.3.0.

What to measure next cycle: impressions on `iphone webcam usb` and on `obs` before and
after. If `mac` and `obs` in the keyword field show nothing, they are the cheapest terms to
trade back for `podcast` (item 2 above).
