#!/usr/bin/env bash
# vcam-test.sh: Simulierte End-zu-End-Abnahme der macOS-Virtual-Camera ohne iPhone.
#
# Startet usbcam-sim auf einem freien Port, laesst die Host-App (mac-app, headless,
# --debug-tcp) den Strom in die CoreMediaIO-Camera-Extension "TetherCam" schieben,
# nimmt die virtuelle Kamera per ffmpeg/avfoundation auf und prueft Aufloesung,
# Bildrate, Bildzahl und Bewegung (PSNR zweier Frames). Optional (VCAM_BROWSER=1)
# zaehlt ein Browser die Kamera per getUserMedia/enumerateDevices auf.
# Beendet nur die selbst gestarteten Prozesse (per PID, nie per pkill).
# Wiederholbar: alle Artefakte liegen unter /tmp/vcam-test und werden ueberschrieben.
#
# Exit-Codes: 0 PASS, 1 FAIL, 3 Extension wartet auf Freigabe in den Systemeinstellungen,
#             4 Extension nicht registriert (mac-app/scripts/install-local.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/tools"
PORT="${IUCM_PORT:-7980}"   # 7979 gehoert integration.sh, beide laufen parallel
VCAM_NAME="${VCAM_NAME:-TetherCam}"
VCAM_EXT_ID="${VCAM_EXT_ID:-at.gotzendorfer.tethercam.mac.camera}"
VCAM_SECONDS="${VCAM_SECONDS:-3}"
VCAM_BROWSER="${VCAM_BROWSER:-0}"
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
FFPROBE="${FFPROBE:-/opt/homebrew/bin/ffprobe}"
AGENT_BROWSER="${AGENT_BROWSER:-/opt/homebrew/bin/agent-browser}"
WIDTH=1920
HEIGHT=1080
LIST_TIMEOUT_S=20   # so lange darf die Kamera brauchen, bis avfoundation sie listet
WARMUP_S=0.3        # erster Vergleichsframe
MOTION_S=1.5        # zweiter Vergleichsframe
PSNR_MAX=45         # unterhalb gilt: Bild bewegt sich

OUT=/tmp/vcam-test
SIMLOG="$OUT/sim.log"
APPLOG="$OUT/app.log"
MP4="$OUT/cam.mp4"
F1="$OUT/f1.png"
F2="$OUT/f2.png"
HTML="$OUT/enum.html"

if [ -n "${VCAM_APP:-}" ]; then
    APP="$VCAM_APP"
elif [ -d /Applications/TetherCam.app ]; then
    APP=/Applications/TetherCam.app
else
    APP="$ROOT/mac-app/build/Build/Products/Release/TetherCam.app"
fi
APP_BIN="$APP/Contents/MacOS/TetherCam"

