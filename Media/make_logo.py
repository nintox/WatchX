# WatchX logo, WoW-style: a gold bevelled frame like a spell icon, a deep crimson glow, two crossed swords and a
# hunter's eye (slit pupil, glowing iris) in a scope ring. Drawn big and scaled down (anti-aliasing).
#   python3 make_logo.py <out dir>   -> logo_512.png, logo_128.png (+ .tga for the game), previews at 64/32/20
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

N = 1024
GOLD_HI, GOLD, GOLD_LO = (255, 226, 140), (204, 163, 77), (110, 78, 28)   # WoW Forever gold, light and dark
SILVER_HI, SILVER_LO = (236, 240, 246), (128, 138, 152)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def radial(size, inner, outer, cx=0.5, cy=0.5, power=1.4):
    """A radial gradient (inner colour in the middle)."""
    g = Image.new("RGBA", (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            dx, dy = x / size - cx, y / size - cy
            t = min(1.0, (math.hypot(dx, dy) / 0.72) ** power)
            px[x, y] = lerp(inner, outer, t) + (255,)
    return g


def rounded_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([inset, inset, size - inset, size - inset], radius=radius, fill=255)
    return m


def sword(length, width):
    """One sword pointing up, on its own layer (centre of the layer = where the swords cross)."""
    L = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(L)
    cx, top = N / 2, N / 2 - length * 0.62
    guard_y = N / 2 + length * 0.18
    # blade: two halves (lit left, shaded right), a point at the top
    d.polygon([(cx, top), (cx - width / 2, top + width * 1.1), (cx - width / 2, guard_y), (cx, guard_y)], fill=SILVER_HI)
    d.polygon([(cx, top), (cx + width / 2, top + width * 1.1), (cx + width / 2, guard_y), (cx, guard_y)], fill=SILVER_LO)
    d.line([(cx, top + width * 0.9), (cx, guard_y - 10)], fill=(90, 98, 112), width=6)   # the fuller
    # crossguard, grip, pommel
    gw, gh = width * 3.2, width * 0.55
    d.rounded_rectangle([cx - gw / 2, guard_y, cx + gw / 2, guard_y + gh], radius=gh / 2, fill=GOLD, outline=GOLD_LO, width=6)
    grip_end = guard_y + gh + length * 0.22
    d.rectangle([cx - width * 0.28, guard_y + gh, cx + width * 0.28, grip_end], fill=(70, 40, 24))
    for k in range(5):   # leather wraps
        y = guard_y + gh + (k + 0.5) * (grip_end - guard_y - gh) / 5
        d.line([(cx - width * 0.28, y - 8), (cx + width * 0.28, y + 8)], fill=(40, 22, 12), width=6)
    pr = width * 0.48
    d.ellipse([cx - pr, grip_end - pr * 0.3, cx + pr, grip_end + pr * 1.7], fill=GOLD, outline=GOLD_LO, width=6)
    return L


def almond(cx, cy, half_w, half_h, steps=300):
    R = (half_w ** 2 + half_h ** 2) / (2 * half_h)
    a = math.asin(half_w / R)
    top = [(cx + R * math.sin(t), cy - (R * math.cos(t) - (R - half_h))) for t in [(-a + 2 * a * i / steps) for i in range(steps + 1)]]
    bot = [(x, 2 * cy - y) for (x, y) in reversed(top)]
    return top + bot


img = radial(N, (150, 24, 20), (14, 6, 8))
# a soft spotlight behind the eye
glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([N * 0.22, N * 0.24, N * 0.78, N * 0.76], fill=(255, 90, 40, 110))
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(90)))

# crossed swords (a dark shadow under them first)
swords = Image.new("RGBA", (N, N), (0, 0, 0, 0))
s = sword(700, 74)
swords.alpha_composite(s.rotate(42, resample=Image.BICUBIC, center=(N / 2, N / 2)))
swords.alpha_composite(s.rotate(-42, resample=Image.BICUBIC, center=(N / 2, N / 2)))
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
shadow.putalpha(swords.getchannel("A").point(lambda a: int(a * 0.7)))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)), (10, 16))
img.alpha_composite(swords)

