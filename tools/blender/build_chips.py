# build_chips.py — 无头渲染赌场筹码贴图（8 张 256x256 RGBA 透明 PNG）
# 用法: "E:/ProgramData/Blender 5.2/blender.exe" --background --python tools/blender/build_chips.py
import bpy
import math
import os

OUT_DIR = "E:/workspace/godot/poker/assets/chips"
RES = 256
MM = 0.001  # 场景按米建模，尺寸以 mm 书写便于理解

# ---- 尺寸（mm）----
CHIP_R = 19.5 * MM  # 直径 39mm
CHIP_H = 3.3 * MM   # 厚度
N_SPOTS = 8         # 边缘齿纹数
RING_R = 15.0 * MM  # 顶面外圈圆环半径

# ---- 配色 (sRGB hex) ----
CHIPS = {
    "white": {"body": "#e8e8e8", "spot": "#7a8ba0"},
    "red":   {"body": "#c0392b", "spot": "#e8e8e8"},
    "blue":  {"body": "#2e5ea8", "spot": "#e8e8e8"},
    "black": {"body": "#1a1a1a", "spot": "#e8e8e8"},
}


def hex_to_linear_rgba(h):
    h = h.lstrip("#")
    vals = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        c = c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        vals.append(c)
    return (*vals, 1.0)


def make_material(name, hex_color, roughness=0.48):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return m


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_chip(body_mat, spot_mat):
    """建一个筹码（主体 + 边缘齿纹 + 顶面圆环）。"""
    # 主体扁圆柱 + 倒角
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=CHIP_R, depth=CHIP_H, location=(0, 0, 0))
    body = bpy.context.active_object
    body.name = "ChipBody"
    body.data.materials.append(body_mat)
    bevel = body.modifiers.new("EdgeBevel", "BEVEL")
    bevel.width = 0.7 * MM
    bevel.segments = 3
    bevel.limit_method = "ANGLE"

    # 边缘齿纹：小方块放射状嵌入侧缘，顶部微微凸出（俯视呈短白杠）
    box_radial = 2.4 * MM    # 径向尺寸，外缘基本与筹码齐平
    box_width = 4.0 * MM     # 切向宽度
    box_height = 4.6 * MM    # 高于筹码厚度，上下各凸出一点
    r_center = CHIP_R - box_radial / 2.0 + 0.1 * MM
    for i in range(N_SPOTS):
        ang = i * 2.0 * math.pi / N_SPOTS
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(r_center * math.cos(ang), r_center * math.sin(ang), -0.1 * MM))
        box = bpy.context.active_object
        box.name = "Spot_%02d" % i
        box.scale = (box_radial, box_width, box_height)
        box.rotation_euler[2] = ang
        bpy.ops.object.transform_apply(scale=True)
        box.data.materials.append(spot_mat)

    # 顶面外圈细圆环（torus 压扁，半嵌入顶面）
    bpy.ops.mesh.primitive_torus_add(major_radius=RING_R, minor_radius=0.55 * MM,
                                     major_segments=64, minor_segments=12,
                                     location=(0, 0, CHIP_H / 2.0))
    ring = bpy.context.active_object
    ring.name = "TopRing"
    ring.scale = (1.0, 1.0, 0.6)
    bpy.ops.object.transform_apply(scale=True)
    ring.data.materials.append(spot_mat)


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


def add_camera(name, loc, rot_x_deg, ortho_scale):
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    data.clip_start = 0.0001  # 场景只有几厘米大，默认 0.1m 会把筹码裁掉
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (math.radians(rot_x_deg), 0.0, 0.0)
    return obj


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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    clear_scene()
    scene = bpy.context.scene
    setup_render(scene)

    # 世界环境：低强度环境光
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.58, 0.62, 1.0)
    bg.inputs["Strength"].default_value = 0.05
    scene.world = world

    # 灯光：主光 + 补光（小场景，能量用零点几瓦级）
    add_area_light("Key", (0.035, -0.025, 0.055), 0.07, 0.03, (1.0, 0.97, 0.92))
    add_area_light("Fill", (-0.04, 0.03, 0.03), 0.025, 0.035, (0.85, 0.9, 1.0))

    # 相机：顶视（正上方）与 45° 斜视
    cam_top = add_camera("CamTop", (0, 0, 0.08), 0.0, CHIP_R * 2 / 0.92)
    tilt_dist = 0.08
    cam_tilt = add_camera(
        "CamTilt",
        (0, -tilt_dist * math.cos(math.radians(45)), tilt_dist * math.sin(math.radians(45))),
        45.0,
        CHIP_R * 2 / 0.85,
    )

    for chip_name, colors in CHIPS.items():
        body_mat = make_material("Body_" + chip_name, colors["body"])
        spot_mat = make_material("Spot_" + chip_name, colors["spot"], roughness=0.5)
        build_chip(body_mat, spot_mat)

        for suffix, cam in (("", cam_top), ("_tilt", cam_tilt)):
            scene.camera = cam
            path = os.path.join(OUT_DIR, "chip_%s%s.png" % (chip_name, suffix))
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            print("RENDERED", path)

        # 清掉本筹码（只删筹码网格对象，保留相机灯光）
        for obj in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
            bpy.data.objects.remove(obj, do_unlink=True)


main()
