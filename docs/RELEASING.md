# Releasing TetherCam

One tag `vX.Y.Z` releases both artefacts: the macOS OBS plugin (signed, notarized
`.pkg` on a GitHub release) and the iOS app (TestFlight). Everything below is a
one-time setup except part 3, which is the recurring runbook.

Repository layout for remotes: the public GitHub repository **`Kanevry/tethercam`** is
the source of truth and the release host, because GitHub Actions provides free macOS runners and a
release-asset host. That owner/repo pair appears in `scripts/install.sh`
(`OWNER`/`REPO`), in the Homebrew cask draft and in the CHANGELOG link references;
keep the three in sync. The user-facing entry point is **https://tethercam.app**.

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

### 1b. Developer ID Installer certificate (signs the `.pkg`): MISSING

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
   `at.gotzendorfer.tethercam` (the current bundle id) if it is not registered yet.
   The App Store Connect record must use exactly this bundle id. (Historical: the
   retired `at.gotzendorfer.usbcam` id is no longer built and needs no record.)
2. appstoreconnect.apple.com → Apps → `+` → New App → platform iOS, pick the bundle
   id, set a name and SKU. The name must be unique across the whole App Store.
3. Issue a **second** API key with role **App Manager** →
   `ASC_KEY_P8` / `ASC_KEY_ID` / `ASC_ISSUER_ID`. The Developer-role key from 1c
   cannot upload builds.

### 1e. GitHub secrets

Set all of them at once: Settings → Secrets and variables → Actions. The full table,
including how to obtain and rotate each, is in [SECRETS.md](SECRETS.md).

---

## Status 2026-09-05

Verified on this Mac and against the App Store Connect API on 2026-09-05.

**Set as GitHub secrets on `Kanevry/tethercam`** (names only): `ASC_KEY_P8`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.

All six point at **one** App Store Connect key, which is also in use by the
WalkAITalkie project and holds the **Admin** role. That is more authority than either
job needs and it couples two products to one credential: revoking it for one breaks
the other. It works today (Admin can both upload builds and notarize) and it is
deliberately temporary. Replace it with a dedicated **App Manager** key for
`ASC_*` and a dedicated **Developer** key for `NOTARY_*`, per the split argued in
[SECRETS.md](SECRETS.md), before anything ships publicly.

**Done:** the App ID `at.gotzendorfer.tethercam` is registered (`2G7A77TNZ6`,
platform UNIVERSAL). Step 1d.1 is complete.

**Still blocking, both owner-only — no API key can do either:**

- **App Store Connect app record** (step 1d.2). The API can register bundle ids but
  cannot create app records. Until someone creates it at appstoreconnect.apple.com →
  Apps → `+` → New App (platform iOS, bundle id `at.gotzendorfer.tethercam`, a
  globally unique name, any SKU), every upload fails with *"No suitable application
  records were found"*.
- **Developer ID Installer certificate** (step 1b). `security find-identity -v` still
  shows none. The `.pkg` therefore ships unsigned and unnotarized: Gatekeeper blocks
  it everywhere except the build host.

**Local alternative to the CI upload:** `scripts/appstore-upload.sh` runs the same
archive/export/upload flow on this Mac using the key at
`~/.appstoreconnect/private_keys/` (path only — the key never enters the repository).
`scripts/appstore-upload.sh --dry-run` exports a signed `.ipa` without uploading and
was verified green on 2026-09-05: `Authority=Apple Distribution: Bernhard
Goetzendorfer (G3QZ66475M)`, profile *iOS Team Store Provisioning Profile:
at.gotzendorfer.tethercam*, `get-task-allow=false`. Use it for the first real upload
once the app record exists — its errors are far more legible than a CI log.
`scripts/asc-api.sh` queries the API directly (`apps`, `bundle-ids`,
`builds <appId>`, `raw`) to check what actually exists on Apple's side.

The full runbook lives in `.claude/skills/distribute/SKILL.md`.

### Stand 2026-09-05 abends

CSR und privater Schluessel fuer das Developer ID Installer Zertifikat liegen
vorbereitet unter `~/.appstoreconnect/certs/developer-id-installer.certSigningRequest`
und `~/.appstoreconnect/certs/developer-id-installer.key` (nur Pfade, keine Inhalte
in diesem Dokument oder im Repository). Es fehlen weiterhin zwei owner-only Schritte:
die signierte `.cer`-Datei von developer.apple.com (aus der CSR) und der Export des
Developer ID Application Zertifikats als `.p12`. Solange beide fehlen, bleibt das Taggen
von `v0.1.0` blockiert, denn `productbuild --sign` und die Notarisierung brauchen die
Installer-Identitaet.

Ein lokaler `.pkg`-Testlauf wurde durchgefuehrt und verifiziert: das Paket ist
unsigniert (kein Installer-Zertifikat vorhanden), `spctl` weist es erwartungsgemaess
zurueck, das Installationsziel (`~/Library/Application Support/obs-studio/plugins/`)
ist korrekt gesetzt, und die enthaltene Plugin-Binary ist ein Universal Binary
(`x86_64` und `arm64`, verifiziert mit `lipo -info`).

