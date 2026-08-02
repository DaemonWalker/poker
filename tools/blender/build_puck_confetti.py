# build_puck_confetti.py — 无头渲染庄家按钮 + 彩带贴图（5 张 RGBA 透明 PNG）
# 用法: blender.exe --background --python tools/blender/build_puck_confetti.py
# 输出: assets/ui/dealer_puck.png (128x128), assets/ui/confetti_01..04.png (64x64)
import bpy
import math
import os

OUT_DIR = "E:/workspace/godot/poker/assets/ui"
MM = 0.001  # 场景按米建模

# ---- 庄家按钮尺寸（mm）----
PUCK_R = 20.0 * MM   # 直径 40mm
PUCK_H = 5.5 * MM    # 厚度，直径/厚度 ≈ 7.3
D_HEIGHT = 0.48 * 2 * PUCK_R  # 字母 D 高度，约占顶面直径 48%
RING_R = 16.5 * MM   # 顶面凹刻圆环半径

# ---- 彩带尺寸（mm）----
CONF_RES = 64
CONF_ORTHO = 30.0 * MM        # 视野高度
RIB_L = 0.70 * CONF_ORTHO     # 彩带纵向跨度 ≈ 画面 70%
RIB_W = 4.0 * MM              # 彩带宽 ≈ 8.5px
RIB_N = 96                    # 中心线分段数

FONT_PATHS = ["C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/Dengb.ttf"]


def hex_to_linear_rgba(h):
    h = h.lstrip("#")
    vals = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        c = c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        vals.append(c)
    return (*vals, 1.0)


def make_material(name, hex_color, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return m


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add_area_light(name, loc, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    direction = -obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def add_top_camera(name, z, ortho_scale):
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    data.clip_start = 0.0001  # 小尺度场景，默认 0.1m 会裁掉物体
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = (0, 0, z)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    return obj


def setup_render(scene, res):
    scene.render.engine = "BLENDER_EEVEE"
    for attr in ("taa_samples", "taa_render_samples"):
        if hasattr(scene.eevee, attr):
            setattr(scene.eevee, attr, 64)
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def add_world(scene, strength=0.05):
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.58, 0.62, 1.0)
    bg.inputs["Strength"].default_value = strength
    scene.world = world


# ================= 庄家按钮 =================

def build_puck(white_mat, dark_mat):
    # 白色扁圆柱 + 顶底边缘倒角
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=PUCK_R, depth=PUCK_H)
    body = bpy.context.active_object
    body.name = "PuckBody"
    body.data.materials.append(white_mat)
    bevel = body.modifiers.new("EdgeBevel", "BEVEL")
    bevel.width = 0.8 * MM
    bevel.segments = 3
    bevel.limit_method = "ANGLE"

    # 顶面外圈凹刻细圆环（深色 torus 半嵌入顶面）
    bpy.ops.mesh.primitive_torus_add(major_radius=RING_R, minor_radius=0.5 * MM,
                                     major_segments=72, minor_segments=12,
                                     location=(0, 0, PUCK_H / 2.0 - 0.08 * MM))
    ring = bpy.context.active_object
    ring.name = "TopRing"
    ring.data.materials.append(dark_mat)

    # 顶面字母 "D"：文本转网格，按包围盒居中并缩放到目标高度
    font_path = next((p for p in FONT_PATHS if os.path.exists(p)), None)
    bpy.ops.object.text_add(location=(0, 0, 0))
    txt = bpy.context.active_object
    txt.name = "LetterD"
    txt.data.body = "D"
    if font_path:
        txt.data.font = bpy.data.fonts.load(font_path)
    txt.data.extrude = 0.8 * MM
    txt.data.bevel_depth = 0.15 * MM  # 字面边缘微圆角
    bpy.ops.object.convert(target="MESH")
    d = bpy.context.active_object
    # 按包围盒把 D 平移到原点（x/y 向）
    bb = [d.matrix_world @ v.co for v in d.data.vertices]  # corner-free: 用顶点包围盒
    xs = [v.x for v in bb]
    ys = [v.y for v in bb]
    cx = (min(xs) + max(xs)) / 2.0
    cy = (min(ys) + max(ys)) / 2.0
    h = max(ys) - min(ys)
    s = D_HEIGHT / h
    for v in d.data.vertices:
        v.co.x = (v.co.x - cx) * s
        v.co.y = (v.co.y - cy) * s
        # z 向不缩放：文本默认 1m 高，extrude 会一起被缩没
    d.location = (0, 0, PUCK_H / 2.0 - 0.15 * MM)  # 底部微嵌入顶面
    d.data.materials.append(dark_mat)


