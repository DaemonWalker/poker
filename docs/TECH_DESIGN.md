# 德州扑克 · 技术设计文档

> 面向要接手改代码的工程师，是理解代码库的第一手技术参考。
> 对应规则文档：`docs/GDD.md`。本文档描述的是**最终实现**，一切以代码为准。

---

## 1. 技术栈与架构总览

- 引擎：**Godot 4.7（项目目标版本，`project.godot` 标记 4.7 / Forward Plus）；本机开发测试用 4.6.2**，逻辑层仅用基础 GDScript 特性，两版行为一致。
- 语言：GDScript。平台：Windows 桌面，窗口 1280×720（`canvas_items` 拉伸 + `expand`）。
- 主场景 `scenes/main.tscn`；唯一自动加载单例 `AudioManager`（`ui/audio_manager.gd`）。

### 1.1 逻辑与表现分离

- **逻辑层（core/）**：纯 `RefCounted` 类，不依赖场景树、不创建节点。负责全部规则：发牌、下注状态机、边池、牌力评估、AI 决策、锦标赛调度、存档序列化。可脱离 UI 在无头模式单测。
- **表现层（scenes/ + ui/）**：场景与节点。消费逻辑层事件，播放动画与音效，把玩家输入转译为动作提交。
- 两层通过**事件队列**通信：逻辑层把状态变化累积为 `Dictionary` 事件（`pop_events()` 取出），表现层逐条消费并播动画，播完再取下一条。动画时序不干扰规则逻辑。

### 1.2 动作提交制（硬约束）

**逻辑层禁止使用 await 等待玩家输入**。人类回合时 HandController 发出 `ACTION_REQUIRED` 事件后以状态变量（`waiting_seat`）挂起；表现层收集输入后调 `submit_human_action()` 恢复推进。由此保证：逻辑层任意时刻状态可外部读取、可在手牌边界整体序列化。

### 1.3 分层调用关系

```
表现层  Main(路由) → TableScene → EventPlayer → SeatUI/CardUI/ActionPanel
            ▲ 事件队列 pop_events()      │ submit_human_action(action)
逻辑层  TournamentManager → HandController → BettingRound/PotManager/Deck
          → HandEvaluator / AIDecider(→HandStrength)；SaveManager/StatsManager/Events
```

---

## 2. 目录结构

```
res://
├── project.godot            # 主场景 main.tscn；autoload AudioManager；1280x720
├── docs/                    # GDD.md（游戏规则）、本文档
├── core/                    # 逻辑层（纯 RefCounted，无节点）
│   ├── card.gd / deck.gd / hand_evaluator.gd / player_state.gd
│   ├── betting_round.gd     # 单轮下注状态机
│   ├── pot_manager.gd       # 底池/边池分层与结算（全静态）
│   ├── hand_controller.gd   # 一手牌完整流程
│   ├── events.gd            # 事件类型枚举 + 工厂函数
│   ├── tournament_manager.gd# 锦标赛调度 + 整体序列化
│   ├── save_manager.gd / stats_manager.gd   # 存档 / 战绩读写
│   └── ai/                  # ai_decider.gd（决策）/ hand_strength.gd（评分）/ ai_profiles.gd（风格+身份）
├── scenes/                  # main.tscn（常驻）+ table.tscn（手摆槽位+UILayer）+
│                            #   main_menu/settings/result/stats.tscn（最小壳，UI 代码构建）
├── ui/                      # 表现层脚本与组件
│   ├── main.gd              # Main：场景路由器 + 开局意图
│   ├── main_menu.gd / settings_ui.gd / result_ui.gd / stats_ui.gd
│   ├── game_settings.gd     # GameSettings：设置持久化（静态接口）
│   ├── ui_theme.gd          # UITheme：代码构建共享 Theme
│   ├── audio_manager.gd     # AudioManager：音效单例（autoload）
│   ├── table_scene.gd       # TableScene：牌桌控制器、事件→UI 映射
│   ├── event_player.gd      # EventPlayer：事件队列播放器
│   ├── action_panel.gd / raise_slider.gd / seat_ui.gd / card_ui.gd
├── assets/
│   ├── cards/               # 扑克牌贴图（playing-cards-assets，MIT，222x323）
│   ├── avatars/             # 头像 9（程序化生成）
│   ├── chips/ bg/ trophy/   # 筹码 4×2 视角 / 背景 2 / 奖杯 1（均 Blender 渲染，脚本 tools/blender/）
│   ├── audio/               # 音效 10 个（Kenney，CC0）
│   └── SOURCES.md           # 素材来源与许可证（audio/ 下另有一份）
└── tests/                   # 无头模式测试
    ├── run_tests.gd         # 运行器（7 套件，失败 quit(1)）
    ├── test_base.gd         # 断言计数 + 构造/驱动助手基类
    ├── simulate.gd          # 全 AI 批量锦标赛模拟（筹码守恒校验）
    └── test_deck / test_hand_evaluator / test_betting_round / test_pot_manager /
        test_hand_controller / test_tournament / test_save_load
```

---

## 3. 逻辑层模块职责

### 3.1 Card（core/card.gd）

