# build_avatars.py — 无头渲染浮雕金属徽章头像（9 张 128x128 RGBA 透明 PNG）
# 工艺：读原版 64x64 PNG 提取符号掩码 + 底色，薄圆柱徽章顶面用掩码做 bump 浮雕，
#       符号区域混成更亮更滑的银白金属。
# 用法:
#   测试（只渲 fox 到 _tmp 检查方向）:
#     "E:/ProgramData/Blender 5.2/blender.exe" --background --python tools/blender/build_avatars.py -- test
#   全量（覆盖 assets/avatars/ 9 张）:
#     "E:/ProgramData/Blender 5.2/blender.exe" --background --python tools/blender/build_avatars.py
# 注意：本脚本读取的源图会被自身输出覆盖，属一次性转换；重跑前需先从 git 恢复原版扁平 PNG。
# 实测 blender.exe 位于 Steam 库 E:/SteamLibrary/steamapps/common/Blender/blender.exe
import bpy
import math
import os
import sys
import numpy as np

SRC_DIR = "E:/workspace/godot/poker/assets/avatars"
TMP_DIR = "E:/workspace/godot/poker/tools/blender/_tmp_avatars"
RES = 128
MASK_RES = 256

NAMES = [
    "avatar_rock", "avatar_maniac", "avatar_veteran", "avatar_anchor",
    "avatar_fox", "avatar_shark", "avatar_block", "avatar_drifter",
    "avatar_human",
]

# 方向修正（首轮测试后确定）：图像在圆柱顶盖 UV 上的翻转
FLIP_UD = False
FLIP_LR = False

# ---- 调色参数（第二轮：解决金属+灯光洗白问题）----
BASE_SAT = 1.25    # 底色饱和度提升倍数（过高会把小通道截断到 0，迭代校准乘不动）
BASE_DARK = 0.82   # 底色明度压暗系数（仅作初值，最终由迭代校准逐通道收敛）
SYMBOL_WHITE = 0.45  # 符号向白混合比例（原 0.7 太重，改亮金属感）

def treat_base(base):
    """采样底色 → 加饱和 + 压明度，作为金属基色初值；下限 0.01 避免乘法修正死区。"""
    luma = 0.2126 * base[0] + 0.7152 * base[1] + 0.0722 * base[2]
    c = luma + (base - luma) * BASE_SAT
    return np.clip(c * BASE_DARK, 0.01, 1.0)


def calibrate(out_path, mask64, base_raw, name):
    """渲染后回读圆盘非符号区域 median，与原底色逐通道对比（linear），目标比值 0.85~1.15。
    返回渲染得到的 linear 颜色。"""
    px = load_png_pixels(out_path)
    h, w = px.shape[:2]
    m = mask64
    if m.shape[0] != h:  # 渲染分辨率与掩码不同时最近邻对齐（掩码行列序与渲染一致）
        idx = (np.arange(h) * m.shape[0] / h).astype(int)
        m = m[np.ix_(idx, idx)]
    cy, cx = (h - 1) / 2.0, (w - 1) / 2.0
    yy, xx = np.mgrid[0:h, 0:w]
    disc = (np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2) < 0.7 * (w / 2.0)) & (m < 0.5) & (px[..., 3] > 0.5)
    got = np.array([np.median(px[..., i][disc]) for i in range(3)])
    ratio = got / np.maximum(base_raw, 1e-4)
    print("CALIB %s got=%s raw=%s ratio=%s" % (
        name, np.round(got, 3), np.round(base_raw, 3), np.round(ratio, 3)))
    return got

# ---- 尺寸（米）----
BADGE_R = 0.5
BADGE_H = 0.1


# ---------- 图像分析 ----------

