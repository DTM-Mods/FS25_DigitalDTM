"""Draws the monitor's screen texture (the panels the live text and bars are drawn on) and a preview with
sample data for the shop images and the README, then converts the textures to .dds with GIANTS' textureTool.

    python tools/make_textures.py [--no-dds]

Writes:
    src/textures/monitor_screen_diffuse.png   -> textures/monitor_screen_diffuse.dds   (in the mod)
    src/textures/monitor_preview.png          (sample screen, used by tools/render_store.py and the README)

The layout numbers are the same as StorageMonitor.LAYOUT in scripts/StorageMonitor.lua (tests compare).
"""
import io
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "src", "textures")
OUT = os.path.join(ROOT, "textures")
FONT = os.path.join(ROOT, "..", "_brand", "font", "Outfit.ttf")
TEXTURE_TOOL = r"C:\Program Files\GIANTS Software\GIANTS_Editor_10.0.14\tools\textureTool.exe"

DESIGN_W = 1.6
PX = 1000                      # pixels per design unit while drawing (1600 x 1000)
TEX_SIZE = (2048, 1024)        # stored size; the quad's UVs undo the squash

LAYOUT = {
    "header": (0.000, 0.000, 1.600, 0.105),
    "capPanel": (0.035, 0.130, 1.565, 0.370),
    "listPanel": (0.035, 0.395, 1.565, 0.905),
    "footer": (0.000, 0.930, 1.600, 1.000),
    "listHeadV": 0.440,
    "listTopV": 0.468,
    "listBottomV": 0.899,
    "listInnerU": (0.065, 1.535),
    "colGap": 0.050,
    "rowH": 0.062,
    "stackBar": (0.420, 0.235, 1.530, 0.285),
    "rowBarU": (0.700, 1.170),
    "rowBarHalfH": 0.011,
    "pageBar": (0.600, 0.962, 1.000, 0.968),
}
ROWS = 7

# Colour themes: one screen texture each (textures/screen_<id>.dds). The text and bar colours of each theme
# are in StorageMonitor.THEMES (scripts/StorageMonitor.lua); keep the ids in the same order.
THEMES = {
    "night": dict(bg=((9, 16, 29), (12, 22, 38)), header=((16, 38, 68), (13, 30, 54)), panel=(14, 27, 47),
                  border=(33, 62, 99), accent=(34, 211, 238), footer=(10, 19, 33), dim=(128, 148, 176),
                  grid=(80, 130, 200, 10), scan=22),
    "field": dict(bg=((15, 38, 28), (20, 51, 38)), header=((31, 77, 58), (24, 62, 46)), panel=(22, 54, 41),
                  border=(46, 107, 79), accent=(217, 164, 65), footer=(13, 33, 25), dim=(127, 164, 138),
                  grid=(127, 164, 138, 10), scan=18),
    "amber": dict(bg=((8, 6, 2), (14, 10, 4)), header=((34, 22, 6), (24, 16, 4)), panel=(17, 12, 4),
                  border=(96, 64, 14), accent=(255, 176, 0), footer=(10, 7, 2), dim=(160, 112, 36),
                  grid=(255, 176, 0, 9), scan=40),
    "light": dict(bg=((226, 232, 240), (210, 218, 229)), header=((38, 58, 88), (28, 45, 70)), panel=(242, 245, 249),
                  border=(160, 176, 196), accent=(0, 120, 200), footer=(196, 205, 217), dim=(90, 106, 128),
                  grid=(40, 70, 110, 12), scan=8, vignette=35),
}
THEME_ORDER = ["night", "field", "amber", "light"]

T = THEMES["night"]                     # the preview with sample data uses the default theme
ACCENT = T["accent"]
DIM = T["dim"]


def px(v):
    return int(round(v * PX))


def box(b):
    return [px(b[0]), px(b[1]), px(b[2]), px(b[3])]


def gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def corner_brackets(d, b, color, length=26, width=3):
    x0, y0, x1, y1 = box(b)
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.line([(cx, cy), (cx + sx * length, cy)], fill=color, width=width)
        d.line([(cx, cy), (cx, cy + sy * length)], fill=color, width=width)


def font(size, weight=None):
    f = ImageFont.truetype(FONT, size)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f


