# 图片素材来源清单（assets/）

## 扑克牌（assets/cards/，CC0）

Kenney Playing Cards Pack（www.kenney.nl），**CC0 协议**（无署名要求），许可证原文见 `Kenney-License.txt`。

- 取包内 `PNG/Cards (large)`（64x64，牌面竖版居中于透明底）的 52 张正面 + `card_back.png` 牌背 + `card_empty.png` 空槽位框
- 已用 Godot 脚本按不透明区域裁剪为 42x60（宽高比 0.7，与 `CardUI.SIZE` 一致），文件名保持原命名：`card_<spades|hearts|clubs|diamonds>_<02..10|J|Q|K|A>.png`
- 下载来源（2026-08-01）：https://kenney.nl/assets/playing-cards-pack （直链 zip）
- 注意：该包为像素风竖版牌；牌面图案与许可证经抽验确认无误

## 头像 / 筹码 / 背景（程序化自生成，无版权问题）

以下素材为本项目用 Godot 脚本（SceneTree 脚本逐像素绘制 Image 后 save_png）程序化生成，无第三方素材、无版权问题：

| 目录 | 文件 | 说明 |
|---|---|---|
| assets/avatars/ | avatar_rock / avatar_maniac / avatar_veteran / avatar_anchor / avatar_fox / avatar_shark / avatar_block / avatar_drifter .png | 8 个 AI 身份头像（64x64 圆形徽章 + 白色几何符号：山/闪电/六角星/吊锤/狐耳/背鳍/方块/波浪，8 种配色），对应 `AIProfiles.IDENTITIES` 的 avatar_id |
| assets/avatars/ | avatar_human.png | 人类玩家默认头像（金色，人像符号），对应 `avatar_human` |
| assets/chips/ | chip_white / chip_red / chip_blue / chip_black .png | 32x32 圆筹码（齿边 + 内圈），按金额区间着色：白 <100、红 <500、蓝 <1000、黑 ≥1000 |
| assets/bg/ | table_felt.png | 1280x720 牌桌桌布（深绿毛毡风：径向渐变 + 噪点 + 暗角），seed=42 |
| assets/bg/ | menu_bg.png | 1280x720 外围界面背景（同风格更深配色），主菜单/设置/结算/战绩共用 |

曾尝试寻找 CC0 头像包（OpenGameArt / Kenney），未找到 8 个差异化头像的合适免费包，按任务降级方案改为程序化生成。
