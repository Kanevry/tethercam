# r/obs setup guide

Submitted on 2026-09-09 as u/CartographerNo3791, flair Guide. Subsequently removed by Reddit’s filters, verified both publicly and in the author account. Exact filter/trigger not disclosed. Bernhard personally read and sent the moderator review request, explicitly confirmed by him on 2026-09-09. Moderator review and any public restoration remain pending. The send is user-confirmed, not independently verified from a sent entry: Reddit's `/message/sent/` returned “Page not found.” See `reddit-filter-review-2026-09-09.md`.

Post: https://www.reddit.com/r/obs/comments/1wbgklm/iphone_into_obs_over_usb_on_macos_i_built_a_free/

Live rules checked in logged-in Chrome on 2026-09-09:
https://www.reddit.com/r/obs/wiki/rules-selfpromo/

The community permits helpful how-to and instruction links when not spammed. It
prohibits promotion solely to gain viewers/subscribers. This version provides the
complete setup and troubleshooting context, discloses authorship, and links only to
the relevant free tool and its documentation. The separate creator story covers
AgenticCutter. Flair: Guide, if available in the live form.

## Title

iPhone into OBS over USB on macOS: I built a free plugin, here's the setup

## Body

I built TetherCam after my iPhone kept losing its camera connection while I was recording YouTube videos for Agentic Builders. AirDrop wasn't solving the workflow for me either. I wanted a cable-based setup I could rely on, independent of Continuity Camera.

It's a free, open-source iPhone app and OBS plugin for macOS. The camera feed goes over USB. No Wi-Fi, cloud service or account.

If you want to try it, here's the setup:

1. Install the signed Mac plugin from https://tethercam.app/install and restart OBS when you're done recording.
2. Install TetherCam on the iPhone from the App Store (linked in the guide).
3. Connect a USB data cable, unlock the phone and accept "Trust This Computer" if prompted. Keep TetherCam open in the foreground.
4. In OBS, choose Tools → TetherCam: Add iPhone camera to current scene.

It supports 720p/1080p at 30 or 60 fps. You need iOS 17+, macOS 12+ and OBS 30+. Mac only for now. The current App Store app sends video; the iPhone microphone audio update is still in review, so use your usual microphone in OBS for now.

If there's no picture, check the status line in the source's Properties. Start with the cable, the trust prompt and whether the phone app is still open. A charge-only cable won't work.

Source and bug reports: https://github.com/Kanevry/tethercam

I've tested this on my own setup, and I'd appreciate reports from other phones and Macs. If you try it, which iPhone, macOS and OBS versions worked for you, or where did it get stuck?

## Media availability

The r/obs composer offered text only (no image or link-embed attachment). The linked setup guide contains the product imagery. Prepared but not attached, Pencil setup graphic: `/Users/bernhardgoetzendorfer/Desktop/TetherCam-AppStore/marketing-6.9/02-three-steps.png`.
Caption: "TetherCam setup and the actual OBS Tools menu entry. The iPhone app must stay open on an unlocked phone."

## Claim verification

- Apple listing: https://apps.apple.com/us/app/tethercam/id6808997521 (0.1.0 live).
- Mac plugin: https://github.com/Kanevry/tethercam/releases/tag/v0.2.0 (published).
- iPhone 0.2.0 audio update awaiting App Review, per current project release record.
- No claim of being the first or only USB solution; Continuity Camera supports USB too.
- No unsupported latency or zero-dropout claim.
