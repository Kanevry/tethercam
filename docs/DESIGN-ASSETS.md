# Design assets: App Store frames and website gallery

`tethercam.pen` at the repository root is the Pen (pen.dev) design file for the five App
Store screenshots. It is the source; the exported PNGs are derived and not committed.

## Rules

- **No faces, no private rooms.** The camera picture in every frame is the AI-generated
  studio-desk scene `images/generated-1788629447997.png` (no people). Never place a real
  recording of the owner in store assets. `web/demo.mp4` and the README screenshots are
  owner-approved exceptions for the website and README only.
- **Real app elements only.** The status capsule "Streaming 1080p30", the gear icon, the
  camera names (Back Wide, Back Ultra Wide, Back Telephoto, Front), the Advanced switches,
  the diagnostics rows and the OBS source name "TetherCam iPhone" are the strings of the
  shipping build. When the app changes them, change the frames.
- House style: Lyra tokens (`--bg #0B0C10`, accent `#8B7CF6`, signal `#4ADE80`), Space
  Grotesk for headlines, JetBrains Mono for eyebrows and values, Inter as the stand-in for
  the iOS system font.

## Frames (design size 1398x645, export 2x = 2796x1290, iPhone 6.7"/6.9" landscape)

| # | Node name | Content |
|---|---|---|
| 1 | `01 Hero` | Mac camera picker card (FaceTime HD Camera, TetherCam with a checkmark, OBS Virtual Camera) and the small phone with the same picture. Reworked 2026-09-10 for the Mac-first positioning; exports as `01-hero-wired-into-mac.png` |
| 2 | `02 Connect` | three step cards plus the real Tools-menu screenshot `docs/images/obs-tools-menu.png` |
| 3 | `03 Lenses` | big phone plus the CAMERA card |
| 4 | `04 Level` | phone rotated 7 degrees plus the ADVANCED card |
| 5 | `05 Diagnostics` | big phone plus the DIAGNOSTICS card |
| 1 | `01 Hero v2` | 2026-09-10, v2 voice: "Your iPhone, instead of a webcam." plus the Mac camera picker card and the small phone; exports as `drafts-v2/01-hero.png` |
| 2 | `02 Connect v2` | 2026-09-10, "Download both apps. Plug in. Done." — two app cards (Mac + iPhone) joined by a cable and the Mac menu-bar hint ("Camera: ready", "Streaming from iPhone"); the OBS Tools-menu screenshot is gone; exports as `drafts-v2/02-connect.png` |
| 3 | `03 Lenses v2` | 2026-09-10, "Wide, ultra wide, telephoto or front." with the CAMERA card; sub says every Mac app sees the change; exports as `drafts-v2/03-lenses.png` |
| 4 | `04 Level v2` | 2026-09-10, "Turn the phone. Picture stays level." with the ADVANCED card; sub says the picture arrives upright on the Mac; exports as `drafts-v2/04-level.png` |
| 5 | `05 Diagnostics v2` | 2026-09-10, "See exactly what is happening." with the DIAGNOSTICS card incl. the real 0.3.0 row `Receiver = TetherCam for Mac 0.3.0`; exports as `drafts-v2/05-diagnostics.png` |
| OG | `OG v2` | 2026-09-10, website Open-Graph card 1200x630 (export 1x): headline, eyebrow "Two apps · one cable", camera picker card and the small phone; exports as `web/img/og.png` |
| A0 | `A0 App live` | Full-bleed app screen for the website gallery and the README: scene image, status capsule "Streaming 1080p30", gear icon, no headline. Added 2026-09-10 for #26; exports as `docs/images/app-live.png` (2796x1290) and, scaled, `web/img/app-live.png` / `.webp` (1400x646) |

The `v2` set (2026-09-10, issue #31) is the Mac-app-first voice: two apps, one cable, every
Mac app instead of OBS. It goes live with the **next iOS version** — 0.3.0 is in App Review,
and screenshots may not be swapped under a submission that is being reviewed. Until then the
v2 exports stay in `~/Desktop/TetherCam-AppStore/drafts-v2/` and are not uploaded. `OG v2` is
the exception: `web/img/og.png` is a website asset and ships with the next deploy.

Reusable components: `Phone` (722x352) and `Phone small` (430x210). Their `Screen` fill is
the scene image; change it once and every frame follows.

## Export and upload

1. Open `tethercam.pen` in Pen.app (the MCP tools only work on an open file).
2. Export the five frames as PNG at scale 2. Pen writes RGBA; Apple rejects alpha:
   `ffmpeg -i in.png -vf format=rgb24 -pix_fmt rgb24 out.png`.
3. Put them in `~/Desktop/TetherCam-AppStore/marketing-6.9/` with the file names listed in
   `scripts/asc-listing.py` (`SCREENSHOTS`).
4. `scripts/asc-listing.py --replace-screenshots` deletes the old set and uploads the new one
   in en-US and de-DE.
5. Website gallery: `cwebp -q 82 -resize 1398 0 in.png -o web/img/store-<name>.webp`.

## Withdrawn

The 30 s App Preview cut from the demo video was uploaded and then deleted on 2026-09-05
because it showed the owner. 0.1.0 has no App Preview. A face-free recording of the real
flow is the open follow-up.
