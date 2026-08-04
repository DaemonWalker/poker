extends "res://tests/test_base.gd"
## AIMemory 情绪系统与 tilt 决策调制的单元测试。

const TEST_SAVE := "user://save/test_ai_mem.save"
const TEST_STATS := "user://save/test_ai_mem_stats.save"


# ---- AIMemory 更新规则 ----

## 小输（低于大锅阈值）不触发 tilt
func test_small_loss_no_tilt() -> void:
	var m := AIMemory.new()
	m.notify_hand_result(-100, 1000, 20, 0.9, 0.0)  # 10% 筹码 < 20% 阈值
	expect_eq(m.tilt_level, 0.0, "小输不触发 tilt")
	expect_eq(m.last_big_loss, 0, "小输不记录大锅")


## 大输触发 tilt，涨幅随 sensitivity 单调
func test_big_loss_triggers_tilt() -> void:
	var low := AIMemory.new()
	var high := AIMemory.new()
	low.notify_hand_result(-300, 1000, 20, 0.3, 0.0)
	high.notify_hand_result(-300, 1000, 20, 0.9, 0.0)
	check(low.tilt_level > 0.0, "大输触发 tilt")
	check(high.tilt_level > low.tilt_level, "高 sensitivity 涨幅更大")
	expect_eq(high.last_big_loss, 300, "记录大锅损失额")


## 深筹码时 15BB 阈值比 20% 筹码比例更紧
func test_deep_stack_bb_threshold() -> void:
	var m := AIMemory.new()
	m.notify_hand_result(-400, 10000, 20, 1.0, 0.0)  # 400=20BB ≥ 15BB，但仅 4% 筹码
	check(m.tilt_level > 0.0, "深筹码按 15BB 阈值触发")


## tilt 每手自然衰减，recovery 越高衰减越快；赢牌不涨 tilt
func test_tilt_decay() -> void:
	var fast := AIMemory.new()
	var slow := AIMemory.new()
	fast.tilt_level = 0.8
	slow.tilt_level = 0.8
	fast.notify_hand_result(100, 1000, 20, 0.5, 1.0)
	slow.notify_hand_result(100, 1000, 20, 0.5, 0.2)
	check(fast.tilt_level < 0.8 and slow.tilt_level < 0.8, "无大输时 tilt 自然衰减")
	check(fast.tilt_level < slow.tilt_level, "高 recovery 衰减更快")


## tilt 上限钳制到 1
func test_tilt_clamped() -> void:
	var m := AIMemory.new()
	m.notify_hand_result(-1000, 1000, 20, 1.0, 0.0)  # 输掉全部筹码
	check(m.tilt_level <= 1.0, "tilt 不超过 1：%f" % m.tilt_level)


## memory 序列化往返（含对手统计）
func test_memory_serialization() -> void:
	var m := AIMemory.new()
	m.tilt_level = 0.6
	m.last_big_loss = 500
	m.opponent_stats["hands_seen"] = 12
	m.opponent_stats["vpip"] = 0.62
	m.opponent_stats["pfr"] = 0.31
	m.opponent_stats["aggression"] = 0.55
	m.opponent_stats["showdown_strength"] = 0.42
	var m2 := AIMemory.new()
	m2.from_dict(m.to_dict())
	expect_eq(m2.tilt_level, 0.6, "tilt 序列化往返")
	expect_eq(m2.last_big_loss, 500, "损失额序列化往返")
	expect_eq(int(m2.opponent_stats["hands_seen"]), 12, "对手手数序列化往返")
	expect_eq(m2.opponent_stats["vpip"], 0.62, "vpip 序列化往返")
	expect_eq(m2.opponent_stats["pfr"], 0.31, "pfr 序列化往返")
	expect_eq(m2.opponent_stats["aggression"], 0.55, "aggression 序列化往返")
	expect_eq(m2.opponent_stats["showdown_strength"], 0.42, "showdown 序列化往返")

	# 旧格式（无 opponent_stats 字段）按基准初值回填
	var m3 := AIMemory.new()
	m3.from_dict({"tilt_level": 0.3, "last_big_loss": 100})
	expect_eq(m3.tilt_level, 0.3, "旧格式 tilt 正常恢复")
	expect_eq(int(m3.opponent_stats["hands_seen"]), 0, "旧格式对手统计回默认")


# ---- tilt 对决策的调制 ----

## 构造一个弱牌面对小注的决策上下文（7♠2♦ 评分 ≈0.24，
## 介于疯子上头入局阈值 0.20 与平时阈值 0.27 之间）
static func _weak_hand_ctx(mem: AIMemory) -> Dictionary:
	var community: Array[Card] = []
	return {
		"hole_cards": cards("7s 2d"), "community": community,
		"legal_actions": {"can_check": false, "can_call": true, "call_amount": 50,
				"can_raise": true, "min_raise_to": 100, "max_raise_to": 1000, "can_all_in": true},
		"pot_size": 100, "call_amount": 50, "street": HandController.Street.PREFLOP,
		"big_blind": 20, "chips": 2000, "profile": "疯子",
		"position": 0.0, "active_opponents": 1, "memory": mem,
	}


