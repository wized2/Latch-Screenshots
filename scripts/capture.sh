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

for p in android.permission.POST_NOTIFICATIONS android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION android.permission.BLUETOOTH_CONNECT; do
  adb shell pm grant "$PKG" "$p" 2>/dev/null || true
done

adb shell am start -W -n "$PKG/$ACT" || adb shell am start -n "$PKG/$ACT"
sleep 6

adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
if grep -q 'Allow Latch' /tmp/ui.xml 2>/dev/null; then
  python3 - <<'PY'
import re,subprocess
xml=open("/tmp/ui.xml",encoding="utf-8",errors="ignore").read()
m=re.search(r'text="Allow"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
if m:
  x1,y1,x2,y2=map(int,m.groups())
  subprocess.check_call(["adb","shell","input","tap",str((x1+x2)//2),str((y1+y2)//2)])
PY
  sleep 2
fi

mkdir -p screenshots raw

tap() {
  local label="$1"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
  python3 - "$label" <<'PY'
import sys,re,subprocess
label=sys.argv[1]
xml=open("/tmp/ui.xml",encoding="utf-8",errors="ignore").read()
for attr in ("text","content-desc"):
    m=re.search(r'%s="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%(attr,re.escape(label)), xml)
    if m:
        x1,y1,x2,y2=map(int,m.groups())
        subprocess.check_call(["adb","shell","input","tap",str((x1+x2)//2),str((y1+y2)//2)])
        print("ok", label)
        sys.exit(0)
print("missing", label)
sys.exit(1)
PY
}

adb exec-out screencap -p > raw/01_home.png

tap "Create rule" || tap "Add"
sleep 4
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
grep -qiE 'New rule|Edit rule|text="Name"' /tmp/ui.xml
adb exec-out screencap -p > raw/04_edit_rule.png

tap "Back" || true
sleep 2
adb shell am start -n "$PKG/$ACT" >/dev/null 2>&1 || true
sleep 2

tap "Settings"
sleep 3
adb exec-out screencap -p > raw/02_settings.png

H=$(adb shell wm size | tr -d '\r' | sed -n 's/.*x\([0-9]*\).*/\1/p')
W=$(adb shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*\)x.*/\1/p')
adb shell input swipe $((W/2)) $((H*4/5)) $((W/2)) $((H/5)) 400
sleep 1
adb exec-out screencap -p > raw/03_settings_scrolled.png

python3 <<'PY'
from pathlib import Path
from PIL import Image, ImageDraw
RAW, OUT = Path("raw"), Path("screenshots")
OUT.mkdir(exist_ok=True)
BEZEL, RADIUS, INNER, HOLE = 28, 90, 10, 18

def frame(src, dst):
    shot = Image.open(src).convert("RGBA")
    sw, sh = shot.size
    bw, bh = sw + 2*(BEZEL+INNER), sh + 2*(BEZEL+INNER)
    body = Image.new("RGBA", (bw, bh), (0,0,0,0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((0,0,bw-1,bh-1), radius=RADIUS, fill=(18,18,20,255))
    d.rounded_rectangle((1,1,bw-2,bh-2), radius=RADIUS-1, outline=(55,55,60,255), width=2)
    d.rounded_rectangle((BEZEL,BEZEL,bw-BEZEL-1,bh-BEZEL-1), radius=RADIUS-BEZEL//2, fill=(0,0,0,255))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,sw-1,sh-1), radius=max(24,RADIUS-BEZEL), fill=255)
    body.paste(shot, (BEZEL+INNER, BEZEL+INNER), mask)
    cx, cy = bw//2, BEZEL+INNER+28
    d.ellipse((cx-HOLE,cy-HOLE,cx+HOLE,cy+HOLE), fill=(8,8,10,255))
    d.ellipse((cx-HOLE+4,cy-HOLE+4,cx+HOLE-4,cy+HOLE-4), fill=(25,28,40,255))
    d.rounded_rectangle((bw-6,int(bh*0.28),bw-1,int(bh*0.28)+90), radius=3, fill=(40,40,44,255))
    d.rounded_rectangle((0,int(bh*0.24),5,int(bh*0.24)+60), radius=3, fill=(40,40,44,255))
    d.rounded_rectangle((0,int(bh*0.24)+75,5,int(bh*0.24)+150), radius=3, fill=(40,40,44,255))
    body.save(dst)

for n in ["01_home.png","02_settings.png","03_settings_scrolled.png","04_edit_rule.png"]:
    assert (RAW/n).stat().st_size > 20000
    frame(RAW/n, OUT/n)
    (OUT/f"raw_{n}").write_bytes((RAW/n).read_bytes())
    print("ok", n)
PY
ls -la screenshots
