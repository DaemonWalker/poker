# build_backgrounds.py — 无头渲染两张 1280x720 背景图（不透明 PNG）
#   table_felt.png —— 正俯视牌桌桌布（主画面背景）
#   menu_bg.png    —— 斜俯视桌面场景（主菜单/设置/结算/战绩背景）
# 用法: "E:/ProgramData/Blender 5.2/blender.exe" --background --python tools/blender/build_backgrounds.py
import bpy
import math
import os
import numpy as np

OUT_DIR = "E:/workspace/godot/poker/assets/bg"
RES_X, RES_Y = 1280, 720
MM = 0.001

# ---- 桌子尺寸（米）。宽:深 与 16:9 一致，俯视时桌沿在四边等宽 ----
TABLE_W = 2.60
TABLE_D = TABLE_W * RES_Y / RES_X      # 1.4625
RAIL_W = 0.10                          # 约 49px @1280 宽
FELT_W = TABLE_W - 2.0 * RAIL_W
FELT_D = TABLE_D - 2.0 * RAIL_W
OUTER_R = 0.42                         # 桌沿外圆角半径
INNER_R = 0.34                         # 桌沿内圆角半径
RAIL_H = 0.022                         # 桌沿顶面高出毛毡
FELT_OVER = 0.012                      # 毛毡伸入桌沿下方的搭接量

# ---- 筹码尺寸（同 build_chips.py）----
CHIP_R = 19.5 * MM
CHIP_H = 3.3 * MM


def hex_to_linear_rgba(h):
    h = h.lstrip("#")
    vals = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        c = c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        vals.append(c)
    return (*vals, 1.0)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------- 几何 ----------

def rounded_rect_points(w, d, r, n=12):
    """逆时针（从 +Z 看）圆角矩形轮廓点。四个角各 n+1 点。"""
    pts = []
    corners = [
        (w / 2 - r, d / 2 - r, 0),
        (-w / 2 + r, d / 2 - r, 90),
        (-w / 2 + r, -d / 2 + r, 180),
        (w / 2 - r, -d / 2 + r, 270),
    ]
    for cx, cy, a0 in corners:
        for i in range(n + 1):
            a = math.radians(a0 + i * 90.0 / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def make_prism(name, pts, z_top, z_bottom, mat):
    """圆角矩形薄板（顶/底/侧壁）。"""
    n = len(pts)
    verts = [(x, y, z_top) for x, y in pts] + [(x, y, z_bottom) for x, y in pts]
    faces = [tuple(range(n))]                       # 顶面（CCW → +Z）
    faces.append(tuple(range(2 * n - 1, n - 1, -1)))  # 底面
    for i in range(n):
        j = (i + 1) % n
        faces.append((n + i, n + j, j, i))          # 外壁朝外
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def make_ring(name, outer_pts, inner_pts, z_top, z_bottom, mat):
    """两道等长轮廓之间的圆环（顶环面 + 外壁 + 内壁）。"""
    n = len(outer_pts)
    ot = [(x, y, z_top) for x, y in outer_pts]
    it = [(x, y, z_top) for x, y in inner_pts]
    ob = [(x, y, z_bottom) for x, y in outer_pts]
    ib = [(x, y, z_bottom) for x, y in inner_pts]
    verts = ot + it + ob + ib
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))                      # 顶环面（+Z）
        faces.append((2 * n + j, 2 * n + i, i, j))              # 外壁朝外
        faces.append((n + i, n + j, 3 * n + j, 3 * n + i))      # 内壁朝内
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


# ---------- 材质 ----------

