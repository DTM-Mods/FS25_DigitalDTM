"""Builds the Digital DTM monitor models in Blender, exports each with the GIANTS I3D exporter and renders
their shop images.

    blender --background --factory-startup --python tools/build_model.py -- [variant ...]

Variants (all screens are 16:10):
    kiosk      1.20 m screen on a pedestal, tilted back 10 degrees
    wall       2.40 m screen on two posts, to stand against a silo or wall
    billboard  4.00 m screen on two tall posts, readable from a tractor
    wallMount  2.40 m screen on a bracket against a silo (grows upwards from 2 m)
    buildingMount  2.40 m screen flat against a building wall (grows upwards from 2 m)
    hanging    2.40 m screen hanging on two rods, for inside a shed (grows upwards from 2.5 m)
    billboard2 4.00 m two-sided billboard: a screen on the front and one on the back

Geometry is written in i3d coordinates (x right, y up, +z towards the viewer) and converted to Blender's
z-up axes (x, -z, y) only when an object is created; the exporter converts back.

Writes i3d/monitor_<variant>.i3d(.shapes), src/store/store_<variant>.png and build/<variant>.blend.
"""
import importlib
import math
import os
import sys

import addon_utils
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME_DIR = "C:/Program Files (x86)/Steam/steamapps/common/Farming Simulator 25/"
TEXTURES = os.path.join(ROOT, "textures")
SRC = os.path.join(ROOT, "src")

EXPORTER = "io_export_i3d_10_0_2"
try:
    import importlib.util as _ilu
    if _ilu.find_spec(EXPORTER) is None and _ilu.find_spec("io_export_i3d") is not None:
        EXPORTER = "io_export_i3d"
except Exception:
    pass

COL_BUILDING = ("0x1034", "0xfffffbff")
COL_PLAYER_TRIGGER = ("0x20000000", "0x100000")
SIZE_WIDTHS = [0.8, 1.2, 1.6, 2.0, 2.4, 3.0, 3.6, 4.2, 4.8, 6.0, 7.2, 8.4, 9.6, 12.0]   # = StorageMonitor.SIZE_WIDTHS
# the largest size of each model (= maxWidth in its placeable XML; tools/gen_placeables.py): collisions only up to it
MAX_WIDTHS = {"kiosk": 3.0, "wall": 6.0}
MAX_WIDTH = SIZE_WIDTHS[-1]
SILO_BOTTOM = 2.0                                                  # silo mount: screen bottom edge above ground

VARIANTS = {
    "kiosk": dict(width=1.20, center_y=1.40, tilt=-10.0, bezel=0.045, depth=0.06, housing=0.10,
                  mount="pedestal", trigger=((0.0, 1.0, 1.0), (1.8, 2.0, 1.8)), clip=200),
    "wall": dict(width=2.40, center_y=2.05, tilt=0.0, bezel=0.06, depth=0.07, housing=0.08,
                 mount="posts", post=0.08, post_x=0.75, trigger=((0.0, 1.0, 1.5), (3.0, 2.0, 2.6)), clip=300),
    "billboard": dict(width=4.00, center_y=3.80, tilt=0.0, bezel=0.09, depth=0.10, housing=0.12,
                      mount="posts", post=0.14, post_x=1.30, trigger=((0.0, 1.0, 2.5), (5.0, 2.0, 4.6)), clip=500),
    # silo mount: no posts; the screen hangs on a bracket whose back touches the silo wall, and the game
    # scales the "mount" node to the screen size chosen in the monitor's settings (bottom edge at 2 m)
    "wallMount": dict(width=2.40, center_y=2.846, lower_extent=0.846, tilt=0.0, bezel=0.06, depth=0.07, housing=0.08,
                      mount="silo", arm=0.30, trigger=((0.0, 1.0, 1.6), (3.0, 2.0, 2.6)), clip=300, backdrop="silo"),
    # the same, flat against a building wall: short arms, a plate the full height of the screen
    "buildingMount": dict(width=2.40, center_y=2.846, lower_extent=0.846, tilt=0.0, bezel=0.06, depth=0.07, housing=0.08,
                          mount="silo", arm=0.05, trigger=((0.0, 1.0, 1.4), (3.0, 2.0, 2.4)), clip=300, backdrop="wall"),
    # hangs from a ceiling or beam on two rods; its bottom edge stays at 2.5 m, it grows upwards (rods and all)
    "hanging": dict(width=2.40, center_y=3.346, lower_extent=0.846, bottom=2.5, tilt=0.0, bezel=0.06, depth=0.07,
                    housing=0.08, mount="hang", rod=1.2, trigger=((0.0, 1.0, 1.4), (3.0, 2.0, 2.8)), clip=300,
                    backdrop="beam"),
    # two screens back to back between two tall posts
    "billboard2": dict(width=4.00, center_y=3.80, tilt=0.0, bezel=0.09, depth=0.10, housing=0.12, mount="posts2",
                       post=0.14, post_x=1.30, two_sided=True, trigger=((0.0, 1.0, 0.0), (5.0, 2.0, 9.2)), clip=500),
}
RAISED = ("silo", "hang")       # mounts whose bottom edge stays put and that grow upwards

