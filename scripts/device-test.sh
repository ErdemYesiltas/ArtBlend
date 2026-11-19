#!/usr/bin/env bash
# Runs an apps/studio integration test on an Android device as the separate
# app dev.atelier.atelier_studio.itest ("ArtBlend Test").
#
# Deliberately not `flutter test integration_test -d …`: its cleanup uninstalls
# the package it resolved before building, which can be the real app — and an
# uninstall deletes all of the real app's drawings and libraries.
#
#   scripts/device-test.sh <serial> [integration_test/<file>.dart]
set -euo pipefail
trap 'echo "device-test: failed at line $LINENO" >&2' ERR

DEVICE="${1:?usage: scripts/device-test.sh <serial> [integration_test/<file>.dart]}"
TARGET="${2:-integration_test/device_test.dart}"
TEST_PKG=dev.atelier.atelier_studio.itest
USER_PKG=dev.atelier.atelier_studio
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB=("$SDK/platform-tools/adb" -s "$DEVICE")
AAPT=$(ls -d "$SDK"/build-tools/*/aapt | sort -V | tail -1)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/apps/studio"

installed() { "${ADB[@]}" shell dumpsys package "$USER_PKG" | grep -E 'firstInstallTime|lastUpdateTime' || true; }
"${ADB[@]}" get-state >/dev/null
BEFORE=$(installed)

"$ROOT/scripts/flutterw" build apk --debug -t "$TARGET" --dart-define=ARTBLEND_ITEST=true
APK=build/app/outputs/flutter-apk/app-debug.apk
BUILT=$("$AAPT" dump badging "$APK" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
if [[ "$BUILT" != "$TEST_PKG" ]]; then
  echo "refusing to install: built package is '$BUILT', expected $TEST_PKG" >&2
  exit 1
fi

"${ADB[@]}" get-state >/dev/null
"${ADB[@]}" install -r "$APK"
cleanup() {
  "${ADB[@]}" shell am force-stop "$TEST_PKG" || true
  "${ADB[@]}" uninstall "$TEST_PKG" >/dev/null || true
}
trap cleanup EXIT
"${ADB[@]}" logcat -c || true
"${ADB[@]}" shell am start -W -n "$TEST_PKG/$USER_PKG.MainActivity" >/dev/null

RESULT=timeout
for _ in $(seq 120); do
  sleep 5
  LOG=$("${ADB[@]}" logcat -d -s flutter:I)
  if grep -q 'All tests passed' <<<"$LOG"; then RESULT=passed; break; fi
  if grep -q 'Some tests failed' <<<"$LOG"; then RESULT=failed; break; fi
done
"${ADB[@]}" logcat -d -s flutter:I | sed 's/^.*flutter *: //'

cleanup
trap - EXIT

AFTER=$(installed)
if [[ "$BEFORE" != "$AFTER" ]]; then
  echo "WARNING: $USER_PKG install times changed:" >&2
  echo "before: $BEFORE" >&2
  echo "after:  $AFTER" >&2
  exit 2
fi
echo "result: $RESULT ($USER_PKG untouched)"
[[ "$RESULT" == passed ]]
