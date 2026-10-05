#!/bin/bash
# Films the trailer tour on an iOS Simulator.
# Usage: SIM_UDID=<simulator> tools/trailer/record.sh
# Writes build/trailer/raw.mov (screen recording) and build/trailer/marks.txt (scene timestamps).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SIM="${SIM_UDID:?Set SIM_UDID to a booted iPhone simulator}"
DD="${DERIVED_DATA:-$ROOT/build/DerivedData-trailer}"
OUT="$ROOT/build/trailer"
mkdir -p "$OUT"

xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl ui "$SIM" appearance light
/opt/homebrew/bin/xcodegen generate --quiet

common=(-project SermonSet.xcodeproj -scheme SermonSet -destination "platform=iOS Simulator,id=$SIM"
        -derivedDataPath "$DD" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
        -only-testing:SermonSetUITests/TrailerTour)
xcodebuild "${common[@]}" build-for-testing > "$OUT/build.log" 2>&1

rm -f "$OUT/raw.mov" "$OUT/rec.log"
xcrun simctl io "$SIM" recordVideo --codec=h264 --force "$OUT/raw.mov" > "$OUT/rec.log" 2>&1 &
REC=$!
until grep -q "Recording started" "$OUT/rec.log" 2>/dev/null; do sleep 0.05; done
REC_START=$(python3 -c 'import time; print(f"{time.time():.3f}")')

TEST_RUNNER_SERMONSET_TRAILER=1 xcodebuild "${common[@]}" test-without-building > "$OUT/tour.log" 2>&1 || true
sleep 1
kill -INT "$REC"
wait "$REC" || true

{ echo "REC_START $REC_START"; grep -o "TRAILER-MARK .*" "$OUT/tour.log"; } > "$OUT/marks.txt"
cat "$OUT/marks.txt"

# The recording has variable frame timing; cut points in edl.json refer to this 30 fps master.
ffmpeg -v error -y -i "$OUT/raw.mov" -vf fps=30 -c:v libx264 -preset fast -crf 14 -pix_fmt yuv420p "$OUT/cfr.mp4"
echo "wrote $OUT/cfr.mp4 — check cut points in tools/trailer/edl.json, then run tools/trailer/edit.py"
