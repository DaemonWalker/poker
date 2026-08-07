# AGENTS.md · AI 助手上手指南

> 目的：让新对话快速掌握这个项目并安全地改代码。细节查 `docs/GDD.md`（规则）与 `docs/TECH_DESIGN.md`（技术），本文件只放高频必需信息。

## 项目是什么

Godot 4.x / GDScript 的单机无限注德州扑克锦标赛游戏（Windows 桌面，1280×720，中文界面）。玩家 + 1~8 个 AI 淘汰制锦标赛。**开发已完成（M1~M8）**，当前处于成品维护阶段：优先修 bug 与打磨，新功能想法先记入 `docs/GDD.md` 第 10 章候选方向再排期。

## 必会命令

```bash
# 新增 class_name 脚本或新资源后必须先跑一次（生成全局类缓存，否则报 "Could not find type"）
godot --headless --path . --import

# 逻辑层单元测试：1257 项断言，改 core/ 后必跑
godot --headless --path . --script tests/run_tests.gd

# UI 全链路冒烟：AI 代打完整场自动 quit，0 报错为通过；改 ui/、scenes/ 后必跑
godot --headless --path . -- --auto

# 观战模式冒烟：全 AI（含 0 号位）打完整场自动 quit，0 报错为通过；且不得写 tournament.save / 动 stats.save
godot --headless --path . -- --spectate

# 批量模拟：筹码守恒逐手校验，改下注/结算逻辑后建议跑
godot --headless --path . --script tests/simulate.gd -- 100 1

# 座位布局校验：实测 SeatUI 尺寸 + 2~9 人桌矩形相交检测，改座位尺寸/椭圆参数后必跑
godot --headless --path . --script tools/check_layout.gd

# 窗口模式人工试玩（视觉/交互类改动只能靠这个验收）
godot --path .
```

本机开发用 Godot 4.7.1（Steam 版），项目标记 4.7，逻辑层无版本敏感特性。

## 架构红线（不可违反）

- **逻辑层（core/）与表现层（scenes/ + ui/）严格分离**：core/ 全是纯 `RefCounted`，不碰场景树；UI 不直接改规则状态。
- 两层只通过**事件队列**通信：逻辑层累积 Dictionary 事件 → `pop_events()` → 表现层逐条消费播动画。
- **动作提交制**：逻辑层禁止 await 等玩家输入。人类回合发 `ACTION_REQUIRED` 后挂起，UI 调 `submit_human_action()` 恢复。这条保证存档可在手牌边界整体序列化。
- 新增逻辑层行为必须配无头单元测试（tests/test_*.gd，基类 test_base.gd）。

## 代码约定

- 注释与 UI 文案用中文；标识符英文；风格跟随同目录现有文件。
- UI 组件优先**代码构建**（参考 seat_ui.gd / card_ui.gd / ui_theme.gd），新场景做最小 tscn 壳 + `_ready` 构建布局。
- 设置持久化统一走 `user://save/settings.cfg`（读写前先 `cfg.load()` 保留其他段），接口在 `ui/game_settings.gd`；音量接口在 `ui/audio_manager.gd`。
- 素材来源与许可证必须记录到 `assets/SOURCES.md`（音频在 `assets/audio/SOURCES.md`）。

## 已知陷阱（踩过的坑）

- Dictionary 取值与枚举比较结果是 Variant，`var x :=` 类型推断会 parse error——显式标类型（如 `var rank: int = event.rank`）。
- GDScript 默认参数必须是常量表达式，不能引用 `static var`（参见 `Events.action_required` 的 -1 哨兵写法）。
- `--script` 的 SceneTree 测试脚本用不了自动加载单例标识符（编译期找不到 AudioManager），且 `_init` 里 add_child 不触发 `_ready`。
- 无头模式下场景脚本 parse 失败引擎不会自行退出，会挂到超时——看输出里的 ERROR 判断。
- BettingRound 测试的 3 条 `push_error` 是"非法动作被拒绝"用例的预期输出，不是失败。
- 整手牌同步跑完后事件才逐条回放：UI 处理事件时读 `PlayerState` 实时状态拿到的已是手牌终局值（淘汰者已是 OUT），读实时 `pot_size()`/`chips`/`current_bet` 更会提前泄露后续 AI 动作结果。状态、筹码、下注、底池显示都必须用事件快照（`HAND_START.alive_seats/start_chips`、`DEAL_HOLE.chips/bet`、`PLAYER_ACTION.status/bet/chips_left`、`ROUND_END.pot`、`POT_AWARD.chips`），参见 TECH_DESIGN 设计决策 18。

## 不可破坏的既有行为

- `--auto` 入口：`Main._ready` 检测参数直达牌桌；TableScene 内 `anim_enabled=false` 跳动画但音效保留；锦标赛结束自动 `quit()`。冒烟回归全依赖它。`--spectate` 复用同一套冒烟行为，但开的是观战局（config.spectator=true，全 AI 明牌 + 后台线程算胜率）。
- `TableScene.ANIM_SPEED` 是所有 tween 时长的乘数，改动画时保持统一乘算。
- 盲注静默扣除（无 PLAYER_ACTION 事件），UI 在 DEAL_HOLE 时从 `tm.players` 同步刷新——这是有意设计，不要为盲注新增事件。
- 战绩由逻辑层 `TournamentManager._tournament_end` 自动 record + save，界面只读展示，不要在 UI 侧写战绩。

## 环境备忘

- 项目根是 git 仓库，提交前确认 `git status` 只包含本次改动；Godot 可执行文件在 `E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`（不在 PATH，命令里的 `godot` 需替换为全路径）。
