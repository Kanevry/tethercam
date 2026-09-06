#!/usr/bin/env bash
# integration.sh: End-zu-End-Abnahme ohne iPhone.
#
# Baut das Paket, startet usbcam-sim auf einem freien Port, laesst usbcam-recv
# 5 s aufzeichnen, prueft die Kennzahlen und dekodiert einen Frame mit ffmpeg.
# Beendet nur den selbst gestarteten Simulator (per PID, nie per pkill).
# Wiederholbar: alle Artefakte liegen unter /tmp und werden ueberschrieben.
set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/tools"
PORT="${IUCM_PORT:-7979}"
DUMP=/tmp/iucm-int.hevc
DUMPA=/tmp/iucm-int-audio.aac
PNG=/tmp/iucm-int.png
JSONF=/tmp/iucm-int.json
SIMLOG=/tmp/iucm-int-sim.log
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
FFPROBE="${FFPROBE:-/opt/homebrew/bin/ffprobe}"
WIDTH=1280
HEIGHT=720

SIM_PID=""
# shellcheck disable=SC2329  # invoked via trap
cleanup() {
    if [ -n "$SIM_PID" ] && kill -0 "$SIM_PID" 2>/dev/null; then
        kill "$SIM_PID" 2>/dev/null
        wait "$SIM_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

die() { echo "FAIL: $*" >&2; exit 1; }

for bin in "$FFMPEG" "$FFPROBE"; do
    [ -x "$bin" ] || die "$bin nicht gefunden (FFMPEG=/FFPROBE= setzen)"
done

echo "== build"
swift build -c release --package-path "$PKG" || die "swift build"

SIM="$PKG/.build/release/usbcam-sim"
RECV="$PKG/.build/release/usbcam-recv"
[ -x "$SIM" ] || die "usbcam-sim fehlt"
[ -x "$RECV" ] || die "usbcam-recv fehlt"

echo "== sim auf 127.0.0.1:$PORT"
rm -f "$DUMP" "$DUMPA" "$PNG" "$JSONF"
"$SIM" --bind 127.0.0.1 --port "$PORT" >"$SIMLOG" 2>&1 &
SIM_PID=$!
for _ in $(seq 1 50); do
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then break; fi
    sleep 0.1
done
nc -z 127.0.0.1 "$PORT" 2>/dev/null || die "Simulator lauscht nicht auf $PORT (siehe $SIMLOG)"
echo "   pid=$SIM_PID"

echo "== recv 5 s"
"$RECV" --tcp "127.0.0.1:$PORT" --size ${WIDTH}x${HEIGHT} --bitrate 6000 \
        --seconds 5 --dump "$DUMP" --dump-audio "$DUMPA" --json >"$JSONF"
RC=$?
[ $RC -eq 0 ] || die "usbcam-recv exit $RC"
SUMMARY="$(cat "$JSONF")"
echo "   $SUMMARY"

field() { python3 -c "import json,sys;print(json.load(open('$JSONF'))['$1'])"; }

FPS=$(field fps_avg); KEY=$(field keyframes); FFMS=$(field first_frame_ms)
RTT=$(field ping_rtt_ms_avg); FRAMES=$(field frames); NALS=$(field nals)
AUDIO_FRAMES=$(field audio_frames); AUDIO_RATE=$(field audio_sample_rate)
AUDIO_SKEW=$(field audio_video_pts_skew_ms)

assert() { # assert <ist> <op> <soll> <label>
    python3 -c "import sys;sys.exit(0 if float('$1') $2 float('$3') else 1)" \
        || die "$4: $1 nicht $2 $3"
    echo "   ok  $4 ($1 $2 $3)"
}
assert "$FPS" ">=" 25 "fps_avg"
assert "$KEY" ">=" 4 "keyframes"
assert "$FFMS" "<" 1500 "first_frame_ms"
assert "$RTT" ">=" 0 "ping_rtt_ms_avg gemessen"
assert "$RTT" "<" 50 "ping_rtt_ms_avg"
assert "$FRAMES" ">" 0 "frames"
assert "$NALS" ">=" "$FRAMES" "nals"

# Audio: 5 s bei 46,9 AAC-Frames/s (48000 Hz / 1024 Samples je Frame) sind rund 234
# Frames; 100 laesst Anlaufzeit und Hostlast Luft, ohne die Abnahme zu verwaessern.
assert "$AUDIO_FRAMES" ">=" 100 "audio_frames"
assert "$AUDIO_RATE" "==" 48000 "audio_sample_rate"
AUDIO_SKEW_ABS=$(python3 -c "print(abs(float('$AUDIO_SKEW')))")
assert "$AUDIO_SKEW_ABS" "<=" 50 "audio_video_pts_skew_ms_abs"

echo "== ffmpeg decode"
[ -s "$DUMP" ] || die "$DUMP ist leer"
"$FFMPEG" -v error -i "$DUMP" -frames:v 1 -y "$PNG" || die "ffmpeg decode"
SIZE="$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=width,height \
        -of csv=s=x:p=0 "$PNG")"
[ "$SIZE" = "${WIDTH}x${HEIGHT}" ] || die "PNG ist $SIZE, erwartet ${WIDTH}x${HEIGHT}"
echo "   ok  $PNG $SIZE"

echo "== ffprobe audio"
[ -s "$DUMPA" ] || die "$DUMPA ist leer"
ASTREAM="$("$FFPROBE" -v error -show_entries stream=codec_name,sample_rate,channels \
        -of csv=p=0 "$DUMPA")"
[ "$ASTREAM" = "aac,48000,1" ] || die "Audio-Stream ist $ASTREAM, erwartet aac,48000,1"
echo "   ok  $DUMPA $ASTREAM"

echo
echo "PASS  frames=$FRAMES fps=$FPS keyframes=$KEY first_frame_ms=$FFMS rtt_ms=$RTT png=$SIZE audio_frames=$AUDIO_FRAMES skew_ms=$AUDIO_SKEW"
exit 0