MATERIALS = {   # name: (base colour, emission, roughness)
    "monitor_frame": ((0.035, 0.038, 0.045), None, 0.45),
    "monitor_metal": ((0.30, 0.32, 0.35), None, 0.35),
    "monitor_base": ((0.10, 0.11, 0.12), None, 0.6),
    "monitor_led": ((0.10, 0.90, 0.45), (0.10, 0.90, 0.45), 0.3),
    "monitor_accent": ((0.13, 0.80, 0.93), (0.07, 0.45, 0.52), 0.3),
}


def to_blender(p):
    return (p[0], -p[2], p[1])


def make_materials(screen_image):
    for name, (color, emission, rough) in MATERIALS.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = color + (1.0,)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Emission Color"].default_value = (emission or (0.0, 0.0, 0.0)) + (1.0,)
        if emission:
            bsdf.inputs["Emission Strength"].default_value = 1.0
        mat.diffuse_color = color + (1.0,)
        mat.use_backface_culling = True
    # the screen: glowShader "staticLight" without emitColor glows with its own texture, so the panels can be
    # read at night; the script sets the glow (lightControl, brightness setting) and swaps the texture (theme)
    mat = bpy.data.materials.new("monitor_screen")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.25
    tex = nodes.new("ShaderNodeTexImage")
    tex.name = "screenTexture"
    tex.image = screen_image
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat["customShader"] = "$data/shaders/glowShader.xml"
    mat["customShaderVariation"] = "staticLight"
    mat["customParameter_lightControl"] = "0.25"
    mat.diffuse_color = (0.05, 0.08, 0.13, 1.0)
    mat.use_backface_culling = True

    # live bars: the game's glowShader in "staticLight" mode, whose glow colour the script sets per copy
    # (emitColor), like vehicle dashboard lights; a plain white texture, the colour comes from emitColor
    mat = bpy.data.materials.new("monitor_bar")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    img = bpy.data.images.new("monitor_white_diffuse", 4, 4)
    img.source = "FILE"
    img.filepath = os.path.join(TEXTURES, "monitor_white_diffuse.dds")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat["customShader"] = "$data/shaders/glowShader.xml"
    mat["customShaderVariation"] = "staticLight"
    mat["customParameter_lightControl"] = "1"
    mat["customParameter_emitColor"] = "1 1 1 1"
    mat.diffuse_color = (0.2, 0.8, 0.9, 1.0)
    mat.use_backface_culling = True