cx, cy = N / 2, N / 2 - 10
# the scope ring and its ticks (gold), with a dark outline so it reads on the blades
ring = Image.new("RGBA", (N, N), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
R0 = 250
rd.ellipse([cx - R0, cy - R0, cx + R0, cy + R0], outline=(20, 10, 8), width=44)
for (x0, y0, x1, y1) in [(cx, cy - R0 - 70, cx, cy - R0 + 40), (cx, cy + R0 - 40, cx, cy + R0 + 70),
                         (cx - R0 - 70, cy, cx - R0 + 40, cy), (cx + R0 - 40, cy, cx + R0 + 70, cy)]:
    rd.line([x0, y0, x1, y1], fill=(20, 10, 8), width=44)
rd.ellipse([cx - R0, cy - R0, cx + R0, cy + R0], outline=GOLD, width=24)
for (x0, y0, x1, y1) in [(cx, cy - R0 - 60, cx, cy - R0 + 34), (cx, cy + R0 - 34, cx, cy + R0 + 60),
                         (cx - R0 - 60, cy, cx - R0 + 34, cy), (cx + R0 - 34, cy, cx + R0 + 60, cy)]:
    rd.line([x0, y0, x1, y1], fill=GOLD, width=24)
img.alpha_composite(ring)

# the eye: dark lids, a glowing iris, a slit pupil, a glint
eye = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ed = ImageDraw.Draw(eye)
ed.polygon(almond(cx, cy, 225, 135), fill=(12, 6, 6))
ed.polygon(almond(cx, cy, 200, 112), fill=(40, 14, 12))
iris = radial(240, (255, 236, 120), (220, 60, 20), power=1.1)
im = Image.new("L", (240, 240), 0)
ImageDraw.Draw(im).ellipse([0, 0, 239, 239], fill=255)
iris.putalpha(im)
eye.alpha_composite(iris, (int(cx - 120), int(cy - 120)))
ed = ImageDraw.Draw(eye)
ed.ellipse([cx - 120, cy - 120, cx + 120, cy + 120], outline=(120, 30, 10), width=10)
ed.polygon([(cx, cy - 98), (cx + 26, cy), (cx, cy + 98), (cx - 26, cy)], fill=(10, 4, 4))   # the slit
ed.ellipse([cx + 34, cy - 74, cx + 70, cy - 38], fill=(255, 255, 255, 230))
# keep it inside the lids
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).polygon(almond(cx, cy, 225, 135), fill=255)
eye.putalpha(ImageChops.multiply(eye.getchannel("A"), mask))
eglow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(eglow).polygon(almond(cx, cy, 240, 150), fill=(255, 120, 40, 200))
img.alpha_composite(eglow.filter(ImageFilter.GaussianBlur(28)))
img.alpha_composite(eye)

# vignette inside the frame
vig = Image.new("RGBA", (N, N), (0, 0, 0, 0))
vd = ImageDraw.Draw(vig)
for k in range(40):
    vd.rounded_rectangle([k * 3, k * 3, N - k * 3, N - k * 3], radius=120, outline=(0, 0, 0, int(160 * (1 - k / 40))), width=4)
img.alpha_composite(vig.filter(ImageFilter.GaussianBlur(10)))

# the gold frame: bevelled like a spell icon (light top-left, dark bottom-right), a dark line inside
frame = Image.new("RGBA", (N, N), (0, 0, 0, 0))
F = 58
outer, inner = rounded_mask(N, 10, 150), rounded_mask(N, 10 + F, 110)
bevel = Image.new("RGBA", (N, N))
bp = bevel.load()
for y in range(N):
    for x in range(N):
        t = (x + y) / (2 * N)
        bp[x, y] = (lerp(GOLD_HI, GOLD, t / 0.5) if t < 0.5 else lerp(GOLD, GOLD_LO, (t - 0.5) / 0.5)) + (255,)
frame.paste(bevel, (0, 0), ImageChops.subtract(outer, inner))
fd = ImageDraw.Draw(frame)
fd.rounded_rectangle([10, 10, N - 10, N - 10], radius=150, outline=(40, 26, 8), width=12)
fd.rounded_rectangle([10 + F, 10 + F, N - 10 - F, N - 10 - F], radius=110, outline=(30, 16, 6), width=14)
fd.rounded_rectangle([10 + F * 0.42, 10 + F * 0.42, N - 10 - F * 0.42, N - 10 - F * 0.42], radius=130,
                     outline=(255, 236, 170, 120), width=5)   # a thin highlight line in the gold

final = Image.new("RGBA", (N, N), (0, 0, 0, 0))
final.paste(img, (0, 0), outer)
final.alpha_composite(frame)

out = sys.argv[1] if len(sys.argv) > 1 else "."
final.resize((512, 512), Image.LANCZOS).save(out + "/logo_512.png")
small = final.resize((128, 128), Image.LANCZOS)
small.save(out + "/logo_128.png")
small.save(out + "/logo.tga")
for s in (64, 32, 20):
    final.resize((s, s), Image.LANCZOS).resize((128, 128), Image.NEAREST).save(out + f"/preview_{s}.png")
