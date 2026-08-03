extends "res://tests/test_base.gd"
## HandController 整手牌流程测试：scripted 动作 + 固定牌堆/种子。

func _make_human_players(chips: Array[int]) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for i in chips.size():
		var p := make_player(i, chips[i])
		p.is_human = true
		out.append(p)
	return out


## 全员弃牌仅剩一人 → 提前收池，不摊牌、不公开手牌
func test_early_win_no_showdown() -> void:
	var players := _make_human_players([1000, 1000, 1000] as Array[int])
	var hc := HandController.new(players, 0, 10, 20, 1, AIDecider.new(1), 1)
	hc.start()

	# 挂起点：UTG（座位 0）等待人类动作，事件携带合法动作集合
	check(hc.is_waiting(), "人类回合应挂起")
	expect_eq(hc.waiting_seat, 0, "翻牌前 UTG 为座位 0")
	var ev := hc.pop_events()
	var found_ar := false
	var human_hole_visible := false
	for e in ev:
		if e.type == Events.Type.ACTION_REQUIRED:
			found_ar = true
			check(e.legal_actions.can_call, "UTG 应可跟注")
		if e.type == Events.Type.DEAL_HOLE and e.seat == 0:
			human_hole_visible = e.cards.size() == 2
	check(found_ar, "应有 ACTION_REQUIRED 事件")
	check(human_hole_visible, "人类底牌应对自己可见")

	# 座位 0 跟注，其余弃牌
	var script := func(seat: int, _legal: Dictionary) -> Dictionary:
		return call_action() if seat == 0 else fold()
	drive_hand(hc, script)

	check(hc.is_finished(), "手牌应结束")
	var pot_awards := 0
	var showdown_seen := false
	for e in hc.pop_events():
		if e.type == Events.Type.POT_AWARD:
			pot_awards += 1
			expect_eq(e.seat, 0, "提前判胜者")
			expect_eq(e.amount, 50, "底池 = 跟注 20 + 小盲 10 + 大盲 20")
		if e.type == Events.Type.SHOWDOWN:
			showdown_seen = true
	expect_eq(pot_awards, 1, "提前判胜应只有一笔派彩")
	check(not showdown_seen, "提前判胜不应摊牌")
	expect_eq(players[0].chips, 1030, "赢家筹码")
	expect_eq(players[0].chips + players[1].chips + players[2].chips, 3000, "筹码守恒")


## 多全下边池：短筹码皇家同花顺赢主池，次短筹码赢边池
func test_all_in_side_pots() -> void:
	var players := _make_human_players([100, 50, 200] as Array[int])
	var hc := HandController.new(players, 0, 10, 20, 1, AIDecider.new(1), 1)
	# 发牌顺序：p1=As, p2=2c, p0=7h, p1=Ks, p2=3d, p0=8h, 公共牌 Qs Js Ts 4c 9d
	hc.deck = rigged_deck(cards("As 2c 7h Ks 3d 8h Qs Js Ts 4c 9d"))
	hc.start()

	var script := func(seat: int, _legal: Dictionary) -> Dictionary:
		return call_action() if seat == 2 else all_in()
	drive_hand(hc, script)

	check(hc.is_finished(), "手牌应结束")
	var awards := {}
	var showdown_seen := false
	var royal_seen := false
	for e in hc.pop_events():
		if e.type == Events.Type.SHOWDOWN:
			showdown_seen = true
			expect_eq(e.reveals.size(), 3, "摊牌应公开全部未弃牌者")
			for r in e.reveals:
				if r.seat == 1 and r.hand_name == "皇家同花顺":
					royal_seen = true
					var best_names: Array = []
					for c in r.best:
						best_names.append((c as Card).to_string_short())
					best_names.sort()
					expect_eq(best_names, ["As", "Js", "Ks", "Qs", "Ts"], "best 应为皇家同花顺五张")
		if e.type == Events.Type.POT_AWARD:
			awards[e.seat] = e.amount
	check(showdown_seen, "全下跑完公共牌后应摊牌")
	check(royal_seen, "座位 1 应为皇家同花顺")
	expect_eq(awards.get(1, 0), 150, "主池 50×3 归座位 1")
	expect_eq(awards.get(0, 0), 100, "边池 50×2 归座位 0")
	check(not awards.has(2), "座位 2 不应赢池")
	expect_eq(players[1].chips, 150, "座位 1 终局筹码")
	expect_eq(players[0].chips, 100, "座位 0 终局筹码")
	expect_eq(players[2].chips, 100, "座位 2 终局筹码")