class Mesh:
    """Quads in i3d coordinates with UVs and a material per face."""

    def __init__(self):
        self.faces = []      # (points, uvs, material)

    def quad(self, pts, mat, uv=((0, 0), (1, 0), (1, 1), (0, 1))):
        self.faces.append(([Vector(p) for p in pts], list(uv), mat))

    def box(self, lo, hi, mat, skip=()):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        faces = {   # counter-clockwise seen from outside
            "+x": [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)],
            "-x": [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],
            "+y": [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)],
            "-y": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
            "+z": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
            "-z": [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)],
        }
        for key, pts in faces.items():
            if key not in skip:
                self.quad(pts, mat)

    def transformed(self, fn):
        out = Mesh()
        out.faces = [([fn(p) for p in pts], uv, m) for pts, uv, m in self.faces]
        return out

    def extend(self, other):
        self.faces += other.faces

    def to_object(self, name, parent):
        verts, polys = [], []
        for pts, _, _ in self.faces:
            polys.append(list(range(len(verts), len(verts) + len(pts))))
            verts += [to_blender(p) for p in pts]
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], polys)
        mats = []
        for _, _, m in self.faces:
            if m not in mats:
                mats.append(m)
        for m in mats:
            me.materials.append(bpy.data.materials[m])
        uv = me.uv_layers.new(name="uv0")
        for poly, (_, uvs, m) in zip(me.polygons, self.faces):
            poly.material_index = mats.index(m)
            for li, t in zip(poly.loop_indices, uvs):
                uv.data[li].uv = t
        me.validate()
        me.update()
        return add_object(name, me, parent)


def add_object(name, data, parent, location=(0.0, 0.0, 0.0), rot_x=0.0, rot_y=0.0):
    obj = bpy.data.objects.new(name, data)
    assert obj.name == name, "duplicate node name " + name
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = to_blender(location)
    # i3d x rotation == Blender x rotation; i3d y (up) == Blender z (up)
    obj.rotation_euler = (math.radians(rot_x), 0.0, math.radians(rot_y))
    return obj


def node(name, parent=None, location=(0.0, 0.0, 0.0), rot_x=0.0, rot_y=0.0):
    obj = add_object(name, None, parent, location, rot_x, rot_y)
    obj.empty_display_size = 0.2
    return obj


FILTERS = {}     # node name -> {attribute: hex string}: written back after export (see fix_i3d)


def attrs(obj, **kw):
    # exporter 10.0 reads i3D_*, 10.5 I3D_* (and wants the collision filters as integers)
    for k, v in kw.items():
        obj["i3D_" + k] = v
        if k in ("collisionFilterGroup", "collisionFilterMask"):
            FILTERS.setdefault(obj.name, {})[k] = v
        if k in ("collisionFilterGroup", "collisionFilterMask") and isinstance(v, str):
            v = int(v, 16)
            if v >= 2 ** 31:        # Blender's int properties are signed 32-bit
                v -= 2 ** 32
        obj["I3D_" + k] = v
    return obj


def head(v):
    """The screen unit around its own centre (glass centre at the origin, facing +z)."""
    w = v["width"]
    h = w / 1.6
    b, d, hd = v["bezel"], v["depth"], v["housing"]
    glass_z = d / 2 - 0.008
    body = Mesh()
    hw, hh = w / 2, h / 2
    # bezel: four bars around the glass, front at +d/2
    body.box((-hw - b, -hh - b * 1.6, -d / 2), (hw + b, -hh, d / 2), "monitor_frame")          # bottom (taller chin)
    body.box((-hw - b, hh, -d / 2), (hw + b, hh + b, d / 2), "monitor_frame")                  # top
    body.box((-hw - b, -hh, -d / 2), (-hw, hh, d / 2), "monitor_frame", skip=("+y", "-y"))     # left
    body.box((hw, -hh, -d / 2), (hw + b, hh, d / 2), "monitor_frame", skip=("+y", "-y"))       # right
    # inner lip behind the glass (no gap visible) and the back housing
    body.box((-hw, -hh, -d / 2), (hw, hh, glass_z - 0.004), "monitor_frame", skip=("+x", "-x", "+y", "-y"))
    inset = b * 2.5
    body.box((-hw - b + inset, -hh - b * 1.6 + inset, -d / 2 - hd), (hw + b - inset, hh + b - inset, -d / 2),
             "monitor_frame", skip=("+z",))
    # power LED and an accent strip on the chin
    chin_y = -hh - b * 0.8
    led = max(0.012, b * 0.22)
    body.box((hw - b * 0.2 - led * 2.5, chin_y - led / 2, d / 2), (hw - b * 0.2 - led * 1.5, chin_y + led / 2, d / 2 + 0.004), "monitor_led", skip=("-z",))
    strip = max(0.004, b * 0.08)
    body.box((-w * 0.18, chin_y - strip / 2, d / 2), (w * 0.18, chin_y + strip / 2, d / 2 + 0.002), "monitor_accent", skip=("-z",))

    glass = Mesh()
    glass.quad([(-hw, -hh, glass_z), (hw, -hh, glass_z), (hw, hh, glass_z), (-hw, hh, glass_z)], "monitor_screen")
    return body, glass, glass_z


