# WatchX logo: LayerSwap-style dark rounded tile, a teal eye with a gold iris, and a scope crosshair.
import math, sys
from PIL import Image, ImageDraw, ImageFilter

N = 1024                       # drawn big, scaled down (anti-aliasing)
BG = (27, 32, 48, 255)         # LayerSwap navy
EDGE = (14, 16, 24, 255)
TEAL = (56, 204, 173, 255)     # WatchX accent #38CCAD
TEAL_DIM = (56, 204, 173, 110)
GOLD = (232, 182, 76, 255)     # LayerSwap gold
GOLD_DARK = (176, 128, 44, 255)
PUPIL = (20, 24, 36, 255)
WHITE = (255, 255, 255, 235)

img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
m, r = 28, 150
d.rounded_rectangle([m, m, N - m, N - m], radius=r, fill=EDGE)
d.rounded_rectangle([m + 22, m + 22, N - m - 22, N - m - 22], radius=r - 20, fill=BG)

cx, cy = N / 2, N / 2 + 6
# crosshair: four ticks outside the eye
w = 30
for (x0, y0, x1, y1) in [(cx, 120, cx, 250), (cx, N - 250, cx, N - 120), (110, cy, 205, cy), (N - 205, cy, N - 110, cy)]:
    d.line([x0, y0, x1, y1], fill=TEAL_DIM, width=w)

# the eye: an almond made of two circle arcs
def almond(half_w, half_h, steps=400):
    # circle through (-hw,0), (hw,0), (0,hh): radius R, centre at (0, hh-R)
    R = (half_w ** 2 + half_h ** 2) / (2 * half_h)
    a = math.asin(half_w / R)
    top = [(cx + R * math.sin(t), cy - (R * math.cos(t) - (R - half_h))) for t in [(-a + 2 * a * i / steps) for i in range(steps + 1)]]
    bot = [(x, 2 * cy - y) for (x, y) in reversed(top)]
    return top + bot

d.polygon(almond(330, 205), fill=TEAL)
d.polygon(almond(290, 165), fill=BG)
# iris and pupil
ir = 150
d.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=GOLD)
d.ellipse([cx - ir + 26, cy - ir + 26, cx + ir - 26, cy + ir - 26], outline=GOLD_DARK, width=10)
pr = 68
d.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=PUPIL)
# shine
d.ellipse([cx + 22, cy - 82, cx + 70, cy - 34], fill=WHITE)

# keep the eye inside the almond (the iris shouldn't stick out over the lids)
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).polygon(almond(292, 167), fill=255)
inner = Image.new("RGBA", (N, N), (0, 0, 0, 0))
inner.paste(img, (0, 0), mask)
base = Image.new("RGBA", (N, N), (0, 0, 0, 0))
bd = ImageDraw.Draw(base)
bd.rounded_rectangle([m, m, N - m, N - m], radius=r, fill=EDGE)
bd.rounded_rectangle([m + 22, m + 22, N - m - 22, N - m - 22], radius=r - 20, fill=BG)
for (x0, y0, x1, y1) in [(cx, 120, cx, 250), (cx, N - 250, cx, N - 120), (110, cy, 205, cy), (N - 205, cy, N - 110, cy)]:
    bd.line([x0, y0, x1, y1], fill=TEAL, width=w)
bd.polygon(almond(330, 205), fill=TEAL)
bd.polygon(almond(290, 165), fill=BG)
base.alpha_composite(inner)

out = sys.argv[1]
base.resize((512, 512), Image.LANCZOS).save(out + "/logo_512.png")
base.resize((128, 128), Image.LANCZOS).save(out + "/logo_128.png")
for s in (64, 32, 20):
    base.resize((s, s), Image.LANCZOS).resize((128, 128), Image.NEAREST).save(out + f"/preview_{s}.png")