def load_png_pixels(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px  # 行序：index 0 = 图像底行（Blender 约定）


def box_blur(m, r=1, passes=3):
    out = m.astype(np.float32)
    n = (2 * r + 1) ** 2
    for _ in range(passes):
        acc = out.copy()
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if dx == 0 and dy == 0:
                    continue
                acc += np.roll(np.roll(out, dx, 0), dy, 1)
        out = acc / n
    return out


def upsample_bilinear(m, size):
    h, w = m.shape
    ys = np.clip((np.arange(size) + 0.5) * h / size - 0.5, 0, h - 1.001)
    xs = np.clip((np.arange(size) + 0.5) * w / size - 0.5, 0, w - 1.001)
    y0 = ys.astype(int)
    x0 = xs.astype(int)
    fy = (ys - y0).astype(np.float32)
    fx = (xs - x0).astype(np.float32)
    y1 = np.minimum(y0 + 1, h - 1)
    x1 = np.minimum(x0 + 1, w - 1)
    top = m[np.ix_(y0, x0)] * (1 - fx)[None, :] + m[np.ix_(y0, x1)] * fx[None, :]
    bot = m[np.ix_(y1, x0)] * (1 - fx)[None, :] + m[np.ix_(y1, x1)] * fx[None, :]
    return top * (1 - fy)[:, None] + bot * fy[:, None]


def analyze_avatar(path):
    """返回 (掩码 float32 h×w, 底色 linear rgb)。"""
    px = load_png_pixels(path)
    h, w = px.shape[:2]
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    # 符号掩码：近白像素
    mask = ((r > 0.85) & (g > 0.85) & (b > 0.85)).astype(np.float32)
    # 底色：圆内、非符号、远离边缘的像素取 median
    cy, cx = (h - 1) / 2.0, (w - 1) / 2.0
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
    inner = (dist < 0.75 * (w / 2.0)) & (a > 0.5) & (mask < 0.5)
    base = np.array([
        np.median(r[inner]), np.median(g[inner]), np.median(b[inner]),
    ], dtype=np.float32)
    return mask, base


def save_mask_image(mask, path):
    """掩码 64x64 → 模糊 + 上采样 256，存灰度 PNG（保持 Blender 行序，磁盘上方向与源图一致）。"""
    m = mask
    if FLIP_UD:
        m = np.flipud(m)
    if FLIP_LR:
        m = np.fliplr(m)
    m = box_blur(m, r=1, passes=3)
    m = upsample_bilinear(m, MASK_RES)
    m = np.ascontiguousarray(m, dtype=np.float32)
    img = bpy.data.images.new("mask", MASK_RES, MASK_RES, alpha=False)
    rgba = np.stack([m, m, m, np.ones_like(m)], axis=-1)
    img.pixels = rgba.ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


# ---------- 场景搭建 ----------

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_render(scene):
    scene.render.engine = "BLENDER_EEVEE"
    for attr in ("taa_samples", "taa_render_samples"):
        if hasattr(scene.eevee, attr):
            setattr(scene.eevee, attr, 64)
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def add_area_light(name, loc, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (-obj.location).to_track_quat("-Z", "Y").to_euler()
    return obj


def build_badge(mask_path, base_rgb, name):
    """薄圆柱徽章：顶盖 = 浮雕材质（掩码 bump + 亮金属符号），侧面/底面/倒角 = 底色金属。
    base_rgb 传入的是 treat_base 处理后的基色。"""
    # 侧面材质：底色金属，略暗
    side_mat = bpy.data.materials.new("Side_" + name)
    side_mat.use_nodes = True
    sbsdf = side_mat.node_tree.nodes["Principled BSDF"]
    sbsdf.inputs["Base Color"].default_value = (
        float(base_rgb[0]) * 0.7, float(base_rgb[1]) * 0.7, float(base_rgb[2]) * 0.7, 1.0)
    sbsdf.inputs["Metallic"].default_value = 0.9
    sbsdf.inputs["Roughness"].default_value = 0.38

    # 顶面材质：底色 ↔ 亮金属符号 按掩码混合
    top_mat = bpy.data.materials.new("Top_" + name)
    top_mat.use_nodes = True
    nt = top_mat.node_tree
    tbsdf = nt.nodes["Principled BSDF"]
    tbsdf.inputs["Metallic"].default_value = 0.92
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(mask_path)
    tex.interpolation = "Cubic"
    tex.location = (-600, 100)
    uv = nt.nodes.new("ShaderNodeTexCoord")
    uv.location = (-800, 100)
    nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])

    # 符号色：处理后底色向白混合 SYMBOL_WHITE，亮金属而非近白
    silver = tuple(min(1.0, float(c) * (1.0 - SYMBOL_WHITE) + SYMBOL_WHITE) for c in base_rgb)
    mix_col = nt.nodes.new("ShaderNodeMixRGB")
    mix_col.blend_type = "MIX"
    mix_col.inputs[1].default_value = (float(base_rgb[0]), float(base_rgb[1]), float(base_rgb[2]), 1.0)
    mix_col.inputs[2].default_value = (*silver, 1.0)
    mix_col.location = (-300, 250)
    nt.links.new(tex.outputs["Color"], mix_col.inputs[0])
    nt.links.new(mix_col.outputs["Color"], tbsdf.inputs["Base Color"])

    # 粗糙度：底 0.35 → 符号 0.25（0.15 太光滑，正俯视下只反射暗环境导致符号发暗）
    mix_rough = nt.nodes.new("ShaderNodeMixRGB")
    mix_rough.blend_type = "MIX"
    mix_rough.inputs[1].default_value = (0.35, 0.35, 0.35, 1.0)
    mix_rough.inputs[2].default_value = (0.28, 0.28, 0.28, 1.0)
    mix_rough.location = (-300, 0)
    nt.links.new(tex.outputs["Color"], mix_rough.inputs[0])
    nt.links.new(mix_rough.outputs["Color"], tbsdf.inputs["Roughness"])

    # bump 浮雕
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    bump.inputs["Distance"].default_value = 0.03
    bump.location = (-300, -250)
    nt.links.new(tex.outputs["Color"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], tbsdf.inputs["Normal"])

    # 圆柱 + 倒角；顶盖 n-gon 用顶面材质，其余用侧面材质
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=BADGE_R, depth=BADGE_H)
    badge = bpy.context.active_object
    badge.name = "Badge_" + name
    badge.data.materials.append(side_mat)   # index 0
    badge.data.materials.append(top_mat)    # index 1
    # Blender 5.2 默认圆柱顶盖 UV 只占左下象限，须手动重映射为内切圆铺满 [0,1]^2
    uv_data = badge.data.uv_layers.active.data
    for poly in badge.data.polygons:
        if poly.normal.z > 0.9:
            poly.material_index = 1
            for li in poly.loop_indices:
                co = badge.data.vertices[badge.data.loops[li].vertex_index].co
                uv_data[li].uv = (co.x / (2.0 * BADGE_R) + 0.5,
                                  co.y / (2.0 * BADGE_R) + 0.5)
    bevel = badge.modifiers.new("EdgeBevel", "BEVEL")
    bevel.width = 0.02
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bevel.material = 0  # 倒角面用侧面材质
    return badge


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    test_only = "test" in args
    test_names = [a for a in args if a.startswith("avatar_")] or ["avatar_fox"]
    os.makedirs(TMP_DIR, exist_ok=True)
    clear_scene()
    scene = bpy.context.scene
    setup_render(scene)

    # 世界环境：金属反射来源（强度抬高给饱和色留出修正空间，中性色由校准拉回）
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.55, 0.58, 1.0)
    bg.inputs["Strength"].default_value = 0.4
    scene.world = world

    # 灯光：主 Area 左前上 + 弱补光（1m 尺度场景；第二轮降功率防洗白）
    add_area_light("Key", (-0.8, -0.6, 1.2), 30.0, 0.5, (1.0, 0.97, 0.92))
    add_area_light("Fill", (0.9, 0.7, 0.8), 9.0, 0.6, (0.85, 0.9, 1.0))

    # 相机：正俯视正交，徽章直径占画面 96%
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = BADGE_R * 2 / 0.96
    cam_data.clip_start = 0.0001
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0, 0, 2.0)
    scene.camera = cam

    names = test_names if test_only else NAMES
    for name in names:
        src = os.path.join(SRC_DIR, name + ".png")
        mask, base = analyze_avatar(src)
        mask_path = os.path.join(TMP_DIR, name + "_mask.png")
        save_mask_image(mask, mask_path)
        out_dir = TMP_DIR if test_only else SRC_DIR
        out = os.path.join(out_dir, name + (".test.png" if test_only else ".png"))
        scene.render.filepath = out

        # 迭代校准：sat+dark 初值起渲，按 原色/渲染色 比值逐通道修正基色，
        # 最多 3 轮，全通道 ratio 落入 [0.85, 1.15] 提前停（最终一轮渲染即交付文件）
        treated = treat_base(base)
        for it in range(4):
            build_badge(mask_path, treated, name)
            bpy.ops.render.render(write_still=True)
            got = calibrate(out, mask, base, name)
            for obj in [o for o in scene.objects if o.type == "MESH"]:
                bpy.data.objects.remove(obj, do_unlink=True)
            ratio = got / np.maximum(base, 1e-4)
            if np.all(ratio >= 0.85) and np.all(ratio <= 1.15):
                break
            corr = np.clip(base / np.maximum(got, 1e-3), 1.0 / 3.0, 3.0)
            treated = np.clip(treated * corr, 0.01, 1.0)
        print("RENDERED", out)


main()
