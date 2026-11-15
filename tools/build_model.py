"""Builds the three Storage Monitor models in Blender, exports each with the GIANTS I3D exporter and renders
their shop images.

    blender --background --factory-startup --python tools/build_model.py -- [variant ...]

Variants (all screens are 16:10):
    kiosk      1.20 m screen on a pedestal, tilted back 10 degrees
    wall       2.40 m screen on two posts, to stand against a silo or wall
    billboard  4.00 m screen on two tall posts, readable from a tractor

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

VARIANTS = {
    "kiosk": dict(width=1.20, center_y=1.40, tilt=-10.0, bezel=0.045, depth=0.06, housing=0.10,
                  mount="pedestal", trigger=((0.0, 1.0, 1.0), (1.8, 2.0, 1.8)), clip=200),
    "wall": dict(width=2.40, center_y=2.05, tilt=0.0, bezel=0.06, depth=0.07, housing=0.08,
                 mount="posts", post=0.08, post_x=0.75, trigger=((0.0, 1.0, 1.5), (3.0, 2.0, 2.6)), clip=300),
    "billboard": dict(width=4.00, center_y=3.80, tilt=0.0, bezel=0.09, depth=0.10, housing=0.12,
                      mount="posts", post=0.14, post_x=1.30, trigger=((0.0, 1.0, 2.5), (5.0, 2.0, 4.6)), clip=500),
}

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
    mat.diffuse_color = (0.05, 0.08, 0.13, 1.0)


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


def add_object(name, data, parent, location=(0.0, 0.0, 0.0), rot_x=0.0):
    obj = bpy.data.objects.new(name, data)
    assert obj.name == name, "duplicate node name " + name
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = to_blender(location)
    obj.rotation_euler = (math.radians(rot_x), 0.0, 0.0)    # i3d x rotation == Blender x rotation
    return obj


def node(name, parent=None, location=(0.0, 0.0, 0.0), rot_x=0.0):
    obj = add_object(name, None, parent, location, rot_x)
    obj.empty_display_size = 0.2
    return obj


def attrs(obj, **kw):
    for k, v in kw.items():
        obj["i3D_" + k] = v
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
    if v["mount"] == "posts":
        p = v["post"]
        top = v["center_y"] + h / 2 - b
        for sx in (-1, 1):
            x = sx * v["post_x"]
            m.box((x - p / 2, 0.0, back_z - p), (x + p / 2, top, back_z), "monitor_metal", skip=("-y",))
            m.box((x - p * 2, 0.0, back_z - p * 3), (x + p * 2, 0.02, back_z + p * 1.2), "monitor_base", skip=("-y",))
        # cross bar under the screen
        m.box((-v["post_x"], bottom_y - p * 1.4, back_z - p * 0.8), (v["post_x"], bottom_y - p * 0.6, back_z - p * 0.2), "monitor_metal")
    else:   # pedestal
        m.box((-0.35, 0.0, -0.35), (0.35, 0.04, 0.25), "monitor_base", skip=("-y",))
        m.box((-0.08, 0.04, -0.18), (0.08, v["center_y"] - 0.15, -0.06), "monitor_metal", skip=("-y",))
        m.box((-0.15, v["center_y"] - 0.25, -0.16), (0.15, v["center_y"] - 0.12, back_z + 0.02), "monitor_frame")
    return m


def build(name, v):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    blend = os.path.join(ROOT, "build", "monitor_%s.blend" % name)
    os.makedirs(os.path.dirname(blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend)

    img = bpy.data.images.new("monitor_screen_diffuse", 4, 4)
    img.source = "FILE"
    img.filepath = os.path.join(TEXTURES, "monitor_screen_diffuse.dds")
    make_materials(img)

    tilt = math.radians(v["tilt"])
    cy = v["center_y"]

    def place(p):      # head local -> model: tilt about x, then lift to the screen centre
        y = p.y * math.cos(tilt) - p.z * math.sin(tilt)
        z = p.y * math.sin(tilt) + p.z * math.cos(tilt)
        return Vector((p.x, y + cy, z))

    root = attrs(node("storageMonitor_" + name), clipDistance=float(v["clip"]))
    body, glass, glass_z = head(v)
    full = body.transformed(place)
    full.extend(mount(v))
    attrs(full.to_object("body", root), static=True, collisionFilterGroup=COL_BUILDING[0],
          collisionFilterMask=COL_BUILDING[1], clipDistance=float(v["clip"]))
    attrs(glass.transformed(place).to_object("screenGlass", root), castsShadows=False, receiveShadows=True,
          clipDistance=float(v["clip"]))
    node("screen", root, tuple(place(Vector((0.0, 0.0, glass_z)))), rot_x=v["tilt"])

    (tc, ts) = v["trigger"]
    for tname in ("infoTrigger", "playerTrigger"):
        t = Mesh()
        hx, hy, hz = (s / 2 for s in ts)
        t.box((tc[0] - hx, tc[1] - hy, tc[2] - hz), (tc[0] + hx, tc[1] + hy, tc[2] + hz), "monitor_frame")
        attrs(t.to_object(tname, root), trigger=True, nonRenderable=True, static=True, castsShadows=False,
              receiveShadows=False, collisionFilterGroup=COL_PLAYER_TRIGGER[0],
              collisionFilterMask=COL_PLAYER_TRIGGER[1])
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    return root


def export(path):
    addon_utils.enable(EXPORTER, default_set=False, persistent=False)
    exp = importlib.import_module(EXPORTER + ".i3d_export")
    dccb = importlib.import_module(EXPORTER + ".dcc.dccBlender")
    dccb.isNodeVisible = lambda name: not bpy.data.objects[name].get("i3d_hidden", False)
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
    st.i3D_exportUseSoftwareFileName = False
    st.i3D_exportFileLocation = path
    st.i3D_gameLocationDisplay = GAME_DIR
    st.i3D_exportRelativePaths = True
    st.i3D_exportGameRelativePath = False
    st.i3D_exportVerbose = True
    if os.path.exists(path):
        os.remove(path)
    exp.I3DExportAll()
    if not (os.path.exists(path) and os.path.exists(path + ".shapes")):
        sys.exit("export failed, see the I3D lines above")
    return problems


def render_store(name, v, out_png):
    """512 x 512 transparent shop image with the sample screen."""
    for obj in bpy.data.objects:
        obj.hide_render = bool(obj.get("i3D_nonRenderable", False))
    preview = bpy.data.images.load(os.path.join(SRC, "textures", "monitor_preview_tex.png"))
    bpy.data.materials["monitor_screen"].node_tree.nodes["screenTexture"].image = preview

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
    total_h = v["center_y"] + w / 3.2 + v["bezel"]
    target = Vector(to_blender((0.0, total_h * 0.5, 0.0)))
    dist = max(total_h, w) * 1.55
    yaw, pitch = math.radians(-28), math.radians(12)
    pos = Vector(to_blender((dist * math.sin(-yaw), total_h * 0.5 + dist * math.sin(pitch), dist * math.cos(yaw))))
    cam.location = pos
    cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(total_h, w) * 1.12
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(VARIANTS)
    for name in names:
        v = VARIANTS[name]
        build(name, v)
        out = os.path.join(ROOT, "i3d", "monitor_%s.i3d" % name)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        problems = export(out)
        print("EXPORTED", out, os.path.getsize(out), os.path.getsize(out + ".shapes"), "problems:", len(problems))
        os.makedirs(os.path.join(SRC, "store"), exist_ok=True)
        render_store(name, v, os.path.join(SRC, "store", "store_%s.png" % name))


if __name__ == "__main__":
    main()
