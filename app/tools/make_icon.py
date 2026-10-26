"""Builds the app icons from the R monogram (assets/icons/app_icon_fg.png) at build time.

Look chosen 26 Oct 2026: ivory background, the R brighter and as large as the icon allows.
  assets/icons/app_icon.png     1024 x 1024, ivory square, R at 82% (phone icon on older Android, iPhone, web)
  assets/icons/app_icon_fg.png  1024 x 1024, transparent, R at 62% (Android adaptive icon; the outer part is cropped by the phone)
Runs in GitHub Actions before flutter_launcher_icons. Re-running it is harmless: it always starts from the original R.
"""
import os, shutil
from PIL import Image, ImageEnhance

SRC = 'assets/icons/app_icon_fg.png'
ORIG = 'assets/icons/r_original.png'
IVORY = (255, 253, 248, 255)

if not os.path.exists(ORIG):
    shutil.copy(SRC, ORIG)
r = Image.open(ORIG).convert('RGBA')

# 1. remove the white square baked into the artwork
px = r.load()
for y in range(r.height):
    for x in range(r.width):
        cr, cg, cb, a = px[x, y]
        if a == 0:
            continue
        m = min(cr, cg, cb)
        if m > 238:
            px[x, y] = (cr, cg, cb, 0)
        elif m > 215:
            px[x, y] = (cr, cg, cb, int(a * (238 - m) / 23))

# 2. brighter, richer colours
alpha = r.split()[3]
rgb = r.convert('RGB')
rgb = ImageEnhance.Color(rgb).enhance(1.35)
rgb = ImageEnhance.Brightness(rgb).enhance(1.06)
rgb = ImageEnhance.Contrast(rgb).enhance(1.18)
r = rgb.convert('RGBA'); r.putalpha(alpha)
r = r.crop(r.getbbox())

def place(canvas, share):
    w = int(canvas.width * share)
    h = int(r.height * w / r.width)
    if h > canvas.height * share:
        h = int(canvas.height * share); w = int(r.width * h / r.height)
    im = r.resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(im, ((canvas.width - w) // 2, (canvas.height - h) // 2))
    return canvas

place(Image.new('RGBA', (1024, 1024), IVORY), .82).convert('RGB').save('assets/icons/app_icon.png')
place(Image.new('RGBA', (1024, 1024), (0, 0, 0, 0)), .62).save('assets/icons/app_icon_fg.png')
print('icons written')
