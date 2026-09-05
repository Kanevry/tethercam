# App Store Connect click path for TetherCam 0.1.0

Ordered. Each step is **OWNER** (a human in a browser, cannot be automated) or **AUTOMATED**
(already done in this repo or done by CI). Section references point into
`docs/APP-STORE-RELEASE.md`. Apple's own API documentation forbids creating app records via
API, so the record itself is unavoidably manual (section 2.1, step O4).

## Phase 0: preconditions

| # | Step | Who | Reference |
|---|---|---|---|
| 1 | developer.apple.com > Account > Membership details: membership active, team G3QZ66475M, note the renewal date | OWNER | 6.1 |
| 2 | App Store Connect > Business > Trader Status: declare EU trader status, submit address, phone, mail, wait for verification. Do this first, it gates EU distribution and takes days | OWNER | 2.1 O2, 6.2 |
| 3 | App Store Connect > Business > Agreements: accept the current Apple Developer Program License Agreement. Skip Paid Applications, the app is free | OWNER | 2.1 O3, 6.3 |
| 4 | developer.apple.com > Certificates, Identifiers & Profiles > Identifiers: confirm `at.gotzendorfer.tethercam` exists as an explicit App ID, not a wildcard | OWNER | 6.4 |
| 5 | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` in `ios-app/project.yml` | AUTOMATED (done, commit 581a800) | 2.2 C1, risk 4 |
| 6 | In-app privacy policy link in the settings sheet | AUTOMATED (done, commit 581a800) | 2.2 C2, risk 3 |
| 7 | `https://tethercam.app/privacy` and `https://tethercam.app/#faq` return 200 with a real contact address | AUTOMATED (done, live since 2026-09-05) | 2.2 C3, 6.9 |

## Phase 1: the app record

| # | Step | Who | Reference |
|---|---|---|---|
| 8 | App Store Connect > Apps > `+` > New App. Platform **iOS**, Name **TetherCam**, Primary Language **English (U.S.)**, Bundle ID **at.gotzendorfer.tethercam**, SKU **tethercam-ios**, User Access **Full**. The bundle id can never be changed afterwards | OWNER | 2.1 O4, 6.5 |
| 9 | App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys > `+`, role **App Manager**, download the `.p8` once. This is a different key from the notarization key in `docs/RELEASING.md` 1c | OWNER | 2.1 O5, 6.6 |
| 10 | github.com/Kanevry/tethercam > Settings > Secrets and variables > Actions: add `ASC_KEY_P8` (`base64 -i AuthKey_XXXX.p8 \| pbcopy`), `ASC_KEY_ID`, `ASC_ISSUER_ID`, then delete the `.p8` from disk | OWNER | 6.7 |

## Phase 2: compliance questionnaires, required before any external testing

| # | Step | Who | Reference |
|---|---|---|---|
| 11 | App Store Connect > TetherCam > App Privacy > Get Started > "Do you or your third-party partners collect data from this app?" **No** > Publish. Answers table in `docs/app-store/en-US.md` | OWNER | 2.1 O6, 6.10 |
| 12 | App Store Connect > TetherCam > Age Rating > Edit. Answer the 2025 questionnaire, all None or No, per the table in `docs/app-store/en-US.md`. Confirm the result reads **4+** | OWNER | 3.7, 6.11 |
| 13 | App Store Connect > TetherCam > Pricing and Availability: price **Free**, availability all countries and regions | OWNER | 3.8 |

## Phase 3: build

| # | Step | Who | Reference |
|---|---|---|---|
| 14 | Push tag `v0.1.0`, or run the `testflight-ios` workflow via workflow_dispatch. It generates the project with xcodegen, archives with `-allowProvisioningUpdates` and uploads with `packaging/ExportOptions.plist` | AUTOMATED (CI, needs the secrets from step 10) | 2, 2.3 |
| 15 | App Store Connect > TetherCam > TestFlight > iOS builds: wait for processing, 5 to 30 minutes. "Missing Compliance" must not appear; if it does, step 5 did not reach the build | OWNER (watch only) | 2.3 |

