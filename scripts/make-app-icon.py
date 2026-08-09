#!/usr/bin/env python3
"""Generates Roster's AppIcon PNGs.

The icon is the app itself in miniature: a night-blueprint sheet, the
room drawn in ink with its door gap, one desk, and the lavender agent
dot mid-crossing on its dashed path.

Like DockKeep's icon script, small sizes get their own drawing instead
of a blind downscale: 16 px keeps only the room and the dot; the grid
and the path appear from 128 px up.

Usage:
    python3 scripts/make-app-icon.py
Writes into app/Roster/Resources/Assets.xcassets/AppIcon.appiconset/.
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / (
    "app/Roster/Resources/Assets.xcassets/AppIcon.appiconset"
)

# Night blueprint palette (matches BlueprintTheme.dark).
BG_TOP = (14, 26, 46, 255)        # #0E1A2E
BG_BOTTOM = (9, 17, 32, 255)      # a touch darker, subtle vertical ramp
INK = (169, 194, 232, 255)        # #A9C2E8
ACCENT = (108, 120, 230, 255)     # #6C78E6

BG_MID = tuple((BG_TOP[i] + BG_BOTTOM[i]) // 2 for i in range(4))


def blend(color: tuple, opacity: float) -> tuple:
    """Pre-blends `color` over the background: PIL's ImageDraw replaces
    pixels instead of compositing, so semi-transparent fills would punch
    holes in the icon."""
    return tuple(
        int(BG_MID[i] + (color[i] - BG_MID[i]) * opacity) for i in range(3)
    ) + (255,)


INK_SOFT = blend(INK, 0.55)
INK_FAINT = blend(INK, 0.09)
HALO = blend(ACCENT, 0.30)


def draw_icon(size: int) -> Image.Image:
    """Draws one icon at `size`, using 4x supersampling for clean lines."""
    scale = 4
    s = size * scale

    def px(v: float) -> float:
        """Design units (0..1) to pixels."""
        return v * s

    margin = px(0.055)
    radius = px(0.225)

    # Everything is drawn opaque on the ramped background; the rounded
    # mask is applied at the very end.
    content = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    cd = ImageDraw.Draw(content)
    for y in range(s):
        t = y / s
        color = tuple(
            int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(4)
        )
        cd.line([(0, y), (s, y)], fill=color)
    d = cd

    detailed = size >= 128
    line = max(px(0.018), 1.5 * scale)
    thin = max(px(0.008), 1.0 * scale)

    # ── Drafting grid (big sizes only) ───────────────────────────────
    if detailed:
        step = px(0.135)
        x = margin + step
        while x < s - margin:
            d.line([(x, margin), (x, s - margin)], fill=INK_FAINT, width=int(thin))
            x += step
        y = margin + step
        while y < s - margin:
            d.line([(margin, y), (s - margin, y)], fill=INK_FAINT, width=int(thin))
            y += step

    # ── The room: walls with a door gap bottom-left ──────────────────
    left, top = px(0.22), px(0.24)
    right, bottom = px(0.78), px(0.80)
    gap_from, gap_to = px(0.30), px(0.44)  # door gap on the bottom wall

    w = int(line)
    d.line([(left, bottom), (left, top)], fill=INK, width=w)          # left
    d.line([(left, top), (right, top)], fill=INK, width=w)            # top
    d.line([(right, top), (right, bottom)], fill=INK, width=w)        # right
    d.line([(right, bottom), (gap_to, bottom)], fill=INK, width=w)    # bottom (right of gap)
    d.line([(gap_from, bottom), (left, bottom)], fill=INK, width=w)   # bottom (left of gap)
    if detailed:
        # Door leaf into the room.
        d.line([(gap_from, bottom), (gap_from, bottom - px(0.10))], fill=INK_SOFT, width=int(thin))

    # ── One desk at the top (a working station) ──────────────────────
    desk_w, desk_h = px(0.20), px(0.075)
    desk_x, desk_y = px(0.30), px(0.31)
    d.rectangle(
        [desk_x, desk_y, desk_x + desk_w, desk_y + desk_h],
        outline=INK, width=max(int(thin), 1)
    )
    if detailed:
        # Monitor bar on the desk.
        d.rectangle(
            [desk_x + desk_w * 0.28, desk_y + desk_h * 0.28,
             desk_x + desk_w * 0.72, desk_y + desk_h * 0.55],
            fill=INK,
        )

    # ── The dashed walk path (big sizes only) ─────────────────────────
    dot_x, dot_y = px(0.585), px(0.615)
    if detailed:
        start = (px(0.44), px(0.42))
        end = (dot_x, dot_y)
        segments = 7
        for i in range(segments):
            t0 = i / segments
            t1 = (i + 0.55) / segments
            a = (start[0] + (end[0] - start[0]) * t0, start[1] + (end[1] - start[1]) * t0)
            b = (start[0] + (end[0] - start[0]) * t1, start[1] + (end[1] - start[1]) * t1)
            d.line([a, b], fill=INK_SOFT, width=int(thin))

    # ── The agent: lavender dot with a soft halo ──────────────────────
    halo_r = px(0.115)
    dot_r = px(0.062) if size >= 32 else px(0.085)
    d.ellipse([dot_x - halo_r, dot_y - halo_r, dot_x + halo_r, dot_y + halo_r], fill=HALO)
    d.ellipse([dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r], fill=ACCENT)

    # Rounded-square mask, applied once everything is drawn.
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, s - margin, s - margin], radius=radius, fill=255
    )
    img.paste(content, (0, 0), mask)
    return img.resize((size, size), Image.LANCZOS)


SIZES = [16, 32, 64, 128, 256, 512, 1024]

ENTRIES = [
    ("icon_16.png", "16x16", "1x", 16),
    ("icon_32.png", "16x16", "2x", 32),
    ("icon_32.png", "32x32", "1x", 32),
    ("icon_64.png", "32x32", "2x", 64),
    ("icon_128.png", "128x128", "1x", 128),
    ("icon_256.png", "128x128", "2x", 256),
    ("icon_256.png", "256x256", "1x", 256),
    ("icon_512.png", "256x256", "2x", 512),
    ("icon_512.png", "512x512", "1x", 512),
    ("icon_1024.png", "512x512", "2x", 1024),
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for size in SIZES:
        draw_icon(size).save(OUT / f"icon_{size}.png")
        print(f"icon_{size}.png")

    images = ",\n".join(
        f'    {{ "filename" : "{name}", "idiom" : "mac", "scale" : "{scale}", "size" : "{sizes}" }}'
        for name, sizes, scale, _ in ENTRIES
    )
    (OUT / "Contents.json").write_text(
        '{\n  "images" : [\n%s\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
        % images
    )
    print("Contents.json")


if __name__ == "__main__":
    main()