`suit`（0=黑桃 1=红桃 2=梅花 3=方块）+ `rank`（2~14，11=J 12=Q 13=K 14=A），纯 int 存储。`to_string_short()` 输出 "As"/"Td"；`static from_string(s)` 逆运算（测试用）。常量 `RANK_CHARS="23456789TJQKA"`、`SUIT_CHARS="shcd"`（素材映射也用，见第 9 章）。

### 3.2 Deck（core/deck.gd）

52 张 Card，**牌堆顶为数组末尾**（`draw()` = `pop_back()`）。`shuffle(rng_seed := 0)`：Fisher-Yates；`seed != 0` 固定种子可复现，`== 0` 随机。测试用 `test_base.rigged_deck()` 直接替换 `cards` 获得确定牌序。

### 3.3 PlayerState（core/player_state.gd）

纯数据结构：`seat_index / name / avatar_id / is_human / ai_profile / chips / hole_cards / status / current_bet / hand_total_bet`。`Status { ACTIVE, FOLDED, ALL_IN, OUT }`，OUT 表示锦标赛淘汰。`hand_total_bet` 是边池分层与底池总额的输入。

### 3.4 HandEvaluator（core/hand_evaluator.gd，全静态）

```gdscript
static func evaluate(cards: Array[Card]) -> HandRank   # 支持 5~7 张，取最优
static func compare(a: HandRank, b: HandRank) -> int   # a>b 1，a<b -1，等 0
static func best_five(cards) -> Array[Card]
static func category_name(category: int) -> String     # 中文牌型名
```

`HandRank` = `category`（枚举 HIGH_CARD..ROYAL_FLUSH，升序即牌力升序）+ `tiebreakers: Array[int]`。比较先比 category 再逐项比踢脚，统一数组比较覆盖所有牌型，无特判。算法：枚举全部 5 张组合（7 张时 21 种）取最大，暴力够用；顺子特判 A-2-3-4-5（A 当 1）。

### 3.5 BettingRound（core/betting_round.gd）

单轮下注状态机（无限注）。`ActionType { FOLD, CHECK, CALL, RAISE, ALL_IN }`。

```gdscript
func _init(p_players: Array[PlayerState], first_to_act_seat: int, p_big_blind: int)
# 盲注由调用方（HandController）预先计入各玩家 current_bet 后再构造；
# current_high 统计所有在局玩家（含盲注全下者）
func get_legal_actions(p: PlayerState) -> Dictionary
# {can_check, can_call, call_amount, can_raise, min_raise_to, max_raise_to, can_all_in}
func apply_action(p: PlayerState, action: Dictionary) -> bool
# 校验轮次与合法性，非法 push_error 并返回 false（不改状态）
func current_actor() -> PlayerState   # 轮次结束返回 null
func is_round_complete() -> bool
```

规则要点：

- 最小加注到 `current_high + last_raise_increment`（翻牌前即 2BB）；足额加注重新开启所有可行动玩家的行动权。
- 不足额全下只要求已行动者回应，但封锁其再加注权（`raise_blocked`）。
- `can_raise`：有余码 且 全下总额 ≥ 最小加注 且 未被封锁；**`can_all_in`：被封锁时仅当全下总额 ≤ current_high（等同跟注）才为 true**——合法动作集合与状态机判定严格一致，UI 直接依赖它显隐按钮。
- 轮次结束条件：全部 ACTIVE 玩家已行动且下注齐平，或仅剩一名可行动玩家且无注可跟。

### 3.6 PotManager（core/pot_manager.gd，全静态）

`build_pots(players) -> Array`：按 `hand_total_bet` 升序去重分层，第 i 层池金额 = (Lᵢ−Lᵢ₋₁) × 该层及以上人数（**含已弃牌者，弃牌者只贡献不赢池**），每层记录有资格座位（bet ≥ Lᵢ 且未弃牌）。返回 `[{amount, eligible: Array[int], level}]`。

```gdscript
static func settle(pots: Array, players: Array[PlayerState],
        community: Array[Card], button_seat: int) -> Array
# 每个池在有资格玩家中用 HandEvaluator 比牌，胜者平分；
# 余数从按钮后第一位赢家起顺时针依次分配（_rotate_after）
# 返回 [{seat, amount, hand_rank, pot_index}]，供表现层播收池动画
```

### 3.7 HandController（core/hand_controller.gd）

一手牌的执行引擎。`State { IDLE, BETTING, FINISHED }`、`Street { PREFLOP, FLOP, TURN, RIVER }`。

```gdscript
func _init(p_players, p_button_seat, p_small_blind, p_big_blind,
        p_deck_seed: int, p_ai_decider: AIDecider, p_hand_no: int, p_rig_seat := -1)
func start() -> void                 # 初始化 → 收盲注 → 发底牌 → 翻牌前下注轮 → run()
func run() -> void                   # 推进到挂起点或结束
func submit_human_action(action: Dictionary) -> bool  # 非法拒绝并保持挂起可重试
func pop_events() -> Array[Dictionary]
func is_waiting() -> bool            # waiting_seat >= 0
func is_finished() -> bool
func pot_size() -> int               # 全部 hand_total_bet 之和
```

