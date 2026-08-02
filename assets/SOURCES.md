# 图片素材来源清单（assets/）

## 扑克牌（assets/cards/，MIT）

hayeah/playing-cards-assets（GitHub），**MIT 协议**，许可证原文见 `LICENSE-playing-cards-assets.txt`。牌面图案源自 Byron Knoll 公有领域（public domain）矢量扑克牌。

- 52 张正面为 222x323 高分辨率 PNG（替换 2026-08-02 前使用的 Kenney 像素风 42x60 版，原版本在 56x80 显示尺寸下放大约 1.33 倍导致模糊）
- 原 PNG 只有图案层（无白色牌身），已用 Godot 脚本垫白底圆角牌身（圆角半径 12，约为牌宽 5%）
- 牌背 `card_back.png` 取包内 `back@2x.png`（314x476），原图为白底浅灰纹，已改色为经典蓝底白纹 + 白色牌边 + 圆角
- 空槽位框 `card_empty.png` 为本项目程序化生成（222x323 圆角镂空框，Godot 脚本绘制）
- 文件名按项目规范重命名：`card_<spades|hearts|clubs|diamonds>_<02..10|J|Q|K|A>.png`（原名 `<rank>_of_<suit>.png`）
- 下载来源（2026-08-02）：https://github.com/hayeah/playing-cards-assets （master zip）

## 头像 / 筹码 / 背景 / 奖杯（自生成，无版权问题）

以下素材均为本项目自生成，无第三方素材、无版权问题：头像用 Godot 脚本（SceneTree 逐像素绘制 Image 后 save_png）程序化生成；筹码 / 背景 / 奖杯用 Blender 无头渲染生成（脚本在 `tools/blender/`）：

| 目录 | 文件 | 说明 |
|---|---|---|
| assets/avatars/ | avatar_rock / avatar_maniac / avatar_veteran / avatar_anchor / avatar_fox / avatar_shark / avatar_block / avatar_drifter .png | 8 个 AI 身份头像（64x64 圆形徽章 + 白色几何符号：山/闪电/六角星/吊锤/狐耳/背鳍/方块/波浪，8 种配色），对应 `AIProfiles.IDENTITIES` 的 avatar_id |
| assets/avatars/ | avatar_human.png | 人类玩家默认头像（金色，人像符号），对应 `avatar_human` |
| assets/chips/ | chip_white / chip_red / chip_blue / chip_black .png（+ 各 `_tilt` 45° 斜视版） | 256x256 赌场筹码（边缘嵌块齿纹 + 顶面圆环 + 倒角），Blender 无头渲染（脚本 `tools/blender/build_chips.py`），按金额区间着色：白 <100、红 <500、蓝 <1000、黑 ≥1000 |
| assets/bg/ | table_felt.png | 1280x720 牌桌桌布（俯视：深绿毛毡 + 胡桃木桌沿），Blender 渲染 + numpy 后处理（脚本 `tools/blender/build_backgrounds.py` / `darken_bg.py`） |
| assets/bg/ | menu_bg.png | 1280x720 外围界面背景（斜俯视牌桌 + 散落筹码/素面牌，暗色调），主菜单/设置/结算/战绩共用，同脚本生成 |
| assets/trophy/ | trophy.png | 512x512 带 alpha 金奖杯（车削杯身 + 双把手 + 底座铭牌），Blender 无头渲染，用于结算界面夺冠标题（result_ui.gd） |

曾尝试寻找 CC0 头像包（OpenGameArt / Kenney），未找到 8 个差异化头像的合适免费包，按任务降级方案改为程序化生成。