---

## 2. One-time TestFlight distribution setup

TestFlight is the only free public distribution channel Apple offers for an iOS app
outside the App Store. Ad-hoc distribution caps at 100 registered device UDIDs, and
enterprise distribution requires a different, non-free program membership.

1. Upload a first build (part 3 does this).
2. App Store Connect → your app → **TestFlight** → fill in *Test Information*: what to
   test, feedback email, and (required for external testing) a privacy policy URL.
3. **Internal group**: up to 100 testers who are members of your team, available within
   minutes of processing, no review.
4. **External group**: create one, add the build, submit for **Beta App Review**. This
   is a real human review; budget a day or two for the first submission. Later builds
   of the same major version usually pass automatically.
5. Once approved: enable the **public link** on the external group. That URL is what
   goes into the README and the release notes. It works for anyone, capped at 10 000
   testers, and each build expires after 90 days, so a public TestFlight link needs a
   fresh build roughly every quarter to stay usable.

---

## 3. Cutting a release

**Release order:** bump, commit, `--tag`, push origin and github, the workflow builds a
draft release, then PUBLISH the draft. Skipping the publish step leaves
`releases/latest/download/...` on the website returning 404, because GitHub only serves
assets from a published release. Verify with:

```bash
curl -sI https://github.com/Kanevry/tethercam/releases/latest/download/TetherCam-obs-plugin.pkg
```

Expect `302` (redirect to the asset). A `404` means the draft is still unpublished.

TestFlight is the distribution path for the iOS app until an App Store release; there is
no equivalent "publish" step to forget there, App Store Connect processing does that on
its own once a build is uploaded.

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

# 5. Push. The GitHub push is what starts the workflows.
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

### 5. Erstlauf-Hinweis verifizieren

Das Plugin schreibt genau eine Hinweiszeile ins OBS-Log, wenn die aktive
Szenensammlung keine TetherCam-Quelle enthaelt (`obs-plugin/src/tools_menu.c`,
`hint_if_no_source`), ausgeloest sowohl bei `OBS_FRONTEND_EVENT_FINISHED_LOADING`
(Programmstart) als auch bei `OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED`
(Wechsel der Szenensammlung waehrend OBS laeuft, kein Neustart noetig). Merkt sich das
pro Szenensammlung in `first-run.json` unter `obs_module_config_path`. Enthaelt die
Sammlung bereits eine TetherCam-Quelle, loggt das Plugin stattdessen die
unterdrueckte Zeile `first-run hint: TetherCam source present in collection '<name>',
nothing to do` und setzt kein Flag. Eine Entwicklermaschine, auf der immer eine Quelle
liegt, sieht den eigentlichen Hinweis daher nie, wohl aber die unterdrueckte Zeile.

