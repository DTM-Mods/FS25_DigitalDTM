"""Checks the mod and packs build/FS25_DigitalDTM.zip.

    python tools/build_mod.py

Checks: every file the XMLs point to exists, GIANTS' limits (at most 128 files, Lua files at most 0.5 MB,
known file types only), Lua syntax, and the offline tests (tests/run_tests.py).
"""
import os
import re
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ZIP = os.path.join(ROOT, "build", "FS25_DigitalDTM.zip")
SHIP_DIRS = {"scripts": (".lua",), "translations": (".xml",), "placeables": (".xml",), "i3d": (".i3d", ".shapes"),
             "textures": (".dds",), "store": (".dds",)}
SHIP_FILES = ["modDesc.xml", "icon_storageMonitor.dds"]
KNOWN = (".xml", ".lua", ".i3d", ".shapes", ".dds", ".png", ".ogg", ".txt")
MAX_FILES, MAX_LUA = 128, 512 * 1024

errors = []


def check(cond, msg):
    if not cond:
        errors.append(msg)


def files():
    out = list(SHIP_FILES)
    for d, exts in SHIP_DIRS.items():
        for name in sorted(os.listdir(os.path.join(ROOT, d))):
            if name.endswith(exts):
                out.append(d + "/" + name)
    return out


def exists_game_path(base_dir, ref):
    if ref.startswith("$"):
        return True
    path = os.path.normpath(os.path.join(base_dir, ref))
    if os.path.exists(path):
        return True
    root, ext = os.path.splitext(path)
    return ext == ".png" and os.path.exists(root + ".dds")


def check_refs(shipped):
    mod = ET.parse(os.path.join(ROOT, "modDesc.xml")).getroot()
    check(exists_game_path(ROOT, mod.find("iconFilename").text), "icon missing")
    for item in mod.iter("storeItem"):
        rel = item.get("xmlFilename")
        check(rel in shipped, "store item not shipped: " + rel)
        x = ET.parse(os.path.join(ROOT, rel)).getroot()
        i3d = x.find("base/filename").text
        check(i3d in shipped, "%s: i3d not shipped: %s" % (rel, i3d))
        img = x.find("storeData/image").text
        check(exists_game_path(ROOT, img), "%s: shop image missing: %s" % (rel, img))
        check(x.find("storageMonitor") is not None, "%s: no storageMonitor element" % rel)
        ids = {m.get("id") for m in x.iter("i3dMapping")}
        for attr in ("screenNode", "playerTrigger"):
            check(x.find("storageMonitor").get(attr) in ids, "%s: %s not mapped" % (rel, attr))
        i3d_root = ET.parse(os.path.join(ROOT, i3d)).getroot()
        for f in i3d_root.find("Files"):
            ref = f.get("filename")
            if not ref.startswith("$"):
                target = os.path.relpath(os.path.normpath(os.path.join(ROOT, os.path.dirname(i3d), ref)), ROOT).replace("\\", "/")
                check(target in shipped, "%s: texture not shipped: %s" % (i3d, target))
        shapes = i3d_root.find("Shapes").get("externalShapesFile")
        check(os.path.dirname(i3d) + "/" + shapes in shipped, "%s: shapes not shipped" % i3d)
    for spec in mod.iter("specialization"):
        if spec.get("filename"):
            check(spec.get("filename") in shipped, "specialization file not shipped: " + spec.get("filename"))
    for src in mod.iter("sourceFile"):
        check(src.get("filename") in shipped, "source file not shipped: " + src.get("filename"))


def check_lua(rel):
    path = os.path.join(ROOT, rel)
    check(os.path.getsize(path) <= MAX_LUA, "%s: larger than 0.5 MB" % rel)
    import lupa
    lua = lupa.LuaRuntime()
    src = open(path, encoding="utf-8").read()
    ok, err = lua.eval("function(s, n) local f, e = load(s, n) return f ~= nil, e end")(src, rel)
    check(ok, "%s: %s" % (rel, err))


def main():
    shipped = files()
    check(len(shipped) <= MAX_FILES, "%d files (limit %d)" % (len(shipped), MAX_FILES))
    for rel in shipped:
        check(rel.lower().endswith(KNOWN), "unknown file type: " + rel)
        if rel.endswith(".lua"):
            check_lua(rel)
        if rel.endswith(".xml"):
            try:
                ET.parse(os.path.join(ROOT, rel))
            except ET.ParseError as e:
                check(False, "%s: %s" % (rel, e))
    check_refs(set(shipped))
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tests", "run_tests.py")], capture_output=True, text=True)
    check(r.returncode == 0, "tests failed:\n" + r.stdout + r.stderr)
    if errors:
        print("\n".join("ERROR: " + e for e in errors))
        sys.exit(1)

    os.makedirs(os.path.dirname(ZIP), exist_ok=True)
    tmp = ZIP + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in shipped:
            z.write(os.path.join(ROOT, rel), rel)
    os.replace(tmp, ZIP)
    version = re.search(r"<version>([^<]+)</version>", open(os.path.join(ROOT, "modDesc.xml"), encoding="utf-8").read()).group(1)
    print("built %s (%d files, %d bytes, version %s)" % (ZIP, len(shipped), os.path.getsize(ZIP), version))


if __name__ == "__main__":
    main()