`p_rig_seat >= 0` 时启用**简单模式洗牌**（`_rig_deck`）：正常洗牌后按真实发牌顺序（底牌座位序 + 之后 5 张公共牌）模拟整手布局，反复以派生种子（`base_seed + attempt`）重洗，直到该座位**假定摊牌全场唯一最强**——起手牌因此更强、公共牌更有利。上限 `RIG_MAX_ATTEMPTS = 100`（9 人局单次命中约 1/9，几乎必然成功），保底保留击败对手最多的一局。同 `base_seed` 下洗牌序列确定，存档恢复后可复现。

流程：HAND_START → **盲注静默扣除**（`_post_blind` 直接改筹码/下注，**不产生 PLAYER_ACTION 事件**；筹码不足按全下）→ 逐张发底牌（从小盲位起，DEAL_HOLE ×人数；单挑时按钮位下小盲、从按钮位发起）→ 四轮下注（每轮结束 ROUND_END，随后发公共牌事件）→ 摊牌（SHOWDOWN，公开全部未弃牌者手牌与牌型名）或提前判胜（仅剩一名未弃牌者，直接 POT_AWARD 不摊牌、牌型名为空串）→ PotManager 结算（POT_AWARD ×n）→ 淘汰检测（ELIMINATED ×n，**同手淘汰者按本手开始时筹码多少排名，多者名次靠前**，名次从本手开始时的存活数倒排）→ HAND_END。

人类回合：置 `waiting_seat` 并发 ACTION_REQUIRED 后挂起。AI 回合：同步调 `ai_decider.decide(ctx)`；**AI 产出非法动作属实现错误，降级为过牌/跟注/弃牌保底**（push_error）。决策上下文 ctx 键：`hole_cards, community, legal_actions, pot_size, call_amount, street, big_blind, chips, profile`。

### 3.8 Events（core/events.gd）

事件即 `{type, ...payload}` 的 Dictionary，统一用静态工厂构造保证字段名一致（15 种事件见第 4 章）。`static var DEFAULT_DEADLINE_MS := 30000`：人类行动倒计时，设置界面可改写（0=关闭）。**`action_required(seat, legal, deadline_ms := -1)` 用 -1 哨兵**：传负值取当前 DEFAULT_DEADLINE_MS（GDScript 默认参数必须是常量表达式，不能引用 static var）。

### 3.9 TournamentManager（core/tournament_manager.gd）

锦标赛调度 + 整体序列化。持有 `config / players / button_seat / blind_level / hands_played / hand_count_total / eliminated / finished` 与 `_rng`（`RandomNumberGenerator`）。

- `TournamentConfig`（内部类）：`starting_chips=1000`、`hands_per_level=10`、`blind_levels` 10 级表（10/20…200/400）、`easy_mode=false`（简单模式，洗牌偏向人类）；`blinds_at(level)` 超表后末级 × `1 << (level - 9)` 翻倍；`to_dict/from_dict`。
- `start_new(config, ai_count, rng_seed := 0)`：人类坐 0 号位（名字"你"、`avatar_human`）；AI 身份从 `AIProfiles.IDENTITIES` 洗牌抽取（不重复），风格按 `IDENTITY_PREFERRED_PROFILE` 配对；按钮位随机。开局即存档。
- `run_next_hand()`：`deck_seed := _rng.randi()`，以**同一手牌种子**构造 Deck 洗牌与 `AIDecider.new(deck_seed)`——存档恢复后决策序列可复现；`config.easy_mode` 时把人类座位作为 `rig_seat` 传入 HandController；执行一手并转发事件；手牌结束走 `_after_hand_end`。
- `_after_hand_end`：记录淘汰（按 ELIMINATED 事件顺序）→ 更新战绩（总手数、人类赢池、筹码峰值）→ 胜负判定（人类出局 → TOURNAMENT_LOSE{rank}；仅剩人类 → TOURNAMENT_WIN）→ 按钮移到下一存活座位 → 够手数则盲注升级（BLIND_UP）→ 战绩落盘 + 自动存档。`_tournament_end` 时 `save_manager.clear()` 清进度存档。
- 其余接口：`submit_human_action(action)` / `is_waiting_for_human()` / `pop_events()` / `alive_count()` / `human()` / `load_save() -> bool`（无存档或版本不匹配返回 false）/ `to_dict` / `from_dict`。

### 3.10 SaveManager（core/save_manager.gd）

`user://save/tournament.save`，JSON（tab 缩进，人可读）。`has_save() / load()（损坏返回 {}）/ save(data) / clear()`。路径可注入（测试/模拟用临时路径）。版本校验由 `TournamentManager.from_dict` 负责（`SAVE_VERSION = 1`）。

### 3.11 StatsManager（core/stats_manager.gd）

`user://save/stats.save`，JSON `{version, stats}`（`STATS_VERSION = 1`）。`data: StatsData` 字段：`games_played / wins / top3 / total_hands / pots_won / chip_peak / rank_distribution[9]`。构造时自动 load。`record_tournament_finish(rank, player_count)` 在锦标赛结束时由逻辑层调用；`total_hands / pots_won / chip_peak` 每手结束时增量更新并落盘。

