#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SIM_UDID="${SIM_UDID:-32502FB1-1CBE-4555-B1FE-CF1712B1A45C}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData-core}"
ACTION="${1:-help}"
if [[ $# -gt 0 ]]; then shift; fi
mkdir -p "$ROOT/build/logs-core"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
generate() { /opt/homebrew/bin/xcodegen generate; }
xcode() {
  local operation="$1"; shift
  local scheme="SermonSet"
  if [[ "$operation" == test ]]; then scheme="${TEST_SCHEME:-SermonSetCore}"; fi
  local command=(xcodebuild -project SermonSet.xcodeproj -scheme "$scheme" -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath "$DERIVED_DATA" -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO)
  if [[ "$operation" == test ]]; then
    command+=(-parallel-testing-enabled NO -resultBundlePath "$ROOT/build/logs-core/tests-$STAMP.xcresult")
  fi
  command+=("$@" "$operation")
  printf '+ '; printf '%q ' "${command[@]}"; printf '\n'
  "${command[@]}" 2>&1 | tee "$ROOT/build/logs-core/$operation-$STAMP.log"
}
boot() {
  if ! xcrun simctl list devices booted | /usr/bin/grep -q "$SIM_UDID"; then xcrun simctl boot "$SIM_UDID"; fi
  xcrun simctl bootstatus "$SIM_UDID" -b
}
case "$ACTION" in
  generate) generate ;;
  build) generate; xcode build ;;
  test) generate; boot; xcode test ;;
  run)
    generate; xcode build; boot
    xcrun simctl install "$SIM_UDID" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/SermonSet.app"
    local_bundle=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/SermonSet.app/Info.plist")
    xcrun simctl launch --terminate-running-process "$SIM_UDID" "$local_bundle" "$@"
    ;;
  screenshot)
    [[ $# == 1 ]] || { echo 'Usage: scripts/dev.sh screenshot <png>' >&2; exit 2; }
    mkdir -p "$(dirname "$1")"
    xcrun simctl io "$SIM_UDID" screenshot "$1"
    ;;
  *) echo 'Usage: scripts/dev.sh {generate|build|test|run [launch args…]|screenshot <png>}' ;;
esac
