"""Writes placeables/monitor_<variant>.xml from the exported i3d files (node paths read from the i3d, so the
XML always matches the model) and converts the shop images to .dds.

    python tools/gen_placeables.py
"""
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEXTURE_TOOL = r"C:\Program Files\GIANTS Software\GIANTS_Editor_10.0.14\tools\textureTool.exe"

# name, screen width (m), draw distance (m), price, daily upkeep, silo mount (bottom edge height, centre to
# bottom edge of the model at size 1) or None
VARIANTS = [
    ("kiosk", 1.20, 30, 3500, 2, None),
    ("wall", 2.40, 50, 6500, 3, None),
    ("billboard", 4.00, 90, 12000, 5, None),
    ("wallMount", 2.40, 50, 6000, 3, (2.0, 0.846)),
]
NODES = ("body", "screenGlass", "screen", "barTemplate", "iconTemplate", "collisions", "mount", "infoTrigger",
         "playerTrigger")

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

    <storageMonitor screenNode="screen" width="{width}" drawDistance="{draw}" searchRadius="40" playerTrigger="playerTrigger"
                    barTemplate="barTemplate" iconTemplate="iconTemplate" glassNode="screenGlass" collisions="collisions">{mount}
    </storageMonitor>

    <i3dMappings>
{mappings}
    </i3dMappings>
</placeable>
"""


def mappings(i3d_path):
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
    missing = [n for n in NODES if n not in out]
    if missing:
        sys.exit("%s: missing nodes %s" % (i3d_path, missing))
    return out


def to_dds(png, dds):
    r = subprocess.run([TEXTURE_TOOL, "-inputs", png, "-targetFile", dds, "-ignoreTimestamp", "-silent"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dds):
        sys.exit("textureTool failed for %s:\n%s%s" % (png, r.stdout, r.stderr))


def main():
    os.makedirs(os.path.join(ROOT, "placeables"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "store"), exist_ok=True)
    for name, width, draw, price, upkeep, silo in VARIANTS:
        m = mappings(os.path.join(ROOT, "i3d", "monitor_%s.i3d" % name))
        lines = "\n".join('        <i3dMapping id="%s" node="%s"/>' % (n, m[n]) for n in NODES)
        if silo:      # grows upwards from its bottom edge
            mount = '\n        <mount node="mount" mode="silo" bottom="%.2f" lowerExtent="%.3f"/>' % silo
        else:         # grows from the ground
            mount = '\n        <mount node="mount" mode="ground"/>'
        xml = TEMPLATE.format(name=name, price=price, upkeep=upkeep, width="%.2f" % width, draw=draw, mappings=lines,
                              mount=mount)
        path = os.path.join(ROOT, "placeables", "monitor_%s.xml" % name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(xml)
        print("wrote", path)
        if "--no-dds" not in sys.argv:
            to_dds(os.path.join(ROOT, "src", "store", "store_%s.png" % name), os.path.join(ROOT, "store", "store_%s.dds" % name))
    if "--no-dds" not in sys.argv:
        to_dds(os.path.join(ROOT, "src", "icon_storageMonitor.png"), os.path.join(ROOT, "icon_storageMonitor.dds"))


if __name__ == "__main__":
    main()
