# build_cardback_logo.py — 无头渲染牌背与主菜单 Logo（一次运行出两张）
# 用法: blender --background --python tools/blender/build_cardback_logo.py
import bpy
import math
import os

CARD_OUT = "E:/workspace/godot/poker/assets/cards/card_back.png"
LOGO_OUT = "E:/workspace/godot/poker/assets/ui/logo.png"
MM = 0.001


def hex_to_linear(h):
    h = h.lstrip("#")
    vals = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        c = c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        vals.append(c)
    return (*vals, 1.0)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_common(scene):
    scene.render.engine = "BLENDER_EEVEE"
    for attr in ("taa_samples", "taa_render_samples"):
        if hasattr(scene.eevee, attr):
            setattr(scene.eevee, attr, 64)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True


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


def rounded_plate(name, w, h, thickness, radius, z):
    """圆角薄板：手工建网格（曲线物体的 Generated 坐标对 Image 纹理不可靠）。"""
    hw, hh = w / 2.0, h / 2.0
    SEG = 8
    outline = []
    centers = [(hw - radius, hh - radius, 0.0),
               (-(hw - radius), hh - radius, 90.0),
               (-(hw - radius), -(hh - radius), 180.0),
               (hw - radius, -(hh - radius), 270.0)]
    for cx, cy, start_deg in centers:
        for i in range(SEG):
            a = math.radians(start_deg + 90.0 * i / SEG)
            outline.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    n = len(outline)
    z0, z1 = z, z + thickness
    verts = [(x, y, z1) for x, y in outline] + [(x, y, z0) for x, y in outline]
    faces = [tuple(range(n)),                      # 顶面（CCW，法线 +Z）
             tuple(range(2 * n - 1, n - 1, -1))]   # 底面
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))         # 侧壁
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------- 牌背
def build_card_back():
    clear_scene()
    scene = bpy.context.scene
    setup_common(scene)

    # 实际采样自旧 card_back.png 的颜色
    BLUE_BG = hex_to_linear("#97a7d1")    # 蓝底
    BLUE_DARK = hex_to_linear("#7c90c2")  # 徽章暗纹
    LINE = hex_to_linear("#ced5e7")       # 白纹
    EDGE = hex_to_linear("#fcfcfa")       # 牌边白

    CARD_W = 63 * MM
    CARD_H = 95.5 * MM          # 314:476 比例
    CORNER = 3.0 * MM           # ≈4.8% 牌宽
    BORDER = 3.6 * MM           # 白边厚度（≈3.8% 牌高）

    # 白色牌身 + 蓝色内嵌板
    body = rounded_plate("CardBody", CARD_W, CARD_H, 1.2 * MM, CORNER, 0)
    white = bpy.data.materials.new("CardEdge")
    white.use_nodes = True
    bsdf = white.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = EDGE
    bsdf.inputs["Roughness"].default_value = 0.75
    body.data.materials.append(white)

    face = rounded_plate("CardFace", CARD_W - 2 * BORDER, CARD_H - 2 * BORDER,
                         1.2 * MM, max(CORNER - BORDER, 0.8 * MM), 0.15 * MM)

    # 蓝色牌面：菱格白纹 + 中央徽章暗纹直接逐像素烘焙成贴图（规避节点不稳定因素）
    face_w = CARD_W - 2 * BORDER
    face_h = CARD_H - 2 * BORDER
    aspect = face_w / face_h
    TEX_W, TEX_H = 556, 880  # ≈2x 显示分辨率，自带抗锯齿
    FREQ = 13.0 / math.sqrt(2.0)  # 斜线间距 ≈ 牌面宽 1/13
    COS45 = math.cos(math.radians(45))
    SIN45 = math.sin(math.radians(45))

    def smooth(a, b, x):
        t = min(1.0, max(0.0, (x - a) / (b - a)))
        return t * t * (3.0 - 2.0 * t)

    pixels = [0.0] * (TEX_W * TEX_H * 4)
    for y in range(TEX_H):
        v = (y + 0.5) / TEX_H
        row = y * TEX_W * 4
        for x in range(TEX_W):
            u = (x + 0.5) / TEX_W
            s1 = u * COS45 + v * SIN45
            s2 = u * COS45 - v * SIN45
            line1 = smooth(0.92, 0.975, math.sin(2.0 * math.pi * FREQ * s1))
            line2 = smooth(0.92, 0.975, math.sin(2.0 * math.pi * FREQ * s2))
            line = max(line1, line2)
            # 中央徽章：圆环 + 内盘，淡淡压暗
            r = math.hypot((u - 0.5) * aspect, v - 0.5)
            ring = 1.0 - smooth(0.012, 0.024, abs(r - 0.19))
            disk = 1.0 - smooth(0.11, 0.13, r)
            emblem = min(1.0, ring * 0.55 + disk * 0.3)
            c = [BLUE_BG[i] * (1.0 - emblem) + BLUE_DARK[i] * emblem for i in range(3)]
            c = [c[i] * (1.0 - line) + LINE[i] * line for i in range(3)]
            i = row + x * 4
            pixels[i] = c[0]
            pixels[i + 1] = c[1]
            pixels[i + 2] = c[2]
            pixels[i + 3] = 1.0

    tex_img = bpy.data.images.new("CardFacePattern", TEX_W, TEX_H, alpha=False)
    tex_img.colorspace_settings.name = "Non-Color"  # 值即线性反照率，不做色彩变换
    tex_img.pixels = pixels
    tex_img.pack()  # 打包确保渲染时采样到最新像素

    mat = bpy.data.materials.new("CardFaceBlue")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.78
    bsdf.inputs["Metallic"].default_value = 0.0

    tex = nt.nodes.new("ShaderNodeTexCoord")
    img_node = nt.nodes.new("ShaderNodeTexImage")
    img_node.image = tex_img
    nt.links.new(tex.outputs["Generated"], img_node.inputs["Vector"])
    nt.links.new(img_node.outputs["Color"], bsdf.inputs["Base Color"])

    # 织物噪波 bump
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 120.0
    noise.inputs["Detail"].default_value = 2.0
    noise.inputs["Roughness"].default_value = 0.7
    nt.links.new(tex.outputs["Generated"], noise.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.18
    bump.inputs["Distance"].default_value = 0.15 * MM
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    face.data.materials.append(mat)

    # 均匀打光：强环境光为主（避免光斑），一盏软面光给倒角一点明暗
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bg.inputs["Strength"].default_value = 0.68
    scene.world = world
    add_area_light("Key", (0.04, -0.03, 0.15), 0.08, 0.12, (1.0, 1.0, 1.0))
    add_area_light("Fill", (-0.05, 0.04, 0.10), 0.025, 0.12, (0.95, 0.97, 1.0))

    # 正交相机垂直俯视，牌身充满画面
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = CARD_H
    cam_data.clip_start = 0.0001
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0, 0, 0.05)
    cam.rotation_euler = (0, 0, 0)
    scene.camera = cam

    scene.render.resolution_x = 314
    scene.render.resolution_y = 476
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.filepath = CARD_OUT
    bpy.ops.render.render(write_still=True)
    print("RENDERED", CARD_OUT)

    # 自检像素
    img = bpy.data.images.load(CARD_OUT)
    w, h = img.size
    px = img.pixels[:]
    for name, x, y in [("center", 157, 238), ("corner", 2, 2), ("edge", 157, 470)]:
        i = (y * w + x) * 4
        print("CARD PX", name, tuple(round(v, 3) for v in px[i:i + 4]))


