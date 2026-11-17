"""Mod icon: the wall monitor's shop render on GIANTS' ModHub mod icon background, the standard ModHub icon
(the same picture GIANTS' FS Icon Generator 25 makes in its Mod Icon mode). No logo or pin: ModHub allows no
modder references on the icon.

    python tools/make_icon.py        (after tools/build_model.py; then tools/gen_placeables.py makes the .dds)

Writes src/icon_storageMonitor.png (the game icon) and modhub/icon_512.png (the ModHub upload), both 512 x 512.
The background is ../_tools/modhub/modIcon_background.png (from GIANTS' FS Icon Generator 25).
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BACKGROUND = os.path.join(ROOT, "..", "_tools", "modhub", "modIcon_background.png")


def icon(size):
    bg = Image.open(BACKGROUND).convert("RGBA").resize((size, size), Image.LANCZOS)
    render = Image.open(os.path.join(ROOT, "src", "store", "store_wall.png")).convert("RGBA")
    render = render.crop(render.getbbox())
    scale = min(size * 0.88 / render.width, size * 0.88 / render.height)
    render = render.resize((int(render.width * scale), int(render.height * scale)), Image.LANCZOS)
    bg.alpha_composite(render, ((size - render.width) // 2, (size - render.height) // 2))
    return bg.convert("RGB")


def main():
    for size, rel in ((512, os.path.join("src", "icon_storageMonitor.png")), (512, os.path.join("modhub", "icon_512.png"))):
        out = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        icon(size).save(out, optimize=True)
        print("wrote", out)


if __name__ == "__main__":
    main()