def felt_material():
    m = bpy.data.materials.new("Felt")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.95

    # 大面积深浅斑驳
    noise_big = nt.nodes.new("ShaderNodeTexNoise")
    noise_big.inputs["Scale"].default_value = 5.0
    noise_big.inputs["Detail"].default_value = 4.0
    noise_big.inputs["Roughness"].default_value = 0.8
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = hex_to_linear_rgba("#164e30")
    ramp.color_ramp.elements[1].color = hex_to_linear_rgba("#1d6340")
    nt.links.new(noise_big.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    # 注：Eevee 会按屏幕像素足迹预过滤高频程序化纹理，亚像素级绒毛噪波在
    # 渲染里不可见，故布料细颗粒改在后处理（post_process 的 grain 参数）里加。
    return m


def wood_material():
    m = bpy.data.materials.new("Walnut")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Specular IOR Level"].default_value = 0.3

    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.noise_dimensions = "3D"
    tex.inputs["Scale"].default_value = 3.5
    tex.inputs["Detail"].default_value = 5.0
    tex.inputs["Roughness"].default_value = 0.7
    tex.inputs["Distortion"].default_value = 0.3
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 7.0, 1.0)  # 拉长木纹
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = hex_to_linear_rgba("#150b04")
    ramp.color_ramp.elements[0].position = 0.2
    mid = ramp.color_ramp.elements.new(0.55)
    mid.color = hex_to_linear_rgba("#2e1c0e")
    ramp.color_ramp.elements[1].color = hex_to_linear_rgba("#452a15")
    ramp.color_ramp.elements[1].position = 0.85
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])

    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.18
    bump.inputs["Distance"].default_value = 1.2 * MM
    nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def plain_material(name, hex_color, roughness=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


# ---------- 桌子 ----------

def build_table(felt_mat, wood_mat, inlay_mat, base_mat):
    outer = rounded_rect_points(TABLE_W, TABLE_D, OUTER_R, n=16)
    inner = rounded_rect_points(FELT_W, FELT_D, INNER_R, n=16)
    # 满铺木底板（矩形、伸出画面，俯视时四角也充满木纹）
    full = [(-1.7, -1.1), (-1.7, 1.1), (1.7, 1.1), (1.7, -1.1)]
    make_prism("WoodBase", full, -0.004, -0.035, wood_mat)
    # 底座暗板（毛毡与桌沿间缝隙透出深色 = 内嵌分割线的一部分）
    make_prism("Base", outer, -0.004, -0.02, base_mat)
    # 毛毡（比桌沿内圈略大，伸到桌沿下方）
    felt_pts = rounded_rect_points(FELT_W + 2 * FELT_OVER, FELT_D + 2 * FELT_OVER, INNER_R + FELT_OVER, n=16)
    make_prism("Felt", felt_pts, 0.0, -0.012, felt_mat)
    # 内嵌分割线（细黑环，压在毛毡与桌沿交界内侧）
    inlay_out = rounded_rect_points(FELT_W + 0.016, FELT_D + 0.016, INNER_R + 0.008, n=16)
    inlay_in = rounded_rect_points(FELT_W + 0.002, FELT_D + 0.002, INNER_R + 0.001, n=16)
    make_ring("Inlay", inlay_out, inlay_in, 0.0008, 0.0, inlay_mat)
    # 木桌沿
    make_ring("Rail", outer, inner, RAIL_H, -0.035, wood_mat)


# ---------- 灯光 / 相机 ----------

def add_area_light(name, loc, energy, size, color, target):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    direction = mathutils_vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def mathutils_vector(t):
    from mathutils import Vector
    return Vector(t)


def setup_render(scene):
    scene.render.engine = "BLENDER_EEVEE"
    for attr in ("taa_samples", "taa_render_samples"):
        if hasattr(scene.eevee, attr):
            setattr(scene.eevee, attr, 64)
    scene.render.resolution_x = RES_X
    scene.render.resolution_y = RES_Y
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def set_world(scene, hex_color, strength):
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = hex_to_linear_rgba(hex_color)
    bg.inputs["Strength"].default_value = strength
    scene.world = world


# ---------- 后处理（径向提亮 / 暗角，线性空间乘算）----------

def post_process(path, brighten=0.0, vig_start=0.8, vig_end=1.45, vig_strength=0.0,
                 center_dim=0.0, gain=1.0, grain=0.0):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.asarray(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    yy, xx = np.mgrid[0:h, 0:w]
    nx = (xx / float(w) - 0.5) * 2.0
    ny = (yy / float(h) - 0.5) * 2.0
    r = np.sqrt(nx * nx + ny * ny)
    f = np.full_like(r, gain)
    if brighten:
        f += brighten * np.clip(1.0 - r, 0.0, 1.0) ** 1.5
    if vig_strength:
        t = np.clip((r - vig_start) / max(vig_end - vig_start, 1e-6), 0.0, 1.0)
        f *= 1.0 - vig_strength * t * t
    if center_dim:
        t = np.clip(1.0 - r / 0.55, 0.0, 1.0)
        f *= 1.0 - center_dim * t * t
    px[:, :, 0] *= f
    px[:, :, 1] *= f
    px[:, :, 2] *= f
    if grain:
        # 布料细颗粒：只加在绿色主导（毛毡）区域，三通道同值亮度噪点
        rr, gg, bb = px[:, :, 0], px[:, :, 1], px[:, :, 2]
        mask = (gg > rr * 1.15) & (gg > bb * 1.1)
        rng = np.random.default_rng(7)
        noise = rng.normal(0.0, grain, (h, w)).astype(np.float32) * mask
        px[:, :, 0] += noise
        px[:, :, 1] += noise
        px[:, :, 2] += noise
    np.clip(px, 0.0, None, out=px)
    img.pixels = px.ravel()
    img.save()
    bpy.data.images.remove(img)
    print("POST", path)


# ---------- 场景一：俯视桌布 ----------

def render_table_felt():
    clear_scene()
    scene = bpy.context.scene
    setup_render(scene)
    set_world(scene, "#b9c0b9", 0.2)

    build_table(felt_material(), wood_material(),
                plain_material("Inlay", "#101010", 0.6),
                plain_material("Base", "#0b1f14", 0.9))

    # 相机：正俯视，桌子恰好充满画面
    cam_data = bpy.data.cameras.new("CamTop")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = TABLE_W
    cam_data.clip_start = 0.01
    cam = bpy.data.objects.new("CamTop", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, 0.0, 3.0)
    scene.camera = cam

    # 均匀柔和打光：中央大面光 + 四角补光，自然轻微径向衰减
    add_area_light("Key", (0, 0, 2.4), 150.0, 2.0, (1.0, 0.97, 0.92), (0, 0, 0))
    for i, (lx, ly) in enumerate(((1.7, 1.0), (-1.7, 1.0), (1.7, -1.0), (-1.7, -1.0))):
        add_area_light("Fill%d" % i, (lx, ly, 1.8), 40.0, 1.4, (0.98, 0.95, 0.9), (0, 0, 0))

    path = os.path.join(OUT_DIR, "table_felt.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)
    # 中心极轻提亮 + 四角轻暗角，整体略压暗便于 UI 叠加，毛毡加细颗粒
    post_process(path, brighten=0.05, vig_start=0.85, vig_end=1.45, vig_strength=0.16,
                 gain=0.92, grain=0.010)


# ---------- 场景二：斜俯视桌面 ----------

def build_chip_stack(x, y, count, body_mat, spot_mat, rng_seed):
    import random
    rng = random.Random(rng_seed)
    for k in range(count):
        z = k * (CHIP_H + 0.15 * MM)
        rot = rng.uniform(0, math.pi / 4)
        top = (k == count - 1)
        # 主体
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=CHIP_R, depth=CHIP_H,
                                            location=(x, y, z + CHIP_H / 2.0), rotation=(0, 0, rot))
        body = bpy.context.active_object
        body.name = "Chip"
        body.data.materials.append(body_mat)
        # 边缘嵌块
        for i in range(8):
            ang = rot + i * 2.0 * math.pi / 8
            bx = x + (CHIP_R - 1.1 * MM) * math.cos(ang)
            by = y + (CHIP_R - 1.1 * MM) * math.sin(ang)
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, by, z + CHIP_H / 2.0))
            box = bpy.context.active_object
            box.name = "Spot"
            box.scale = (2.4 * MM, 4.0 * MM, CHIP_H + 1.2 * MM)
            box.rotation_euler[2] = ang
            bpy.ops.object.transform_apply(scale=True)
            box.data.materials.append(spot_mat)
        # 顶面圆环仅最上面一片
        if top:
            bpy.ops.mesh.primitive_torus_add(major_radius=15.0 * MM, minor_radius=0.55 * MM,
                                             major_segments=48, minor_segments=8,
                                             location=(x, y, z + CHIP_H))
            ring = bpy.context.active_object
            ring.scale = (1.0, 1.0, 0.6)
            bpy.ops.object.transform_apply(scale=True)
            ring.data.materials.append(spot_mat)


