# Releasing TetherCam

One tag `vX.Y.Z` releases both artefacts: the macOS OBS plugin (signed, notarized
`.pkg` on a GitHub release) and the iOS app (TestFlight). Everything below is a
one-time setup except part 3, which is the recurring runbook.

Repository layout for remotes: **GitLab `agents/obs-iphone-usb-cam` stays primary**,
the public GitHub repository is a mirror that exists because GitHub Actions provides
free macOS runners and a release-asset host. Assume `Kanevry/tethercam` until
the name is decided; it appears in `scripts/install.sh` (`OWNER`/`REPO`) and in the
CHANGELOG link references.

---

## 1. One-time Apple setup

### 1a. Developer ID Application certificate (signs the `.plugin`)

Already present on this Mac: *Developer ID Application: Bernhard Goetzendorfer
(G3QZ66475M)*. Export it for CI:

1. Keychain Access → **My Certificates** → find the identity → expand it so the
   private key is selected together with the certificate.
2. Right-click → **Export 2 items…** → format *Personal Information Exchange (.p12)*
   → pick a password.
3. `base64 -i DeveloperIDApplication.p12 | pbcopy` → paste into the GitHub secret
   `MACOS_CERT_P12`; the password goes into `MACOS_CERT_PASSWORD`.
4. Delete the `.p12` from disk afterwards.

### 1b. Developer ID Installer certificate (signs the `.pkg`) — MISSING

Verified on this Mac on 2026-09-05: `security find-identity -v` lists a *Developer ID
Application* identity but **no *Developer ID Installer* identity**. These are two
different certificate types. `productbuild --sign` needs the Installer one, and Apple
**rejects unsigned `.pkg` submissions to notarytool**, so without it the release
produces a `.pkg` that Gatekeeper blocks on every machine but this one.

Create it (free, included in the membership):

1. developer.apple.com → Certificates, Identifiers & Profiles → **Certificates** →
   `+` → **Developer ID Installer** → follow the CSR flow (Keychain Access →
   Certificate Assistant → Request a Certificate From a Certificate Authority).
2. Download the `.cer`, double-click to import into the login keychain.
3. Export as `.p12` exactly as in 1a → `MACOS_INSTALLER_CERT_P12` /
   `MACOS_INSTALLER_CERT_PASSWORD`.

Until this exists, the release workflow still runs: it builds and packages, warns
loudly, skips notarization, and the `.zip` asset remains the only artifact users can
install without right-click-Open gymnastics.

### 1c. Notarization API key

App Store Connect → Users and Access → Integrations → **App Store Connect API** →
Team Keys → `+` → role **Developer** → download `AuthKey_<KEYID>.p8`. **It downloads
exactly once.** Set `NOTARY_KEY_P8` (base64), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.

### 1d. App Store Connect app record (for TestFlight)

The workflow can create certificates and profiles on demand
(`-allowProvisioningUpdates`), but it **cannot create the app record**. Without it the
upload fails with *"No suitable application records were found"*.

1. developer.apple.com → Identifiers → register the App ID
   `at.gotzendorfer.usbcam` (the current bundle id) if it is not registered yet.
2. appstoreconnect.apple.com → Apps → `+` → New App → platform iOS, pick the bundle
   id, set a name and SKU. The name must be unique across the whole App Store.
3. Issue a **second** API key with role **App Manager** →
   `ASC_KEY_P8` / `ASC_KEY_ID` / `ASC_ISSUER_ID`. The Developer-role key from 1c
   cannot upload builds.

### 1e. GitHub secrets

Set all of them at once: Settings → Secrets and variables → Actions. The full table,
including how to obtain and rotate each, is in [SECRETS.md](SECRETS.md).

---

## 2. One-time TestFlight distribution setup

TestFlight is the only free public distribution channel Apple offers for an iOS app
outside the App Store. Ad-hoc distribution caps at 100 registered device UDIDs, and
enterprise distribution requires a different, non-free program membership.

