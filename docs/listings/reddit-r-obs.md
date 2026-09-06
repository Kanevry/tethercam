# r/obs post draft

**Check the subreddit rules (sidebar, Community rules) from a logged-in browser
immediately before posting; self-promo rules change.** Verification attempted on
2026-09-06 from this session: `curl -sL -A "Mozilla/5.0" https://www.reddit.com/r/obs/about/rules.json`
returned HTTP 403 ("Blocked due to a network policy"; body asks to log in or use the
API with developer credentials), and the `https://old.reddit.com/r/obs/` fallback also
returned HTTP 403. Reddit blocks unauthenticated/scripted access from this environment,
so the rules below still could not be verified. Treat everything below as a draft body,
not a cleared-for-posting text, and read the actual sidebar/Community rules from a
logged-in browser immediately before posting. If the rules require a specific flair, a
mod-approval step, or forbid a link in the body, follow that over anything written here.

Venue: https://www.reddit.com/r/obs/submit, text post (not a bare link). The v0.1.0
GitHub release is published and the OBS forum resource draft is ready
(`docs/listings/obs-forum-resource.md`); post this after the forum resource is actually
live so the `<FORUM_URL>` placeholder below can be filled in and linked.

## Title

```
I wrote an open-source plugin that gets the iPhone camera into OBS over USB on macOS (TetherCam, first release, beta)
```

## Body (under 200 words)

```
Disclosure: this is my own project and I am the author. It is free and open source, no paid tier.

Continuity Camera stopped working for me after an iOS/macOS version mismatch (handshake fine, picture black), and the alternatives I found were paid and closed. So I built the boring version: the iPhone encodes HEVC in hardware and serves it on a local TCP port, the Mac reaches that port through usbmuxd over the cable, and an OBS plugin decodes with VideoToolbox. No Wi-Fi, no cloud, no pairing code.

What to expect from a first release: 1080p30 and 1080p60 work on my setup (iPhone 15 Pro Max, Apple Silicon Mac, OBS 32.2.2), about 1 ms ping over USB and about 90 ms to the first frame. Video only, no audio yet, macOS only, one phone per OBS source. The iPhone app is free on TestFlight now, App Store release pending review, so bugs are likely and reports are welcome.

Requirements: iPhone XR or newer on iOS 17+, macOS 12+, OBS 30+, a data cable.

Site and plugin download: https://tethercam.app
iPhone app (TestFlight): https://testflight.apple.com/join/wmT74Ry8
Source, issues, protocol spec: https://github.com/Kanevry/tethercam
OBS forum page: <FORUM_URL>
```

Word count of the body: 191. Re-count after editing (feature honesty edits already cost 20 words once; do not casually add sentences back without re-running the word count above).

## Flair suggestion

`Bug/Issue Report` is wrong; the closest fit among commonly seen r/obs flairs is
something like `Discussion` or `Resource/Tool` (naming varies by subreddit skin and
could not be confirmed, see the rules note above). Pick whichever flair option in the
actual submit form reads closest to "release" or "tool/plugin"; do not post without a
flair if the submit form marks one as required.

## Optional media

If r/obs allows a media attachment alongside a text post, attach one of:

- The 54 second demo video `web/demo.mp4` (also embedded at https://tethercam.app).
- The still `web/img/og.png` if video upload is not available or is too large.

Neither is required; the text post stands on its own. Do not attach both.

## Feature claims, cross-checked against README.md

Every feature named above (USB only, HEVC hardware encode, horizon leveling, lens
picker, no Wi-Fi, no cloud, TestFlight/App Store status) exists in the shipped app as
described in the repo `README.md` as of 2026-09-06. Do not add claims that are not in
that file; audio capture from the iPhone was implemented today but is not part of the
0.1.0 release, so do not claim audio support, Windows/Linux support, or a virtual
camera, none of which exist in this release.

## Placeholders

- `<FORUM_URL>`: the OBS Resources page once it is approved. Drop the line if you post
  before the forum page exists.