# ---------------------------------------------------------------- Logo
def build_logo():
    clear_scene()
    scene = bpy.context.scene
    setup_common(scene)

    # 金材质（同奖杯风格）
    gold = bpy.data.materials.new("Gold")
    gold.use_nodes = True
    bsdf = gold.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.25
    bsdf.inputs["Base Color"].default_value = hex_to_linear("#d49426")

    # 文本对象
    curve = bpy.data.curves.new("LogoText", "FONT")
    curve.body = "德州扑克锦标赛"
    font = None
    for path in ("C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/msyh.ttc"):
        try:
            font = bpy.data.fonts.load(path)
            print("FONT OK", path)
            break
        except Exception as e:
            print("FONT FAIL", path, e)
    if font:
        curve.font = font
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    SIZE = 0.1
    curve.size = SIZE
    curve.extrude = 0.010          # ≈字高 9%
    curve.bevel_depth = 0.0035
    curve.bevel_resolution = 3
    curve.materials.append(gold)

    obj = bpy.data.objects.new("LogoText", curve)
    bpy.context.collection.objects.link(obj)
    obj.rotation_euler = (math.radians(90), 0, 0)  # 面朝 -Y

    # 世界：低强度灰供金属反射
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.45, 0.47, 0.5, 1.0)
    bg.inputs["Strength"].default_value = 0.6
    scene.world = world

    # 三点打光：暖主光 + 弱冷补 + 轮廓光（文字实际约 2.3m 宽，灯拉远加大功率）
    add_area_light("Key", (0.8, -1.0, 0.9), 250.0, 0.6, (1.0, 0.9, 0.75))
    add_area_light("Fill", (-0.9, -0.6, -0.15), 60.0, 0.8, (0.7, 0.8, 1.0))
    add_area_light("Rim", (0.0, 0.9, 0.9), 320.0, 0.5, (1.0, 0.95, 0.85))

    # 正交相机正面平视（无透视变形）；先粗取景渲染，测 alpha 包围盒后精确二次取景
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.clip_start = 0.01
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0, -2.5, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception as e:
        print("LOOK FAIL", e)

    # 第一遍：粗取景
    ROUGH_W, ROUGH_H = 1600, 500
    cam_data.ortho_scale = 1.5  # 竖直 1.5m，水平 4.8m，必然装得下
    scene.render.resolution_x = ROUGH_W
    scene.render.resolution_y = ROUGH_H
    scene.render.resolution_percentage = 100
    scene.render.filepath = LOGO_OUT
    bpy.ops.render.render(write_still=True)

    # 测 alpha 包围盒
    img = bpy.data.images.load(LOGO_OUT)
    px = img.pixels[:]
    min_x, min_y, max_x, max_y = ROUGH_W, ROUGH_H, -1, -1
    for y in range(ROUGH_H):
        row = y * ROUGH_W * 4
        for x in range(ROUGH_W):
            if px[row + x * 4 + 3] > 0.02:
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
    print("BBOX", min_x, min_y, max_x, max_y)
    if max_x < 0:
        raise RuntimeError("logo render empty")

    # 像素 → 世界坐标。横幅画幅下 ortho_scale 作用于水平方向（AUTO sensor fit）
    wpp = cam_data.ortho_scale / ROUGH_W
    cx_world = ((min_x + max_x) / 2.0 - ROUGH_W / 2.0) * wpp
    cz_world = ((min_y + max_y) / 2.0 - ROUGH_H / 2.0) * wpp
    bw_world = (max_x - min_x + 1) * wpp
    bh_world = (max_y - min_y + 1) * wpp

    # 第二遍：精确取景，宽 1200px，四周少量透明边距（横画幅：ortho_scale = 水平跨度）
    res_x = 1200
    span_x = bw_world * 1.05
    span_y = bh_world * 1.18
    res_y = max(2, round(res_x * span_y / span_x))
    cam.location.x = cx_world
    cam.location.z = cz_world
    cam_data.ortho_scale = span_x
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    bpy.ops.render.render(write_still=True)
    print("RENDERED", LOGO_OUT, "%dx%d" % (res_x, res_y))

    # 自检像素
    img = bpy.data.images.load(LOGO_OUT)
    px = img.pixels[:]
    i = (2 * res_x + 2) * 4
    print("LOGO PX corner", tuple(round(v, 3) for v in px[i:i + 4]))
    cy = res_y // 2
    i = (cy * res_x + res_x // 2) * 4
    print("LOGO PX center", tuple(round(v, 3) for v in px[i:i + 4]))


def main():
    os.makedirs(os.path.dirname(LOGO_OUT), exist_ok=True)
    build_card_back()
    build_logo()


main()