### 3.12 AI（core/ai/ 三件）

- **AIProfiles**：4 组风格参数 `PROFILES`（`looseness / aggression / bluff_frequency`，数值见 GDD 4.1）；`IDENTITIES` 8 个固定身份（石头/疯子/老枪/秤砣/狐狸/鲨鱼/木头/浪人，各配 `avatar_*` id）；`IDENTITY_PREFERRED_PROFILE` 习惯配对；`get_profile(id)`。
- **HandStrength**（全静态）：`score(hole, community) -> float(0~1)` 按公共牌数量分流。翻牌前：启发式公式（对子 0.50~1.0；非对子按双高牌 + 同花/连张加成 − 断层扣分），覆盖全部 169 种起手归类，不用字面查表。翻牌后：成牌基础分（牌型映射 + 踢脚微调）+ 听牌出路 × 0.02（同花听 9、两头顺 8、卡顺 4，粗算不减重复牌）。
- **AIDecider**：`var rng` 按手牌种子播种（`_init(rng_seed := 0)`）。`decide(ctx) -> {type, amount}`：评分 → 风格调制（入局线 `0.55 − looseness×0.35`）→ 分档选动作（短筹码 < `SHORT_STACK_BB=8.0` 倍大盲触发全下倾向；强牌按激进度加注；跟注站弱牌爱跟便宜注，贵注线 `EXPENSIVE_CALL_RATIO=0.25`；加注金额 ½~1 池随机受激进度缩放）→ **`_clamp` 终点钳制**，返回值永远在 `legal_actions` 允许集合内。

---

## 4. 事件清单（core/events.gd）

| 事件 | 字段 | 说明 |
|---|---|---|
| HAND_START | hand_no, button_seat, sb, bb, alive_seats | 一手开始；alive_seats = 本手参与者座位快照 |
| DEAL_HOLE | seat, cards, status | 发底牌；**AI 的 cards 为 []（不公开）**，人类为 2 张；status 为发牌时状态快照 |
| ACTION_REQUIRED | seat, legal_actions, deadline_ms | 人类回合，**事件队列在此停住**等待提交 |
| PLAYER_ACTION | seat, action, amount, chips_left, status | 一次有效行动（**盲注无此事件**，UI 在 DEAL_HOLE 时顺带刷新筹码/下注显示）；status 为动作后状态快照 |
| DEAL_FLOP | cards(3) | 发翻牌（3 张一并给出） |
| DEAL_TURN / DEAL_RIVER | card | 转牌 / 河牌 |
| ROUND_END | pot | 本轮下注收拢后的底池总额 |
| SHOWDOWN | reveals: [{seat, cards, best, hand_name}] | 摊牌，公开全部未弃牌者；best 为 HandEvaluator.best_five 选出的最佳五张组合 |
| POT_AWARD | seat, amount, pot_index, hand_name | 收池（提前判胜时 hand_name 为空串） |
| ELIMINATED | seat, rank | 淘汰；rank 由 HandController 算好（同手按手始筹码排名） |
| BLIND_UP | level, sb, bb | 盲注升级 |
| HAND_END | — | 一手结束（此时已完成自动存档） |
| TOURNAMENT_WIN | — | 夺冠 |
| TOURNAMENT_LOSE | rank | 人类出局，rank 为人类名次 |

事件对象中的 `card`/`cards` 是 `Card` 实例（不是字符串），表现层直接取用。

---

## 5. 表现层

### 5.1 Main（ui/main.gd，场景路由器）

唯一常驻场景。`SCENES` 常量注册 5 个场景；`change_scene(name, params := {})`：释放当前场景、实例化新场景，params 非空且新场景实现 `setup(params)` 时调用之（结算界面靠它收名次表）。

**开局意图**由 Main 持有（避免新增全局单例）：`table_intent`（CONTINUE/NEW）、`table_ai_count`（默认 5）、`table_config`；`continue_tournament()` / `start_new_tournament(ai_count, config := null)`。TableScene 作为其子节点在 `_ready` 时读取。`--auto` 命令行参数：`_ready` 直达牌桌（无头冒烟回归入口）；否则进主菜单。

### 5.2 TableScene（ui/table_scene.gd，牌桌控制器）

持有 `tm` 与 `event_player`。`_ready`：读 `--auto`（置 `anim_enabled=false`）与动画速度（`ANIM_SPEED = GameSettings.anim_speed()`，标准 1.0/快速 0.5，全部 tween 时长乘此系数）；按路由意图 `tm.load_save()` 恢复或 `tm.start_new(...)` 新开（config 为空用 `GameSettings.make_config()`）；**--auto/独立运行时**兜底"有存档继续、否则默认 5 AI 新局"（常量 `AI_COUNT = 5`）。

场景结构（table.tscn）：`TableFelt`（桌布贴图）+ `SeatSlots/SeatSlot0..8`（9 个手摆 Marker2D，按参赛人数启用前 N 个实例化 SeatUI；0 号人类座位上移避开行动面板）+ `CommunitySlots/Slot0..4` + `DeckSlot`（发牌动画起点）+ `UILayer`（CanvasLayer：TopBar、MenuButton、StreetLabel、PotLabel、MessageLabel、BlindBanner、ActionPanel）。桌面中央下注区为常量 `POT_POS(640, 300)`。

