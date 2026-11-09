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

# On a cold Android 11 emulator boot, System UI can occasionally show its own
# ANR prompt while the target app remains alive, resumed, and fully drawn.
# Select Android's "Wait" action and verify recovery before deciding whether
# the application launch itself failed.
for recovery_attempt in 1 2; do
  if grep -Eq 'Application Not Responding: (system|com\.android\.systemui)' \
      dist/window-after-launch.txt; then
    SCREEN_SIZE="$(adb shell wm size | awk -F': ' '/Physical size/ {print $2; exit}' | tr -d '\r')"
    SCREEN_WIDTH="$(printf '%s' "$SCREEN_SIZE" | cut -dx -f1)"
    SCREEN_HEIGHT="$(printf '%s' "$SCREEN_SIZE" | cut -dx -f2)"
    if [[ ! "$SCREEN_WIDTH" =~ ^[0-9]+$ || ! "$SCREEN_HEIGHT" =~ ^[0-9]+$ ]]; then
      SCREEN_WIDTH=1080
      SCREEN_HEIGHT=1920
    fi
    WAIT_X=$((SCREEN_WIDTH / 2))
    WAIT_Y=$((SCREEN_HEIGHT * 474 / 1000))
    echo "System UI ANR dialog detected; selecting Wait (attempt $recovery_attempt/2)."
    adb shell input tap "$WAIT_X" "$WAIT_Y" || true
    sleep 20
    collect_diagnostics
  else
    break
  fi
done

adb exec-out screencap -p > dist/launch-screen.png
test -s dist/launch-screen.png

if ! grep -Eq "mResumedActivity:.*com\.ahmed\.qalammuslim/com\.quran\.aya\.MainActivity" dist/activities-after-launch.txt; then
  echo "Qalam Muslim MainActivity is not the resumed Activity."
  exit 1
fi

if ! grep -Eq "mFocusedApp=.*com\.ahmed\.qalammuslim/com\.quran\.aya\.MainActivity" dist/activities-after-launch.txt; then
  echo "Qalam Muslim is not the focused application Activity."
  exit 1
fi

# Android 11 exposes focus differently in dumpsys window and dumpsys activity.
# Extract the app's own window and verify that its surface is visibly rendered.
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

if ! grep -q "package=com.ahmed.qalammuslim" dist/app-window-after-launch.txt ||
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

if grep -E "FATAL EXCEPTION|Process: com\.ahmed\.qalammuslim|ANR in com\.ahmed\.qalammuslim|Application Not Responding: com\.ahmed\.qalammuslim" dist/android-launch-log.txt; then
  echo "A fatal exception or application ANR was recorded."
  exit 1
fi

# A system-owned ANR is acceptable only if Android recovered after selecting
# "Wait". Do not pass while a system dialog still obscures the app.
if grep -Eq 'Application Not Responding: (system|com\.android\.systemui)|package=android appop=SYSTEM_ALERT_WINDOW' dist/window-after-launch.txt; then
  echo "Android System UI remained unresponsive after recovery attempts."
  exit 1
fi

echo "PASS: application installed, process remained alive, MainActivity stayed resumed, its window rendered, and no blocking ANR dialog remained on Android 11."
