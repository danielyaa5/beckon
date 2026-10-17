#!/usr/bin/env python3
"""Turn the captures from `Beckon --screenshots <raw>` into the README and
website images: screenshots, a widgets picture, and the demo GIF and MP4.

    python3 release/make_media.py <raw folder> docs

Needs Pillow and ffmpeg. See release/screenshots.sh, which runs both steps.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

raw = Path(sys.argv[1])
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)


def load(name, scale=1.0):
    im = Image.open(raw / f"{name}.png").convert("RGBA")
    if scale != 1.0:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    return im


def backdrop(w, h):
    """A soft desktop-like gradient, cool so Beckon's orange stands out."""
    top, bottom = (214, 224, 246), (150, 168, 226)
    im = Image.new("RGBA", (w, h))
    px = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(h - 1, 1)
        px.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w * 0.55, -h * 0.4, w * 1.3, h * 0.6], fill=(255, 214, 190, 120))
    return Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(120)))


def save_png(im, name, width=None):
    if width and im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(out / name, optimize=True)
    print("wrote", out / name)


# Screenshots (2x captures, kept sharp but not huge).
save_png(load("window-all"), "screenshot-window.png", 1600)
save_png(load("window-airtags"), "screenshot-airtags.png", 1600)
save_png(load("menu"), "screenshot-menu.png", 700)
save_png(load("palette-air"), "screenshot-palette.png", 1100)

# The widgets on a desktop-like background.
small, medium, recent = load("widget-small-ring"), load("widget-medium-ring"), load("widget-recent")
gap = 8
w = small.width + medium.width + gap + 80
h = small.height + recent.height + gap + 80
pic = backdrop(w, h)
pic.alpha_composite(small, (40, 40))
pic.alpha_composite(medium, (40 + small.width + gap, 40))
pic.alpha_composite(recent, (40 + small.width + gap, 40 + medium.height + gap))
pic.alpha_composite(load("widget-small-sent"), (40, 40 + small.height + gap))
save_png(pic, "screenshot-widgets.png", 1200)

# The demo: a desktop at 1x, the palette, the HUD and the widgets.
W, H = 1280, 800
half = 0.5
desk = backdrop(W, H)
widget_small = {s: load(f"widget-small-{s}", half) for s in ("ring", "sending", "sent")}
recent_before, recent_after = load("widget-recent", half), load("widget-recent-after", half)
palette = {q: load(f"palette-{q}", half) for q in ("empty", "a", "ai", "air")}
hud = {s: load(f"hud-{s}", half) for s in ("ringing", "sent")}

right = W - recent_before.width - 24
small_pos = (right + recent_before.width - widget_small["ring"].width, 24)
recent_pos = (right, 24 + widget_small["ring"].height - 10)
palette_pos = ((W - 360 - palette["empty"].width) // 2 + 40, 70)
hud_pos = ((W - 360 - hud["ringing"].width) // 2 + 40 + 60, 470)


def cursor(im, x, y, pressed=False):
    """A plain arrow pointer; a ring around it when it clicks."""
    d = ImageDraw.Draw(im)
    if pressed:
        d.ellipse([x - 16, y - 16, x + 16, y + 16], outline=(255, 255, 255, 230), width=3)
    pts = [(x, y), (x, y + 22), (x + 6, y + 17), (x + 10, y + 26), (x + 14, y + 24), (x + 10, y + 15), (x + 17, y + 15)]
    d.polygon(pts, fill=(0, 0, 0, 255), outline=(255, 255, 255, 255))


def frame(palette_q=None, hud_s=None, small_s="ring", rec=None, pointer=None, pressed=False):
    im = desk.copy()
    im.alpha_composite(widget_small[small_s], small_pos)
    im.alpha_composite(rec or recent_before, recent_pos)
    if palette_q is not None:
        im.alpha_composite(palette[palette_q], palette_pos)
    if hud_s:
        im.alpha_composite(hud[hud_s], hud_pos)
    if pointer:
        cursor(im, *pointer, pressed=pressed)
    return im.convert("RGB")


# The small widget's Ring button, where the pointer clicks.
button = (small_pos[0] + widget_small["ring"].width // 2, small_pos[1] + widget_small["ring"].height - 46)
rest = (button[0] - 120, button[1] + 140)
frames = [
    (frame(), 1.0),
    (frame("empty"), 0.8),
    (frame("a"), 0.3),
    (frame("ai"), 0.3),
    (frame("air"), 1.0),
    (frame(hud_s="ringing"), 1.3),
    (frame(hud_s="sent", rec=recent_after), 1.5),
    (frame(rec=recent_after, pointer=rest), 0.7),
    (frame(rec=recent_after, pointer=button), 0.35),
    (frame(rec=recent_after, pointer=button, pressed=True, small_s="sending"), 1.1),
    (frame(rec=recent_after, pointer=button, small_s="sent"), 1.6),
    (frame(rec=recent_after, pointer=rest), 0.8),
]

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    lines = []
    for i, (im, seconds) in enumerate(frames):
        name = f"f{i:02d}.png"
        im.save(tmp / name)
        lines += [f"file '{name}'", f"duration {seconds}"]
    lines.append(f"file 'f{len(frames) - 1:02d}.png'")
    (tmp / "list.txt").write_text("\n".join(lines) + "\n")
    concat = ["-f", "concat", "-safe", "0", "-i", str(tmp / "list.txt")]
    ff = ["ffmpeg", "-y", "-loglevel", "error"]
    subprocess.run(ff + concat + ["-vf", "fps=10,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
                                  str(out / "demo.gif")], check=True)
    subprocess.run(ff + concat + ["-vf", "fps=30,format=yuv420p", "-c:v", "libx264", "-crf", "20",
                                  "-movflags", "+faststart", str(out / "demo.mp4")], check=True)
    shutil.copy(tmp / "f06.png", out / "demo-poster.png")
print("wrote", out / "demo.gif", "and demo.mp4")
