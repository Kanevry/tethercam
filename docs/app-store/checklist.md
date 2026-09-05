# App Store Connect click path for TetherCam 0.1.0

Ordered. Each step is **OWNER** (a human in a browser, cannot be automated) or **AUTOMATED**
(already done in this repo or done by CI). Section references point into
`docs/APP-STORE-RELEASE.md`. Apple's own API documentation forbids creating app records via
API, so the record itself is unavoidably manual (section 2.1, step O4).

## Phase 0: preconditions

| # | Step | Who | Reference |
|---|---|---|---|
| 1 | developer.apple.com > Account > Membership details: membership active, team G3QZ66475M, note the renewal date | OWNER | 6.1 |
| 2 | App Store Connect > Business > Trader Status: declare EU trader status, submit address, phone, mail, wait for verification. Do this first, it gates EU distribution and takes days | DONE 2026-09-05: Compliance row "Gesetz ueber digitale Dienste" Aktiv since 2026-03-11, DAC7 activated 2026-09-05 | 2.1 O2, 6.2 |
| 3 | App Store Connect > Business > Agreements: accept the current Apple Developer Program License Agreement. Skip Paid Applications, the app is free | DONE (both contracts active, seen in App Store Connect > Business on 2026-09-05) | 2.1 O3, 6.3 |
| 4 | developer.apple.com > Certificates, Identifiers & Profiles > Identifiers: confirm `at.gotzendorfer.tethercam` exists as an explicit App ID, not a wildcard | DONE 2026-09-05 (registered via API, id 2G7A77TNZ6) | 6.4 |
| 5 | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` in `ios-app/project.yml` | AUTOMATED (done, commit 581a800) | 2.2 C1, risk 4 |
| 6 | In-app privacy policy link in the settings sheet | AUTOMATED (done, commit 581a800) | 2.2 C2, risk 3 |
| 7 | `https://tethercam.app/privacy` and `https://tethercam.app/#faq` return 200 with a real contact address | AUTOMATED (done, live since 2026-09-05) | 2.2 C3, 6.9 |

## Phase 1: the app record

| # | Step | Who | Reference |
|---|---|---|---|
| 8 | App Store Connect > Apps > `+` > New App. Platform **iOS**, Name **TetherCam**, Primary Language **English (U.S.)**, Bundle ID **at.gotzendorfer.tethercam**, SKU **tethercam-ios**, User Access **Full**. The bundle id can never be changed afterwards | DONE 2026-09-05 (app id 6808997521) | 2.1 O4, 6.5 |
| 9 | App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys > `+`, role **App Manager**, download the `.p8` once. This is a different key from the notarization key in `docs/RELEASING.md` 1c | DONE 2026-09-05 with the existing Admin team key (shared with WalkAITalkie); a dedicated App Manager key is optional hygiene, see `docs/SECRETS.md` | 2.1 O5, 6.6 |
| 10 | github.com/Kanevry/tethercam > Settings > Secrets and variables > Actions: add `ASC_KEY_P8` (`base64 -i AuthKey_XXXX.p8 \| pbcopy`), `ASC_KEY_ID`, `ASC_ISSUER_ID`, then delete the `.p8` from disk | DONE 2026-09-05 (all six ASC_*/NOTARY_* secrets set) | 6.7 |

## Phase 2: compliance questionnaires, required before any external testing

| # | Step | Who | Reference |
|---|---|---|---|
| 11 | App Store Connect > TetherCam > App Privacy > Get Started > "Do you or your third-party partners collect data from this app?" **No** > Publish. Answers table in `docs/app-store/en-US.md` | OWNER | 2.1 O6, 6.10 |
| 12 | App Store Connect > TetherCam > Age Rating > Edit. Answer the 2025 questionnaire, all None or No, per the table in `docs/app-store/en-US.md`. Confirm the result reads **4+** | DONE 2026-09-05 via `scripts/asc-listing.py` | 3.7, 6.11 |
| 13 | App Store Connect > TetherCam > Pricing and Availability: price **Free**, availability all countries and regions | DONE 2026-09-05 via API (Free, 175 territories) | 3.8 |

## Phase 3: build

| # | Step | Who | Reference |
|---|---|---|---|
| 14 | Push tag `v0.1.0`, or run the `testflight-ios` workflow via workflow_dispatch. It generates the project with xcodegen, archives with `-allowProvisioningUpdates` and uploads with `packaging/ExportOptions.plist` | DONE 2026-09-05: build 0.1.0 (2) uploaded locally with `scripts/appstore-upload.sh` | 2, 2.3 |
| 15 | App Store Connect > TetherCam > TestFlight > iOS builds: wait for processing, 5 to 30 minutes. "Missing Compliance" must not appear; if it does, step 5 did not reach the build | DONE: processing state VALID, export compliance answered in the build | 2.3 |

## Phase 4: TestFlight

| # | Step | Who | Reference |
|---|---|---|---|
| 16 | TestFlight > Internal Testing: add the team as internal testers, install, verify the app on a real device before anyone external sees it | OWNER | 2.3 |
| 17 | TestFlight > **Test Information**: beta app description, feedback email `office@gotzendorfer.at`, what to test, marketing URL, privacy policy URL. Required before external distribution | DONE 2026-09-05 via API | 2.4, 6.13 |
| 18 | TestFlight > `+` next to **External Testing** > group name `Public Beta` > Create | DONE 2026-09-05 via API | 2.4, 6.14 |
| 19 | In the group: **Add Builds** > select the build > fill "What to Test" > **Submit for Review**. Beta App Review, budget one to two working days. Paste `docs/app-store/review-notes.md` | DONE 2026-09-05: build in the group, Beta App Review WAITING_FOR_REVIEW | 2.4, 6.14 |
| 20 | When the status reads **Testing**: group > Testers > **Create Public Link** > Open to Anyone (or Filter by Criteria for iOS 17+) > optional tester limit > Confirm > copy the URL | DONE: https://testflight.apple.com/join/wmT74Ry8 (accepts testers once Beta App Review approves) | 2.4, 6.15 |
| 21 | Publish the public link on https://tethercam.app. Remember: every build expires 90 days after upload, so refresh at least quarterly | DONE 2026-09-05 (site, README, llms.txt) | 2.4, 6.15 |