**桌心信息布局**（`_style_center_labels`）：街名小字压公共牌正上方，底池金色 20 号字居中，消息条与盲注横幅为药丸底色块；**顶栏 TopBar 是 HBoxContainer，`_build_top_bar` 生成"级别 / 盲注 / 距升级"三枚胶囊徽章**，`_refresh_top_bar` 只更新文本。

**主循环** `_run_tournament()`：`while not tm.finished and not _exit_to_menu: tm.run_next_hand() → event_player.play_events(...) → await queue_drained`（本手按过"跳过本局"则再 `await skip_popup_confirmed` 等摘要弹窗确认）。**顶栏"主菜单"按钮只置 `_exit_to_menu` 标志位，在手牌边界生效切场景**（进度已自动保存；中途释放场景会打断本循环的 await）。--auto 下隐藏菜单按钮。

**跳过本局**（`_build_skip_button` / `_build_skip_popup`）：人类弃牌的 PLAYER_ACTION 后右下角显示"跳过本局"按钮（auto 不显示）；点击置 `_skip_active`、`anim_enabled=false`、`event_player.fast_forward=true`，本手剩余事件瞬间播完，HAND_END 恢复原节奏。期间各 `on_xxx` 把事件写入 `_skip_sections`（按街分节：`_street` 由 `_set_street` 维护、`_community_dealt` 由发牌事件累积，供节标题与摊牌节公共牌行使用）；主循环在 `queue_drained` 后若 `_skip_has_content()` 则弹摘要弹窗（RichTextLabel：节标题加粗、行间全角缩进、节间空行、收池金色/淘汰灰色），摊牌节用 reveal 的 `best` 字段展示各牌手最佳五张组合。点"继续下一局"emit `skip_popup_confirmed`。

**事件→UI 映射**（`on_xxx` 由 EventPlayer 逐一 await 调用）：A1 发牌飞行 / A2 公共牌翻面 / A3 筹码到池 / A4 筹码到座 / A5 摊牌翻面 / A6 座位高亮 / A7 淘汰淡出 / A8 盲注横幅，各自顺带触发 S1~S8 音效；DEAL_HOLE 时顺带刷新筹码与盲注下注显示（盲注无事件）。`on_action_required`：存 legal、高亮座位，`auto_play` 直接返回，否则 `_action_panel.show_for(legal, pot_size, deadline_ms, bb)`。`on_tournament_end`：auto 直接 `quit()`；否则 `_build_standings()` 算好名次表（冠军 = eliminated 之外的存活者，其余按 eliminated 倒序）随 params 切 result 场景。面板回调：玩家提交 → `event_player.deliver_human_action(action)`；**超时自动动作 = 可过牌则过牌否则弃牌**。`_spawn_chip(pos, amount)` 生成飞行筹码（按金额区间着色，见第 9 章）。

### 5.3 EventPlayer（ui/event_player.gd，动画编排）

事件队列 `_queue`；`play_events(events)` 入队并启动 `_drain()`：逐条 `await _dispatch(event)`，空了发 `queue_drained`。分发到 `table.on_xxx` 后按类型插入间隔（DELAY_SHORT 0.25 / NORMAL 0.45 / LONG 1.0 / HAND_END 0.8；auto 或 `fast_forward`（跳过本局）模式统一 0.03）。

- **A9 思考延迟在本层**：PLAYER_ACTION 分支，非 auto、非 fast_forward 且行动者是 AI 时先 `table.play_thinking(seat, randf_range(0.5, 1.5))` 再播行动动画。
- **ACTION_REQUIRED**：调 `table.on_action_required` 后停住——auto 模式 `_auto_choose`（能过牌则过牌、否则跟注、再不行弃牌）直接代打；正常模式 `await human_action` 信号。动作经 `tm.submit_human_action()` 提交，新事件入队继续。
- `deliver_human_action(action)` 是 TableScene 转交玩家输入的入口。

### 5.4 ActionPanel（ui/action_panel.gd）

信号 `action_submitted(action)` / `timed_out()`。`show_for(legal_actions, pot, deadline_ms, bb)`：按 legal 显隐按钮（过牌/跟注同钮按上下文换文字；`can_raise=false` 时加注按钮与滑条一起隐藏）；滑条 `setup(min_raise_to, max_raise_to, bb 作步进, pot)`；**`deadline_ms=0`（倒计时关闭）时隐藏进度条且 `_process` 不计时**。全下二次确认：首次点击"上膛"变为"确认全下？"。提交与上膛均播 S10。**按钮色阶分级（`_style_btn`，hover/pressed 由基准色推导）：弃牌暗红、过牌·跟注绿、加注金、全下正红**。

### 5.5 SeatUI / CardUI / RaiseSlider