def mount(v):
    m = Mesh()
    w = v["width"]
    h = w / 1.6
    d, hd, b = v["depth"], v["housing"], v["bezel"]
    back_z = -d / 2 - hd
    bottom_y = v["center_y"] - h / 2 - b * 1.6
    if v["mount"] == "posts2":   # two-sided: the posts stand between the two screens
        p = v["post"]
        top = v["center_y"] + h / 2 - b
        for sx in (-1, 1):
            x = sx * v["post_x"]
            m.box((x - p / 2, 0.0, -p / 2), (x + p / 2, top, p / 2), "monitor_metal", skip=("-y",))
            m.box((x - p * 2, 0.0, -p * 3), (x + p * 2, 0.02, p * 3), "monitor_base", skip=("-y",))
        m.box((-v["post_x"], bottom_y - p * 1.4, -p * 0.3), (v["post_x"], bottom_y - p * 0.6, p * 0.3), "monitor_metal")
    elif v["mount"] == "hang":   # in the mount node's space: screen centre at y = 0; two rods up to ceiling plates
        rod, r = v["rod"], 0.03
        top_y = h / 2 + b
        for sx in (-1, 1):
            x = sx * w * 0.3
            m.box((x - r / 2, top_y, -r / 2), (x + r / 2, top_y + rod, r / 2), "monitor_metal", skip=("-y",))
            m.box((x - 0.05, top_y, -0.04), (x + 0.05, top_y + 0.03, 0.04), "monitor_base")             # clamp
            m.box((x - 0.09, top_y + rod, -0.09), (x + 0.09, top_y + rod + 0.015, 0.09), "monitor_base")  # ceiling plate
    elif v["mount"] == "posts":
        p = v["post"]
        top = v["center_y"] + h / 2 - b
        for sx in (-1, 1):
            x = sx * v["post_x"]
            m.box((x - p / 2, 0.0, back_z - p), (x + p / 2, top, back_z), "monitor_metal", skip=("-y",))
            m.box((x - p * 2, 0.0, back_z - p * 3), (x + p * 2, 0.02, back_z + p * 1.2), "monitor_base", skip=("-y",))
        # cross bar under the screen
        m.box((-v["post_x"], bottom_y - p * 1.4, back_z - p * 0.8), (v["post_x"], bottom_y - p * 0.6, back_z - p * 0.2), "monitor_metal")
    elif v["mount"] == "silo":   # in the mount node's space: screen centre at y = 0
        arm, a = v["arm"], max(0.05, b * 0.9)
        h2 = h / 2
        for sx in (-1, 1):
            x = sx * w * 0.3
            for y in (h2 * 0.55, -h2 * 0.55):
                m.box((x - a / 2, y - a / 2, back_z - arm), (x + a / 2, y + a / 2, back_z), "monitor_metal", skip=("+z",))
            # wall plate the arms end on
            m.box((x - a * 1.4, -h2 * 0.7, back_z - arm - 0.015), (x + a * 1.4, h2 * 0.7, back_z - arm), "monitor_base")
    else:   # pedestal
        m.box((-0.35, 0.0, -0.35), (0.35, 0.04, 0.25), "monitor_base", skip=("-y",))
        m.box((-0.08, 0.04, -0.18), (0.08, v["center_y"] - 0.15, -0.06), "monitor_metal", skip=("-y",))
        m.box((-0.15, v["center_y"] - 0.25, -0.16), (0.15, v["center_y"] - 0.12, back_z + 0.02), "monitor_frame")
    return m


