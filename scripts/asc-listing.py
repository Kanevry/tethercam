#!/usr/bin/env python3
"""Push the App Store listing for TetherCam from docs/app-store/ to App Store Connect.

Idempotent: re-running PATCHes existing localizations and skips media that already
exists in the target set. Needs ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH from the
environment or the git-ignored .env.local. Never prints the key or a token.

Usage:
  scripts/asc-listing.py [--app-id ID] [--media-dir ~/Desktop/TetherCam-AppStore]
                         [--skip-media] [--skip-pricing] [--dry-run]
"""
import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "at.gotzendorfer.tethercam"
DOCS = os.path.join(ROOT, "docs", "app-store")

REVIEW_CONTACT = {
    "contactFirstName": "Bernhard",
    "contactLastName": "Götzendorfer",
    "contactPhone": "+436604301954",
    "contactEmail": "office@gotzendorfer.at",
}
COPYRIGHT = "2026 Bernhard Goetzendorfer"
SUPPORT_URL = "https://tethercam.app/#faq"
MARKETING_URL = "https://tethercam.app"
PRIVACY_URL = "https://tethercam.app/privacy"
PRIMARY_CATEGORY = "PHOTO_AND_VIDEO"
SECONDARY_CATEGORY = "UTILITIES"
SCREENSHOT_DISPLAY_TYPE = "APP_IPHONE_67"   # 6.7"/6.9" iPhone set, 2796x1290 landscape
PREVIEW_TYPE = "IPHONE_67"
SCREENSHOTS = [
    "screenshots-6.9/01-live-preview.png",
    "screenshots-6.9/02-camera-lens-picker.png",
    "screenshots-6.9/03-rotation-leveling.png",
    "screenshots-6.9/04-diagnostics.png",
]
PREVIEW = "app-preview-6.9-landscape.mp4"


# --- auth ------------------------------------------------------------------

