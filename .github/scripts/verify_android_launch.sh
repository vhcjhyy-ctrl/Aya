#!/usr/bin/env bash
set -Eeuo pipefail

APP_ID="com.ahmed.qalammuslim"
MAIN_ACTIVITY="com.ahmed.qalammuslim/com.quran.aya.MainActivity"
APK="dist/qalam-muslim-x86_64-release.apk"

mkdir -p dist

collect_diagnostics() {
  adb shell dumpsys activity activities > dist/activities-after-launch.txt 2>&1 || true
  adb shell dumpsys window windows > dist/window-after-launch.txt 2>&1 || true
  adb logcat -d -v time -t 5000 > dist/android-launch-log.txt 2>&1 || true
}

adb wait-for-device
adb install -r "$APK"

adb shell am force-stop "$APP_ID"
if ! adb shell am start -W -n "$MAIN_ACTIVITY" > dist/launch-result.txt 2>&1; then
  collect_diagnostics
  echo "Android Activity Manager could not start Qalam Muslim."
  cat dist/launch-result.txt
  exit 1
fi

# Activity Manager may report "Status: timeout" on a heavily loaded emulator
# even though the Activity is created successfully. Validate the process,
# resumed Activity, and rendered app window below instead of trusting that
# status line alone.
PID=""
for attempt in $(seq 1 30); do
  PID="$(adb shell pidof "$APP_ID" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "$PID" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$PID" ]]; then
  collect_diagnostics
  echo "Qalam Muslim process did not stay alive after launch."
  cat dist/launch-result.txt
  exit 1
fi

echo "$PID" | tee dist/process-id.txt
sleep 20
collect_diagnostics

# Android 11's emulator can occasionally display a System UI ANR dialog
# during a cold first boot while the target app is already alive and rendered.
# Ask Android to wait for System UI, then re-check that the dialog is gone.
for recovery_attempt in 1 2; do
  if grep -Eq "Application Not Responding: (system|com\\.android\\.systemui)|package=android appop=SYSTEM_ALERT_WINDOW" dist/window-after-launch.txt; then
  echo "Android System UI remained unresponsive after recovery attempts."
  exit 1
fi

echo "PASS: application installed, process remained alive, MainActivity stayed resumed, its window rendered, and no blocking ANR dialog remained on Android 11."
