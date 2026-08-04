extends "res://tests/test_base.gd"
## OpponentTracker 事件解析、AIMemory 对手统计 EWMA、AIDecider 对手调制方向的单元测试。

const TEST_SAVE := "user://save/test_opp_track.save"
const TEST_STATS := "user://save/test_opp_track_stats.save"


# ---- 事件 → 统计增量解析 ----

## 翻牌前 call/raise/all_in 算主动入局；check/fold 不算；raise/all_in 另计 pfr
func test_parse_vpip_pfr() -> void:
	var start := Events.hand_start(1, 1, 10, 20, [0, 1])
	var cases := [
		[BettingRound.ActionType.CALL, true, false],
		[BettingRound.ActionType.RAISE, true, true],
		[BettingRound.ActionType.ALL_IN, true, true],
		[BettingRound.ActionType.CHECK, false, false],
		[BettingRound.ActionType.FOLD, false, false],
	]
	for c in cases:
		var ev: Array = [start, Events.player_action(0, c[0], 20, 980), Events.hand_end()]
		var inc := OpponentTracker.parse_hand(ev, 0)
		expect_eq(inc["hands"], 1, "action %d：参与本手" % c[0])
		expect_eq(inc["vpip"], c[1], "action %d 的 vpip" % c[0])
		expect_eq(inc["pfr"], c[2], "action %d 的 pfr" % c[0])


## 座位不在 alive_seats 中 → hands=0，不进入统计
func test_parse_not_in_hand() -> void:
	var ev: Array = [Events.hand_start(1, 1, 10, 20, [1, 2]), Events.hand_end()]
	var inc := OpponentTracker.parse_hand(ev, 0)
	expect_eq(inc["hands"], 0, "未参与 hands=0")
	expect_eq(inc["vpip"], false, "未参与 vpip=false")


## 按 street 分类：翻牌后动作不进 vpip/pfr；攻击性 = raise/(raise+call)
func test_parse_postflop_aggression() -> void:
	var ev: Array = [
		Events.hand_start(1, 1, 10, 20, [0, 1]),
		Events.player_action(0, BettingRound.ActionType.CALL, 20, 980),
		Events.deal_flop(cards("2s 3h 4d")),
		Events.player_action(0, BettingRound.ActionType.CALL, 40, 940),
		Events.player_action(0, BettingRound.ActionType.RAISE, 120, 860),
		Events.hand_end(),
	]
	var inc := OpponentTracker.parse_hand(ev, 0)
	expect_eq(inc["vpip"], true, "翻牌前 call 入局")
	expect_eq(inc["pfr"], false, "翻牌后 raise 不计 pfr")
	expect_eq(inc["aggression"], 0.5, "翻牌后 1 raise / (1 raise + 1 call)")


## 翻牌后无 call/raise（只过牌）→ aggression 为 null（本手无样本）
func test_parse_aggression_null_without_sample() -> void:
	var ev: Array = [
		Events.hand_start(1, 1, 10, 20, [0, 1]),
		Events.player_action(0, BettingRound.ActionType.CALL, 20, 980),
		Events.deal_flop(cards("2s 3h 4d")),
		Events.player_action(0, BettingRound.ActionType.CHECK, 0, 980),
		Events.hand_end(),
	]
	var inc := OpponentTracker.parse_hand(ev, 0)
	expect_eq(inc["aggression"], null, "无翻牌后 call/raise 时 aggression=null")
	expect_eq(inc["showdown"], null, "未摊牌时 showdown=null")


## 摊牌牌力按 HandStrength 口径（hole + 事件流累积的 5 张公共牌）
func test_parse_showdown_strength() -> void:
	var ev: Array = [
		Events.hand_start(1, 1, 10, 20, [0, 1]),
		Events.player_action(0, BettingRound.ActionType.CALL, 20, 980),
		Events.deal_flop(cards("2s 3h 4d")),
		Events.deal_turn(Card.from_string("5c")),
		Events.deal_river(Card.from_string("9h")),
		Events.showdown([{"seat": 0, "cards": cards("As Kd"), "best": [], "hand_name": "高牌"}]),
		Events.hand_end(),
	]
	var inc := OpponentTracker.parse_hand(ev, 0)
	var community := cards("2s 3h 4d 5c 9h")
	expect_eq(inc["showdown"], HandStrength.score(cards("As Kd"), community), "摊牌牌力 = HandStrength.score")


# ---- AIMemory 对手统计 EWMA ----

