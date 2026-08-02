class_name HandController extends RefCounted
## 一手牌的完整流程驱动（TECH_DESIGN 4.5）：
## 收盲注 → 发底牌 → 四轮下注 → 摊牌/提前判胜 → PotManager 结算 → 淘汰检测 → HAND_END。
##
## 人类回合：发出 ACTION_REQUIRED 事件后状态挂起（waiting_seat >= 0），
## 表现层调用 submit_human_action() 恢复推进。不使用 await，任意时刻状态可外部读取。

enum State { IDLE, BETTING, FINISHED }
enum Street { PREFLOP, FLOP, TURN, RIVER }

var players: Array[PlayerState]  # 本手参与者（不再变动；OUT 由淘汰检测标记）
var button_seat: int
var small_blind: int
var big_blind: int
var hand_no: int

var deck: Deck
var community: Array[Card] = []
var events: Array[Dictionary] = []
var state: State = State.IDLE
var street: Street = Street.PREFLOP
var round: BettingRound
var waiting_seat: int = -1  # >=0：挂起等待该座位（人类）提交动作
var ai_decider: AIDecider

var _chips_at_start := {}  # seat -> 本手开始时筹码（淘汰名次排序用）
var _alive_at_start := 0


## p_players 为本手参与者（筹码 > 0），调用前请确保按钮/盲注已确定。
func _init(p_players: Array[PlayerState], p_button_seat: int, p_small_blind: int, p_big_blind: int,
		p_deck_seed: int, p_ai_decider: AIDecider, p_hand_no: int) -> void:
	players = p_players
	button_seat = p_button_seat
	small_blind = p_small_blind
	big_blind = p_big_blind
	ai_decider = p_ai_decider
	hand_no = p_hand_no
	deck = Deck.new()
	deck.shuffle(p_deck_seed)


## 启动本手牌：初始化玩家手牌状态、收盲注、发底牌，然后推进到挂起点或结束。
func start() -> void:
	_alive_at_start = players.size()
	for p in players:
		p.hole_cards.clear()
		p.current_bet = 0
		p.hand_total_bet = 0
		p.status = PlayerState.Status.ACTIVE
		_chips_at_start[p.seat_index] = p.chips

	var alive_seats: Array[int] = []
	for p in players:
		alive_seats.append(p.seat_index)
	events.append(Events.hand_start(hand_no, button_seat, small_blind, big_blind, alive_seats))
	_post_blinds()
	_deal_hole()
	_start_betting_round(Street.PREFLOP)
	run()


## 推进流程，直到挂起等待人类动作或本手结束。
func run() -> void:
	while state != State.FINISHED and waiting_seat < 0:
		_step()


## 人类动作提交。非法动作被拒绝（返回 false），保持挂起状态可重新提交。
func submit_human_action(action: Dictionary) -> bool:
	if waiting_seat < 0:
		push_error("HandController: 当前没有等待中的人类回合")
		return false
	var p := _by_seat(waiting_seat)
	if not round.apply_action(p, action):
		return false  # 保持挂起，由表现层重试
	events.append(Events.player_action(p.seat_index, action.get("type", -1), action.get("amount", 0), p.chips, p.status))
	waiting_seat = -1
	run()
	return true


func pop_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


func is_waiting() -> bool:
	return waiting_seat >= 0


func is_finished() -> bool:
	return state == State.FINISHED


## 当前底池总额（本轮未收拢的下注 + 历史投入）。
func pot_size() -> int:
	var total := 0
	for p in players:
		total += p.hand_total_bet
	return total


func _step() -> void:
	# 仅剩一名未弃牌者 → 提前收池，不摊牌
	if _not_folded_count() <= 1:
		_early_win()
		return

	var actor := round.current_actor()
	if actor == null:
		_end_round()
		return

	var legal := round.get_legal_actions(actor)
	if actor.is_human:
		waiting_seat = actor.seat_index
		events.append(Events.action_required(actor.seat_index, legal))
		return

	# AI 回合：同步决策
	var action := ai_decider.decide({
		"hole_cards": actor.hole_cards,
		"community": community,
		"legal_actions": legal,
		"pot_size": pot_size(),
		"call_amount": legal.call_amount,
		"street": street,
		"big_blind": big_blind,
		"chips": actor.chips,
		"profile": actor.ai_profile,
	})
	if not round.apply_action(actor, action):
		# AI 产出非法动作属实现错误：降级为 过牌/跟注/弃牌 保底
		push_error("HandController: AI 动作被 BettingRound 拒绝，使用保底动作")
		if legal.can_check:
			action = {"type": BettingRound.ActionType.CHECK}
		elif legal.can_call:
			action = {"type": BettingRound.ActionType.CALL}
		else:
			action = {"type": BettingRound.ActionType.FOLD}
		round.apply_action(actor, action)
	events.append(Events.player_action(actor.seat_index, action.get("type", -1), action.get("amount", 0), actor.chips, actor.status))


# ---- 盲注与发牌 ----

func _post_blinds() -> void:
	var sb_p: PlayerState
	var bb_p: PlayerState
	if players.size() == 2:
		sb_p = _by_seat(button_seat)  # 单挑时按钮位下小盲
		bb_p = _next_player_after(button_seat)
	else:
		sb_p = _next_player_after(button_seat)
		bb_p = _next_player_after(sb_p.seat_index)
	_post_blind(sb_p, small_blind)
	_post_blind(bb_p, big_blind)