def render_puck(scene):
    white = make_material("PuckWhite", "#f5f5f5", 0.5)
    dark = make_material("PuckDark", "#1a1a1a", 0.6)
    build_puck(white, dark)
    cam = add_top_camera("CamPuck", 0.08, 2 * PUCK_R / 0.92)
    scene.camera = cam
    setup_render(scene, 128)
    add_area_light("Key", (0.035, -0.025, 0.055), 0.07, 0.03, (1.0, 0.97, 0.92))
    add_area_light("Fill", (-0.04, 0.03, 0.03), 0.025, 0.035, (0.85, 0.9, 1.0))
    path = os.path.join(OUT_DIR, "dealer_puck.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)
    # 清场（网格 + 相机 + 灯）
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


# ================= 彩带 =================

def ribbon_mesh(name, shape_fn, mat):
    """按中心线形状函数建一条薄片彩带（视图平面 XY，z 为深度）。"""
    pts = [shape_fn(i / RIB_N) for i in range(RIB_N + 1)]  # (x, y, z, twist)
    verts = []
    from mathutils import Vector
    for i, (x, y, z, twist) in enumerate(pts):
        p = Vector((x, y, z))
        if i == 0:
            t = Vector(pts[1][:3]) - p
        elif i == RIB_N:
            t = p - Vector(pts[i - 1][:3])
        else:
            t = Vector(pts[i + 1][:3]) - Vector(pts[i - 1][:3])
        t.normalize()
        # 面内垂直方向，再绕切线扭转 twist 角
        w = Vector((-t.y, t.x, 0.0))
        if w.length < 1e-6:
            w = Vector((1.0, 0.0, 0.0))
        w.normalize()
        from mathutils import Matrix
        w = Matrix.Rotation(twist, 4, t) @ w
        verts.append(tuple(p + w * (RIB_W / 2.0)))
        verts.append(tuple(p - w * (RIB_W / 2.0)))
    faces = []
    for i in range(RIB_N):
        a = 2 * i
        faces.append((a, a + 1, a + 3, a + 2))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    sol = obj.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness = 0.15 * MM
    return obj


def shape_s(t):
    """S 形缓波 + 深度跟随"""
    A = 4.5 * MM
    return (A * math.sin(2 * math.pi * t),
            (t - 0.5) * RIB_L,
            2.2 * MM * math.sin(2 * math.pi * t + math.pi / 3),
            0.3 * math.pi * math.sin(2 * math.pi * t))


def shape_accordion(t):
    """手风琴式硬折（三角波），折痕处深度交替"""
    A = 5.0 * MM
    tri = (2.0 / math.pi) * math.asin(math.sin(2 * math.pi * 1.5 * t))
    return (A * tri,
            (t - 0.5) * RIB_L,
            2.0 * MM * math.cos(2 * math.pi * 1.5 * t),
            0.0)


def shape_hook(t):
    """上直下卷 J 钩：底部振幅渐大的卷尾"""
    A = 5.5 * MM
    return (A * t * t * math.sin(2 * math.pi * t),
            (t - 0.5) * RIB_L,
            2.2 * MM * t * math.cos(2 * math.pi * t),
            0.9 * math.pi * t)


def shape_twist(t):
    """密波 + 扭转"""
    A = 3.8 * MM
    return (A * math.sin(3 * math.pi * t),
            (t - 0.5) * RIB_L,
            1.5 * MM * math.sin(3 * math.pi * t - math.pi / 2),
            2.0 * math.pi * t)


def render_confetti(scene):
    paper = make_material("Paper", "#f0f0f0", 0.85)
    cam = add_top_camera("CamConf", 0.1, CONF_ORTHO)
    scene.camera = cam
    setup_render(scene, CONF_RES)
    # 近白贴图：低环境光保整体亮度，侧向主光让褶皱翻面的角度差转成明暗差
    world = bpy.data.worlds["W"]
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    add_area_light("Front", (0.0, 0.0, 0.06), 0.015, 0.04, (1.0, 1.0, 1.0))
    add_area_light("Key", (0.045, 0.02, 0.025), 0.045, 0.02, (1.0, 0.97, 0.92))
    add_area_light("Fill", (-0.035, -0.02, 0.04), 0.012, 0.03, (0.85, 0.9, 1.0))

    shapes = [("confetti_01", shape_s), ("confetti_02", shape_accordion),
              ("confetti_03", shape_hook), ("confetti_04", shape_twist)]
    for fname, fn in shapes:
        obj = ribbon_mesh(fname, fn, paper)
        path = os.path.join(OUT_DIR, fname + ".png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("RENDERED", path)
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    clear_scene()
    scene = bpy.context.scene
    add_world(scene)
    render_puck(scene)
    render_confetti(scene)


main()