def build(name, v):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    blend = os.path.join(ROOT, "build", "monitor_%s.blend" % name)
    os.makedirs(os.path.dirname(blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=False)

    img = bpy.data.images.new("screen_night", 4, 4)
    img.source = "FILE"
    img.filepath = os.path.join(TEXTURES, "screen_night.dds")
    make_materials(img)

    tilt = math.radians(v["tilt"])
    silo = v["mount"] in RAISED
    cy = 0.0 if silo else v["center_y"]     # a raised mount's head is lifted by its mount node instead
    two = v.get("two_sided", False)
    zo = (v["depth"] / 2 + v["housing"] + v["post"] / 2) if two else 0.0    # back to back, posts between

    def place(p):      # head local -> model: tilt about x, then lift to the screen centre
        y = p.y * math.cos(tilt) - p.z * math.sin(tilt)
        z = p.y * math.sin(tilt) + p.z * math.cos(tilt)
        return Vector((p.x, y + cy, z + zo))

    def place_back(p):     # the back screen: the front one turned 180 degrees about y
        q = place(p)
        return Vector((-q.x, q.y, -q.z))

    # Everything visible hangs below "mount", which the script scales to the chosen screen size: a silo
    # mount from its bottom edge (the node sits at the screen centre), a free-standing one from the ground.
    root = attrs(node("storageMonitor_" + name), clipDistance=float(v["clip"]))
    parent = node("mount", root, (0.0, v["center_y"] if silo else 0.0, 0.0))
    body, glass, glass_z = head(v)
    full = body.transformed(place)
    if two:
        full.extend(body.transformed(place_back))
    full.extend(mount(v))
    attrs(full.to_object("body", parent), clipDistance=float(v["clip"]))      # visual only: it is resized
    # Collision for every screen size (StorageMonitor.SIZE_WIDTHS), outside "mount": a static body cannot be
    # scaled, so the script switches on the one that fits the chosen size and the others off. Without it the
    # monitor cannot be selected (to sell it) in construction mode. Named by width in cm.
    collisions = node("collisions", root)
    for width in [w for w in SIZE_WIDTHS if w <= MAX_WIDTHS.get(name, MAX_WIDTH) + 1e-6]:
        s = width / v["width"]
        if silo:     # grows upwards from its bottom edge, depth kept (as setStorageMonitorSize does)
            lift = v.get("bottom", SILO_BOTTOM) + v["lower_extent"] * s

            def sized(p, s=s, lift=lift):
                return Vector((p.x * s, p.y * s + lift, p.z))
        else:        # grows from the ground
            def sized(p, s=s):
                return Vector((p.x * s, p.y * s, p.z * s))
        attrs(full.transformed(sized).to_object("collision_%03d" % round(width * 100), collisions), static=True,
              nonRenderable=True, castsShadows=False, receiveShadows=False,
              collisionFilterGroup=COL_BUILDING[0], collisionFilterMask=COL_BUILDING[1])
    faces = [("", place, 0.0)]
    if two:
        faces.append(("Back", place_back, 180.0))
    for suffix, fn, rot_y in faces:
        attrs(glass.transformed(fn).to_object("screenGlass" + suffix, parent), castsShadows=False, receiveShadows=True,
              clipDistance=float(v["clip"]))
        screen = node("screen" + suffix, parent, tuple(fn(Vector((0.0, 0.0, glass_z)))), rot_x=v["tilt"], rot_y=rot_y)
        # 1 x 1 m rectangle, top-left corner at the node, spanning +x and -y, facing +z; hidden: the script
        # copies it for every bar and sets each copy's place, size and colour
        bar = Mesh()
        bar.quad([(0.0, -1.0, 0.0), (1.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 0.0)], "monitor_bar",
                 uv=((0.5, 0.5),) * 4)
        template = attrs(bar.to_object("barTemplate" + suffix, screen), castsShadows=False, receiveShadows=False,
                         clipDistance=float(v["clip"]))
        template["i3d_hidden"] = True
        # the same with real UVs: product icons (the script puts each product's HUD icon on a copy)
        icon = Mesh()
        icon.quad([(0.0, -1.0, 0.0), (1.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 0.0)], "monitor_bar",
                  uv=((0.001, 0.0), (1.0, 0.0), (1.0, 1.0), (0.001, 1.0)))
        template = attrs(icon.to_object("iconTemplate" + suffix, screen), castsShadows=False, receiveShadows=False,
                         clipDistance=float(v["clip"]))
        template["i3d_hidden"] = True

    (tc, ts) = v["trigger"]
    for tname in ("infoTrigger", "playerTrigger"):
        t = Mesh()
        hx, hy, hz = (s / 2 for s in ts)
        t.box((tc[0] - hx, tc[1] - hy, tc[2] - hz), (tc[0] + hx, tc[1] + hy, tc[2] + hz), "monitor_frame")
        attrs(t.to_object(tname, root), trigger=True, nonRenderable=True, static=True, castsShadows=False,
              receiveShadows=False, collisionFilterGroup=COL_PLAYER_TRIGGER[0],
              collisionFilterMask=COL_PLAYER_TRIGGER[1])
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=False)
    return root


