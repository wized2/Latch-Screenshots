#!/usr/bin/env bash
set -eux
adb wait-for-device
for i in $(seq 1 90); do
  booted=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
  if [ "$booted" = "1" ]; then
    echo "booted"
    break
  fi
  sleep 3
done
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb install -r -t apk/latch.apk
PKG=com.endroid.latch
adb shell am force-stop "$PKG" || true
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
sleep 8
mkdir -p screenshots
adb exec-out screencap -p > screenshots/01_home.png
adb shell input tap 1000 150
sleep 3
adb exec-out screencap -p > screenshots/02_settings.png
adb shell input swipe 540 1700 540 400 350
sleep 1
adb exec-out screencap -p > screenshots/03_settings_scrolled.png
adb shell input keyevent KEYCODE_BACK
sleep 2
adb shell input tap 980 1900
sleep 3
adb exec-out screencap -p > screenshots/04_edit_or_create.png
ls -la screenshots
file screenshots/*.png
for f in screenshots/*.png; do
  sz=$(stat -c%s "$f")
  test "$sz" -gt 1000
done