## Phase 4: TestFlight

| # | Step | Who | Reference |
|---|---|---|---|
| 16 | TestFlight > Internal Testing: add the team as internal testers, install, verify the app on a real device before anyone external sees it | OWNER | 2.3 |
| 17 | TestFlight > **Test Information**: beta app description, feedback email `office@gotzendorfer.at`, what to test, marketing URL, privacy policy URL. Required before external distribution | OWNER | 2.4, 6.13 |
| 18 | TestFlight > `+` next to **External Testing** > group name `Public Beta` > Create | OWNER | 2.4, 6.14 |
| 19 | In the group: **Add Builds** > select the build > fill "What to Test" > **Submit for Review**. Beta App Review, budget one to two working days. Paste `docs/app-store/review-notes.md` | OWNER | 2.4, 6.14 |
| 20 | When the status reads **Testing**: group > Testers > **Create Public Link** > Open to Anyone (or Filter by Criteria for iOS 17+) > optional tester limit > Confirm > copy the URL | OWNER | 2.4, 6.15 |
| 21 | Publish the public link on https://tethercam.app. Remember: every build expires 90 days after upload, so refresh at least quarterly | OWNER | 2.4, 6.15 |

## Phase 5: App Store submission

| # | Step | Who | Reference |
|---|---|---|---|
| 22 | Distribution > iOS App > **1.0 Prepare for Submission**. Paste name, subtitle, keywords, promotional text, description, what's new from `docs/app-store/en-US.md` | OWNER | 3.1, 3.2 |
| 23 | Add the **German (de-DE)** localization and paste `docs/app-store/de-DE.md` | OWNER | 3.2 |
| 24 | URLs: Support `https://tethercam.app/#faq`, Marketing `https://tethercam.app`, Privacy Policy `https://tethercam.app/privacy` | OWNER | 3.3 |
| 25 | Categories: primary **Photo & Video**, secondary **Utilities** | OWNER | 3.4 |
| 26 | Screenshots, **iPhone 6.9" set, landscape**: drag in `~/Desktop/TetherCam-AppStore/screenshots-6.9/01..04` in that order. 01 shows the standalone live preview and must stay first, it is the 4.2.3 defence. No iPad set exists or is accepted, the target is iPhone only | OWNER (files AUTOMATED) | 3.5, risk 1, risk 7 |
| 27 | App Preview: same 6.9" slot, drag in `~/Desktop/TetherCam-AppStore/app-preview-6.9-landscape.mp4` (29.5 s, 1920x886, H.264, 30 fps). Pick the poster frame in the App Store Connect editor; `app-preview-poster.png` shows the intended one, the OBS window with the TetherCam source live | OWNER (file AUTOMATED) | 3.5 |
| 28 | App icon: nothing to upload, App Store Connect takes the 1024x1024 from the build | AUTOMATED | 3.6 |
| 29 | Copyright `2026 Bernhard Goetzendorfer`. Sign-in required: **unchecked**, there is no account | OWNER | 3.9 |
| 30 | App Review Information > Notes: paste `docs/app-store/review-notes.md`, contact `office@gotzendorfer.at`, phone as required by the form | OWNER | 3.10, 4.7 |
| 31 | Version Release: **Manually release this version**, so the page goes live when the website and the plugin download are ready | OWNER | 3.11 |
| 32 | Build: select the processed build, confirm export compliance shows as answered | OWNER | 3.12 |
| 33 | **Add for Review > Submit**. Then watch App Store Connect > App Review for the status | OWNER | 3.13 |
| 34 | On rejection under 4.2.3 or 2.1: reply in the Resolution Center with the standalone feature list and a timestamp into the demo video. Do not resubmit an unchanged binary | OWNER | 3, closing paragraph |

## Verification

`bash docs/app-store/validate.sh` checks the character limits in `en-US.md` and `de-DE.md`
and the dimensions, colour depth and duration of every file in
`~/Desktop/TetherCam-AppStore/`. Run it before step 22.
