#!/usr/bin/env bash
set -Eeuo pipefail

APP_ID="com.ahmed.qalammuslim"
MAIN_ACTIVITY="com.ahmed.qalammuslim/com.quran.aya.MainActivity"
APK="dist/qalam-muslim-x86_64-release.apk"

mkdir -p dist

collect_diagnostics() {
  adb shell dumpsys activity activities > dist/activities-after-launch.txt 2>&1 || true
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

sleep 10

PID=""
for attempt in $(seq 1 15); do
  PID="$(adb shell pidof "$APP_ID" 2>/dev/null | tr -d '\\r' || true)"
  if [[ -n "$PID" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$PID" ]]; then
  collect_diagnostics
  echo "Qalam Muslim process did not stay alive after launch."
  exit 1
fi

echo "$PID" | tee dist/process-id.txt
sleep 15
collect_diagnostics
adb exec-out screencap -p > dist/launch-screen.png

if ! grep -q "com.quran.aya.MainActivity" dist/activities-after-launch.txt; then
  echo "Qalam Muslim MainActivity is not visible in the activity stack."
  exit 1
fi

if grep -E "FATAL EXCEPTION|Process: ${APP_ID}" dist/android-launch-log.txt; then
  echo "A fatal application exception was recorded."
  exit 1
fi

echo "PASS: application installed, launched, and remained alive on Android 11."