def draw_background(theme="night"):
    t = THEMES[theme]
    accent, border = t["accent"], t["border"]
    w, h = px(DESIGN_W), PX
    img = gradient((w, h), *t["bg"]).convert("RGBA")
    over = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)

    # faint grid
    for x in range(0, w, 40):
        d.line([(x, 0), (x, h)], fill=t["grid"])
    for y in range(0, h, 40):
        d.line([(0, y), (w, y)], fill=t["grid"])

    # header band with an accent line
    hb = box(LAYOUT["header"])
    head = gradient((hb[2] - hb[0], hb[3] - hb[1]), *t["header"]).convert("RGBA")
    over.alpha_composite(head, (hb[0], hb[1]))
    d.line([(0, hb[3] - 2), (w, hb[3] - 2)], fill=accent + (170,), width=3)
    d.rectangle([px(0.050) - 22, px(0.035), px(0.050) - 14, px(0.075)], fill=accent + (255,))   # title marker

    # panels
    for name in ("capPanel", "listPanel"):
        b = box(LAYOUT[name])
        d.rounded_rectangle(b, radius=14, fill=t["panel"] + (235,), outline=border + (255,), width=2)
        corner_brackets(d, LAYOUT[name], accent + (200,))

    # list: column header line; no row stripes, the rows change with the number of products
    lp = LAYOUT["listPanel"]
    sep = px(LAYOUT["listHeadV"] + 0.015)
    d.line([(px(lp[0]) + 18, sep), (px(lp[2]) - 18, sep)], fill=border + (255,), width=2)

    # capacity panel: divider between the big number and the bar
    cp = LAYOUT["capPanel"]
    d.line([(px(0.385), px(cp[1]) + 22), (px(0.385), px(cp[3]) - 22)], fill=border + (255,), width=2)

    # footer band with a dim name
    fb = box(LAYOUT["footer"])
    d.rectangle(fb, fill=t["footer"] + (255,))
    d.line([(0, fb[1]), (w, fb[1])], fill=border + (255,), width=2)
    d.text((px(0.050), px(0.973)), "DIGITAL DTM", font=font(26, 500), fill=t["dim"] + (110,), anchor="ls")

    img.alpha_composite(over)

    # scan lines and a soft vignette: reads as a screen, not a poster
    lines = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for y in range(0, h, 4):
        ld.line([(0, y), (w, y)], fill=(0, 0, 0, t["scan"]))
    img.alpha_composite(lines)
    vignette = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vignette)
    vd.rectangle([60, 40, w - 60, h - 40], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(90))
    dark = Image.new("RGBA", (w, h), (0, 0, 0, t.get("vignette", 120)))
    img = Image.composite(img, Image.alpha_composite(img, dark), vignette)
    return img.convert("RGB")


SAMPLE = [  # title, litres, colour (as the Lua palette)
    ("Wheat", 412000, (0.93, 0.76, 0.33)),
    ("Canola", 168500, (0.98, 0.90, 0.20)),
    ("Barley", 96200, (0.85, 0.66, 0.36)),
    ("Soybeans", 61800, (0.86, 0.80, 0.55)),
    ("Corn", 40250, (1.00, 0.78, 0.10)),
    ("Sorghum", 18400, (0.80, 0.42, 0.25)),
    ("Sunflowers", 9100, (1.00, 0.84, 0.00)),
    ("Chaff", 21, (0.63, 0.85, 0.25)),
]
SAMPLE_CAPACITY = 1000000


def rgb(c, a=255):
    return tuple(int(round(x * 255)) for x in c) + (a,)


def fmt(n):
    return "{:,} l".format(int(round(n)))


def draw_preview(bg):
    img = bg.convert("RGBA")
    d = ImageDraw.Draw(img)
    L = LAYOUT
    text, dim, ok, accent = (230, 242, 255, 255), DIM + (255,), (52, 211, 153, 255), ACCENT + (255,)

    d.text((px(0.050), px(0.070)), "MULTIFRUIT SILO", font=font(px(0.050) + 6, 700), fill=text, anchor="ls")
    d.text((px(1.550), px(0.070)), "14:35", font=font(px(0.045) + 6, 700), fill=accent, anchor="rs")

    used = sum(s[1] for s in SAMPLE)
    pct = round(used / SAMPLE_CAPACITY * 100)
    d.text((px(0.070), px(0.185)), "CAPACITY", font=font(px(0.032) + 4, 600), fill=dim, anchor="ls")
    d.text((px(0.070), px(0.318)), "%d%%" % pct, font=font(px(0.125) + 14, 800), fill=(252, 191, 36, 255) if pct >= 75 else ok, anchor="ls")
    sb = L["stackBar"]
    d.text((px(sb[0]), px(sb[1] - 0.022)), "USED  " + fmt(used), font=font(px(0.040) + 4, 700), fill=text, anchor="ls")
    d.text((px(sb[2]), px(sb[1] - 0.022)), "TOTAL  " + fmt(SAMPLE_CAPACITY), font=font(px(0.040) + 4, 400), fill=dim, anchor="rs")
    d.rectangle(box(sb), fill=(26, 41, 66, 255))
    u = sb[0]
    for _, litres, col in SAMPLE:
        w = (sb[2] - sb[0]) * litres / SAMPLE_CAPACITY
        if w > 0.002:
            d.rectangle([px(u), px(sb[1]), px(u + w), px(sb[3])], fill=rgb(col))
            u += w
    d.rectangle([px(sb[0]), px(sb[3] + 0.004), px(sb[0] + (sb[2] - sb[0]) * used / SAMPLE_CAPACITY), px(sb[3] + 0.009)], fill=ok)
    d.text((px(sb[0]), px(0.338)), "FREE  " + fmt(SAMPLE_CAPACITY - used), font=font(px(0.034) + 4, 400), fill=ok, anchor="ls")
    d.text((px(sb[2]), px(0.338)), "%d PRODUCTS" % len(SAMPLE), font=font(px(0.034) + 4, 400), fill=dim, anchor="rs")

    small = font(px(0.028) + 4, 600)
    d.text((px(0.070), px(L["listHeadV"])), "PRODUCT", font=small, fill=dim, anchor="ls")
    d.text((px(L["rowBarU"][0]), px(L["listHeadV"])), "FILL", font=small, fill=dim, anchor="ls")
    d.text((px(1.385), px(L["listHeadV"])), "AMOUNT", font=small, fill=dim, anchor="rs")
    d.text((px(1.535), px(L["listHeadV"])), "%", font=small, fill=dim, anchor="rs")
    row_font, pct_font = font(px(0.040) + 4, 400), font(px(0.036) + 4, 700)
    for r, (title, litres, col) in enumerate(SAMPLE[:ROWS]):
        vc = L["listTopV"] + L["rowH"] * (r + 0.5)
        d.rectangle([px(0.070), px(vc - 0.014), px(0.098), px(vc + 0.014)], fill=rgb(col))
        d.text((px(0.120), px(vc + 0.014)), title, font=row_font, fill=text, anchor="ls")
        u0, u1 = L["rowBarU"]
        h = L["rowBarHalfH"]
        d.rectangle([px(u0), px(vc - h), px(u1), px(vc + h)], fill=(26, 38, 61, 255))
        frac = litres / SAMPLE_CAPACITY
        d.rectangle([px(u0), px(vc - h), px(u0 + max(0.004, (u1 - u0) * frac)), px(vc + h)], fill=rgb(col))
        d.text((px(1.385), px(vc + 0.014)), fmt(litres), font=row_font, fill=text, anchor="rs")
        p = max(1, round(frac * 100)) if litres > 0 else 0
        d.text((px(1.535), px(vc + 0.014)), "%d%%" % p, font=pct_font, fill=rgb(col), anchor="rs")

    d.text((px(1.550), px(0.973)), "PAGE 1/2", font=small, fill=dim, anchor="rs")
    pb = L["pageBar"]
    d.rectangle(box(pb), fill=(18, 28, 46, 255))
    d.rectangle([px(pb[0]), px(pb[1]), px(pb[0] + (pb[2] - pb[0]) * 0.6), px(pb[3])], fill=accent)
    return img.convert("RGB")


