extends RefCounted
## 测试基类：断言计数 + 常用构造助手。

var failures := 0
var checks := 0
var current := ""  # 当前用例名（由运行器设置）


func check(cond: bool, msg := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL [%s] %s" % [current, msg])


func expect_eq(actual, expected, msg := "") -> void:
	checks += 1
	if actual != expected:
		failures += 1
		printerr("FAIL [%s] %s: 期望 %s，实际 %s" % [current, msg, str(expected), str(actual)])


## "As Kd Qh" -> Array[Card]
static func cards(s: String) -> Array[Card]:
	var out: Array[Card] = []
	for tok in s.split(" ", false):
		out.append(Card.from_string(tok))
	return out


static func make_player(seat: int, chips: int, bet := 0, total := -1) -> PlayerState:
	var p := PlayerState.new()
	p.seat_index = seat
	p.name = "P%d" % seat
	p.chips = chips
	p.current_bet = bet
	p.hand_total_bet = bet if total < 0 else total
	return p


## 动作构造助手
static func fold() -> Dictionary:
	return {"type": BettingRound.ActionType.FOLD}

static func check_action() -> Dictionary:
	return {"type": BettingRound.ActionType.CHECK}

static func call_action() -> Dictionary:
	return {"type": BettingRound.ActionType.CALL}

static func raise_to(amount: int) -> Dictionary:
	return {"type": BettingRound.ActionType.RAISE, "amount": amount}

static func all_in() -> Dictionary:
	return {"type": BettingRound.ActionType.ALL_IN}


# ---- 手牌/锦标赛驱动助手 ----

## 构造"牌堆"：draw_order 为期望的发牌顺序（第一张被最先摸走）。
## 用于替换 HandController.deck，绕开洗牌获得确定牌局。
static func rigged_deck(draw_order: Array[Card]) -> Deck:
	var d := Deck.new()
	d.cards.clear()
	for i in range(draw_order.size() - 1, -1, -1):
		d.cards.append(draw_order[i])
	return d


## HandController 等待中座位的 AI 决策上下文。
static func make_decision_ctx(hc: HandController, seat: int, profile := AIProfiles.DEFAULT_PROFILE) -> Dictionary:
	var p: PlayerState = null
	for q in hc.players:
		if q.seat_index == seat:
			p = q
	var legal := hc.round.get_legal_actions(p)
	return {
		"hole_cards": p.hole_cards, "community": hc.community,
		"legal_actions": legal, "pot_size": hc.pot_size(),
		"call_amount": legal.call_amount, "street": hc.street,
		"big_blind": hc.big_blind, "chips": p.chips, "profile": profile,
	}


## 用脚本驱动 HandController 至结束。script: Callable(seat, legal) -> action。
static func drive_hand(hc: HandController, script: Callable) -> void:
	var guard := 0
	while not hc.is_finished():
		guard += 1
		assert(guard < 1000, "手牌驱动超出步数上限（疑似死循环）")
		assert(hc.is_waiting(), "手牌未结束但未挂起：脚本驱动只能处理人类回合")
		var legal := hc.round.get_legal_actions(_seat_of(hc, hc.waiting_seat))
		var action: Dictionary = script.call(hc.waiting_seat, legal)
		hc.submit_human_action(action)


## 用 AI 代打人类座位，把 TournamentManager 当前手牌推进到不再挂起。
static func drive_waiting(tm: TournamentManager, decider: AIDecider) -> void:
	var guard := 0
	while tm.is_waiting_for_human():
		guard += 1
		assert(guard < 1000, "锦标赛驱动超出步数上限（疑似死循环）")
		var ctx := make_decision_ctx(tm.hand, tm.hand.waiting_seat)
		tm.submit_human_action(decider.decide(ctx))


static func _seat_of(hc: HandController, seat: int) -> PlayerState:
	for p in hc.players:
		if p.seat_index == seat:
			return p
	return null
