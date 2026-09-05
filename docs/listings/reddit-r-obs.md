# r/obs post draft

**Check the subreddit rules (sidebar, Community rules) from a logged-in browser
immediately before posting; self-promo rules change.** These could not be verified from
this sandbox (no logged-in Reddit access), so treat everything below as a draft body,
not a cleared-for-posting text. If the rules require a specific flair, a mod-approval
step, or forbid a link in the body, follow that over anything written here.

Venue: https://www.reddit.com/r/obs/submit, text post (not a bare link). Do not post
before the v0.1.0 GitHub release is published (see `README.md` in this folder). Post
after the OBS forum resource exists so you can link it.

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

## Optional media

If r/obs allows a media attachment alongside a text post, attach one of:

- The 54 second demo video `web/demo.mp4` (also embedded at https://tethercam.app).
- The still `web/img/og.png` if video upload is not available or is too large.

Neither is required; the text post stands on its own. Do not attach both.

## Feature claims, cross-checked against README.md

Every feature named above (USB only, HEVC hardware encode, horizon leveling, lens
picker, no Wi-Fi, no cloud, TestFlight/App Store status) exists in the shipped app as
described in the repo `README.md` as of 2026-09-05. Do not add claims that are not in
that file; do not claim audio support, Windows/Linux support, or a virtual camera, none
of which exist in this release.

## Placeholders

- `<FORUM_URL>`: the OBS Resources page once it is approved. Drop the line if you post
  before the forum page exists.
