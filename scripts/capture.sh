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

for p in \
  android.permission.POST_NOTIFICATIONS \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION \
  android.permission.BLUETOOTH_CONNECT \
  android.permission.CAMERA
do
  adb shell pm grant "$PKG" "$p" 2>/dev/null || true
done

launch_latch() {
  adb shell am force-stop com.android.settings 2>/dev/null || true
  adb shell am force-stop com.google.android.apps.nexuslauncher 2>/dev/null || true
  adb shell am force-stop "$PKG" 2>/dev/null || true
  adb shell am start -W -n "$PKG/$ACT" || adb shell am start -n "$PKG/$ACT"
  sleep 3
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 2
  for _ in 1 2 3 4 5 6; do
    FOCUS=$(adb shell dumpsys window 2>/dev/null | tr -d '\r' | grep -m1 mCurrentFocus || true)
    echo "FOCUS=$FOCUS"
    echo "$FOCUS" | grep -q "$PKG" && return 0
    adb shell am start -n "$PKG/$ACT" || true
    sleep 2
  done
  return 1
}

dump_ui() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
}

tap_label() {
  local label="$1"
  dump_ui
  python3 - "$label" <<'PY'
import sys,re,subprocess
label=sys.argv[1]
xml=open("/tmp/ui.xml",encoding="utf-8",errors="ignore").read()
if 'com.endroid.latch' not in xml:
    sys.exit(3)
for attr in ("text","content-desc"):
    m=re.search(r'%s="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%(attr,re.escape(label)), xml)
    if m:
        x1,y1,x2,y2=map(int,m.groups())
        x,y=(x1+x2)//2,(y1+y2)//2
        print(f"{label}->{x},{y}")
        subprocess.check_call(["adb","shell","input","tap",str(x),str(y)])
        sys.exit(0)
sys.exit(2)
PY
}

launch_latch
mkdir -p screenshots raw

# 1 Home
dump_ui
grep -q 'com.endroid.latch' /tmp/ui.xml
adb exec-out screencap -p > raw/01_home.png

# 2 Edit rule FIRST (before Settings navigation)
tap_label "Create rule" || tap_label "Add"
sleep 4
dump_ui
grep -qiE 'New rule|Edit rule|text="Name"' /tmp/ui.xml
grep -q 'com.endroid.latch' /tmp/ui.xml
adb exec-out screencap -p > raw/04_edit_rule.png

# Back to list via in-app Back
tap_label "Back" || adb shell input keyevent KEYCODE_BACK
sleep 2
dump_ui
# if left app, relaunch
if ! grep -q 'com.endroid.latch' /tmp/ui.xml; then
  launch_latch
fi

# 3 Settings
tap_label "Settings"
sleep 3
dump_ui
grep -qi 'Settings' /tmp/ui.xml
grep -q 'com.endroid.latch' /tmp/ui.xml
adb exec-out screencap -p > raw/02_settings.png

H=$(adb shell wm size | tr -d '\r' | sed -n 's/.*x\([0-9]*\).*/\1/p')
W=$(adb shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*\)x.*/\1/p')
adb shell input swipe $((W/2)) $((H*4/5)) $((W/2)) $((H/5)) 400
sleep 1
adb exec-out screencap -p > raw/03_settings_scrolled.png

# Pixel-like frame
python3 <<'PY'
from pathlib import Path
from PIL import Image, ImageDraw

RAW = Path("raw")
OUT = Path("screenshots")
OUT.mkdir(exist_ok=True)
BEZEL, RADIUS, INNER_PAD, HOLE_R = 28, 90, 10, 18

def frame_screenshot(src: Path, dst: Path):
    shot = Image.open(src).convert("RGBA")
    sw, sh = shot.size
    bw = sw + 2 * (BEZEL + INNER_PAD)
    bh = sh + 2 * (BEZEL + INNER_PAD)
    body = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.rounded_rectangle((0, 0, bw - 1, bh - 1), radius=RADIUS, fill=(18, 18, 20, 255))
    draw.rounded_rectangle((1, 1, bw - 2, bh - 2), radius=RADIUS - 1, outline=(55, 55, 60, 255), width=2)
    ix0 = iy0 = BEZEL
    ix1, iy1 = bw - BEZEL, bh - BEZEL
    draw.rounded_rectangle((ix0, iy0, ix1 - 1, iy1 - 1), radius=RADIUS - BEZEL // 2, fill=(0, 0, 0, 255))
    sx = sy = BEZEL + INNER_PAD
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=max(24, RADIUS - BEZEL), fill=255)
    body.paste(shot, (sx, sy), mask)
    cx, cy = bw // 2, BEZEL + INNER_PAD + 28
    draw.ellipse((cx - HOLE_R, cy - HOLE_R, cx + HOLE_R, cy + HOLE_R), fill=(8, 8, 10, 255))
    draw.ellipse((cx - HOLE_R + 4, cy - HOLE_R + 4, cx + HOLE_R - 4, cy + HOLE_R - 4), fill=(25, 28, 40, 255))
    draw.rounded_rectangle((bw - 6, int(bh * 0.28), bw - 1, int(bh * 0.28) + 90), radius=3, fill=(40, 40, 44, 255))
    draw.rounded_rectangle((0, int(bh * 0.24), 5, int(bh * 0.24) + 60), radius=3, fill=(40, 40, 44, 255))
    draw.rounded_rectangle((0, int(bh * 0.24) + 75, 5, int(bh * 0.24) + 150), radius=3, fill=(40, 40, 44, 255))
    body.save(dst, "PNG")
    print("framed", dst.name, body.size)

for name in ["01_home.png", "02_settings.png", "03_settings_scrolled.png", "04_edit_rule.png"]:
    src = RAW / name
    assert src.exists() and src.stat().st_size > 20000, src
    frame_screenshot(src, OUT / name)
    (OUT / f"raw_{name}").write_bytes(src.read_bytes())
print("done")
PY
ls -la screenshots