## 重复样本使统计量向样本值收敛；hands_seen 逐手累积
func test_ewma_converges() -> void:
	var m := AIMemory.new()
	for _i in 20:
		m.notify_opponent_hand({"hands": 1, "vpip": true, "pfr": true,
				"aggression": 1.0, "showdown": 0.9})
	expect_eq(int(m.opponent_stats["hands_seen"]), 20, "hands_seen 逐手累积")
	check(float(m.opponent_stats["vpip"]) > 0.95, "vpip 收敛向 1：%f" % float(m.opponent_stats["vpip"]))
	check(float(m.opponent_stats["pfr"]) > 0.9, "pfr 收敛向 1：%f" % float(m.opponent_stats["pfr"]))
	check(float(m.opponent_stats["aggression"]) > 0.95, "aggression 收敛向 1：%f" % float(m.opponent_stats["aggression"]))
	check(float(m.opponent_stats["showdown_strength"]) > 0.85, "showdown 收敛向 0.9：%f" % float(m.opponent_stats["showdown_strength"]))


## null 字段（本手无样本）不参与 EWMA；其余字段照常更新
func test_ewma_null_fields_skipped() -> void:
	var m := AIMemory.new()
	m.notify_opponent_hand({"hands": 1, "vpip": false, "pfr": false,
			"aggression": null, "showdown": null})
	expect_eq(float(m.opponent_stats["aggression"]), 0.4, "无样本手不更新 aggression")
	expect_eq(float(m.opponent_stats["showdown_strength"]), 0.5, "无样本手不更新 showdown")
	var expected_vpip := 0.3 * (1.0 - AIMemory.OPP_ALPHA)  # vpip 照常衰减向 0
	check(absf(float(m.opponent_stats["vpip"]) - expected_vpip) < 1e-9, "vpip 照常 EWMA 更新")


## hands=0（人类未参与）整手忽略
func test_notify_hands_zero_noop() -> void:
	var m := AIMemory.new()
	m.notify_opponent_hand({"hands": 0, "vpip": true, "pfr": true,
			"aggression": 1.0, "showdown": 1.0})
	expect_eq(int(m.opponent_stats["hands_seen"]), 0, "未参与不计手数")
	expect_eq(float(m.opponent_stats["vpip"]), 0.3, "未参与 vpip 不动")


# ---- 对手调制方向（老枪 adaptability=0.90，满样本 hands_seen=20） ----

## 构造老枪的翻牌前决策上下文（对 1 名对手，无位置偏移）
static func _veteran_ctx(mem: AIMemory, hole: String, call_amount: int, can_check: bool) -> Dictionary:
	var community: Array[Card] = []
	return {
		"hole_cards": cards(hole), "community": community,
		"legal_actions": {"can_check": can_check, "can_call": call_amount > 0,
				"call_amount": call_amount, "can_raise": true,
				"min_raise_to": 40, "max_raise_to": 2000, "can_all_in": true},
		"pot_size": 100, "call_amount": call_amount, "street": HandController.Street.PREFLOP,
		"big_blind": 20, "chips": 2000, "profile": "老枪",
		"position": 0.0, "active_opponents": 1, "memory": mem,
	}


## 构造载有对手统计的 memory（未指定的维度保持理论基准，隔离单维度影响）
static func _opp_mem(hands: int, vpip := 0.3, aggr := 0.4, show := 0.5) -> AIMemory:
	var m := AIMemory.new()
	m.opponent_stats["hands_seen"] = hands
	m.opponent_stats["vpip"] = vpip
	m.opponent_stats["aggression"] = aggr
	m.opponent_stats["showdown_strength"] = show
	return m


## 松对手（vpip 0.6）→ 老枪收紧：22 对子（评分 0.50）从必跟（平时阈值 0.48）
## 掉到弱牌档（松对手阈值 ≈0.51），跟注率大幅下移
func test_loose_opponent_tightens_entry() -> void:
	var base_calls := 0
	var adj_calls := 0
	var trials := 200
	var loose := _opp_mem(20, 0.6)
	for seed in range(1, trials + 1):
		if AIDecider.new(seed).decide(_veteran_ctx(null, "2s 2d", 50, false)).get("type") == BettingRound.ActionType.CALL:
			base_calls += 1
		if AIDecider.new(seed).decide(_veteran_ctx(loose, "2s 2d", 50, false)).get("type") == BettingRound.ActionType.CALL:
			adj_calls += 1
	var base_rate := float(base_calls) / trials
	var adj_rate := float(adj_calls) / trials
	check(adj_rate < base_rate - 0.4, "松对手：老枪入局率 %.2f 应显著低于平时 %.2f" % [adj_rate, base_rate])


