"""Writes placeables/monitor_<variant>.xml from the exported i3d files (node paths read from the i3d, so the
XML always matches the model) and converts the shop images to .dds.

    python tools/gen_placeables.py
"""
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEXTURE_TOOL = r"C:\Program Files\GIANTS Software\GIANTS_Editor_10.0.14\tools\textureTool.exe"

# name, screen width (m), draw distance (m), price, daily upkeep, raised mount (bottom edge height, centre to
# bottom edge of the model at size 1) or None, two-sided
VARIANTS = [
    ("kiosk", 1.20, 30, 3500, 2, None, False),
    ("wall", 2.40, 50, 6500, 3, None, False),
    ("billboard", 4.00, 90, 12000, 5, None, False),
    ("wallMount", 2.40, 50, 6000, 3, (2.0, 0.846), False),
    ("buildingMount", 2.40, 50, 5500, 3, (2.0, 0.846), False),
    ("hanging", 2.40, 50, 5500, 3, (2.5, 0.846), False),
    ("billboard2", 4.00, 90, 18000, 7, None, True),
]
# the largest screen size of each model (= MAX_WIDTHS in tools/build_model.py, which builds collisions up to it)
MAX_WIDTHS = {"kiosk": 3.0, "wall": 6.0}
MAX_WIDTH = 12.0
NODES = ("body", "screenGlass", "screen", "barTemplate", "iconTemplate", "collisions", "mount", "infoTrigger",
         "playerTrigger")
BACK_NODES = ("screenBack", "screenGlassBack", "barTemplateBack", "iconTemplateBack")

TEMPLATE = """<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<placeable type="storageMonitor" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://validation.gdn.giants-software.com/xml/fs25/placeable.xsd">
    <storeData>
        <name>$l10n_shopItem_storageMonitor_{name}</name>
        <functions>
            <function>$l10n_function_storageMonitor</function>
        </functions>
        <image>store/store_{name}.png</image>
        <price>{price}</price>
        <dailyUpkeep>{upkeep}</dailyUpkeep>
        <lifetime>1000</lifetime>
        <rotation>0</rotation>
        <brand>NONE</brand>
        <species>placeable</species>
        <category>placeableMisc</category>
        <brush>
            <type>placeable</type>
            <category>buildings</category>
            <tab>tools</tab>
        </brush>
    </storeData>

    <base>
        <filename>i3d/monitor_{name}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
        <boughtWithFarmland>true</boughtWithFarmland>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <sounds>
            <place template="smallImp" pitchScale="1.2"/>
        </sounds>
    </placement>

    <clearAreas/>
    <leveling requireLeveling="false"/>
    <indoorAreas/>
    <ai>
        <updateAreas/>
    </ai>

    <infoTrigger triggerNode="infoTrigger"/>

    <storageMonitor screenNode="screen" width="{width}" maxWidth="{maxWidth}" drawDistance="{draw}" searchRadius="40" playerTrigger="playerTrigger"
                    barTemplate="barTemplate" iconTemplate="iconTemplate" glassNode="screenGlass" collisions="collisions">{mount}
    </storageMonitor>

    <i3dMappings>
{mappings}
    </i3dMappings>
</placeable>
"""


def mappings(i3d_path, nodes):
    scene = ET.parse(i3d_path).getroot().find("Scene")
    roots = [c for c in scene if c.tag in ("TransformGroup", "Shape")]
    if len(roots) != 1:
        sys.exit("%s: expected one root node" % i3d_path)
    out = {}

    def walk(elem, path):
        for i, child in enumerate(c for c in elem if c.tag in ("TransformGroup", "Shape")):
            p = path + [str(i)]
            out[child.get("name")] = "0>" + "|".join(p)
            walk(child, p)
    walk(roots[0], [])
    missing = [n for n in nodes if n not in out]
    if missing:
        sys.exit("%s: missing nodes %s" % (i3d_path, missing))
    return out


def to_dds(png, dds):
    r = subprocess.run([TEXTURE_TOOL, "-inputs", png, "-targetFile", dds, "-ignoreTimestamp", "-silent"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dds):
        sys.exit("textureTool failed for %s:\n%s%s" % (png, r.stdout, r.stderr))


# block-compressed formats: bytes per 4x4 block (DXT1 / BC1 = 8, the others 16)
BLOCK_BYTES = {b"DXT1": 8, 70: 8, 71: 8, 72: 8}


def keep_mips(dds, keep=1):
    """Cuts the mipmap chain textureTool writes down to `keep` levels: GIANTS' FS25 ModHub guidelines want shop
    images without mipmaps (it is only drawn in the menu, at most at its own size)."""
    with open(dds, "rb") as f:
        data = f.read()
    count = int.from_bytes(data[28:32], "little")
    if count <= keep:
        return
    width, height = int.from_bytes(data[16:20], "little"), int.from_bytes(data[12:16], "little")
    four_cc = data[84:88]
    header = 128
    block = BLOCK_BYTES.get(four_cc, 16)
    if four_cc == b"DX10":
        header += 20
        block = BLOCK_BYTES.get(int.from_bytes(data[128:132], "little"), 16)
    size = 0
    for level in range(keep):
        w, h = max(width >> level, 1), max(height >> level, 1)
        size += max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * block
    head = bytearray(data[:header])
    head[28:32] = keep.to_bytes(4, "little")
    with open(dds, "wb") as f:
        f.write(bytes(head) + data[header:header + size])


def main():
    os.makedirs(os.path.join(ROOT, "placeables"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "store"), exist_ok=True)
    for name, width, draw, price, upkeep, silo, two in VARIANTS:
        nodes = NODES + (BACK_NODES if two else ())
        m = mappings(os.path.join(ROOT, "i3d", "monitor_%s.i3d" % name), nodes)
        lines = "\n".join('        <i3dMapping id="%s" node="%s"/>' % (n, m[n]) for n in nodes)
        if silo:      # grows upwards from its bottom edge
            mount = '\n        <mount node="mount" mode="silo" bottom="%.2f" lowerExtent="%.3f"/>' % silo
        else:         # grows from the ground
            mount = '\n        <mount node="mount" mode="ground"/>'
        if two:       # the second screen on the back
            mount += ('\n        <back screenNode="screenBack" barTemplate="barTemplateBack" iconTemplate="iconTemplateBack"'
                      ' glassNode="screenGlassBack"/>')
        xml = TEMPLATE.format(name=name, price=price, upkeep=upkeep, width="%.2f" % width, draw=draw, mappings=lines,
                              maxWidth="%.2f" % MAX_WIDTHS.get(name, MAX_WIDTH),
                              mount=mount)
        path = os.path.join(ROOT, "placeables", "monitor_%s.xml" % name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(xml)
        print("wrote", path)
        if "--no-dds" not in sys.argv:
            store = os.path.join(ROOT, "store", "store_%s.dds" % name)
            to_dds(os.path.join(ROOT, "src", "store", "store_%s.png" % name), store)
            keep_mips(store)
    if "--no-dds" not in sys.argv:
        # the mod icon: DXT1 without mipmaps, as ModHub's check wants (textureTool adds mipmaps)
        icon = Image.open(os.path.join(ROOT, "src", "icon_storageMonitor.png")).convert("RGB")
        icon.save(os.path.join(ROOT, "icon_storageMonitor.dds"), format="DDS", pixel_format="DXT1")


if __name__ == "__main__":
    main()