Der Hinweistext selbst steht nicht mehr im C-Code, sondern im Locale-Schluessel
`ToolsMenu.HintNoSource` (`obs-plugin/data/locale/en-US.ini` bzw. `de-DE.ini`), mit der
Anleitungs-URL `https://tethercam.app/#quick-start` in beiden Sprachen eingebettet. Der
englische Text beginnt mit Grossbuchstaben ("No TetherCam source in scene collection
'%s'. ..."), der deutsche mit "Keine TetherCam-Quelle in der Szenensammlung '%s'. ...".
Ein Log-Grep auf einen der beiden Wortlaute greift also nur bei der jeweiligen
OBS-Sprache; robust gegen beide ist ein Grep auf die URL. So wird der Hinweis belegt:

```bash
CFG="$HOME/Library/Application Support/obs-studio/plugin_config/obs-iphone-usb-cam"
LOGS="$HOME/Library/Application Support/obs-studio/logs"

# 1. Flag zuruecksetzen (OBS vorher beenden).
mv "$CFG/first-run.json" "$CFG/first-run.json.bak" 2>/dev/null || true

# 2. OBS mit einer Szenensammlung OHNE TetherCam-Quelle starten
#    (Szenensammlung -> Neu, z. B. "leer"), dann OBS wieder beenden.
#    Alternativ, ohne Neustart: waehrend OBS laeuft auf eine leere Sammlung
#    wechseln, das feuert OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED.

# 3. Die Zeile muss im neuesten Log stehen, genau einmal, in jeder OBS-Sprache.
grep -h "tethercam.app/#quick-start" "$LOGS/$(ls -t "$LOGS" | head -1)"
#   erwartet (en-US): <Zeit>: [obs-iphone-usb-cam] [iphone-cam] No TetherCam source in scene collection 'leer'. Use Tools -> 'TetherCam: Add iPhone camera to current scene', then open TetherCam on the iPhone. Guide: https://tethercam.app/#quick-start
#   erwartet (de-DE): <Zeit>: [obs-iphone-usb-cam] [iphone-cam] Keine TetherCam-Quelle in der Szenensammlung 'leer'. Ueber Tools -> 'TetherCam: iPhone zur aktuellen Szene hinzufuegen' hinzufuegen, dann TetherCam am iPhone oeffnen. Anleitung: https://tethercam.app/#quick-start

# 4. Das Flag ist gesetzt.
cat "$CFG/first-run.json"
#   erwartet: {"leer":true}

# 5. OBS mit derselben Sammlung ein zweites Mal starten (oder erneut dorthin
#    wechseln) und beenden: das neueste Log darf die Zeile NICHT mehr enthalten.
grep -c "tethercam.app/#quick-start" "$LOGS/$(ls -t "$LOGS" | head -1)"
#   erwartet: 0
```

Stand 2026-09-05: nicht live belegt, und die vorherige Fassung dieses Abschnitts
behauptete faelschlich, das *installierte* Plugin enthalte den Hinweis-String. Tatsaechlich
laeuft OBS seit heute Nachmittag ununterbrochen (siehe "Nie einen laufenden
OBS-Prozess beenden" oben) und haelt daher weiter die alte Plugin-Binary aus
`~/Library/Application Support/obs-studio/plugins/`, gebaut 16:11 Uhr, **vor** dem
Erstlauf-Hinweis-Feature: `strings ".../obs-iphone-usb-cam" | grep -c
"ToolsMenu.HintNoSource"` liefert dort `0`. Die frisch gebaute Binary unter
`obs-plugin/build_macos/RelWithDebInfo/obs-iphone-usb-cam.plugin` (20:44 Uhr) enthaelt
den Schluessel dagegen wie erwartet zweimal (`grep -c "ToolsMenu.HintNoSource"` liefert
`2`, einmal aus dem C-Code-Literal, einmal aus der eingebetteten `.ini`-Ressource). Kein
Log unter `logs/` enthaelt die Zeile und `plugin_config/obs-iphone-usb-cam/` existiert
nicht, weil bislang jede Sammlung eine TetherCam-Quelle hatte. Das Rezept oben ist nach
dem naechsten OBS-Neustart mit der neuen Plugin-Version einmal durchzulaufen.

---

## Rolling back

There is no unpublish. If a release is broken:

1. Mark the GitHub release as pre-release or delete it, and delete the tag on both
   remotes.
2. TestFlight builds cannot be deleted, only **expired**: App Store Connect →
   TestFlight → the build → Expire. Testers stop being able to install it.
3. Ship `0.1.1` rather than re-tagging `0.1.0`. A moved tag desynchronises the two
   remotes and invalidates any checksum a user already recorded.

## CI-Umgebung: warum ASan nur auf Linux laeuft

Der `shared-tests`-Job in `.github/workflows/ci-plugin.yml` baut den C-Kern zweimal:
einmal normal und einmal mit `-DIUCM_SANITIZE=ON` (Default-Liste `address,undefined`).
Beide laufen auf `ubuntu-latest`, und der Sanitizer-Lauf ist ein **hartes Gate**: kein
`continue-on-error`. Das ist kein Zufall: dieser Lauf hat beim allerersten CI-Durchgang
(Kanevry/tethercam, Run 33969653856) einen Overread gefunden, den die Mac-Suite nicht
sehen konnte.

Lokal auf macOS ist ASan derzeit nicht benutzbar. Die Apple-clang-17-ASan-Runtime
verklemmt sich auf macOS 26 (Darwin 25.x) waehrend ihrer eigenen Initialisierung: das
Shadow-Memory-Setup re-entriert `libsystem_malloc` und dreht in
`StaticSpinMutex::LockSlow`, noch vor `main()`. Jedes `-fsanitize=address`-Binary haengt
dort. Deshalb wird lokal nur UBSan gebaut:

```bash
cmake -S shared -B shared/build-ubsan -DIUCM_SANITIZE=ON -DIUCM_SANITIZE_LIST=undefined
cmake --build shared/build-ubsan && ctest --test-dir shared/build-ubsan --output-on-failure
```

Fuer Speicherfehler ist auf dem Mac Guard Malloc der Ersatz. Es legt jede
`malloc`-Allokation an eine Guard-Page, ein Byte darueber hinaus faultet sofort:

```bash
DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib MALLOC_STRICT_SIZE=1 \
  ./shared/build-plain/test_frame_parser_fuzz
```

Damit das greift, muessen Testeingaben auf dem Heap und exakt bemessen liegen, denn ein
`static uint8_t noise[8192]` hat keine Guard-Page dahinter.
`test_feed_never_reads_past_chunk_end` in `shared/tests/test_frame_parser_fuzz.c` ist
genau dafuer gebaut.

**Konsequenz fuer Releases:** ein roter `shared-tests`-Job blockiert. Nicht mergen und
nicht taggen, solange er rot ist, auch wenn die macOS-Jobs gruen sind, denn die koennen
diese Fehlerklasse hier nicht sehen.
