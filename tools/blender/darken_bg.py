# darken_bg.py — 对已有两张背景图做压暗/调色后处理（不重渲），迭代收敛到目标像素值
# 用法: "E:/ProgramData/Blender 5.2/blender.exe" --background --python tools/blender/darken_bg.py
# 注意: bpy 加载 PNG 后 image.pixels 为 sRGB 编码值（0..1），采样即所见像素
import bpy
import numpy as np

BG_DIR = "E:/workspace/godot/poker/assets/bg"


def load(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.asarray(img.pixels[:], dtype=np.float32).reshape(h, w, 4).copy()
    return img, px, w, h


def save(img, px):
    np.clip(px, 0.0, 1.0, out=px)
    img.pixels = px.ravel()
    img.save()
    bpy.data.images.remove(img)


def patch_mean(px, cx, cy, rad=20):
    """cx, cy 为像素坐标（原点在左上），返回 RGB 均值。"""
    y0, y1 = max(cy - rad, 0), min(cy + rad, px.shape[0])
    x0, x1 = max(cx - rad, 0), min(cx + rad, px.shape[1])
    # pixels 行序为自下而上，采样块对称时无需翻转
    return px[y0:y1, x0:x1, :3].reshape(-1, 3).mean(axis=0)


def hexs(rgb):
    return "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in rgb)


def felt_mask(px):
    r, g, b = px[:, :, 0], px[:, :, 1], px[:, :, 2]
    return (g > r * 1.15) & (g > b * 1.1)


def radial(w, h):
    yy, xx = np.mgrid[0:h, 0:w]
    nx = (xx / float(w) - 0.5) * 2.0
    ny = (yy / float(h) - 0.5) * 2.0
    return np.sqrt(nx * nx + ny * ny)


def apply_masked_gain(px, mask, gains):
    """mask 内乘 gains（RGB 三元组），mask 外不变。"""
    m = mask.astype(np.float32)
    for c in range(3):
        g = gains[c]
        px[:, :, c] *= 1.0 + m * (g - 1.0)


def iterate_to_target(px, mask, sample_xy, target, iters=6):
    """对 mask 区域按采样点实测值迭代乘算，收敛到 target（sRGB 0..1）。"""
    tgt = np.array(target, dtype=np.float32) / 255.0
    for i in range(iters):
        cur = patch_mean(px, sample_xy[0], sample_xy[1])
        ratio = tgt / np.maximum(cur, 1e-4)
        # 单步只走一部分防止震荡，并限制单步幅度
        step = np.clip(1.0 + (ratio - 1.0) * 0.8, 0.5, 2.0)
        apply_masked_gain(px, mask, step)
        if np.all(np.abs(ratio - 1.0) < 0.02):
            break
    return patch_mean(px, sample_xy[0], sample_xy[1])


def process_table_felt():
    path = BG_DIR + "/table_felt.png"
    img, px, w, h = load(path)
    mask = felt_mask(px)

    # 1) 毛毡：中心收敛到 #1a6133
    center = iterate_to_target(px, mask, (w // 2, h // 2), (0x1a, 0x61, 0x33))

    # 2) 木沿（非毛毡区域）：整体压暗到深胡桃，保持偏棕色调
    wood = ~mask
    wood_gain = (0.38, 0.34, 0.27)  # 红通道稍保留，压蓝绿 => 深棕
    apply_masked_gain(px, wood, wood_gain)

    # 3) 轻加四角暗角，保持中心微亮的渐变
    r = radial(w, h)
    t = np.clip((r - 0.85) / 0.6, 0.0, 1.0)
    f = 1.0 - 0.10 * t * t
    for c in range(3):
        px[:, :, c] *= f

    save(img, px)

    # 验证采样
    img2, px2, w, h = load(path)
    c = patch_mean(px2, w // 2, h // 2)
    corners = [patch_mean(px2, 30, 30), patch_mean(px2, w - 30, 30),
               patch_mean(px2, 30, h - 30), patch_mean(px2, w - 30, h - 30)]
    rail_top = patch_mean(px2, w // 2, 25)
    print("TABLE_FELT center %s (target #1a6133)" % hexs(c))
    print("TABLE_FELT rail_top %s" % hexs(rail_top))
    for i, co in enumerate(corners):
        print("TABLE_FELT corner%d %s" % (i, hexs(co)))
    bpy.data.images.remove(img2)


def process_menu_bg():
    path = BG_DIR + "/menu_bg.png"
    img, px, w, h = load(path)
    mask = felt_mask(px)

    # 1) 全局压暗（含筹码/牌/墙），融进暗氛围
    for c in range(3):
        px[:, :, c] *= 0.62

    # 2) 白牌/白筹码等高明度低饱和区域额外压暗（现在太抢眼）
    mx = px[:, :, :3].max(axis=2)
    mn = px[:, :, :3].min(axis=2)
    bright_neutral = (mx > 0.45) & ((mx - mn) < 0.12)
    apply_masked_gain(px, bright_neutral, (0.62, 0.62, 0.62))

    # 3) 毛毡中心收敛到 #143c26（#0e311e~#1a4530 区间中值偏上）
    center = iterate_to_target(px, mask, (w // 2, int(h * 0.55)), (0x14, 0x3c, 0x26))

    # 4) 加强暗角
    r = radial(w, h)
    t = np.clip((r - 0.35) / 0.95, 0.0, 1.0)
    f = 1.0 - 0.22 * t * t
    for c in range(3):
        px[:, :, c] *= f

    save(img, px)

    # 验证采样
    img2, px2, w, h = load(path)
    c = patch_mean(px2, w // 2, int(h * 0.55))
    corners = [patch_mean(px2, 30, 30), patch_mean(px2, w - 30, 30),
               patch_mean(px2, 30, h - 30), patch_mean(px2, w - 30, h - 30)]
    cards = patch_mean(px2, int(w * 0.40), int(h * 0.56))  # 白牌附近
    print("MENU_BG center %s (target #0e311e~#1a4530)" % hexs(c))
    print("MENU_BG cards_area %s" % hexs(cards))
    for i, co in enumerate(corners):
        print("MENU_BG corner%d %s" % (i, hexs(co)))
    bpy.data.images.remove(img2)


process_table_felt()
process_menu_bg()
