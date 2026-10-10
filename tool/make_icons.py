"""Generates the Lapor Yuk launcher icons.

The mark ("sunrise": half sun on a horizon + three rays) must stay in sync with
LogoMarkPainter in lib/ui/widgets/logo.dart.

    python tool/make_icons.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

BLUE = (47, 95, 234, 255)  # royal blue, kLogoBlue
WHITE = (255, 255, 255, 255)
SS = 4  # supersampling
OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"


def draw_mark(d: ImageDraw.ImageDraw, size: int, scale: float, color=WHITE):
    """Mark in unit space, scaled about the centre by `scale`."""

    def p(x, y):
        return ((0.5 + (x - 0.5) * scale) * size, (0.5 + (y - 0.5) * scale) * size)

    def capsule(x0, y0, x1, y1, w):
        # rounded line from (x0,y0) to (x1,y1) with width w (unit space)
        a, b = p(x0, y0), p(x1, y1)
        width = w * scale * size
        d.line([a, b], fill=color, width=round(width))
        r = width / 2
        for cx, cy in (a, b):
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)

    cx, cy, r = 0.5, 0.655, 0.215
    # half sun
    x0, y0 = p(cx - r, cy - r)
    x1, y1 = p(cx + r, cy + r)
    d.pieslice([x0, y0, x1, y1], 180, 360, fill=color)
    # horizon
    capsule(0.20, cy + 0.04, 0.80, cy + 0.04, 0.08)
    # rays
    for deg in (-150, -90, -30):
        a = math.radians(deg)
        r0, r1 = r + 0.07, r + 0.15
        capsule(cx + math.cos(a) * r0, cy + math.sin(a) * r0, cx + math.cos(a) * r1, cy + math.sin(a) * r1, 0.075)
    # check-mark cut-out inside the sun ("laporan beres")
    cut = BLUE if color == WHITE else WHITE
    pts = [(cx - 0.09, cy - 0.095), (cx - 0.03, cy - 0.045), (cx + 0.09, cy - 0.15)]
    w = 0.06
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        a, b = p(ax, ay), p(bx, by)
        width = w * scale * size
        d.line([a, b], fill=cut, width=round(width))
    for (ax, ay) in pts:
        cxp, cyp = p(ax, ay)
        rr = w * scale * size / 2
        d.ellipse([cxp - rr, cyp - rr, cxp + rr, cyp + rr], fill=cut)


def render(size, bg, scale, rounded=False):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg is not None:
        if rounded:
            d.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.23), fill=bg)
        else:
            d.rectangle([0, 0, big, big], fill=bg)
    draw_mark(d, big, scale)
    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    # Full-bleed square: launchers apply their own mask.
    render(1024, BLUE, 1.0).save(OUT / "icon.png")
    # Adaptive foreground: keep the mark inside the 66% safe zone.
    render(1024, None, 0.62).save(OUT / "foreground.png")
    # Rounded preview for docs / splash reference.
    render(512, BLUE, 1.0, rounded=True).save(OUT / "preview.png")
    print("icons written to", OUT)
