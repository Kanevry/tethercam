# Listing drafts

Ready-to-paste texts for announcing TetherCam outside this repo. Each file is a draft
for one venue. Copy, fill the placeholders, post. Keep the wording honest about the beta
state; none of these venues rewards superlatives.

| File | Venue | Where to post |
|---|---|---|
| `obs-forum-resource.md` | OBS Resources (plugin directory) | https://obsproject.com/forum/resources/ then "Add resource", category Plugins, platform macOS |
| `awesome-obs-pr.md` | awesome-obs list on GitHub | Pull request against https://github.com/Pralhad-Nasane/awesome-obs, section "Camera & Video Sources" |
| `reddit-r-obs.md` | r/obs | https://www.reddit.com/r/obs/submit, text post |

## Prerequisites

**Do not post the forum resource, the awesome-obs PR or the Reddit post before both of
these are true:**

1. The tag `v0.1.0` exists and the GitHub release
   https://github.com/Kanevry/tethercam/releases/tag/v0.1.0 is published with
   `TetherCam-obs-plugin.pkg` and `TetherCam-obs-plugin.zip` attached.
2. The one-line installer (`scripts/install.sh`) resolves that release.

Until then every download link in the drafts, on https://tethercam.app and in the README
returns 404 ("v0.1.0, not released yet" is what the site says today). The tag is set on
purpose only after the Developer ID Installer certificate is in place, see
`docs/RELEASING.md`. A listing whose first click is a 404 is worse than no listing.

**What may be shared now:** the TestFlight public link
https://testflight.apple.com/join/wmT74Ry8. Build 0.1.0 (2) is in Beta App Review as of
2026-09-05; until Apple approves it the link says the beta is not accepting testers.
Check that the link accepts testers before pasting it anywhere that gets traffic.

State on 2026-09-05: App Store version 0.1.0 and TestFlight build 0.1.0 (2) are both
`WAITING_FOR_REVIEW`. No GitHub release exists.

## Placeholder checklist

Every draft uses the same placeholders. Replace all of them before posting:

- [ ] `<RELEASE_URL>`: the published release page, expected
      `https://github.com/Kanevry/tethercam/releases/tag/v0.1.0`
- [ ] `<RELEASE_DATE>`: date of the v0.1.0 release, ISO format
- [ ] `<PKG_URL>`: direct link to `TetherCam-obs-plugin.pkg` on that release
- [ ] TestFlight link verified to accept testers (open it in Safari on an iPhone)
- [ ] `docs/listings/obs-forum-resource.md`: screenshots uploaded (paths listed in the file)
- [ ] `docs/listings/awesome-obs-pr.md`: list format re-checked against the upstream README
      on the day of the PR (the section name may have changed)
- [ ] `docs/listings/reddit-r-obs.md`: current r/obs rules read before posting; some days
      or flairs restrict self-promotion

## Order

1. GitHub release published, links checked by hand.
2. OBS forum resource (the audience that will actually install it).
3. awesome-obs PR (one line, no urgency).
4. Reddit, last, and only once the forum page exists so the post can link to it.