def export(path):
    # the GIANTS exporter (10.x) is written for Blender 3.6; Blender 4.1+ has split normals always and
    # dropped Mesh.calc_normals_split, which the exporter still calls first
    if not hasattr(bpy.types.Mesh, "calc_normals_split"):
        bpy.types.Mesh.calc_normals_split = lambda self: None
    # 10.5 cannot follow blend-relative paths ("//../textures/..."): give it absolute ones, and keep Blender
    # from making them relative again when something saves the file
    bpy.context.preferences.filepaths.use_relative_paths = False
    for image in bpy.data.images:
        if image.filepath.startswith("//"):
            image.filepath = os.path.normpath(bpy.path.abspath(image.filepath))
    # only the FS25 exporter (10.0.x) writes .shapes the game reads (format 10). io_export_i3d 10.5 is the
    # Project Motor Racing exporter: its .shapes (format 12) fail TestRunner and do not load in FS25.
    version = next((m.bl_info.get("version") for m in addon_utils.modules() if m.__name__ == EXPORTER), None)
    if version is None or tuple(version[:2]) != (10, 0):
        sys.exit("%s is version %s, not the FS25 exporter 10.0.x (GDN: GIANTS I3D Exporter Tools for FS25)"
                 % (EXPORTER, version))
    addon_utils.enable(EXPORTER, default_set=False, persistent=False)
    exp = importlib.import_module(EXPORTER + ".i3d_export")
    dccb = importlib.import_module(EXPORTER + ".dcc.dccBlender")
    dccb.isNodeVisible = lambda name: not bpy.data.objects[name].get("i3d_hidden", False)
    # 10.5 turns the texture of a custom-shader material into a blend-relative path ("//../textures/...") and
    # then fails on it; hand it back absolute (the export writes it relative to the i3d anyway)
    try:
        shader_util = importlib.import_module(EXPORTER + ".util.i3d_shaderUtil")
    except ImportError:
        shader_util = None
    for fn_name in ("getMaterialShaderTextureParamFromLinkInputNames", "getMaterialShaderTextureParamFromNodeName"):
        fn = getattr(shader_util, fn_name, None)
        if fn is not None and not getattr(fn, "_absolute", False):
            def absolute(*args, _fn=fn):
                result = _fn(*args)
                if isinstance(result, str) and result.startswith("//"):
                    result = os.path.normpath(bpy.path.abspath(result))
                return result
            absolute._absolute = True
            setattr(shader_util, fn_name, absolute)
    log = importlib.import_module(EXPORTER + ".util.logUtil").ActionLog
    orig = log.addMessage.__func__
    problems = []

    def show(cls, message, messageType="INFO"):
        if messageType in ("ERROR", "WARNING"):
            print("I3D", messageType, message)
            problems.append(message)
        return orig(cls, message, messageType)
    log.addMessage = classmethod(show)

    st = bpy.context.scene.I3D_UIexportSettings
    # exporter 10.0 names its settings i3D_*, 10.5 I3D_*; set whichever this one has (an unknown name on the
    # settings would be silently ignored, and 10.5 would then write c:/tmp/untitled.i3d)
    settings = {"ExportUseSoftwareFileName": False, "ExportFileLocation": path, "GameLocationDisplay": GAME_DIR,
                "GameLocation": GAME_DIR, "ExportRelativePaths": True, "ExportGameRelativePath": False,
                "ExportVerbose": True, "BinaryFiles": True, "UpdateXMLOnExport": False}
    for key, value in settings.items():
        for name in ("i3D_" + key[0].lower() + key[1:], "I3D_" + key[0].lower() + key[1:]):
            if hasattr(st, name):
                setattr(st, name, value)
    if hasattr(st, "I3D_UIexportCopyFiles"):      # 10.5: the textures are in the mod already, nothing to copy
        st.I3D_UIexportCopyFiles = False
    if os.path.exists(path):
        os.remove(path)
    exp.I3DExportAll()
    if not (os.path.exists(path) and os.path.exists(path + ".shapes")):
        sys.exit("export failed, see the I3D lines above")
    return problems


