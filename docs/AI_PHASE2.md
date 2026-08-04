# AI 第二期：对手建模（学习能力）实施指南

> **状态：已完成并合入**（本文件保留作实施记录；现状以 `docs/TECH_DESIGN.md` §3.12 与 §6.1 为准）。
> 交接文档：供新对话直接开工。一期背景见 `docs/TECH_DESIGN.md` §3.12，项目约定见 `AGENTS.md`。
> 一期提交：`953eb19 feat: AI 独立参数表 + 情绪(tilt)系统与 emoji 气泡可视化`。

## 1. 目标

在现有 AI 体系上加**对手建模**：AI 统计人类玩家的行为特征（入局率、加注率、摊牌牌力），
按各自身份的 `adaptability` 参数自我调制打法。让玩家感到"AI 在针对我调整"，这是第二期唯一目标。

## 2. 一期现状（已合入，勿重复建设）

- `core/ai/ai_profiles.gd`：8 身份 × 10 参数（静态风格 6 + 情绪规则 4），键 = 身份名。
- `core/ai/ai_memory.gd`：每 AI 一份跨手存活状态，现有 `tilt_level / last_big_loss`，
  只在手牌边界由 `TournamentManager._after_hand_end` 更新，随锦标赛存档序列化（SAVE_VERSION=2）。
- `core/ai/ai_decider.gd`：`decide(ctx)` 无状态；有效参数 = 静态 + tilt×方向，末尾 `_clamp` 钳制。
- ctx 现有键：`hole_cards, community, legal_actions, pot_size, call_amount, street, big_blind, chips,
  profile, position, active_opponents, memory`。
- UI 侧：tilt emoji 气泡（`SeatUI.set_tilt`）演示了"AI 内部状态 → 只读展示"的模式，二期可复用。

## 3. 设计方案

### 3.1 新增参数（AIProfiles 每身份 +1 项）

```
adaptability: 0~1   # 对手调制幅度系数；0 = 完全不学习（等价一期行为）
```

建议初值：老枪 .90 / 鲨鱼 .85 / 狐狸 .80 / 浪人 .50 / 石头 .40 / 秤砣 .30 / 疯子 .20 / 木头 .10。
（"会读人"的 AI 适应性强；疯子只顾自己打，木头一根筋。）

### 3.2 统计什么（先只对人类玩家建模）

存在 `AIMemory.opponent_stats` 中，全部用**指数衰减平均**（EWMA，α ≈ 0.15），天然近期加权、无需存历史：

| 统计量 | 含义 | 数据来源（事件流） |
|---|---|---|
| `vpip` | 主动入池率（翻牌前 call/raise 占比） | HAND_START 计数分母；PLAYER_ACTION(call/raise/all_in) 且 street=翻牌前 计数分子 |
| `pfr` | 翻牌前加注率 | 同上，仅 raise/all_in |
| `aggression` | 翻牌后攻击性（raise 数 / (raise+call)） | PLAYER_ACTION 按 street 分类 |
| `showdown_strength` | 摊牌平均牌力（0~1，HandStrength 口径） | SHOWDOWN 事件的 reveals（人类座位） |

**关键：数据从事件流解析，不改 HandController**。`TournamentManager._after_hand_end(hand_events)`
已经拿到整手事件数组，在这里逐条解析喂给每个 AI 的 memory（只统计人类座位 0 的行为）。
注意红线：盲注静默扣除无 PLAYER_ACTION 事件——BB 白看牌不算入局，SB 补盲算 call 入局（跟注即算）。

### 3.3 怎么调制（decide 内，叠在 tilt 调制之后）

`decide(ctx)` 读 `ctx.memory.opponent_stats`，按 `adaptability` 缩放生成第三层偏移：

```
对手松（vpip 高）  → 自己入局阈值上调（收紧等他撞）、诈唬频率下调（他爱跟，别诈）
对手紧（vpip 低）  → 诈唬频率上调（多偷池）
对手被动（aggr 低）→ 自己加注倾向上调（多施压）
对手摊牌偏弱      → 面对其加注时跟注倾向上调（他可能在诈）
```

每条偏移量 = `adaptability × 统计量偏离基准的程度 × 系数`，基准取理论均值（vpip≈0.3、pfr≈0.15、aggr≈0.4、
摊牌强度≈0.5）。样本不足（手数 < 10）时按完成度线性缩放，避免开局乱调。

### 3.4 不变量（务必守住）

- `adaptability = 0` 或样本为 0 时行为与一期**逐比特一致**（回归安全网，对应测试断言）。
- memory 仍只在手牌边界更新；决策期只读；随存档序列化（`to_dict/from_dict` 扩展，
  **SAVE_VERSION 升 3**，旧档拒收走新开局，不做迁移）。
- rng 仍只用 `AIDecider` 按手牌种子播种的那个，统计与调制都是确定性的，simulate 可复现。

## 4. 实施步骤（文件级）

1. `core/ai/ai_profiles.gd`：8 张参数表各加 `adaptability`。
2. `core/ai/ai_memory.gd`：加 `opponent_stats: Dictionary`（上表 4 项 + `hands_seen` 计数）、
   `notify_opponent_hand(events 解析结果)` 更新方法与序列化扩展。
3. `core/tournament_manager.gd`：`_after_hand_end` 里新增事件解析段（纯函数可抽到
   `core/ai/opponent_tracker.gd`，便于单测），把结果喂给每个 AI 的 memory。
4. `core/ai/ai_decider.gd`：tilt 调制后叠加对手调制（3.3），全部走既有 `_clamp`。
5. 测试：`tests/test_opponent_tracker.gd`（事件→统计的正确性、EWMA 衰减、样本不足缩放）+
   `tests/test_ai_memory.gd` 扩充（序列化往返、adaptability=0 等价一期）。
6. 回归三件套（AGENTS.md）：`--import` → `run_tests.gd` → `simulate.gd -- 100 1` → `-- --auto`。
7. 文档：TECH_DESIGN §3.12 与 §6.1（存档格式 v3）、GDD §4.1、README/AGENTS 断言数。

## 5. 常见坑（一期踩过，直接复用结论）

- Dictionary 取值是 Variant：`var x := e.amount` 会 parse error，必须显式标类型（`var t: int = e.type`）。
- 事件回放时整手已跑完，读 `PlayerState` 拿到的是终局值；统计只用事件快照，不读实时状态。
- 无头模式下场景脚本 parse 失败会挂到超时——先看输出里的 SCRIPT ERROR。
- 新增 class_name 后先 `godot --headless --path . --import` 再跑测试。
- Godot 可执行文件不在 PATH：`E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`。

## 6. 验收标准

- 单测全绿且新增覆盖：统计正确性、调制方向（松对手→AI 变紧等四条）、adaptability=0 等价一期。
- `simulate.gd -- 100 1` 筹码守恒 0 失败；`--auto` 0 报错。
- 行为可感知：用一个固定"很松"或"很紧"的打法脚本代打人类座位跑 20+ 手，
  高 adaptability 的 AI（老枪/鲨鱼）入局率/诈唬率应出现方向性漂移（可写一次性诊断脚本验证后删除）。

## 7. 范围外（别顺手做）

- AI 之间的相互建模（先只对人类）；跨锦标赛长期学习（不进 stats.save）；
  蒙特卡洛牌力模拟（GDD 第 10 章候选，独立排期）。