func _post_blind(p: PlayerState, amount: int) -> void:
	var actual := mini(amount, p.chips)  # 筹码不足按全下处理
	p.chips -= actual
	p.current_bet += actual
	p.hand_total_bet += actual
	if p.chips == 0:
		p.status = PlayerState.Status.ALL_IN


func _deal_hole() -> void:
	# 从小盲位开始，顺时针每人两张（逐张发）
	for _i in 2:
		var seat := _next_seat_after(button_seat if players.size() > 2 else button_seat - 1)
		for _j in players.size():
			var p := _by_seat(seat)
			p.hole_cards.append(deck.draw())
			seat = _next_seat_after(seat)
	for p in players:
		events.append(Events.deal_hole(p.seat_index, p.hole_cards.duplicate() if p.is_human else [], p.status))


# ---- 下注轮 ----

func _start_betting_round(p_street: Street) -> void:
	street = p_street
	var first: int
	if p_street == Street.PREFLOP:
		# 翻牌前 UTG（大盲后第一位）；单挑时为按钮/小盲位
		first = _next_seat_after(_bb_seat())
	else:
		first = _next_seat_after(button_seat)
	round = BettingRound.new(players, first, big_blind)
	state = State.BETTING


func _bb_seat() -> int:
	if players.size() == 2:
		return _next_seat_after(button_seat)
	return _next_seat_after(_next_seat_after(button_seat))


func _end_round() -> void:
	events.append(Events.round_end(pot_size()))
	for p in players:
		p.current_bet = 0

	match street:
		Street.PREFLOP:
			for _i in 3:
				community.append(deck.draw())
			events.append(Events.deal_flop(community.duplicate()))
			_start_betting_round(Street.FLOP)
		Street.FLOP:
			var turn := deck.draw()
			community.append(turn)
			events.append(Events.deal_turn(turn))
			_start_betting_round(Street.TURN)
		Street.TURN:
			var river := deck.draw()
			community.append(river)
			events.append(Events.deal_river(river))
			_start_betting_round(Street.RIVER)
		Street.RIVER:
			_showdown_and_settle()


# ---- 结算 ----

func _showdown_and_settle() -> void:
	var reveals: Array = []
	for p in players:
		if p.status != PlayerState.Status.FOLDED:
			var seven: Array[Card] = p.hole_cards.duplicate()
			seven.append_array(community)
			var r := HandEvaluator.evaluate(seven)
			reveals.append({"seat": p.seat_index, "cards": p.hole_cards.duplicate(),
					"hand_name": HandEvaluator.category_name(r.category)})
	events.append(Events.showdown(reveals))

	var pots := PotManager.build_pots(players)
	var awards := PotManager.settle(pots, players, community, button_seat)
	for a in awards:
		var p := _by_seat(a.seat)
		p.chips += a.amount
		var hand_name := ""
		if a.hand_rank != null:
			hand_name = HandEvaluator.category_name(a.hand_rank.category)
		events.append(Events.pot_award(a.seat, a.amount, a.pot_index, hand_name))
	_finish_hand()


## 全员弃牌仅剩一人：直接收池，不摊牌、不公开手牌。
func _early_win() -> void:
	var winner: PlayerState = null
	for p in players:
		if p.status != PlayerState.Status.FOLDED:
			winner = p
	assert(winner != null, "提前判胜时无存活玩家")
	var total := pot_size()
	winner.chips += total
	events.append(Events.pot_award(winner.seat_index, total, 0, ""))
	_finish_hand()


func _finish_hand() -> void:
	_elimination_check()
	events.append(Events.hand_end())
	state = State.FINISHED


## 筹码归零者淘汰。同手淘汰者按本手开始时的筹码多少排名（多者名次靠前）。
func _elimination_check() -> void:
	var out: Array[PlayerState] = []
	for p in players:
		if p.chips <= 0 and p.status != PlayerState.Status.OUT:
			out.append(p)
	out.sort_custom(func(a, b): return _chips_at_start[a.seat_index] > _chips_at_start[b.seat_index])
	var rank := _alive_at_start
	for p in out:
		p.status = PlayerState.Status.OUT
		events.append(Events.eliminated(p.seat_index, rank))
		rank -= 1


# ---- 座位工具 ----

func _not_folded_count() -> int:
	var n := 0
	for p in players:
		if p.status != PlayerState.Status.FOLDED:
			n += 1
	return n


func _by_seat(seat: int) -> PlayerState:
	for p in players:
		if p.seat_index == seat:
			return p
	return null


## 座位号大于 seat 的下一位本手玩家（环绕）。
func _next_player_after(seat: int) -> PlayerState:
	return _by_seat(_next_seat_after(seat))


func _next_seat_after(seat: int) -> int:
	var best := -1
	for p in players:
		if p.seat_index > seat and (best < 0 or p.seat_index < best):
			best = p.seat_index
	if best >= 0:
		return best
	# 环绕到最小座位
	for p in players:
		if best < 0 or p.seat_index < best:
			best = p.seat_index
	return best
