#!/usr/bin/env bash
set -eux
adb wait-for-device
sleep 3
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

adb install -r -t apk/latch.apk
adb shell am force-stop com.google.android.googlequicksearchbox 2>/dev/null || true
adb shell am force-stop com.google.android.apps.lens 2>/dev/null || true
adb shell am force-stop com.android.camera2 2>/dev/null || true
PKG=com.endroid.latch.debug
ACT=com.endroid.latch.MainActivity

# Grant runtime permissions so dialogs don't block UI
for p in \
  android.permission.POST_NOTIFICATIONS \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION \
  android.permission.BLUETOOTH_CONNECT \
  android.permission.CAMERA \
  android.permission.ACCESS_WIFI_STATE \
  android.permission.ACCESS_NETWORK_STATE
do
  adb shell pm grant "$PKG" "$p" 2>/dev/null || true
done

adb shell am force-stop "$PKG" || true
adb shell am start -W -n "$PKG/$ACT" || adb shell am start -n "$PKG/$ACT"
sleep 5

# If a permission dialog remains, try Allow
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
if [ -f /tmp/ui.xml ] && grep -qi 'Allow' /tmp/ui.xml; then
  python3 - <<'PY'
import re
xml=open("/tmp/ui.xml",encoding="utf-8",errors="ignore").read()
for label in ("Allow","ALLOW","While using the app"):
    m=re.search(r'text="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%re.escape(label), xml)
    if m:
        x1,y1,x2,y2=map(int,m.groups())
        print((x1+x2)//2,(y1+y2)//2)
        break
PY
  COORDS=$(python3 - <<'PY'
import re
xml=open("/tmp/ui.xml",encoding="utf-8",errors="ignore").read()
for label in ("Allow","ALLOW","While using the app"):
    m=re.search(r'text="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%re.escape(label), xml)
    if m:
        x1,y1,x2,y2=map(int,m.groups())
        print((x1+x2)//2,(y1+y2)//2)
        break
PY
)
  if [ -n "${COORDS:-}" ]; then
    adb shell input tap $COORDS
    sleep 2
  fi
fi

# Ensure app is in foreground
adb shell am start -W -n "$PKG/$ACT" || true
sleep 3
CUR=$(adb shell dumpsys window 2>/dev/null | tr -d '\r' | grep -m1 'mCurrentFocus' || true)
echo "FOCUS=$CUR"
echo "$CUR" | grep -q "$PKG" || {
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 || true
  sleep 3
}

mkdir -p screenshots raw

tap_desc() {
  local desc="$1"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
  python3 - "$desc" <<'PY'
import sys,re
desc=sys.argv[1]
xml=open("/tmp/ui.xml",encoding="utf-8",errors="ignore").read()
for attr in ("content-desc","text"):
    m=re.search(r'%s="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%(attr,re.escape(desc)), xml)
    if not m:
        m=re.search(r'%s="%s".*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%(attr,re.escape(desc)), xml, re.S)
    if m:
        x1,y1,x2,y2=map(int,m.groups())
        print((x1+x2)//2,(y1+y2)//2)
        sys.exit(0)
sys.exit(2)
PY
}

assert_app() {
  local out="$1"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
  if ! grep -qiE 'Latch|com.endroid.latch' /tmp/ui.xml; then
    echo "WARNING: Latch UI not detected before $out"
    adb shell am start -W -n "$PKG/$ACT" || true
    sleep 2
  fi
}

assert_app home
adb exec-out screencap -p > raw/01_home.png

if COORDS=$(tap_desc "Settings"); then
  adb shell input tap $COORDS
else
  # Top app-bar gear: right side
  SIZE=$(adb shell wm size | tr -d '\r')
  W=$(echo "$SIZE" | sed -n 's/.*: \([0-9]*\)x.*/\1/p')
  adb shell input tap $((W - 80)) 180
fi
sleep 3
assert_app settings
adb exec-out screencap -p > raw/02_settings.png

H=$(adb shell wm size | tr -d '\r' | sed -n 's/.*x\([0-9]*\).*/\1/p')
W=$(adb shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*\)x.*/\1/p')
adb shell input swipe $((W/2)) $((H*4/5)) $((W/2)) $((H/5)) 400
sleep 1
adb exec-out screencap -p > raw/03_settings_scrolled.png

adb shell input keyevent KEYCODE_BACK
sleep 2
assert_app home2

# Prefer primary CTA "Create rule", then FAB "Add"
EDIT_OK=
if COORDS=$(tap_desc "Create rule"); then
  adb shell input tap $COORDS
  EDIT_OK=1
elif COORDS=$(tap_desc "Add"); then
  adb shell input tap $COORDS
  EDIT_OK=1
fi
if [ -z "$EDIT_OK" ]; then
  # Last resort: approximate FAB above gesture bar on 1080x2424
  adb shell input tap 980 2100
fi
sleep 3
# If still not edit (e.g. wrong app), back and try Create rule again
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
if ! grep -qiE 'Trigger|Action|Save|Name|Condition|Edit rule|New rule' /tmp/ui.xml; then
  adb shell am start -W -n "$PKG/$ACT" || true
  sleep 2
  if COORDS=$(tap_desc "Create rule"); then
    adb shell input tap $COORDS
    sleep 3
  fi
fi
assert_app edit
adb exec-out screencap -p > raw/04_edit_rule.png
# Must be on New rule / Edit rule form
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
if ! grep -qiE 'New rule|Edit rule|text="Name"|text="When"' /tmp/ui.xml; then
  echo "ERROR: 04 not on edit form"
  # dump a bit of xml for CI logs
  head -c 2000 /tmp/ui.xml || true
  exit 1
fi
if grep -qiE 'Google Lens|Search with any image' /tmp/ui.xml; then
  echo "ERROR: 04 still Google Lens"
  exit 1
fi

# Frame with Pixel-like device chrome
python3 <<'PY'
from pathlib import Path
from PIL import Image, ImageDraw

RAW = Path("raw")
OUT = Path("screenshots")
OUT.mkdir(exist_ok=True)

# Pixel-ish proportions: thin flat bezel, continuous curve, centered punch-hole
BEZEL = 28          # side/top/bottom bezel thickness in px (output scale)
RADIUS = 90         # outer corner radius
INNER_PAD = 10      # gap between glass and bezel
HOLE_R = 18
SCALE = 1  # keep native res

def frame_screenshot(src: Path, dst: Path):
    shot = Image.open(src).convert("RGBA")
    sw, sh = shot.size
    # Outer body size
    bw = sw + 2 * (BEZEL + INNER_PAD)
    bh = sh + 2 * (BEZEL + INNER_PAD)
    body = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)

    # Outer chassis (near-black graphite)
    draw.rounded_rectangle((0, 0, bw - 1, bh - 1), radius=RADIUS, fill=(18, 18, 20, 255))
    # Subtle outer rim highlight
    draw.rounded_rectangle((1, 1, bw - 2, bh - 2), radius=RADIUS - 1, outline=(55, 55, 60, 255), width=2)

    # Inner display well
    ix0 = BEZEL
    iy0 = BEZEL
    ix1 = bw - BEZEL
    iy1 = bh - BEZEL
    draw.rounded_rectangle((ix0, iy0, ix1 - 1, iy1 - 1), radius=RADIUS - BEZEL // 2, fill=(0, 0, 0, 255))

    # Paste screenshot inset
    sx = BEZEL + INNER_PAD
    sy = BEZEL + INNER_PAD
    # Round-mask the screenshot
    mask = Image.new("L", (sw, sh), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, sw - 1, sh - 1), radius=max(24, RADIUS - BEZEL), fill=255)
    body.paste(shot, (sx, sy), mask)

    # Punch-hole camera (top center)
    cx = bw // 2
    cy = BEZEL + INNER_PAD + 28
    draw.ellipse((cx - HOLE_R, cy - HOLE_R, cx + HOLE_R, cy + HOLE_R), fill=(8, 8, 10, 255))
    draw.ellipse((cx - HOLE_R + 4, cy - HOLE_R + 4, cx + HOLE_R - 4, cy + HOLE_R - 4), fill=(25, 28, 40, 255))

    # Side buttons (power right, volume left)
    draw.rounded_rectangle((bw - 6, int(bh * 0.28), bw - 1, int(bh * 0.28) + 90), radius=3, fill=(40, 40, 44, 255))
    draw.rounded_rectangle((0, int(bh * 0.24), 5, int(bh * 0.24) + 60), radius=3, fill=(40, 40, 44, 255))
    draw.rounded_rectangle((0, int(bh * 0.24) + 75, 5, int(bh * 0.24) + 150), radius=3, fill=(40, 40, 44, 255))

    body.save(dst, "PNG")
    print("framed", dst, body.size)

for name in ["01_home.png", "02_settings.png", "03_settings_scrolled.png", "04_edit_rule.png"]:
    src = RAW / name
    if not src.exists():
        raise SystemExit(f"missing {src}")
    # Sanity: file not tiny
    if src.stat().st_size < 20000:
        raise SystemExit(f"suspicious small shot {src}")
    frame_screenshot(src, OUT / name)

# Also keep unframed copies for docs flexibility
for name in ["01_home.png", "02_settings.png", "03_settings_scrolled.png", "04_edit_rule.png"]:
    (OUT / f"raw_{name}").write_bytes((RAW / name).read_bytes())

print("done")
PY

ls -la screenshots
python3 <<'PY'
from pathlib import Path
from PIL import Image
for p in sorted(Path("screenshots").glob("0*.png")):
    im=Image.open(p)
    print(p.name, im.size, p.stat().st_size)
# Fail if 04 still looks like pure launcher (very dark average center after framing is ok)
# Compare file sizes of raw
for p in sorted(Path("raw").glob("*.png")):
    print("raw", p.name, p.stat().st_size)
PY