## 紧对手（vpip 0.05）→ 诈唬频率上调：弱牌无人下注时的加注率上升
func test_tight_opponent_raises_bluff() -> void:
	var base_raises := 0
	var adj_raises := 0
	var trials := 200
	var tight := _opp_mem(20, 0.05)
	for seed in range(1, trials + 1):
		var t1: int = AIDecider.new(seed).decide(_veteran_ctx(null, "7s 2d", 0, true)).get("type")
		if t1 == BettingRound.ActionType.RAISE or t1 == BettingRound.ActionType.ALL_IN:
			base_raises += 1
		var t2: int = AIDecider.new(seed).decide(_veteran_ctx(tight, "7s 2d", 0, true)).get("type")
		if t2 == BettingRound.ActionType.RAISE or t2 == BettingRound.ActionType.ALL_IN:
			adj_raises += 1
	var base_rate := float(base_raises) / trials
	var adj_rate := float(adj_raises) / trials
	check(adj_rate > base_rate + 0.05, "紧对手：老枪诈唬率 %.2f 应高于平时 %.2f" % [adj_rate, base_rate])


## 被动对手（aggression 0.1）→ 加注倾向上调：强牌加注率上升
func test_passive_opponent_raises_aggression() -> void:
	var base_raises := 0
	var adj_raises := 0
	var trials := 200
	var passive := _opp_mem(20, 0.3, 0.1)
	for seed in range(1, trials + 1):
		var t1: int = AIDecider.new(seed).decide(_veteran_ctx(null, "As Ah", 50, false)).get("type")
		if t1 == BettingRound.ActionType.RAISE or t1 == BettingRound.ActionType.ALL_IN:
			base_raises += 1
		var t2: int = AIDecider.new(seed).decide(_veteran_ctx(passive, "As Ah", 50, false)).get("type")
		if t2 == BettingRound.ActionType.RAISE or t2 == BettingRound.ActionType.ALL_IN:
			adj_raises += 1
	var base_rate := float(base_raises) / trials
	var adj_rate := float(adj_raises) / trials
	check(adj_rate > base_rate + 0.05, "被动对手：老枪强牌加注率 %.2f 应高于平时 %.2f" % [adj_rate, base_rate])


## 摊牌偏弱（showdown 0.2）→ 面对下注跟注倾向上调：弱牌跟注率上升
func test_weak_showdown_raises_calling() -> void:
	var base_calls := 0
	var adj_calls := 0
	var trials := 200
	var weak_sd := _opp_mem(20, 0.3, 0.4, 0.2)
	for seed in range(1, trials + 1):
		if AIDecider.new(seed).decide(_veteran_ctx(null, "7s 2d", 50, false)).get("type") == BettingRound.ActionType.CALL:
			base_calls += 1
		if AIDecider.new(seed).decide(_veteran_ctx(weak_sd, "7s 2d", 50, false)).get("type") == BettingRound.ActionType.CALL:
			adj_calls += 1
	var base_rate := float(base_calls) / trials
	var adj_rate := float(adj_calls) / trials
	check(adj_rate > base_rate + 0.05, "摊牌弱对手：老枪弱牌跟注率 %.2f 应高于平时 %.2f" % [adj_rate, base_rate])


## 样本不足线性缩放：同样松对手统计，hands_seen=2 时调制远弱于满样本
func test_low_sample_scales_down() -> void:
	var few_calls := 0
	var full_calls := 0
	var trials := 200
	var few := _opp_mem(2, 0.6)
	var full := _opp_mem(20, 0.6)
	for seed in range(1, trials + 1):
		if AIDecider.new(seed).decide(_veteran_ctx(few, "2s 2d", 50, false)).get("type") == BettingRound.ActionType.CALL:
			few_calls += 1
		if AIDecider.new(seed).decide(_veteran_ctx(full, "2s 2d", 50, false)).get("type") == BettingRound.ActionType.CALL:
			full_calls += 1
	var few_rate := float(few_calls) / trials
	var full_rate := float(full_calls) / trials
	check(few_rate > full_rate + 0.4, "样本不足：hands=2 入局率 %.2f 应接近平时、高于满样本 %.2f" % [few_rate, full_rate])


# ---- 锦标赛集成：整手事件流跨 pop 累积喂给每个 AI ----

## 人类参与的手牌事件分多批 pop（人类动作挂起），对手统计仍须逐手累积
func test_tm_feeds_opponent_stats() -> void:
	var tm := TournamentManager.new(SaveManager.new(TEST_SAVE), StatsManager.new(TEST_STATS))
	tm.start_new(TournamentManager.TournamentConfig.default(), 2, 7)
	var d := AIDecider.new(123)
	var n := 0
	while n < 5 and not tm.finished:
		tm.run_next_hand()
		drive_waiting(tm, d)  # AI 代打人类座位，强制事件分批 pop
		tm.pop_events()
		n += 1
	for seat in tm.ai_memories:
		var st: Dictionary = tm.ai_memories[seat].opponent_stats
		expect_eq(int(st["hands_seen"]), n, "座位 %d 的 hands_seen 逐手累积" % seat)

	SaveManager.new(TEST_SAVE).clear()
	SaveManager.new(TEST_STATS).clear()