def build_card(x, y, rot_deg, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.0006))
    card = bpy.context.active_object
    card.name = "Card"
    card.scale = (0.063, 0.088, 0.0012)
    card.rotation_euler[2] = math.radians(rot_deg)
    bpy.ops.object.transform_apply(scale=True)
    bevel = card.modifiers.new("R", "BEVEL")
    bevel.width = 0.004
    bevel.segments = 3
    card.data.materials.append(mat)
    return card


def render_menu_bg():
    clear_scene()
    scene = bpy.context.scene
    setup_render(scene)
    set_world(scene, "#05070a", 0.02)

    build_table(felt_material(), wood_material(),
                plain_material("Inlay", "#101010", 0.6),
                plain_material("Base", "#0b1f14", 0.9))

    # 地面（桌外暗环境）
    floor_mat = plain_material("Floor", "#0c0c0e", 1.0)
    bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0, 0, -0.036))
    floor = bpy.context.active_object
    floor.data.materials.append(floor_mat)

    # 筹码摞（靠近画面边缘，中央留空压暗给 UI）
    bodies = {
        "red": plain_material("C_red", "#a93226", 0.5),
        "blue": plain_material("C_blue", "#2e5ea8", 0.5),
        "black": plain_material("C_black", "#1c1c1c", 0.5),
        "white": plain_material("C_white", "#dcdcdc", 0.5),
    }
    spot = plain_material("C_spot", "#e8e8e8", 0.5)
    stacks = [
        (-0.72, -0.30, 9, "red"),
        (-0.54, -0.42, 5, "blue"),
        (0.66, -0.34, 11, "black"),
        (0.48, -0.45, 6, "white"),
        (0.78, 0.30, 7, "blue"),
        (-0.80, 0.25, 4, "white"),
        (0.12, 0.42, 8, "red"),
    ]
    for i, (sx, sy, n, cname) in enumerate(stacks):
        build_chip_stack(sx, sy, n, bodies[cname], spot, rng_seed=100 + i)

    # 扑克牌：素面白牌，扇形微叠
    card_mat = plain_material("Card", "#ece9e2", 0.55)
    build_card(-0.22, -0.05, -12, card_mat)
    build_card(-0.15, -0.02, 4, card_mat)
    build_card(-0.08, -0.06, 18, card_mat)

    # 相机：约 30° 仰角斜视，拉近让筹码/牌可辨认
    cam_data = bpy.data.cameras.new("CamMenu")
    cam_data.lens = 33.0
    cam_data.sensor_width = 36.0
    cam_data.clip_start = 0.01
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = 4.5
    cam = bpy.data.objects.new("CamMenu", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, -1.35, 0.85)
    target = mathutils_vector((0.0, 0.12, 0.0))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()

    focus = bpy.data.objects.new("Focus", None)
    bpy.context.collection.objects.link(focus)
    focus.location = (0.0, 0.12, 0.0)
    cam_data.dof.focus_object = focus
    scene.camera = cam

    # 低角度暖色主光 + 两侧轮廓光，世界极暗
    add_area_light("Key", (1.9, -0.6, 0.85), 150.0, 1.0, (1.0, 0.66, 0.38), (0.3, 0.0, 0.0))
    add_area_light("SideL", (-1.9, 0.3, 0.7), 85.0, 0.8, (1.0, 0.82, 0.60), (-0.7, 0.1, 0.0))
    add_area_light("Rim", (-0.3, 1.7, 1.2), 38.0, 1.1, (0.72, 0.78, 1.0), (0.0, 0.3, 0.0))

    path = os.path.join(OUT_DIR, "menu_bg.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)
    # 明显暗角 + 中心再压暗一点（UI 文字叠中央），毛毡轻颗粒
    post_process(path, brighten=0.0, vig_start=0.45, vig_end=1.35, vig_strength=0.55,
                 center_dim=0.14, grain=0.007)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    render_table_felt()
    render_menu_bg()


main()
