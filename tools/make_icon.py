"""Mod icon: the wall monitor's shop render on the DTM night-field green, with the DTM pin bottom right
(building mods keep their shop render as the icon, like `_brand/tools/make_icons.py --badge`).

    python tools/make_icon.py        (after tools/build_model.py; then tools/gen_placeables.py makes the .dds)

Writes src/icon_storageMonitor.png (256 x 256, the game icon) and modhub/icon_512.png (the ModHub upload).
"""
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CREAM, GOLD, NIGHT = (244, 241, 232), (217, 164, 65), (20, 51, 38)


def pin(size):
    """The DTM marker pin of every DTM icon, at the brand tile's place and size: a cream dot (r 30 at 512 px)
    with a 12 px gold ring, i.e. gold out to r 36 and cream inside r 24."""
    ss = 4                                   # drawn 4x larger, then scaled down: smooth edges
    layer = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k = size / 512 * ss
    c = 446 * k
    for r, fill in ((36, GOLD), (24, CREAM)):
        d.ellipse([c - r * k, c - r * k, c + r * k, c + r * k], fill=fill)
    return layer.resize((size, size), Image.LANCZOS)


def icon(size):
    bg = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(bg)
    top, bottom = (31, 77, 58), (20, 51, 38)        # field green -> night field
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    k = size / 256
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([30 * k, 20 * k, 226 * k, 170 * k], fill=(34, 211, 238, 60))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(30 * k)))

    render = Image.open(os.path.join(ROOT, "src", "store", "store_wall.png")).convert("RGBA")
    render = render.crop(render.getbbox())
    scale = min(236 * k / render.width, 236 * k / render.height)
    render = render.resize((int(render.width * scale), int(render.height * scale)), Image.LANCZOS)
    shadow = Image.new("RGBA", render.size, (0, 0, 0, 0))
    shadow.putalpha(render.getchannel("A").point(lambda a: int(a * 0.45)))
    x, y = (size - render.width) // 2, (size - render.height) // 2
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(6 * k)), (int(x + 5 * k), int(y + 6 * k)))
    bg.alpha_composite(render, (x, y))
    bg.alpha_composite(pin(size))
    return bg


def main():
    for size, rel in ((256, os.path.join("src", "icon_storageMonitor.png")), (512, os.path.join("modhub", "icon_512.png"))):
        out = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        icon(size).save(out, optimize=True)
        print("wrote", out)


if __name__ == "__main__":
    main()
