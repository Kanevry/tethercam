# r/obs post draft

Venue: https://www.reddit.com/r/obs/submit, text post. Read the subreddit rules on the day
of posting; self-promotion is tolerated when it is disclosed, on-topic and free, and this
post does all three. Do not post before the v0.1.0 GitHub release is published (see
`README.md` in this folder). Post after the OBS forum resource exists so you can link it.

## Title

```
I wrote an open-source plugin that gets the iPhone camera into OBS over USB on macOS (TetherCam, first release, beta)
```

## Body (under 200 words)

```
Disclosure: this is my own project and I am the author. It is free and open source, no paid tier.

Continuity Camera stopped working for me after an iOS/macOS version mismatch (handshake fine, picture black), and the alternatives I found were paid and closed. So I built the boring version: the iPhone encodes HEVC in hardware and serves it on a local TCP port, the Mac reaches that port through usbmuxd over the cable, and an OBS plugin decodes with VideoToolbox. No Wi-Fi, no cloud, no pairing code.

What to expect from a first release: 1080p30 and 1080p60 work on my setup (iPhone 15 Pro Max, Apple Silicon Mac, OBS 32.2.2), about 1 ms ping over USB and about 90 ms to the first frame. Video only, no audio yet. macOS only. One phone per OBS source. The iPhone app is a public TestFlight beta, so bugs are likely and reports are welcome.

Requirements: iPhone XR or newer on iOS 17+, macOS 12+, OBS 30+, a data cable.

Site and plugin download: https://tethercam.app
iPhone app (TestFlight): https://testflight.apple.com/join/wmT74Ry8
Source, issues, protocol spec: https://github.com/Kanevry/tethercam
OBS forum page: <FORUM_URL>
```

Word count of the body: about 190. Re-count after editing.

## Placeholders

- `<FORUM_URL>`: the OBS Resources page once it is approved. Drop the line if you post
  before the forum page exists.