def render_store(name, v, out_png):
    """512 x 512 transparent shop image with the sample screen."""
    for obj in bpy.data.objects:
        obj.hide_render = bool(obj.get("i3D_nonRenderable", False)) or bool(obj.get("i3d_hidden", False))
    preview = bpy.data.images.load(os.path.join(SRC, "textures", "monitor_preview_tex.png"))
    bpy.data.materials["monitor_screen"].node_tree.nodes["screenTexture"].image = preview

    backdrop = v.get("backdrop")
    if backdrop == "wall":
        # shop picture only: a plank wall behind the flat mount
        wallmat = bpy.data.materials.new("render_plankWall")
        wallmat.diffuse_color = (0.42, 0.30, 0.20, 1.0)
        h = v["width"] / 1.6
        plate_z = -v["depth"] / 2 - v["housing"] - v["arm"] - 0.015
        y0, y1 = v["center_y"] - h * 0.95, v["center_y"] + h * 0.95
        m = Mesh()
        planks = 12
        for i in range(planks):
            x0 = -2.2 + 4.4 * i / planks
            x1 = -2.2 + 4.4 * (i + 1) / planks - 0.012
            m.quad([(x0, y0, plate_z), (x1, y0, plate_z), (x1, y1, plate_z), (x0, y1, plate_z)], "render_plankWall")
        m.to_object("renderWall", None).data.materials[0] = wallmat
    elif backdrop == "beam":
        # shop picture only: the roof beam the rods hang from
        beammat = bpy.data.materials.new("render_beam")
        beammat.diffuse_color = (0.30, 0.32, 0.35, 1.0)
        h = v["width"] / 1.6
        top = v["center_y"] + h / 2 + v["bezel"] + v["rod"] + 0.015
        m = Mesh()
        m.box((-2.0, top, -0.12), (2.0, top + 0.25, 0.12), "render_beam")
        m.to_object("renderBeam", None).data.materials[0] = beammat
    if backdrop == "silo":
        # shop picture only (added after the export): a piece of corrugated silo wall behind the bracket,
        # so the Silo Mount reads as "hangs on a silo"
        wall = bpy.data.materials.new("render_siloWall")
        wall.diffuse_color = (0.62, 0.64, 0.67, 1.0)
        h = v["width"] / 1.6
        plate_z = -v["depth"] / 2 - v["housing"] - v["arm"] - 0.015
        radius, half = 6.0, 2.2
        cz = plate_z - radius
        y0, y1 = v["center_y"] - h * 0.95, v["center_y"] + h * 0.95
        m = Mesh()
        steps = 60
        for i in range(steps):
            a0 = -half / radius + (2 * half / radius) * i / steps
            a1 = -half / radius + (2 * half / radius) * (i + 1) / steps
            r0 = radius + (0.03 if i % 2 else 0.0)        # corrugation
            r1 = radius + (0.0 if i % 2 else 0.03)
            p0 = (math.sin(a0) * r0, math.cos(a0) * r0 + cz)
            p1 = (math.sin(a1) * r1, math.cos(a1) * r1 + cz)
            m.quad([(p0[0], y0, p0[1]), (p1[0], y0, p1[1]), (p1[0], y1, p1[1]), (p0[0], y1, p0[1])], "render_siloWall")
        m.to_object("renderSiloWall", None).data.materials[0] = wall

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_shadows = True
    shading.shadow_intensity = 0.3
    shading.show_cavity = True
    shading.show_specular_highlight = True
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    cam = bpy.data.objects.new("storeCam", bpy.data.cameras.new("storeCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    w = v["width"]
    hi = v["center_y"] + w / 3.2 + v["bezel"] + (v["rod"] + 0.3 if v["mount"] == "hang" else 0.0)
    lo = v["center_y"] - w / 3.2 - v["bezel"] * (5 if v["mount"] == "hang" else 2) if v["mount"] in RAISED else 0.0
    total_h = hi - lo
    target = Vector(to_blender((0.0, lo + total_h * 0.5, 0.0)))
    dist = max(total_h, w) * 1.55
    yaw, pitch = math.radians(-28), math.radians(12)
    pos = Vector(to_blender((dist * math.sin(-yaw), lo + total_h * 0.5 + dist * math.sin(pitch), dist * math.cos(yaw))))
    cam.location = pos
    cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(total_h, w) * 1.12
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)


def fix_i3d(path):
    """Puts back what exporter 10.5 loses or writes differently: a material's glow (it reads the Principled
    BSDF input 'Emission' of Blender 3; Blender 4+ calls it 'Emission Color') and hex collision filters."""
    import xml.etree.ElementTree as ET
    text = open(path, encoding="iso-8859-1").read()
    for name, (_, emission, _) in MATERIALS.items():
        if emission is None:
            continue
        value = " ".join("%g" % (round(c * 255) / 255) for c in emission) + " 1"
        tag = '<Material name="%s" ' % name
        start = text.find(tag)
        if start < 0 or 'emissiveColor="' in text[start:text.find(">", start)]:
            continue
        end = text.find(">", start)
        attrs = text[start:end]
        cut = attrs.find(' specularColor="')
        attrs = (attrs[:cut] + ' emissiveColor="%s"' % value + attrs[cut:]) if cut > 0 else attrs + ' emissiveColor="%s"' % value
        text = text[:start] + attrs + text[end:]
    # the collision filters as set, in hex as the GIANTS Editor writes them (10.5 writes them in decimal, and
    # its binary converter turns a mask above 0x7fffffff into 0)
    import re

    def filters(m):
        tag = m.group(0)
        name = re.search(r' name="([^"]*)"', tag).group(1)
        for attr, value in FILTERS.get(name, {}).items():
            tag = re.sub(r' %s="[^"]*"' % attr, ' %s="%s"' % (attr, value), tag)
        return tag
    text = re.sub(r'<Shape [^>]*collisionFilter[^>]*>', filters, text)
    ET.fromstring(text.encode("iso-8859-1"))      # still well-formed
    with open(path, "w", encoding="iso-8859-1", newline="") as f:
        f.write(text)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(VARIANTS)
    for name in names:
        v = VARIANTS[name]
        build(name, v)
        out = os.path.join(ROOT, "i3d", "monitor_%s.i3d" % name)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        problems = export(out)
        fix_i3d(out)
        print("EXPORTED", out, os.path.getsize(out), os.path.getsize(out + ".shapes"), "problems:", len(problems))
        os.makedirs(os.path.join(SRC, "store"), exist_ok=True)
        render_store(name, v, os.path.join(SRC, "store", "store_%s.png" % name))


if __name__ == "__main__":
    main()
