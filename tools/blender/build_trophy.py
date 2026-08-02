# 冠军奖杯建模 + 渲染脚本（无头运行）
# 输出: E:/workspace/godot/poker/assets/trophy/trophy.png
import bpy
import math
import os
from mathutils import Vector

OUT_PATH = "E:/workspace/godot/poker/assets/trophy/trophy.png"

# ---------- 1. 清空场景 ----------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
              bpy.data.cameras, bpy.data.lights):
    for item in list(block):
        if item.users == 0:
            block.remove(item)

scene = bpy.context.scene

# ---------- 2. 建模 ----------
def lathe(name, profile, segments=96):
    """按 (r, z) 轮廓车削生成旋转体"""
    verts = []
    faces = []
    n = len(profile)
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        for (r, z) in profile:
            verts.append((r * ca, r * sa, z))
    for i in range(segments):
        ni = (i + 1) % segments
        for j in range(n - 1):
            a = i * n + j
            b = ni * n + j
            faces.append((a, a + 1, b + 1, b))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    # 按角度平滑：大角度折边保持锐利（阶梯/杯沿），小角度保持圆润
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40.0))
    except Exception as e:
        print("shade_smooth_by_angle 跳过:", e)
    obj.select_set(False)
    return obj

# 底座轮廓（深色大理石感，阶梯式台座）
base_profile = [
    (0.00, 0.00),
    (0.48, 0.00),
    (0.50, 0.015),
    (0.50, 0.11),
    (0.50, 0.13),
    (0.34, 0.13),
    (0.34, 0.15),
    (0.00, 0.15),
]
base = lathe("TrophyBase", base_profile)

# 杯颈 + 碗状杯身轮廓（金色），含内壁与杯沿；收窄碗部让把手剪影更清晰
cup_profile = [
    (0.00, 0.16),
    (0.28, 0.16),
    (0.30, 0.19),
    (0.13, 0.25),
    (0.10, 0.36),
    (0.13, 0.45),
    (0.22, 0.55),
    (0.30, 0.70),
    (0.35, 0.88),
    (0.37, 1.00),
    (0.39, 1.06),   # 杯沿外翻
    (0.39, 1.11),   # 杯沿外顶
    (0.35, 1.11),   # 杯沿内顶
    (0.33, 1.05),
    (0.28, 0.90),
    (0.19, 0.74),
    (0.10, 0.63),
    (0.00, 0.59),
]
cup = lathe("TrophyCup", cup_profile)

# 把手：粗 Bezier 曲线，镜像两侧
def make_handle(sign):
    cu = bpy.data.curves.new("HandleCurve", 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = 0.055
    cu.bevel_resolution = 4
    cu.resolution_u = 12
    sp = cu.splines.new('BEZIER')
    pts = [
        (0.36, 1.02),
        (0.52, 0.97),
        (0.56, 0.84),
        (0.50, 0.71),
        (0.33, 0.67),
    ]
    sp.bezier_points.add(len(pts) - 1)
    for bp, (x, z) in zip(sp.bezier_points, pts):
        bp.co = (sign * x, 0.0, z)
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new("Handle", cu)
    scene.collection.objects.link(obj)
    return obj

handle_r = make_handle(1)
handle_l = make_handle(-1)

# 铭牌：底座正面空白亮金牌
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, -0.49, 0.07))
plaque = bpy.context.active_object
plaque.name = "Plaque"
plaque.scale = (0.19, 0.035, 0.035)
bpy.ops.object.transform_apply(scale=True)
bev = plaque.modifiers.new("Bevel", 'BEVEL')
bev.width = 0.01
bev.segments = 2

# ---------- 3. 材质 ----------
def make_principled(name, base_color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m

gold = make_principled("Gold", (0.83, 0.58, 0.15), 1.0, 0.25)
gold_bright = make_principled("GoldBright", (0.95, 0.78, 0.32), 1.0, 0.12)
dark = make_principled("DarkMarble", (0.035, 0.028, 0.03), 0.4, 0.18)

cup.data.materials.append(gold)
handle_r.data.materials.append(gold)
handle_l.data.materials.append(gold)
base.data.materials.append(dark)
plaque.data.materials.append(gold_bright)

# ---------- 4. 灯光 & 世界 ----------
def area_light(name, loc, energy, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.shape = 'DISK'
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    scene.collection.objects.link(obj)
    # 指向奖杯中心
    direction = Vector((0.0, 0.0, 0.55)) - obj.location
    obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    return obj

area_light("Key", (3.0, -4.0, 5.0), 700, 2.0, (1.0, 0.95, 0.85))
area_light("Fill", (-4.0, -3.0, 2.5), 500, 2.5, (0.85, 0.9, 1.0))
area_light("Rim", (0.5, 3.0, 4.5), 800, 1.5, (1.0, 0.9, 0.75))

# 世界：浅灰提供金属环境反射，透明由 film_transparent 保证
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.6, 0.6, 0.6, 1.0)
bg.inputs["Strength"].default_value = 0.4

# ---------- 5. 相机 ----------
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 1.30
cam = bpy.data.objects.new("Cam", cam_data)
cam.location = (0.0, -8.0, 0.49)
direction = Vector((0.0, 0.0, 0.555)) - cam.location
cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
scene.camera = cam

# ---------- 6. 渲染设置 ----------
scene.render.engine = 'BLENDER_EEVEE'
for attr, val in (("taa_render_samples", 128), ("taa_samples", 128)):
    try:
        setattr(scene.eevee, attr, val)
    except Exception:
        pass
try:
    scene.eevee.ray_tracing_options.sample_count = 4
    scene.eevee.ray_tracing_options.screen_trace_quality = 1.0
except Exception as e:
    print("ray_tracing_options 跳过:", e)
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
scene.render.filepath = OUT_PATH
try:
    scene.view_settings.look = 'AgX - Medium High Contrast'
except Exception as e:
    print("look 设置跳过:", e)

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
bpy.ops.render.render(write_still=True)
print("render done ->", OUT_PATH)

# ---------- 7. 构图校验：alpha 包围盒占比 ----------
img = bpy.data.images.load(OUT_PATH)
w, h = img.size
px = list(img.pixels)
alpha = px[3::4]
min_x, max_x, min_y, max_y = w, -1, h, -1
for y in range(h):
    row = y * w
    for x in range(w):
        if alpha[row + x] > 0.02:
            if x < min_x: min_x = x
            if x > max_x: max_x = x
            if y < min_y: min_y = y
            if y > max_y: max_y = y
if max_x < 0:
    print("BBOX: 全透明！")
else:
    bw = (max_x - min_x + 1) / w
    bh = (max_y - min_y + 1) / h
    cx = (min_x + max_x) / 2 / w
    cy = (min_y + max_y) / 2 / h
    print(f"BBOX: 宽占比={bw:.3f} 高占比={bh:.3f} 中心=({cx:.3f},{cy:.3f}) "
          f"(0.5,0.5 为居中)")
