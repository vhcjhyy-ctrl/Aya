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
adb exec-out screencap -p > dist/launch-screen.png
test -s dist/launch-screen.png

if ! grep -Eq "mResumedActivity:.*${APP_ID}/com\.quran\.aya\.MainActivity" dist/activities-after-launch.txt; then
  echo "Qalam Muslim MainActivity is not the resumed Activity."
  exit 1
fi

if ! grep -Eq "mFocusedApp=.*${APP_ID}/com\.quran\.aya\.MainActivity" dist/activities-after-launch.txt; then
  echo "Qalam Muslim is not the focused application Activity."
  exit 1
fi

# On Android 11, dumpsys window and dumpsys activity expose focus through
# different records. A system-owned ANR dialog can own mCurrentFocus while
# the app remains resumed and its window is still rendered. Extract the app's
# own window and verify its surface instead of searching for mFocusedApp in
# the window dump (where that field does not exist).
awk -v app="$APP_ID" '
  /^[[:space:]]*Window #[0-9]+ Window\{/ {
    if (block ~ app) printf "%s", block
    block = ""
  }
  { block = block $0 ORS }
  END {
    if (block ~ app) printf "%s", block
  }
' dist/window-after-launch.txt > dist/app-window-after-launch.txt

if ! grep -q "package=${APP_ID}" dist/app-window-after-launch.txt ||
   ! grep -q "mHasSurface=true" dist/app-window-after-launch.txt ||
   ! grep -q "Surface: shown=true" dist/app-window-after-launch.txt ||
   ! grep -q "isVisible=true" dist/app-window-after-launch.txt; then
  echo "Qalam Muslim does not have a visible rendered application window."
  exit 1
fi

if grep -E "table surahs already exists|DatabaseException.*table surahs" dist/android-launch-log.txt; then
  echo "Qalam Muslim failed while bootstrapping its bundled Quran database."
  exit 1
fi

if grep -E "FATAL EXCEPTION|Process: ${APP_ID}|ANR in ${APP_ID}|Application Not Responding: ${APP_ID}" dist/android-launch-log.txt; then
  echo "A fatal exception or application ANR was recorded."
  exit 1
fi

# A visible Android system/System UI ANR dialog can cover the application
# while its Activity and surface still exist. Do not report a clean launch
# while one of these blocking dialogs remains on screen.
if grep -Eq "Application Not Responding: (system|com\\.android\\.systemui)|package=android appop=SYSTEM_ALERT_WINDOW" dist/window-after-launch.txt; then
  echo "Android displayed a system/System UI ANR dialog over the application."
  exit 1
fi

echo "PASS: application installed, process remained alive, MainActivity stayed resumed, its window rendered, and no ANR dialog obscured it on Android 11."