def save_dxt1(im, path):
    """A DXT1 .dds with its full mipmap chain, written with Pillow: textureTool stores the tiny white texture as an
    uncompressed DX10 file, which ModHub's DXT check refuses."""
    levels = [im.convert("RGB")]
    while levels[-1].width > 1 or levels[-1].height > 1:
        w, h = levels[-1].size
        levels.append(levels[0].resize((max(w // 2, 1), max(h // 2, 1)), Image.LANCZOS))
    blobs = []
    for level in levels:
        b = io.BytesIO()
        level.save(b, format="DDS", pixel_format="DXT1")
        blobs.append(b.getvalue())
    head = bytearray(blobs[0][:128])
    head[28:32] = len(levels).to_bytes(4, "little")                                          # mipmap count
    head[8:12] = (int.from_bytes(head[8:12], "little") | 0x20000).to_bytes(4, "little")      # DDSD_MIPMAPCOUNT
    head[108:112] = (int.from_bytes(head[108:112], "little") | 0x400008).to_bytes(4, "little")  # COMPLEX | MIPMAP
    with open(path, "wb") as f:
        f.write(bytes(head) + b"".join(x[128:] for x in blobs))


def main():
    os.makedirs(SRC, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    sources = []
    for theme in THEME_ORDER:                # screen_night is the model's own; the game swaps in the others
        bg = draw_background(theme)
        screen = os.path.join(SRC, "screen_%s.png" % theme)
        bg.resize(TEX_SIZE, Image.LANCZOS).save(screen)
        sources.append(screen)
        bg.save(os.path.join(SRC, "screen_%s_full.png" % theme))      # 1600 x 1000, for tools/render_screen.py
        if theme == "night":
            preview = draw_preview(bg)
            preview.save(os.path.join(SRC, "monitor_preview.png"))
            preview.resize(TEX_SIZE, Image.LANCZOS).save(os.path.join(SRC, "monitor_preview_tex.png"))
        print("wrote", screen)

    white = os.path.join(SRC, "monitor_white_diffuse.png")     # the live bars' texture (colour comes from the script)
    Image.new("RGBA", (16, 16), (255, 255, 255, 255)).save(white)

    if "--no-dds" in sys.argv:
        return
    for src in sources:
        target = os.path.join(OUT, os.path.splitext(os.path.basename(src))[0] + ".dds")
        r = subprocess.run([TEXTURE_TOOL, "-inputs", src, "-targetFile", target, "-ignoreTimestamp", "-silent"],
                           capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(target):
            sys.exit("textureTool failed:\n%s%s" % (r.stdout, r.stderr))
        print("wrote", target, os.path.getsize(target))
    target = os.path.join(OUT, "monitor_white_diffuse.dds")
    save_dxt1(Image.open(white), target)
    print("wrote", target, os.path.getsize(target))


if __name__ == "__main__":
    main()
