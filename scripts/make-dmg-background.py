#!/usr/bin/env python3
"""Draws the background of the .dmg window — a small blueprint sheet.

    python3 scripts/make-dmg-background.py

Writes shared/assets/dmg-background.png (1x) and dmg-background@2x.png (2x).
scripts/build.sh combines the two into a TIFF with `tiffutil -cathidpicheck`
before handing it to create-dmg.

Why two files: a bare PNG carries no scale information, so Finder draws it
at one pixel per point; a multi-representation TIFF is the only way to say
"the same picture at two densities". (Lesson inherited from DockKeep 0.1.1.)

Everything below is in POINTS, at the same scale as the --icon coordinates
in build.sh. The two must agree.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "shared/assets"

# ── The window, in points (must match build.sh) ──────────────────────────
WIDTH, HEIGHT = 660, 380
APP_CENTRE = (180, 222)
FOLDER_CENTRE = (480, 222)

# ── Blueprint paper palette (matches BlueprintTheme.light) ───────────────
PAPER = (248, 246, 240, 255)          # #F8F6F0
INK = (51, 68, 95, 255)               # #33445F


def blend(color, opacity):
    """Pre-blended over the paper — ImageDraw replaces pixels, it doesn't
    composite, so semi-transparent draws would punch holes."""
    return tuple(
        int(PAPER[i] + (color[i] - PAPER[i]) * opacity) for i in range(3)
    ) + (255,)


INK_SOFT = blend(INK, 0.50)
INK_FAINT = blend(INK, 0.12)


def font(size, scale):
    """A monospaced font for the wordmark, wherever one lives."""
    candidates = [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Monaco.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size * scale)
    return ImageFont.load_default()


def draw(scale):
    w, h = WIDTH * scale, HEIGHT * scale
    img = Image.new("RGBA", (w, h), PAPER)
    d = ImageDraw.Draw(img)

    def pt(v):
        return v * scale

    # Drafting grid.
    step = pt(24)
    x = step
    while x < w:
        d.line([(x, 0), (x, h)], fill=INK_FAINT, width=scale)
        x += step
    y = step
    while y < h:
        d.line([(0, y), (w, y)], fill=INK_FAINT, width=scale)
        y += step

    # Wordmark, lettered like a plan annotation.
    mark = font(13, scale)
    text = "R O S T E R"
    tw = d.textlength(text, font=mark)
    d.text(((w - tw) / 2, pt(48)), text, font=mark, fill=INK)
    sub = font(9, scale)
    subtitle = "DRAG TO APPLICATIONS TO INSTALL"
    sw = d.textlength(subtitle, font=sub)
    d.text(((w - sw) / 2, pt(74)), subtitle, font=sub, fill=INK_SOFT)

    # The walk: a dashed path from the app to the Applications folder,
    # ending in an architect's arrow. The same line the agents follow.
    ax, ay = pt(APP_CENTRE[0] + 78), pt(APP_CENTRE[1])
    bx, by = pt(FOLDER_CENTRE[0] - 78), pt(FOLDER_CENTRE[1])
    dash, gap = pt(6), pt(6)
    x = ax
    while x < bx - pt(12):
        d.line([(x, ay), (min(x + dash, bx - pt(12)), by)],
               fill=INK_SOFT, width=int(pt(1.6)))
        x += dash + gap
    # Arrow head.
    d.line([(bx, by), (bx - pt(10), by - pt(6))], fill=INK_SOFT, width=int(pt(1.6)))
    d.line([(bx, by), (bx - pt(10), by + pt(6))], fill=INK_SOFT, width=int(pt(1.6)))

    # Dimension line at the bottom, pure sheet flavour.
    dy = pt(HEIGHT - 28)
    d.line([(pt(24), dy), (w - pt(24), dy)], fill=INK_SOFT, width=scale)
    d.line([(pt(24), dy - pt(5)), (pt(24), dy + pt(5))], fill=INK_SOFT, width=scale)
    d.line([(w - pt(24), dy - pt(5)), (w - pt(24), dy + pt(5))], fill=INK_SOFT, width=scale)

    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    draw(1).save(OUT / "dmg-background.png")
    draw(2).save(OUT / "dmg-background@2x.png")
    print("dmg-background.png + @2x written to shared/assets/")


if __name__ == "__main__":
    main()