SIM_PID=""
APP_PID=""
BROWSER_OPEN=0
# shellcheck disable=SC2329  # invoked via trap
cleanup() {
    if [ "$BROWSER_OPEN" = 1 ]; then
        "$AGENT_BROWSER" --session vcam-test close >/dev/null 2>&1 || true
    fi
    for pid in "$APP_PID" "$SIM_PID"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT

app_tail() {
    if [ -s "$APPLOG" ]; then
        echo "--- $APPLOG (tail)" >&2
        tail -n 20 "$APPLOG" >&2
    fi
}
die() { echo "FAIL: $*" >&2; app_tail; exit 1; }
blocked() { # blocked <exit-code> <text>
    local rc="$1"; shift
    echo "BLOCKED: $*" >&2
    exit "$rc"
}

for bin in "$FFMPEG" "$FFPROBE"; do
    [ -x "$bin" ] || die "$bin nicht gefunden (FFMPEG=/FFPROBE= setzen)"
done
mkdir -p "$OUT"
rm -f "$SIMLOG" "$APPLOG" "$MP4" "$F1" "$F2" "$HTML"

echo "== extension $VCAM_EXT_ID"
# Nach einem Update listet sysextd die alte Version als "terminated waiting to
# uninstall on reboot" hinter der neuen; die aktive Zeile ist die mit "[activated".
EXT_LINE="$(systemextensionsctl list 2>/dev/null | grep -F "$VCAM_EXT_ID (" | grep -F "[activated" | tail -n 1 || true)"
[ -n "$EXT_LINE" ] || EXT_LINE="$(systemextensionsctl list 2>/dev/null | grep -F "$VCAM_EXT_ID (" | tail -n 1 || true)"
if [ -z "$EXT_LINE" ]; then
    blocked 4 "extension not registered, run bash mac-app/scripts/install-local.sh"
fi
echo "   $EXT_LINE"
case "$EXT_LINE" in
    *"[activated enabled]") ;;
    *"waiting for user"*)
        echo "   open \"x-apple.systempreferences:com.apple.LoginItems-Settings.extension\"" >&2
        blocked 3 "approve TetherCam in System Settings > General > Login Items & Extensions > Camera Extensions"
        ;;
    *) die "extension state unexpected: $EXT_LINE" ;;
esac

echo "== app $APP"
[ -x "$APP_BIN" ] || die "$APP_BIN fehlt (VCAM_APP= setzen oder mac-app bauen, siehe mac-app/README.md)"

echo "== build sim"
swift build -c release --package-path "$PKG" --product usbcam-sim || die "swift build usbcam-sim"
SIM="$PKG/.build/release/usbcam-sim"
[ -x "$SIM" ] || die "usbcam-sim fehlt"

echo "== sim auf 127.0.0.1:$PORT"
"$SIM" --bind 127.0.0.1 --port "$PORT" --no-audio >"$SIMLOG" 2>&1 &
SIM_PID=$!
for _ in $(seq 1 50); do
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then break; fi
    sleep 0.1
done
nc -z 127.0.0.1 "$PORT" 2>/dev/null || die "Simulator lauscht nicht auf $PORT (siehe $SIMLOG)"
# nc -z belegt den Simulator kurz als einziger Client; erst loslassen, dann die App starten.
sleep 0.3
echo "   pid=$SIM_PID"

echo "== app headless, debug-tcp 127.0.0.1:$PORT"
"$APP_BIN" --debug-tcp "127.0.0.1:$PORT" --headless >"$APPLOG" 2>&1 &
APP_PID=$!
echo "   pid=$APP_PID"

list_devices() { "$FFMPEG" -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true; }

echo "== warte auf Kamera \"$VCAM_NAME\" in avfoundation (max ${LIST_TIMEOUT_S}s)"
LISTED=0
for i in $(seq 1 "$LIST_TIMEOUT_S"); do
    kill -0 "$APP_PID" 2>/dev/null || die "App beendet, bevor die Kamera erschien (siehe $APPLOG)"
    if list_devices | grep -q "\] $VCAM_NAME\$"; then
        LISTED=$i
        break
    fi
    sleep 1
done
[ "$LISTED" -gt 0 ] || { list_devices | grep -A20 'video devices' >&2 || true
                          die "\"$VCAM_NAME\" nicht in avfoundation nach ${LIST_TIMEOUT_S}s"; }
echo "   ok  gelistet nach ~${LISTED}s"

echo "== capture ${VCAM_SECONDS}s ${WIDTH}x${HEIGHT} nv12"
"$FFMPEG" -hide_banner -v error -y -f avfoundation -framerate 30 -video_size "${WIDTH}x${HEIGHT}" \
    -pixel_format nv12 -i "$VCAM_NAME" -t "$VCAM_SECONDS" "$MP4" || die "ffmpeg capture"
[ -s "$MP4" ] || die "$MP4 ist leer"
kill -0 "$APP_PID" 2>/dev/null || die "App waehrend der Aufnahme beendet"

echo "== ffprobe"
PROBE="$("$FFPROBE" -v error -select_streams v:0 -count_frames \
        -show_entries stream=width,height,avg_frame_rate,nb_read_frames -of csv=p=0 "$MP4")"
echo "   $PROBE"
# Erwartung: <width>,<height>,<num>/<den>,<frames>
read -r PW PH FPS FRAMES <<<"$(python3 - "$PROBE" <<'PY'
import sys
w, h, rate, n = sys.argv[1].strip().split(",")[:4]
num, _, den = rate.partition("/")
fps = float(num) / float(den or 1) if float(den or 1) else 0.0
print(w, h, f"{fps:.2f}", n)
PY
)"

