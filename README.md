# 德州扑克（poker）

单机德州扑克锦标赛游戏：与 8 个风格各异的 AI 同桌竞技，无限注（No-Limit）规则、盲注递增、淘汰制，淘汰所有对手夺得冠军。

- 引擎：Godot 4.x（目标 4.7，开发测试用 4.6.2）/ GDScript / 2D
- 平台：Windows 桌面，1280×720，全中文界面
- 开发状态：**全部里程碑（M1~M8）已完成**，产品流程闭环可用

## 功能一览

- 完整德州扑克规则：无限注、标准牌型排序、边池计算、四轮下注
- 锦标赛模式：固定买入、10 级盲注递增（超表翻倍）、淘汰排名
- 8 个固定身份 AI（4 种打法风格：紧凶/松凶/保守/跟注站），带思考节奏
- 完整外围流程：主菜单 → 新建/继续锦标赛 → 牌桌 → 结算名次表 → 战绩统计 → 再来一局
- 设置：音量、行动倒计时（可关）、动画速度、盲注参数（起始筹码/每级手数）
- 持久化：手牌边界自动存档（可中途退出续玩）、生涯战绩统计、设置持久化
- 表现力：发牌/翻牌/筹码/收池/淘汰/夺冠彩带等 10 组动画 + 10 组音效

## 运行

```bash
# 编辑器打开或直接运行（主场景 scenes/main.tscn，启动进主菜单）
godot --path .

# 无头自动演示（AI 代打完整场后自动退出，冒烟回归用）
godot --headless --path . -- --auto

# 逻辑层单元测试（435 项断言）
godot --headless --path . --script tests/run_tests.gd

# 全 AI 批量锦标赛模拟（筹码守恒校验，默认 100 场）
godot --headless --path . --script tests/simulate.gd -- [场数] [起始种子]
```

> 新增 `class_name` 脚本或新资源后，先跑一次 `godot --headless --path . --import` 再运行/测试。

## 目录结构

```
core/       逻辑层（纯 RefCounted，可无头单测）：规则/下注/边池/AI/锦标赛/存档/战绩
core/ai/    AI 决策器、牌力启发式评分、风格与身份预设
ui/         表现层脚本：路由、牌桌、组件（座位/卡牌/操作面板）、设置、主题、音频
scenes/     场景：main（路由器）、main_menu、table、result、stats、settings
assets/     素材：cards（Kenney，CC0）、avatars/chips/bg（程序化生成）、audio（CC0 音效）
tests/      逻辑层无头单元测试与批量模拟
docs/       文档（见下）
```

## 文档导航

| 文档 | 内容 |
|---|---|
| `docs/GDD.md` | 游戏规则：玩法、锦标赛规则、AI 设计、界面操作、动画音效清单、存档战绩 |
| `docs/TECH_DESIGN.md` | 技术文档：架构、模块职责、事件清单、持久化格式、测试命令、关键实现决策、素材映射 |
| `AGENTS.md` | 给 AI 助手的快速上手指南：命令、约定、陷阱 |
| `assets/SOURCES.md` / `assets/audio/SOURCES.md` | 素材来源与许可证（CC0） |

## 素材与许可证

扑克牌贴图来自 Kenney Playing Cards Pack（CC0）；音效来自 Kenney Casino Audio / Interface Sounds（CC0，经 OpenGameArt 镜像）；头像、筹码、桌布、背景为程序化生成（无版权问题）。明细见 `assets/SOURCES.md`。