## 单挑局盲注全下：筹码不足下盲注按全下处理，公共牌跑完后摊牌
func test_blind_all_in_heads_up() -> void:
	var players := _make_human_players([5, 100] as Array[int])
	var hc := HandController.new(players, 0, 10, 20, 1, AIDecider.new(1), 1)
	# 发牌顺序（单挑从按钮/小盲位发起）：p0=As, p1=2c, p0=Ah, p1=9d, 公共牌 4s 5h 6c Ks Td
	hc.deck = rigged_deck(cards("As 2c Ah 9d 4s 5h 6c Ks Td"))
	hc.start()
	expect_eq(players[0].status, PlayerState.Status.ALL_IN, "小盲筹码不足应为全下")
	expect_eq(players[0].hand_total_bet, 5, "小盲实际投入 5")

	# 大盲无需行动（无人加注超过大盲），手牌直接跑完公共牌
	drive_hand(hc, func(_s, _l): return check_action())
	check(hc.is_finished(), "手牌应结束")

	var awards: Array = []
	for e in hc.pop_events():
		if e.type == Events.Type.POT_AWARD:
			awards.append(e)
	expect_eq(awards.size(), 2, "应有主池 + 超额返还两笔派彩")
	# 主池 5×2=10 归座位 0（一对 A）；座位 1 超额 15 无人竞争直接返还
	for a in awards:
		if a.pot_index == 0:
			expect_eq(a.seat, 0, "主池归座位 0")
			expect_eq(a.amount, 10, "主池金额")
		else:
			expect_eq(a.seat, 1, "超额层归座位 1")
			expect_eq(a.amount, 15, "超额返还金额")
	expect_eq(players[0].chips, 10, "座位 0 未被淘汑")
	expect_eq(players[0].status != PlayerState.Status.OUT, true, "座位 0 不应淘汰")


## 同一种子 + 同一 AI 种子 → 两次运行结果完全一致
func test_seed_reproducible() -> void:
	var run_once := func() -> Array:
		var players: Array[PlayerState] = [make_player(0, 1000), make_player(1, 1000), make_player(2, 1000)]
		var hc := HandController.new(players, 0, 10, 20, 12345, AIDecider.new(12345), 1)
		hc.start()
		var types: Array = [players[0].chips, players[1].chips, players[2].chips]
		for e in hc.pop_events():
			types.append(e.type)
		return types
	var a: Array = run_once.call()
	var b: Array = run_once.call()
	expect_eq(a, b, "同种子两次运行应完全一致")
	expect_eq(a[0] + a[1] + a[2], 3000, "筹码守恒")


## AI 底牌事件不携带牌面（仅人类可见）
func test_ai_hole_hidden() -> void:
	var players: Array[PlayerState] = [make_player(0, 1000), make_player(1, 1000)]
	players[0].is_human = true
	var hc := HandController.new(players, 0, 10, 20, 7, AIDecider.new(7), 1)
	hc.start()
	for e in hc.pop_events():
		if e.type == Events.Type.DEAL_HOLE:
			if e.seat == 0:
				expect_eq(e.cards.size(), 2, "人类底牌可见")
			else:
				expect_eq(e.cards.size(), 0, "AI 底牌应隐藏")
	drive_hand(hc, func(_s, legal):
		return check_action() if legal.can_check else call_action())
	expect_eq(players[0].chips + players[1].chips, 2000, "筹码守恒")


## 事件须携带状态快照：全下后输掉手牌的玩家终局 status 已是 OUT，
## 但 HAND_START/DEAL_HOLE/PLAYER_ACTION 事件里必须保留当时状态（否则 UI 回放时提前显示"出局"）
func test_event_status_snapshot() -> void:
	var players := _make_human_players([1000, 1000] as Array[int])
	var hc := HandController.new(players, 0, 10, 20, 1, AIDecider.new(1), 1)
	# 发牌顺序（单挑）：p0=2h, p1=As, p0=3d, p1=Ac, 公共牌 8s 9h Tc Ks Qd；一对 A 胜
	hc.deck = rigged_deck(cards("2h As 3d Ac 8s 9h Tc Ks Qd"))
	hc.start()

	var all_events: Array[Dictionary] = []
	all_events.append_array(hc.pop_events())
	drive_hand(hc, func(_s, _l): return all_in())
	all_events.append_array(hc.pop_events())
	check(hc.is_finished(), "手牌应结束")

	expect_eq(players[0].status, PlayerState.Status.OUT, "全下输掉后座位 0 应淘汰")

	var start_seen := false
	var deal_status := -1
	var action_status := -1
	var eliminated_seen := false
	for e in all_events:
		match e.type:
			Events.Type.HAND_START:
				start_seen = true
				expect_eq(e.alive_seats, [0, 1] as Array[int], "手牌开始时两座均应存活")
			Events.Type.DEAL_HOLE:
				if e.seat == 0:
					deal_status = e.status
			Events.Type.PLAYER_ACTION:
				if e.seat == 0:
					expect_eq(e.action, BettingRound.ActionType.ALL_IN, "座位 0 应为全下动作")
					action_status = e.status
			Events.Type.ELIMINATED:
				if e.seat == 0:
					eliminated_seen = true
	check(start_seen, "应有 HAND_START 事件")
	expect_eq(deal_status, PlayerState.Status.ACTIVE, "发牌时座位 0 应为 ACTIVE 快照")
	expect_eq(action_status, PlayerState.Status.ALL_IN, "全下动作事件应带 ALL_IN 快照而非终局 OUT")
	check(eliminated_seen, "座位 0 应有 ELIMINATED 事件")