def load_env_local():
    p = os.path.join(ROOT, ".env.local")
    if os.path.exists(p):
        for line in open(p):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"'))


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def mint_token():
    kid = os.environ.get("ASC_KEY_ID")
    iss = os.environ.get("ASC_ISSUER_ID")
    path = os.path.expanduser(os.environ.get("ASC_KEY_PATH", f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8"))
    if not (kid and iss and os.path.exists(path)):
        sys.exit("error: ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH not set (see docs/SECRETS.md)")
    now = int(time.time())
    hdr = b64url(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
    pl = b64url(json.dumps({"iss": iss, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"}).encode())
    msg = f"{hdr}.{pl}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", path], input=msg, capture_output=True, check=True).stdout
    i = 2
    l = der[i + 1]; r = der[i + 2:i + 2 + l]; i += 2 + l
    l2 = der[i + 1]; s = der[i + 2:i + 2 + l2]
    r = r.lstrip(b"\x00").rjust(32, b"\x00"); s = s.lstrip(b"\x00").rjust(32, b"\x00")
    return f"{hdr}.{pl}.{b64url(r + s)}"


TOKEN = None
DRY = False
FIRST_VERSION = True


def api(method, path, body=None, ok=(200, 201, 204)):
    global TOKEN
    if TOKEN is None:
        TOKEN = mint_token()
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    if DRY and method != "GET":
        print(f"  [dry-run] {method} {path} {json.dumps(body)[:160] if body else ''}")
        return {}
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {detail[:800]}") from None


def put_chunk(op, chunk):
    if DRY:
        return
    req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
    for h in op.get("requestHeaders", []):
        req.add_header(h["name"], h["value"])
    with urllib.request.urlopen(req) as resp:
        resp.read()


# --- metadata parsing ------------------------------------------------------

def parse_blocks(md_path):
    """Return {heading: first fenced block text} for every '## X (limit N)' section."""
    out = {}
    heading = None
    fence = None
    for line in open(md_path, encoding="utf-8"):
        line = line.rstrip("\n")
        if fence is not None:
            if line.startswith("```"):
                out[heading] = "\n".join(fence)
                fence = None
                heading = None
            else:
                fence.append(line)
            continue
        if line.startswith("## "):
            heading = re.sub(r"\s*\(limit \d+\)\s*$", "", line[3:]).strip()
        elif line.startswith("```") and heading is not None and heading not in out:
            fence = []
    return out


def load_locale(name):
    b = parse_blocks(os.path.join(DOCS, f"{name}.md"))
    for k in ("Name", "Subtitle", "Keywords", "Promotional text", "Description", "What's New"):
        assert k in b, f"{name}.md: missing block {k}"
    return b


def review_notes():
    b = open(os.path.join(DOCS, "review-notes.md"), encoding="utf-8").read()
    m = re.search(r"```\n(.*?)\n```", b, re.S)
    return m.group(1).strip()


# --- steps -----------------------------------------------------------------

def step(msg):
    print(f"\n== {msg}")


def find_app(app_id):
    if app_id:
        return app_id
    d = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if not d["data"]:
        sys.exit(f"error: no app record for {BUNDLE_ID}; create it in App Store Connect first")
    return d["data"][0]["id"]


def ensure_version(app_id, version_string):
    d = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=5")
    editable = [v for v in d["data"] if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    if not editable:
        sys.exit("error: no editable App Store version; create one in App Store Connect")
    v = editable[0]
    global FIRST_VERSION
    FIRST_VERSION = len(d["data"]) == 1
    attrs = {"releaseType": "MANUAL", "copyright": COPYRIGHT}
    if v["attributes"]["versionString"] != version_string:
        attrs["versionString"] = version_string
    api("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": attrs}})
    print(f"  version {v['id']}: {v['attributes']['versionString']} -> {version_string}, MANUAL release, copyright set")
    return v["id"]


def upsert_version_localization(version_id, locale, b):
    d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    existing = {x["attributes"]["locale"]: x["id"] for x in d["data"]}
    attrs = {
        "description": b["Description"],
        "keywords": b["Keywords"],
        "promotionalText": b["Promotional text"],
        "supportUrl": SUPPORT_URL,
        "marketingUrl": MARKETING_URL,
    }
    # whatsNew is rejected by App Store Connect on the very first version of an app
    # ("cannot be edited at this time"); it only exists from the second version on.
    if FIRST_VERSION is False:
        attrs["whatsNew"] = b["What's New"]
    if locale in existing:
        api("PATCH", f"/v1/appStoreVersionLocalizations/{existing[locale]}", {"data": {"type": "appStoreVersionLocalizations", "id": existing[locale], "attributes": attrs}})
        print(f"  {locale}: version localization updated")
        return existing[locale]
    attrs["locale"] = locale
    r = api("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": attrs, "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
    print(f"  {locale}: version localization created")
    return r.get("data", {}).get("id", "dry")


def app_info(app_id):
    d = api("GET", f"/v1/apps/{app_id}/appInfos")
    editable = [x for x in d["data"] if x["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    return (editable or d["data"])[0]["id"]


def upsert_info_localization(info_id, locale, b):
    d = api("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations")
    existing = {x["attributes"]["locale"]: x["id"] for x in d["data"]}
    attrs = {"subtitle": b["Subtitle"], "privacyPolicyUrl": PRIVACY_URL}
    if locale in existing:
        api("PATCH", f"/v1/appInfoLocalizations/{existing[locale]}", {"data": {"type": "appInfoLocalizations", "id": existing[locale], "attributes": attrs}})
        print(f"  {locale}: app info localization updated (subtitle, privacy URL)")
    else:
        attrs.update({"locale": locale, "name": b["Name"]})
        api("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": attrs, "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}}}})
        print(f"  {locale}: app info localization created (name, subtitle, privacy URL)")


def set_categories(info_id):
    api("PATCH", f"/v1/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id, "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": PRIMARY_CATEGORY}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": SECONDARY_CATEGORY}},
    }}})
    print(f"  categories: {PRIMARY_CATEGORY} / {SECONDARY_CATEGORY}")


def set_age_rating(info_id):
    d = api("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration")
    decl_id = d["data"]["id"]
    attrs = {
        "advertising": False,
        "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        "contests": "NONE",
        "gambling": False,
        "gamblingSimulated": "NONE",
        "gunsOrOtherWeapons": "NONE",
        "healthOrWellnessTopics": False,
        "lootBox": False,
        "medicalOrTreatmentInformation": "NONE",
        "messagingAndChat": False,
        "parentalControls": False,
        "profanityOrCrudeHumor": "NONE",
        "ageAssurance": False,
        "sexualContentGraphicAndNudity": "NONE",
        "sexualContentOrNudity": "NONE",
        "socialMedia": False,
        "horrorOrFearThemes": "NONE",
        "matureOrSuggestiveThemes": "NONE",
        "unrestrictedWebAccess": False,
        "userGeneratedContent": False,
        "violenceCartoonOrFantasy": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
        "violenceRealistic": "NONE",
    }
    api("PATCH", f"/v1/ageRatingDeclarations/{decl_id}", {"data": {"type": "ageRatingDeclarations", "id": decl_id, "attributes": attrs}})
    print("  age rating declaration: everything None/No")


def set_review_detail(version_id):
    d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")
    attrs = dict(REVIEW_CONTACT, demoAccountRequired=False, notes=review_notes())
    if d.get("data"):
        rid = d["data"]["id"]
        api("PATCH", f"/v1/appStoreReviewDetails/{rid}", {"data": {"type": "appStoreReviewDetails", "id": rid, "attributes": attrs}})
        print("  review detail updated (contact, notes)")
    else:
        api("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs, "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
        print("  review detail created (contact, notes)")


def set_free_price(app_id):
    d = api("GET", f"/v1/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=1")
    pp = d["data"][0]
    assert pp["attributes"].get("customerPrice") in (None, "0.0", "0"), pp
    body = {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${price1}"}]},
        }},
        "included": [{"type": "appPrices", "id": "${price1}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": pp["id"]}}}}],
    }
    api("POST", "/v1/appPriceSchedules", body)
    print("  price schedule: Free (USA base, tier 0)")