assert() { # assert <ist> <op> <soll> <label>
    python3 -c "import sys;sys.exit(0 if float('$1') $2 float('$3') else 1)" \
        || die "$4: $1 nicht $2 $3"
    echo "   ok  $4 ($1 $2 $3)"
}
assert "$PW" "==" "$WIDTH" "width"
assert "$PH" "==" "$HEIGHT" "height"
assert "$FPS" ">=" 25 "fps"
# 3 s bei 30 fps sind 90 Frames; 50 laesst der Kamera ~1,7 s Anlaufzeit.
assert "$FRAMES" ">=" 50 "frames"

echo "== motion (PSNR ${WARMUP_S}s vs ${MOTION_S}s)"
"$FFMPEG" -v error -y -ss "$WARMUP_S" -i "$MP4" -frames:v 1 "$F1" || die "frame 1 extrahieren"
"$FFMPEG" -v error -y -ss "$MOTION_S" -i "$MP4" -frames:v 1 "$F2" || die "frame 2 extrahieren"
PSNR_LINE="$("$FFMPEG" -hide_banner -i "$F1" -i "$F2" -filter_complex psnr -f null - 2>&1 \
        | grep -o 'average:[^ ]*' | tail -n 1 || true)"
PSNR="${PSNR_LINE#average:}"
[ -n "$PSNR" ] || die "PSNR nicht ermittelbar"
case "$PSNR" in
    inf|nan|*inf*) die "Bild steht: PSNR=$PSNR zwischen ${WARMUP_S}s und ${MOTION_S}s" ;;
esac
assert "$PSNR" "<" "$PSNR_MAX" "psnr_db (Bewegung)"

BROWSER_LABEL="skipped"
if [ "$VCAM_BROWSER" = 1 ]; then
    echo "== browser enumerateDevices"
    [ -x "$AGENT_BROWSER" ] || die "$AGENT_BROWSER fehlt (AGENT_BROWSER= setzen)"
    cat >"$HTML" <<'HTML'
<!doctype html><meta charset="utf-8"><title>vcam-test</title><pre id="o">pending</pre>
<script>
(async () => {
  const o = document.getElementById('o');
  try {
    const s = await navigator.mediaDevices.getUserMedia({video: true});
    const d = await navigator.mediaDevices.enumerateDevices();
    s.getTracks().forEach(t => t.stop());
    o.textContent = d.filter(x => x.kind === 'videoinput').map(x => x.label).join('\n') || 'no videoinput';
  } catch (e) { o.textContent = 'error: ' + e; }
})();
</script>
HTML
    BROWSER_OPEN=1
    "$AGENT_BROWSER" --session vcam-test --args "--use-fake-ui-for-media-stream" \
        open "file://$HTML" >/dev/null || die "agent-browser open"
    BROWSER_LABEL=""
    for _ in $(seq 1 20); do
        BROWSER_LABEL="$("$AGENT_BROWSER" --session vcam-test get text '#o' 2>/dev/null || true)"
        case "$BROWSER_LABEL" in pending|"") sleep 0.5 ;; *) break ;; esac
    done
    "$AGENT_BROWSER" --session vcam-test close >/dev/null 2>&1 || true
    BROWSER_OPEN=0
    echo "   videoinput: $(echo "$BROWSER_LABEL" | tr '\n' '|')"
    echo "$BROWSER_LABEL" | grep -q "$VCAM_NAME" || die "Browser listet \"$VCAM_NAME\" nicht"
    echo "   ok  browser"
    BROWSER_LABEL="ok"
fi

STATUS="$(grep 'tethercam: link=' "$APPLOG" | tail -n 1 || true)"
echo
echo "   ${STATUS:-tethercam: (keine Statuszeile in $APPLOG)}"
# Placeholder-Schutz: der Extension-Placeholder bewegt sich auch. Nur wenn der
# Host Frames in den Sink geschoben hat, stammt die Aufnahme vom Simulator.
PUSHED="$(printf '%s' "$STATUS" | sed -n 's/.*pushed=\([0-9]*\).*/\1/p')"
[ -n "$PUSHED" ] || die "Statuszeile ohne pushed= (App-Log: $APPLOG)"
assert "$PUSHED" ">" 0 "pushed (Sink hat Frames vom Host)"
echo "PASS  listed_s=$LISTED size=${PW}x${PH} fps=$FPS frames=$FRAMES psnr_db=$PSNR browser=$BROWSER_LABEL"
exit 0
