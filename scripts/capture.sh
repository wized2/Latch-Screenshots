#!/usr/bin/env bash
set -eux
adb wait-for-device
sleep 3
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

adb install -r -t apk/latch.apk
PKG=com.endroid.latch.debug
ACT=com.endroid.latch.MainActivity
adb shell am force-stop "$PKG" || true
adb shell am start -n "$PKG/$ACT"
sleep 6

# Dismiss system dialogs if any
adb shell input keyevent KEYCODE_BACK || true
sleep 1
adb shell am start -n "$PKG/$ACT"
sleep 4

mkdir -p screenshots /tmp/ui

tap_desc() {
  local desc="$1"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  adb pull /sdcard/ui.xml /tmp/ui/ui.xml >/dev/null 2>&1 || true
  if [ ! -f /tmp/ui/ui.xml ]; then return 1; fi
  python3 - "$desc" <<'PY'
import sys, re
desc = sys.argv[1]
xml = open("/tmp/ui/ui.xml", encoding="utf-8", errors="ignore").read()
# content-desc match
pat = re.compile(r'content-desc="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % re.escape(desc))
m = pat.search(xml)
if not m:
    pat = re.compile(r'content-desc="%s".*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % re.escape(desc), re.S)
    m = pat.search(xml)
if not m:
    # text=
    pat = re.compile(r'text="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % re.escape(desc))
    m = pat.search(xml)
if not m:
    sys.exit(2)
x1,y1,x2,y2 = map(int, m.groups())
print((x1+x2)//2, (y1+y2)//2)
PY
}

# 1 Home
adb exec-out screencap -p > screenshots/01_home.png

# 2 Settings via content-desc
if COORDS=$(tap_desc "Settings"); then
  adb shell input tap $COORDS
else
  # fallback top-right on tall Pixel-like screens
  adb shell input tap 980 220
fi
sleep 3
adb exec-out screencap -p > screenshots/02_settings.png

# 3 Scroll settings
adb shell input swipe 540 2000 540 500 400
sleep 1
adb exec-out screencap -p > screenshots/03_settings_scrolled.png

# Back to home
adb shell input keyevent KEYCODE_BACK
sleep 2

# 4 Add / create rule via FAB content-desc "Add"
if COORDS=$(tap_desc "Add"); then
  adb shell input tap $COORDS
else
  # bottom-right FAB fallback for ~1080x2424
  adb shell input tap 960 2200
fi
sleep 3
adb exec-out screencap -p > screenshots/04_edit_rule.png

# Validate sizes + that edit screen is not identical to home
ls -la screenshots
python3 <<'PY'
from pathlib import Path
import hashlib
shots = sorted(Path("screenshots").glob("*.png"))
assert len(shots) >= 4, shots
for p in shots:
    assert p.stat().st_size > 5000, p
h1 = hashlib.md5(Path("screenshots/01_home.png").read_bytes()).hexdigest()
h4 = hashlib.md5(Path("screenshots/04_edit_rule.png").read_bytes()).hexdigest()
assert h1 != h4, "edit screenshot same as home — FAB tap failed"
print("ok", [(p.name, p.stat().st_size) for p in shots])
PY