- **SeatUI**（170px 宽 PanelContainer，角色卡布局）：56px 头像框（圆角描边 PanelContainer 包 TextureRect，`set_avatar` 按 `avatar_id` 加载，缺失连框隐藏不报错；**描边色预留作 RPG 职业/稀有度接口**）、信息列（庄家白色圆形 D 徽章、名字、状态标签（弃牌灰/全下！橙红/出局暗灰 + OUT 整体置灰 0.35）、筹码金色/本轮下注蓝色）、隐藏技能槽行（**RPG 预留，`set_skill_slots(n)` 显示 n 个空槽**）、两张 CardUI；A6 高亮金色边框呼吸循环 tween（切换时 kill 重建，节奏随行动重置属预期）；A9 省略号呼吸；`flip_reveal` 摊牌逐张翻面；`fade_out` 淘汰淡出。
- **CardUI**（56×80）：贴图优先、缺失降级色块+文字（红桃/方块红字）。`flip_to_card(card, dur)` 横向压扁→换面→展开（dur 为半程）。贴图带静态缓存 `_tex_cache`。
- **RaiseSlider**：滑条 + 金额标签 + 快捷按钮 ½池/¾池/1池（对齐步进、钳制范围）。

### 5.6 UITheme（ui/ui_theme.gd）

代码构建共享 `Theme`（炭黑暗底 + 高对比文字，金色只作焦点强调：滑条拖块/倒计时/输入聚焦），`UITheme.apply(root)` 应用到场景根（子控件继承），单例式构建一次。不使用 .tres 主题资源。

### 5.7 AudioManager（ui/audio_manager.gd，autoload 单例）

`SFX` 常量映射 10 个音效名（StringName）→ `assets/audio/*.ogg`（清单见 GDD 第 7 章）。`play(sfx)`：8 个 AudioStreamPlayer 轮询复用，流懒加载缓存；未知名称只 push_warning 不报错。`set_volume(linear 0~1)`：写 Master 总线（0 则 mute）并持久化到 settings.cfg `[audio] volume`；`get_volume()`。表现层任何音效失败都不允许崩溃。

### 5.8 --auto 模式行为汇总

`godot --headless --path . -- --auto`：直达牌桌；`anim_enabled=false` 跳过全部 tween 与 AI 思考延迟（**音效照常播放**，无头下无害）；人类回合由 EventPlayer 自动代打；事件间隔缩为 0.03s；锦标赛结束自动 `quit()`；菜单按钮隐藏。

---

## 6. 持久化

均在 `user://save/` 下。

### 6.1 锦标赛存档 tournament.save（JSON，SAVE_VERSION=1）

**只在手牌边界写**（每手结束与开局时 `_autosave`；锦标赛结束清除）。字段：

```json
{
  "version": 1,
  "config": {"starting_chips": 1000, "blind_levels": [[10,20],...], "hands_per_level": 10},
  "players": [{"seat_index","name","avatar_id","is_human","ai_profile","chips","status"}...],
  "button_seat": 0, "blind_level": 0, "hands_played": 0, "hand_count_total": 0,
  "eliminated": [seat_index...],
  "rng_state": "12345678901234567890"
}
```

- 手牌边界处存活者 status 必为 ACTIVE，淘汰者为 OUT，故不存手牌内状态（hole_cards/current_bet 等）。
- **`rng_state` 存字符串**：`_rng.state` 是 64 位整数，超出 JSON 数字精度；恢复时 `str(d.rng_state).to_int()` 写回。每手牌堆种子由该 RNG 即时产生，保存状态等价于保存"下一手种子"，恢复后牌序与 AI 决策序列均可复现。
- 版本不匹配 `from_dict` 返回 false（`load_save()` 视同无存档）。

### 6.2 战绩 stats.save（JSON，STATS_VERSION=1）

`{"version": 1, "stats": {games_played, wins, top3, total_hands, pots_won, chip_peak, rank_distribution[9]}}`。由逻辑层自动维护：每手结束增量更新（total_hands/pots_won/chip_peak）并落盘；锦标赛结束 `record_tournament_finish` 后落盘。战绩界面只读。

### 6.3 设置 settings.cfg（ConfigFile，即改即存）

GameSettings 与 AudioManager 共用一个文件、各管各的 section（写入前先 load 保留其他段）：

| section / 键 | 值 | 默认 | 读写方 |
|---|---|---|---|
| `audio` / `volume` | 线性 0.0~1.0 | 1.0 | AudioManager |
| `gameplay` / `deadline_ms` | 毫秒，**0 = 关闭倒计时** | 30000 | GameSettings（设置界面 5~120 秒或关） |
| `ui` / `anim_fast` | bool（快速=0.5 倍时长） | false | GameSettings |
| `blinds` / `starting_chips` | 100~100000 | 1000 | GameSettings，仅生效新锦标赛 |
| `blinds` / `hands_per_level` | 1~100 | 10 | GameSettings，仅生效新锦标赛 |
| `display` / `fullscreen` | bool | false | GameSettings，启动时应用，F11 全局切换 |
| `gameplay` / `difficulty` | int（0=默认 1=简单） | 0 | GameSettings，仅生效新锦标赛（经 `make_config()` 写入 `easy_mode`） |

