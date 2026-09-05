#!/usr/bin/env bash
# Verifies the App Store deliverables: metadata character limits and media specs.
# Exits 0 only if everything passes. No network, no App Store Connect access.
#
#   bash docs/app-store/validate.sh [media-dir]
#
# media-dir defaults to ~/Desktop/TetherCam-AppStore. If it is absent the media
# checks are skipped with a warning and the metadata checks still run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA="${1:-$HOME/Desktop/TetherCam-AppStore}"
FAIL=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=1; }
warn() { printf '  warn  %s\n' "$1"; }

# --- metadata -----------------------------------------------------------------
# Each "## <Field> (limit N)" heading is followed by one fenced block whose
# content must not exceed N characters. Counted in Unicode code points, which is
# what App Store Connect counts (umlauts are one character, not two).
check_metadata() {
  local file="$1"
  echo "metadata: $file"
  if [ ! -f "$file" ]; then fail "missing $file"; return; fi
  local out
  out="$(python3 - "$file" <<'PY'
import re, sys, unicodedata
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
pattern = re.compile(r"^## (?P<name>.+?) \(limit (?P<limit>\d+)\)\s*$", re.M)
heads = list(pattern.finditer(text))
if not heads:
    print("FAIL no '## Field (limit N)' headings found")
    sys.exit(0)
seen = 0
for i, m in enumerate(heads):
    start = m.end()
    end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
    section = text[start:end]
    block = re.search(r"^```\n(.*?)^```\s*$", section, re.S | re.M)
    if not block:
        print(f"FAIL {m.group('name')}: no fenced block after the heading")
        continue
    body = block.group(1).rstrip("\n")
    limit = int(m.group("limit"))
    n = len(unicodedata.normalize("NFC", body))
    seen += 1
    status = "OK" if n <= limit else "FAIL"
    slack = limit - n
    print(f"{status} {m.group('name')}: {n}/{limit} chars ({slack} left)")
if seen == 0:
    print("FAIL no fenced blocks matched")
PY
)"
  while IFS= read -r line; do
    case "$line" in
      OK*)   pass "${line#OK }" ;;
      FAIL*) fail "${line#FAIL }" ;;
      *)     [ -n "$line" ] && warn "$line" ;;
    esac
  done <<< "$out"
}

check_metadata "$HERE/en-US.md"
check_metadata "$HERE/de-DE.md"

# --- media --------------------------------------------------------------------
echo "media: $MEDIA"
if [ ! -d "$MEDIA" ]; then
  warn "media directory not found, skipping media checks"
else
  # Screenshots: 2796x1290 landscape, no alpha. Apple accepts this as the
  # iPhone 6.9" landscape set; other sizes are auto-scaled from it.
  shots=("$MEDIA"/screenshots-6.9/0*.png)
  if [ ! -e "${shots[0]}" ]; then
    fail "no screenshots in $MEDIA/screenshots-6.9"
  elif [ "${#shots[@]}" -lt 1 ] || [ "${#shots[@]}" -gt 10 ]; then
    fail "screenshot count ${#shots[@]} outside the allowed 1..10"
  else
    pass "screenshot count ${#shots[@]} within 1..10"
    for f in "${shots[@]}"; do
      info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" 2>/dev/null)"
      w="$(awk '/pixelWidth/{print $2}' <<< "$info")"
      h="$(awk '/pixelHeight/{print $2}' <<< "$info")"
      a="$(awk '/hasAlpha/{print $2}' <<< "$info")"
      if [ "$w" = "2796" ] && [ "$h" = "1290" ] && [ "$a" = "no" ]; then
        pass "$(basename "$f") ${w}x${h} alpha=$a"
      else
        fail "$(basename "$f") is ${w}x${h} alpha=$a, expected 2796x1290 alpha=no"
      fi
    done
  fi

  video="$MEDIA/app-preview-6.9-landscape.mp4"
  if [ ! -f "$video" ]; then
    fail "missing $video"
  elif ! command -v ffprobe >/dev/null 2>&1; then
    warn "ffprobe not installed, skipping video checks"
  else
    probe() { ffprobe -v error -select_streams "$1" -show_entries "$2" -of default=nw=1:nk=1 "$video" | head -1; }
    vw="$(probe v stream=width)"; vh="$(probe v stream=height)"
    fps="$(probe v stream=avg_frame_rate)"; codec="$(probe v stream=codec_name)"
    pixfmt="$(probe v stream=pix_fmt)"
    acodec="$(probe a stream=codec_name)"; ach="$(probe a stream=channels)"
    dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$video")"
    bytes="$(wc -c < "$video" | tr -d ' ')"

    [ "$vw" = "1920" ] && [ "$vh" = "886" ] \
      && pass "preview ${vw}x${vh}" || fail "preview is ${vw}x${vh}, expected 1920x886"
    [ "$codec" = "h264" ] && pass "preview codec $codec" || fail "preview codec $codec, expected h264"
    [ "$pixfmt" = "yuv420p" ] && pass "preview pix_fmt $pixfmt" || fail "preview pix_fmt $pixfmt, expected yuv420p"
    [ "$fps" = "30/1" ] && pass "preview fps $fps" || fail "preview fps $fps, expected 30/1"
    if awk -v d="$dur" 'BEGIN{exit !(d>=15 && d<=30)}'; then
      pass "preview duration ${dur}s within 15..30"
    else
      fail "preview duration ${dur}s outside the allowed 15..30"
    fi
    if [ -n "$acodec" ]; then
      { [ "$acodec" = "aac" ] && [ "$ach" = "2" ]; } \
        && pass "preview audio $acodec stereo" \
        || fail "preview audio $acodec ${ach}ch, expected stereo aac or no audio"
    else
      pass "preview has no audio track (allowed)"
    fi
    if [ "$bytes" -le 524288000 ]; then
      pass "preview size $((bytes / 1048576)) MB under the 500 MB cap"
    else
      fail "preview size $((bytes / 1048576)) MB exceeds the 500 MB cap"
    fi
  fi

  poster="$MEDIA/app-preview-poster.png"
  if [ ! -f "$poster" ]; then
    fail "missing $poster"
  else
    info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$poster" 2>/dev/null)"
    w="$(awk '/pixelWidth/{print $2}' <<< "$info")"
    h="$(awk '/pixelHeight/{print $2}' <<< "$info")"
    a="$(awk '/hasAlpha/{print $2}' <<< "$info")"
    [ "$w" = "1920" ] && [ "$h" = "886" ] && [ "$a" = "no" ] \
      && pass "poster ${w}x${h} alpha=$a" \
      || fail "poster is ${w}x${h} alpha=$a, expected 1920x886 alpha=no"
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "all checks passed"
else
  echo "checks failed"
fi
exit "$FAIL"