## tilt=0 的 memory 与无 memory 决策完全等价（同种子同动作序列）
func test_zero_tilt_equivalent_to_no_memory() -> void:
	var d1 := AIDecider.new(42)
	var d2 := AIDecider.new(42)
	var a1: Dictionary = d1.decide(_weak_hand_ctx(null))
	var a2: Dictionary = d2.decide(_weak_hand_ctx(AIMemory.new()))
	expect_eq(a1.get("type"), a2.get("type"), "tilt=0 决策类型一致")
	expect_eq(a1.get("amount", 0), a2.get("amount", 0), "tilt=0 决策金额一致")


## 疯子上头（tilt=1）后弱牌跟注率显著升高（有效松度↑ → 入局阈值↓）
func test_tilt_loosens_maniac() -> void:
	var base_calls := 0
	var tilt_calls := 0
	var trials := 200
	for seed in range(1, trials + 1):
		var tilted := AIMemory.new()
		tilted.tilt_level = 1.0
		if AIDecider.new(seed).decide(_weak_hand_ctx(null)).get("type") == BettingRound.ActionType.CALL:
			base_calls += 1
		if AIDecider.new(seed).decide(_weak_hand_ctx(tilted)).get("type") == BettingRound.ActionType.CALL:
			tilt_calls += 1
	var base_rate := float(base_calls) / trials
	var tilt_rate := float(tilt_calls) / trials
	check(tilt_rate > base_rate + 0.3, "上头等注率 %.2f 应显著高于平时 %.2f" % [tilt_rate, base_rate])


## 决策只读 memory：decide 不修改 tilt
func test_decide_does_not_mutate_memory() -> void:
	var mem := AIMemory.new()
	mem.tilt_level = 0.5
	var d := AIDecider.new(7)
	for _i in 5:
		d.decide(_weak_hand_ctx(mem))
	expect_eq(mem.tilt_level, 0.5, "决策后 tilt 不变")


# ---- 对手调制的一期等价性（回归安全网） ----

## 样本为 0（hands_seen=0 的全新 memory）：高 adaptability 身份的决策与无 memory 逐比特一致
func test_zero_sample_equivalent_to_no_memory() -> void:
	for seed in range(1, 51):
		var c1 := _weak_hand_ctx(null)
		c1["profile"] = "老枪"  # adaptability=0.90，全场最高
		var c2 := _weak_hand_ctx(AIMemory.new())
		c2["profile"] = "老枪"
		var a1: Dictionary = AIDecider.new(seed).decide(c1)
		var a2: Dictionary = AIDecider.new(seed).decide(c2)
		expect_eq(a1.get("type"), a2.get("type"), "seed %d：零样本决策类型一致" % seed)
		expect_eq(a1.get("amount", 0), a2.get("amount", 0), "seed %d：零样本决策金额一致" % seed)


## adaptability=0：满载对手统计也不影响决策（逐比特等价一期）
func test_zero_adaptability_equivalent() -> void:
	var prof: Dictionary = AIProfiles.get_profile("老枪").duplicate()
	prof["adaptability"] = 0.0
	var loaded := AIMemory.new()
	loaded.opponent_stats["hands_seen"] = 50
	loaded.opponent_stats["vpip"] = 0.9
	loaded.opponent_stats["pfr"] = 0.8
	loaded.opponent_stats["aggression"] = 0.05
	loaded.opponent_stats["showdown_strength"] = 0.1
	for seed in range(1, 51):
		var c1 := _weak_hand_ctx(null)
		c1["profile"] = prof
		var c2 := _weak_hand_ctx(loaded)
		c2["profile"] = prof
		var a1: Dictionary = AIDecider.new(seed).decide(c1)
		var a2: Dictionary = AIDecider.new(seed).decide(c2)
		expect_eq(a1.get("type"), a2.get("type"), "seed %d：adaptability=0 决策类型一致" % seed)
		expect_eq(a1.get("amount", 0), a2.get("amount", 0), "seed %d：adaptability=0 决策金额一致" % seed)


# ---- 锦标赛存档集成 ----

## ai_memory 随锦标赛序列化（SAVE_VERSION 3），旧版本存档被拒绝
func test_tournament_memory_serialization() -> void:
	var tm := TournamentManager.new(SaveManager.new(TEST_SAVE), StatsManager.new(TEST_STATS))
	tm.start_new(TournamentManager.TournamentConfig.default(), 2, 99)
	tm.ai_memories[1].tilt_level = 0.7
	tm.ai_memories[2].last_big_loss = 300
	tm.ai_memories[2].opponent_stats["hands_seen"] = 9
	tm.ai_memories[2].opponent_stats["vpip"] = 0.55

	var tm2 := TournamentManager.new(SaveManager.new(TEST_SAVE), StatsManager.new(TEST_STATS))
	check(tm2.from_dict(tm.to_dict()), "v3 存档可恢复")
	expect_eq(tm2.ai_memories[1].tilt_level, 0.7, "tilt 随锦标赛存档往返")
	expect_eq(tm2.ai_memories[2].last_big_loss, 300, "损失额随锦标赛存档往返")
	expect_eq(int(tm2.ai_memories[2].opponent_stats["hands_seen"]), 9, "对手手数随锦标赛存档往返")
	expect_eq(float(tm2.ai_memories[2].opponent_stats["vpip"]), 0.55, "vpip 随锦标赛存档往返")

	var old := tm.to_dict()
	old["version"] = 2
	var tm3 := TournamentManager.new(SaveManager.new(TEST_SAVE), StatsManager.new(TEST_STATS))
	check(not tm3.from_dict(old), "v2 旧存档被拒绝")

	SaveManager.new(TEST_SAVE).clear()
	SaveManager.new(TEST_STATS).clear()
