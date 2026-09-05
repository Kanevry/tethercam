# Secrets

Every value below lives only in **GitHub → Settings → Secrets and variables → Actions →
Repository secrets**. None of them belongs in the repository, in a `.env`, in a commit
message, or in a workflow log. The workflows only ever check *presence* (`test -n`),
never print a value, and write decoded key material to `$RUNNER_TEMP` with mode 0600,
deleted in an `if: always()` step.

Binary material (`.p12`, `.p8`) is stored base64-encoded, because GitHub secrets are
text. Encode with:

```bash
base64 -i cert.p12 | pbcopy      # macOS, no trailing newline issues
```

## macOS plugin release , `.github/workflows/release-plugin.yml`

| Secret | Purpose | How to obtain | Rotation |
|---|---|---|---|
| `MACOS_CERT_P12` | Developer ID **Application** certificate + private key, base64. Signs the `.plugin` bundle with Hardened Runtime. | Keychain Access → My Certificates → *Developer ID Application: Bernhard Goetzendorfer (G3QZ66475M)* → right-click → Export → `.p12` → `base64 -i`. | Certificate expires after 5 years. Re-export and replace both this and `MACOS_CERT_PASSWORD` when it does, or immediately on suspected exposure , a leaked Developer ID key can sign malware in your name. |
| `MACOS_CERT_PASSWORD` | Password chosen during the `.p12` export. | You pick it at export time. | Together with the certificate. |
| `MACOS_INSTALLER_CERT_P12` | Developer ID **Installer** certificate + private key, base64. Signs the `.pkg`. **Not yet present on this Mac** , see docs/RELEASING.md, step 1b. | developer.apple.com → Certificates → `+` → Developer ID Installer → issue → download → import into Keychain → export as `.p12`. | Same as the Application certificate. |
| `MACOS_INSTALLER_CERT_PASSWORD` | Password for that `.p12`. | You pick it at export time. | Together with the certificate. |
| `MACOS_CODESIGN_IDENT` | *Optional.* Exact identity string, e.g. `Developer ID Application: Bernhard Goetzendorfer (G3QZ66475M)`. Only needed if the keychain holds more than one Developer ID Application identity; otherwise the workflow derives it from the imported certificate. | `security find-identity -v -p codesigning` | Only when the certificate name changes. |
| `NOTARY_KEY_P8` | App Store Connect API key (`AuthKey_XXXX.p8`), base64. Used by `xcrun notarytool`. | appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → Team Keys → `+` → role **Developer** → download. **The `.p8` downloads exactly once.** | Revoke and reissue on exposure or when the key holder changes. No expiry. |
| `NOTARY_KEY_ID` | The key id, ten characters, shown next to the key in the same table. Also embedded in the downloaded filename `AuthKey_<KEYID>.p8`. | Same page. | With the key. |
| `NOTARY_ISSUER_ID` | Team issuer id, a UUID, shown once above the key table. Identical for every key of the team. | Same page. | Practically never; it is a team identifier, not a credential on its own. |

## iOS TestFlight , `.github/workflows/testflight-ios.yml`

| Secret | Purpose | How to obtain | Rotation |
|---|---|---|---|
| `ASC_KEY_P8` | App Store Connect API key, base64. Authenticates `xcodebuild -allowProvisioningUpdates` and the TestFlight upload. Needs role **App Manager** (or Admin) , the Developer role used for notarization cannot upload builds. | Same page as `NOTARY_KEY_P8`, but issue a **separate key** with the App Manager role. Downloads exactly once. | Revoke and reissue on exposure. |
| `ASC_KEY_ID` | Key id for that key. | Same page. | With the key. |
| `ASC_ISSUER_ID` | Team issuer id (same UUID as `NOTARY_ISSUER_ID`). | Same page. | Practically never. |

Two separate keys rather than one shared key with the wider role: the notarization key
then cannot upload builds, and revoking one does not break the other.

## Minimum set per outcome

- **Fork, just wants to build**: none. `ci-plugin.yml` runs with ad-hoc signing.
- **Signed but not notarized `.pkg`** (Gatekeeper still blocks it on other machines):
  `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `MACOS_INSTALLER_CERT_P12`,
  `MACOS_INSTALLER_CERT_PASSWORD`.
- **Distributable plugin**: the four above plus `NOTARY_KEY_P8`, `NOTARY_KEY_ID`,
  `NOTARY_ISSUER_ID`.
- **TestFlight**: `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.

## If a value leaks

Rotate, do not redact. A secret that appeared in a log, a transcript or a pushed file is
compromised the moment it appeared; deleting the log afterwards does not undo it.

1. Revoke the certificate (developer.apple.com) or the API key (App Store Connect) first.
2. Issue a replacement, update the GitHub secret.
3. Only then clean up the artifact that leaked it.
4. Note the date and reason somewhere durable.