## Phase 5: App Store submission

| # | Step | Who | Reference |
|---|---|---|---|
| 22 | Distribution > iOS App > **1.0 Prepare for Submission**. Paste name, subtitle, keywords, promotional text, description, what's new from `docs/app-store/en-US.md` | DONE 2026-09-05 via `scripts/asc-listing.py` (no What's New on a first version, Apple rejects the field) | 3.1, 3.2 |
| 23 | Add the **German (de-DE)** localization and paste `docs/app-store/de-DE.md` | DONE 2026-09-05 via API | 3.2 |
| 24 | URLs: Support `https://tethercam.app/#faq`, Marketing `https://tethercam.app`, Privacy Policy `https://tethercam.app/privacy` | DONE 2026-09-05 via API | 3.3 |
| 25 | Categories: primary **Photo & Video**, secondary **Utilities** | DONE 2026-09-05 via API | 3.4 |
| 26 | Screenshots, **iPhone 6.9" set, landscape**: five marketing frames from `tethercam.pen` (Pen design file, exported 2796x1290, no alpha) in `~/Desktop/TetherCam-AppStore/marketing-6.9/01..05`: OBS + phone hero, three steps with the real Tools menu, lens picker, horizon, diagnostics. The camera picture is AI-generated (no faces). No iPad set exists or is accepted, the target is iPhone only | DONE 2026-09-05 via API (en-US and de-DE, asset state COMPLETE) | 3.5, risk 1, risk 7 |
| 27 | App Preview: same 6.9" slot, drag in `~/Desktop/TetherCam-AppStore/app-preview-6.9-landscape.mp4` (29.5 s, 1920x886, H.264, 30 fps). Pick the poster frame in the App Store Connect editor; `app-preview-poster.png` shows the intended one, the OBS window with the TetherCam source live | WITHDRAWN 2026-09-05: the 30 s cut showed the owner's face; no App Preview in 0.1.0. Optional later: a face-free recording | 3.5 |
| 28 | App icon: nothing to upload, App Store Connect takes the 1024x1024 from the build | AUTOMATED | 3.6 |
| 29 | Copyright `2026 Bernhard Goetzendorfer`. Sign-in required: **unchecked**, there is no account | DONE 2026-09-05 via API (copyright, content rights, no demo account) | 3.9 |
| 30 | App Review Information > Notes: paste `docs/app-store/review-notes.md`, contact `office@gotzendorfer.at`, phone as required by the form | DONE 2026-09-05 via API | 3.10, 4.7 |
| 31 | Version Release: **Manually release this version**, so the page goes live when the website and the plugin download are ready | DONE 2026-09-05 via API (releaseType MANUAL) | 3.11 |
| 32 | Build: select the processed build, confirm export compliance shows as answered | DONE 2026-09-05 via API (build attached) | 3.12 |
| 33 | **Add for Review > Submit**. Blocked only by step 11 (App Privacy has no API). After step 11 either click Add for Review, or let the agent finish the prepared review submission `776750a6-a640-4696-92bf-c53cb4d21a14` via API | OWNER | 3.13 |
| 34 | On rejection under 4.2.3 or 2.1: reply in the Resolution Center with the standalone feature list and a timestamp into the demo video. Do not resubmit an unchanged binary | OWNER | 3, closing paragraph |

## Verification

`bash docs/app-store/validate.sh` checks the character limits in `en-US.md` and `de-DE.md`
and the dimensions, colour depth and duration of every file in
`~/Desktop/TetherCam-AppStore/`. Run it before step 22.

## Nach der Einreichung (2026-09-05 abends)

Offene Owner-Schritte, gesammelt nach dem Einreichen des iOS-Listings:

| # | Step | Who | Reference |
|---|---|---|---|
| 35 | Developer ID Installer Zertifikat: `.cer` von developer.apple.com holen (aus der CSR unter `~/.appstoreconnect/certs/developer-id-installer.certSigningRequest`) und Developer ID Application Zertifikat als `.p12` exportieren, beides nach `~/.appstoreconnect/certs/` | OWNER | RELEASING.md 1b |
| 36 | GitHub-Secrets `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `MACOS_CODESIGN_IDENT`, `MACOS_INSTALLER_CERT_P12`, `MACOS_INSTALLER_CERT_PASSWORD` setzen, sobald die Dateien aus Schritt 35 vorliegen | AUTOMATED sobald Dateien existieren (Agent setzt sie) | RELEASING.md 1a, 1b |
| 37 | Der leere macOS-Review-Submission-Entwurf `776750a6-a640-4696-92bf-c53cb4d21a14` (Plattform MAC_OS, Status READY_FOR_REVIEW laut API am 2026-09-05; die iOS-Einreichung ist `0e749dcd-74bb-43c1-a597-2d64408dfc87`, WAITING_FOR_REVIEW) in App Store Connect verwerfen; per API weder loeschbar noch abbrechbar. Blockiert nichts | OWNER | 3.13 |
| 38 | GitHub Social Preview hochladen: Settings > General > Social preview, Bilddatei `web/img/og.png` | OWNER | n/a |