GameSettings 静态接口：`apply_runtime()`（启动时把 deadline 写入 `Events.DEFAULT_DEADLINE_MS`、应用全屏窗口模式）、`get/set_deadline_ms`、`is/set_anim_fast`、`anim_speed()`、`is/set_fullscreen`、`get/set_difficulty`、`is_easy_mode`、`get_starting_chips`、`get_hands_per_level`、`set_blind_params`（clamp 双保险）、`make_config()`（按设置构造 TournamentConfig，blind_levels 表沿用默认，附带 `easy_mode`）。

---

## 7. 测试与验证

### 7.1 命令（Windows，引擎路径按本机实际）

```bash
# 首次或新增 class_name 文件后：先生成全局类缓存（否则报 "Could not find type"）
godot --headless --path . --import
# 单元测试：7 个套件共 435 项断言，失败 quit(1)
godot --headless --path . --script tests/run_tests.gd
# 全 AI 批量模拟：默认 100 场（8 AI），逐手校验筹码守恒，输出统计
godot --headless --path . --script tests/simulate.gd -- [场数] [起始种子]
# UI 全链路无头冒烟：自动代打打完整场后自动退出
godot --headless --path . -- --auto
```

断言分布：test_deck + test_hand_evaluator 42；test_betting_round + test_pot_manager 99；test_hand_controller 37；test_tournament + test_save_load 257，合计 435。模拟 100 场 0 失败（含筹码守恒、盲注升级覆盖）。

### 7.2 测试基建

`run_tests.gd`（extends SceneTree）顺序跑 7 个 suite 的所有 `test_` 方法并计数。`test_base.gd` 提供断言计数（`check/expect_eq`）、`cards("As Kd")` 牌例构造、`rigged_deck` 确定牌序、`drive_hand/drive_waiting` 脚本驱动挂起的手牌/锦标赛。不引入第三方测试框架。

### 7.3 已知陷阱（踩过的坑）

- **`class_name` 全局类依赖 `.godot/global_script_class_cache.cfg`**：新增后必须先 `--import` 一次，否则 parse 报 "Could not find type"。
- **Variant 推断陷阱**：Dictionary 取值（如 `legal.min_raise_to`）与 `event.type == X` 的比较结果都是 Variant，`var x :=` 推断会 parse error，需显式标类型。
- **默认参数必须是常量表达式**：不能引用 static var（`Events.action_required` 用 -1 哨兵绕过）。
- **`--script` 的 SceneTree 脚本里用不了自动加载单例标识符**（编译期找不到 AudioManager）；且 `_init` 中 add_child 不会立即触发 `_ready`。测单例行为需在真实游戏运行中验证。
- **无头模式下场景脚本 parse 失败引擎不会自行退出**，会挂到超时——冒烟卡住先查 parse 错误。
- BettingRound 测试中 3 条 `push_error` 是"非法动作被拒绝"用例的**预期输出**，非失败。
- MCP `run_project` 无法执行 `--script` 测试脚本，测试统一走命令行。
- 本机引擎 4.6.2、项目标记 4.7；逻辑层无版本敏感特性。换 4.7 正式跑需回归。
- 项目根不是 git 仓库，改动无版本控制兜底。

---

## 8. 关键实现决策

仍有效的核心决策（逐条 + 理由）：

1. **逻辑/表现分离 + 事件队列 + 动作提交制（禁止 await 等输入）**：保证逻辑层任意时刻可序列化、可无头单测，动画时序永不干扰规则。
2. **只在手牌边界存档**：恢复点语义简单（中途退出重打一手），HandController 无需支持手牌中序列化。
3. **存档保存 `_rng.state` 字符串而非"下一手种子"**：等价且更简单；64 位状态超 JSON 数字精度故序列化为字符串。
4. **AI 决策器按手牌种子播种**（`AIDecider.new(deck_seed)`，与牌堆同种子）：存档恢复后继续打的决策序列与原运行完全一致。
5. **盲注静默扣除、不发 PLAYER_ACTION 事件**：发底牌事件是首个座位刷新时机，UI 在 DEAL_HOLE 顺带刷新，省掉无信息量的事件类型。
6. **合法动作集合与状态机判定严格一致**（`can_raise` / `can_all_in` 含不足额全下封锁语义）：UI 直接依赖它显隐按钮，AI 也不会产出被拒动作。
7. **BettingRound 不自己下盲注**：构造器无法推断盲注结构（单挑规则不同），由 HandController 预先计入 `current_bet`。
8. **同手多名淘汰者按本手开始时筹码排名**：确定性与公平性；rank 由 HandController 算好，TournamentManager 只按事件顺序记录。
9. **PotManager.settle 签名带 `community` 与 `button_seat`**：比牌输入与余数分配顺序缺一不可。
10. **不切牌（burn card）**：单机对 AI 无作弊问题，省掉无信息量的状态。
11. **翻牌前起手强度用启发式公式代替 169 项查表**：全覆盖且参数可微调。
12. **开局意图由 Main 持有、路由 params → `setup(params)`**：避免新增全局单例，路由与开局解耦。
13. **设置即改即存 + SpinBox 范围与写入 clamp 双保险**：非法值不可能落盘，省掉确认交互；盲注参数只生效新锦标赛，进行中的不被半路改。
14. **名次表由 TableScene 算好传入结算场景**（冠军 = eliminated 外存活者，其余按淘汰倒序）：table 侧有 tm 上下文；A10 彩带随之落在结算界面。
15. **UI 主题代码构建（UITheme.apply）、座位槽位编辑器手摆 Marker2D**：跟随组件代码构建惯例，免维护二进制主题资源与运行时椭圆计算。
16. **--auto 模式动画跳过、音效保留**：无头冒烟需快速跑完，音效无害且能顺带验证加载。
17. **素材与降级策略**：扑克牌用 playing-cards-assets（MIT，原 Kenney 像素牌 42×60 放大模糊已弃用）、音效用 Kenney CC0 包；空槽位框等少数贴图程序化自生成，头像/筹码/背景/奖杯/UI 贴图（庄家按钮、彩带、Logo、牌背）均为 Blender 无头渲染（脚本 `tools/blender/`，色调/图形自原程序化版提取或对齐）；飞行筹码按金额区间着色不印面值（28px 不可读，金额由座位标签显示）；贴图/音效缺失一律降级不报错（色块占位、push_warning），表现层不允许因素材问题崩溃。
18. **事件携带状态快照（alive_seats / status），UI 不读实时 PlayerState 状态**：整手牌同步跑完后事件才逐条回放，被淘汰者的实时 status 已是 OUT；若 UI 读实时状态，全下（或将淘汰）的玩家会从手牌开始就被显示成"出局"。
19. **简单模式用"假定摊牌必胜"重洗实现，而非改 AI 或改赔率**：只动牌堆顺序，规则/结算/事件零侵入；派生种子（`base_seed + attempt`）保证同种子可复现，存档语义不受影响；难度随 TournamentConfig 快照，进行中锦标赛不被半路改。