def set_availability(app_id):
    try:
        cur = api("GET", f"/v1/apps/{app_id}/appAvailabilityV2")
        print(f"  availability already set (availableInNewTerritories={cur['data']['attributes'].get('availableInNewTerritories')}); leaving as is")
        return
    except RuntimeError as e:
        if "404" not in str(e):
            raise
    terr = api("GET", "/v1/territories?limit=200")["data"]
    ids = [t["id"] for t in terr]
    body = {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                   "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{t{i}}}"} for i in range(len(ids))]}}},
        "included": [{"type": "territoryAvailabilities", "id": f"${{t{i}}}", "attributes": {"available": True},
                      "relationships": {"territory": {"data": {"type": "territories", "id": tid}}}} for i, tid in enumerate(ids)],
    }
    api("POST", "/v2/appAvailabilities", body)
    print(f"  availability: all {len(ids)} territories, available in new territories")


def upload_asset(create_path, set_rel_type, set_id, file_path, item_type, extra_attrs=None):
    size = os.path.getsize(file_path)
    name = os.path.basename(file_path)
    attrs = {"fileName": name, "fileSize": size}
    attrs.update(extra_attrs or {})
    r = api("POST", create_path, {"data": {"type": item_type, "attributes": attrs, "relationships": {set_rel_type: {"data": {"type": set_rel_type + "s" if not set_rel_type.endswith("s") else set_rel_type, "id": set_id}}}}})
    if DRY:
        return
    item = r["data"]
    md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for op in item["attributes"]["uploadOperations"]:
            f.seek(op["offset"])
            chunk = f.read(op["length"])
            md5.update(chunk)
            put_chunk(op, chunk)
    api("PATCH", f"{create_path}/{item['id']}", {"data": {"type": item_type, "id": item["id"], "attributes": {"uploaded": True, "sourceFileChecksum": md5.hexdigest()}}})
    print(f"    uploaded {name} ({size/1e6:.1f} MB)")