1. Upload a first build (part 3 does this).
2. App Store Connect → your app → **TestFlight** → fill in *Test Information*: what to
   test, feedback email, and — required for external testing — a privacy policy URL.
3. **Internal group**: up to 100 testers who are members of your team, available within
   minutes of processing, no review.
4. **External group**: create one, add the build, submit for **Beta App Review**. This
   is a real human review; budget a day or two for the first submission. Later builds
   of the same major version usually pass automatically.
5. Once approved: enable the **public link** on the external group. That URL is what
   goes into the README and the release notes. It works for anyone, capped at 10 000
   testers, and each build expires after 90 days — so a public TestFlight link needs a
   fresh build roughly every quarter to stay usable.

---

## 3. Cutting a release

```bash
# 1. Make sure the working tree is clean and the CHANGELOG Unreleased section
#    actually describes this release.
git status
$EDITOR CHANGELOG.md

# 2. Bump the version files. This writes obs-plugin/buildspec.json,
#    ios-app/project.yml (MARKETING_VERSION + CURRENT_PROJECT_VERSION) and
#    CHANGELOG.md. It does not commit.
scripts/release.sh 0.1.0

# 3. Read the diff, then commit it yourself.
git diff
git add obs-plugin/buildspec.json ios-app/project.yml CHANGELOG.md
git commit -m "chore(release): 0.1.0"

# 4. Create the annotated tag (refuses if the bump is not committed).
scripts/release.sh 0.1.0 --tag

# 5. Push. GitLab first, it is primary; the GitHub push is what starts the workflows.
git push origin HEAD && git push origin v0.1.0
git push github HEAD && git push github v0.1.0
```

Then watch the two workflows:

```bash
gh run watch --repo Kanevry/tethercam
```

`release-plugin.yml` takes roughly 10-20 minutes, most of it notarization.
`testflight-ios.yml` takes 10-15 minutes plus App Store Connect processing.

### 4. Verify before announcing

```bash
gh release download v0.1.0 --repo Kanevry/tethercam --dir /tmp/verify
cd /tmp/verify

# Checksums, as a user would.
shasum -a 256 -c TetherCam-obs-plugin.pkg.sha256

# The verdict that matters: this is what Gatekeeper says on a machine that has
# never seen your certificate.
spctl -a -t install -vv TetherCam-obs-plugin.pkg
#   expected: accepted, source=Notarized Developer ID

pkgutil --check-signature TetherCam-obs-plugin.pkg
xcrun stapler validate TetherCam-obs-plugin.pkg

# What the package would actually do, without installing it.
pkgutil --expand TetherCam-obs-plugin.pkg /tmp/verify/expanded
lsbom -s /tmp/verify/expanded/*component.pkg/Bom | grep obs-studio
#   expected: ./Library/Application Support/obs-studio/plugins/obs-iphone-usb-cam.plugin
```

The `.pkg` installs into the **installing user's home**, not into `/Library`: the
payload carries the relative path `Library/Application Support/obs-studio/plugins` and
the distribution enables only the `currentUserHome` domain. That is the same
construction the upstream obs-plugintemplate uses, and it is why no postinstall script
is needed. See the comment block in `packaging/distribution.xml.in`.

Then the one-liner, on a machine that is not this one:

```bash
curl -fsSL https://raw.githubusercontent.com/Kanevry/tethercam/main/scripts/install.sh | bash
```

Finally, publish: the GitHub release is created as a **draft** so you can read the
notes before anyone else does. Edit if needed, publish, then enable/announce the
TestFlight public link.

---

## Rolling back

There is no unpublish. If a release is broken:

1. Mark the GitHub release as pre-release or delete it, and delete the tag on both
   remotes.
2. TestFlight builds cannot be deleted, only **expired**: App Store Connect →
   TestFlight → the build → Expire. Testers stop being able to install it.
3. Ship `0.1.1` rather than re-tagging `0.1.0`. A moved tag desynchronises the two
   remotes and invalidates any checksum a user already recorded.