---

## 9. 素材映射

### 9.1 扑克牌（ui/card_ui.gd `_face_path`）

```
res://assets/cards/card_<花色>_<点数>.png
花色：spades / hearts / clubs / diamonds（对应 Card.suit 0~3）
点数：02~09 补零；T→10；J/Q/K/A 直用
特殊：card_back.png（牌背）、card_empty.png（空槽位框）
```

源素材为 hayeah/playing-cards-assets（MIT，图案源自 Byron Knoll 公有领域矢量牌）222×323 高分辨率 PNG；原图只有图案层无牌身，已垫白底圆角牌身（圆角半径 12）；牌背 314×476 为本项目 Blender 渲染版（白边 + 蓝底白菱格 + 圆角透明，色调采样自原改色版，脚本 `tools/blender/build_cardback_logo.py`）；空槽位框程序化生成；显示尺寸 `CardUI.SIZE = 56×80`。许可证 `assets/cards/LICENSE-playing-cards-assets.txt`。

### 9.2 头像（core/ai/ai_profiles.gd → ui/seat_ui.gd）

`avatar_id` → `res://assets/avatars/<avatar_id>.png`（128×128 卡通人物头像，DiceBear adventurer 风格，CC-BY 4.0，背景色沿用原身份配色）。对应关系：`avatar_human`=你；`avatar_rock`=石头、`avatar_maniac`=疯子、`avatar_veteran`=老枪、`avatar_anchor`=秤砣、`avatar_fox`=狐狸、`avatar_shark`=鲨鱼、`avatar_block`=木头、`avatar_drifter`=浪人。

### 9.3 筹码（ui/table_scene.gd `_chip_texture`）

`res://assets/chips/chip_<档>.png`（256×256 顶视，Blender 渲染；`_tilt` 45° 斜视版用于下注/收池飞行动画，缺失回落顶视版），飞行筹码按金额区间选档：**chip_white <100、chip_red <500、chip_blue <1000、chip_black ≥1000**；文件缺失降级为金色圆块。座位前的下注额始终是文字标签，不堆筹码。

### 9.4 背景与音效

- `assets/bg/table_felt.png`（1280×720 桌布，table.tscn）、`assets/bg/menu_bg.png`（主菜单/设置/结算/战绩共用），均为 Blender 无头渲染（脚本 `tools/blender/`，色调对齐原程序化版深绿配色）；`assets/trophy/trophy.png`（512×512 带 alpha 金奖杯，result_ui 夺冠标题）与 `assets/trophy/spin/`（16 帧 360° 旋转序列，夺冠时 12fps 循环播放）同为 Blender 渲染；`assets/ui/`（dealer_puck 庄家徽章、confetti_01~04 彩带贴图、logo 主菜单金字标题）亦为 Blender 渲染，各处缺失均有降级路径。
- 音效名 → 文件映射见 `AudioManager.SFX`（10 项，GDD 第 7 章）；原始出处（Kenney Casino Audio 1.1 / Interface Sounds，CC0，经 OpenGameArt 镜像）与逐文件对照见 `assets/audio/SOURCES.md`，许可证 `assets/audio/Kenney-License.txt`。
- 全部素材的来源与生成方式记录在 `assets/SOURCES.md` 与 `assets/audio/SOURCES.md`，替换素材时同步更新这两份清单。