def upload_media(loc_id, media_dir):
    # screenshots
    sets = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?include=appScreenshots")["data"] if not DRY else []
    sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == SCREENSHOT_DISPLAY_TYPE), None)
    if sset is None:
        r = api("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": SCREENSHOT_DISPLAY_TYPE}, "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
        set_id = r.get("data", {}).get("id", "dry")
        have = set()
    else:
        set_id = sset["id"]
        have = {s["attributes"]["fileName"] for s in api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]}
    for rel in SCREENSHOTS:
        p = os.path.join(media_dir, rel)
        if os.path.basename(p) in have:
            print(f"    exists {os.path.basename(p)}")
            continue
        upload_asset("/v1/appScreenshots", "appScreenshotSet", set_id, p, "appScreenshots")
    # preview
    psets = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appPreviewSets")["data"] if not DRY else []
    pset = next((s for s in psets if s["attributes"]["previewType"] == PREVIEW_TYPE), None)
    if pset is None:
        r = api("POST", "/v1/appPreviewSets", {"data": {"type": "appPreviewSets", "attributes": {"previewType": PREVIEW_TYPE}, "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
        pset_id = r.get("data", {}).get("id", "dry")
        have = set()
    else:
        pset_id = pset["id"]
        have = {s["attributes"]["fileName"] for s in api("GET", f"/v1/appPreviewSets/{pset_id}/appPreviews")["data"]}
    p = os.path.join(media_dir, PREVIEW)
    if os.path.basename(p) in have:
        print(f"    exists {PREVIEW}")
    else:
        upload_asset("/v1/appPreviews", "appPreviewSet", pset_id, p, "appPreviews", {"previewFrameTimeCode": "00:00:27:00"})


def main():
    global DRY
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id")
    ap.add_argument("--version", default=None, help="version string; default MARKETING_VERSION from ios-app/project.yml")
    ap.add_argument("--media-dir", default=os.path.expanduser("~/Desktop/TetherCam-AppStore"))
    ap.add_argument("--skip-media", action="store_true")
    ap.add_argument("--skip-pricing", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    DRY = a.dry_run
    load_env_local()

    version = a.version or re.search(r'MARKETING_VERSION:\s*"?([\d.]+)', open(os.path.join(ROOT, "ios-app", "project.yml")).read()).group(1)
    en, de = load_locale("en-US"), load_locale("de-DE")

    step("app record")
    app_id = find_app(a.app_id)
    print(f"  app {app_id} ({BUNDLE_ID})")

    step(f"App Store version {version}")
    vid = ensure_version(app_id, version)

    step("version localizations")
    loc_en = upsert_version_localization(vid, "en-US", en)
    loc_de = upsert_version_localization(vid, "de-DE", de)

    step("app info: localizations, categories, age rating")
    info = app_info(app_id)
    upsert_info_localization(info, "en-US", en)
    upsert_info_localization(info, "de-DE", de)
    set_categories(info)
    set_age_rating(info)

    step("review information")
    set_review_detail(vid)

    if not a.skip_pricing:
        step("pricing and availability")
        try:
            set_free_price(app_id)
        except RuntimeError as e:
            print(f"  price: {str(e)[:300]}")
        try:
            set_availability(app_id)
        except RuntimeError as e:
            print(f"  availability: {str(e)[:300]}")

    if not a.skip_media:
        for loc, lid in (("en-US", loc_en), ("de-DE", loc_de)):
            step(f"media {loc}")
            upload_media(lid, a.media_dir)

    print("\nDone. Still manual in App Store Connect: App Privacy questionnaire (Data Not Collected), build selection once processed, Add for Review.")


if __name__ == "__main__":
    main()
