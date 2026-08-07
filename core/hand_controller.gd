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
var ai_memories: Dictionary = {}  # seat -> AIMemory，由 TournamentManager 持有并共享引用
var reveal_hole_cards: bool = false  # 观战模式：DEAL_HOLE 事件公开所有玩家手牌

var _chips_at_start := {}  # seat -> 本手开始时筹码（淘汰名次排序用）
var _alive_at_start := 0


## p_players 为本手参与者（筹码 > 0），调用前请确保按钮/盲注已确定。
## p_rig_seat >= 0 时启用简单模式洗牌：重洗至该座位假定摊牌必胜（起手强、公共牌有利）。
## p_ai_memories 为 AI 情绪状态表（seat -> AIMemory），决策时只读传入 ctx。
func _init(p_players: Array[PlayerState], p_button_seat: int, p_small_blind: int, p_big_blind: int,
		p_deck_seed: int, p_ai_decider: AIDecider, p_hand_no: int, p_rig_seat: int = -1,
		p_ai_memories: Dictionary = {}, p_reveal_hole_cards: bool = false) -> void:
	players = p_players
	button_seat = p_button_seat
	small_blind = p_small_blind
	big_blind = p_big_blind
	ai_decider = p_ai_decider
	ai_memories = p_ai_memories
	reveal_hole_cards = p_reveal_hole_cards
	hand_no = p_hand_no
	deck = Deck.new()
	deck.shuffle(p_deck_seed)
	if p_rig_seat >= 0 and _by_seat(p_rig_seat) != null:
		_rig_deck(p_rig_seat, p_deck_seed)


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
	var start_chips: Dictionary = {}
	for p in players:
		alive_seats.append(p.seat_index)
		start_chips[p.seat_index] = p.chips
	# 盲注座位：单挑时按钮位下小盲（_post_blinds 按此座位扣盲注）
	var sb_seat: int
	var bb_seat: int
	if players.size() == 2:
		sb_seat = button_seat
		bb_seat = _next_player_after(button_seat).seat_index
	else:
		sb_seat = _next_player_after(button_seat).seat_index
		bb_seat = _next_player_after(sb_seat).seat_index
	events.append(Events.hand_start(hand_no, button_seat, small_blind, big_blind, alive_seats, start_chips, sb_seat, bb_seat))
	_post_blinds(sb_seat, bb_seat)
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
	var chips_before := p.chips
	if not round.apply_action(p, action):
		return false  # 保持挂起，由表现层重试
	events.append(Events.player_action(p.seat_index, action.get("type", -1), _event_amount(p, action, chips_before), p.chips, p.status, p.current_bet))
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


## PLAYER_ACTION 事件金额：加注取动作里的目标总额（"加注到"语义）；
## 跟注/全下的动作字典不带金额，取本动作实际付出的筹码（过牌/弃牌自然为 0）。
func _event_amount(p: PlayerState, action: Dictionary, chips_before: int) -> int:
	if action.get("type", -1) == BettingRound.ActionType.RAISE:
		return action.get("amount", 0)
	return chips_before - p.chips


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
		"position": _position_factor(actor.seat_index),
		"active_opponents": _not_folded_count() - 1,
		"memory": ai_memories.get(actor.seat_index),
	})
	var chips_before := actor.chips
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
	events.append(Events.player_action(actor.seat_index, action.get("type", -1), _event_amount(actor, action, chips_before), actor.chips, actor.status, actor.current_bet))


# ---- 盲注与发牌 ----

## 按 start() 算好的盲注座位扣盲注（单挑时按钮位下小盲，座位计算规则在 start()）。
func _post_blinds(sb_seat: int, bb_seat: int) -> void:
	_post_blind(_by_seat(sb_seat), small_blind)
	_post_blind(_by_seat(bb_seat), big_blind)


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
		var shown: Array = p.hole_cards.duplicate() if (p.is_human or reveal_hole_cards) else []
		events.append(Events.deal_hole(p.seat_index, shown, p.status, p.chips, p.current_bet))


# ---- 简单模式洗牌 ----

## 重洗次数上限。9 人局单次洗牌玩家假定摊牌胜率约 1/9，100 次几乎必然命中。
const RIG_MAX_ATTEMPTS := 100

## 简单模式：反复洗牌，直到 rig_seat 在"假定摊牌"（按当前发牌顺序摸完 5 张公共牌）
## 下持有全场唯一最强牌——起手牌因此更强，公共牌也更倾向于成全玩家。
## 达到尝试上限时保留玩家击败对手数最多的一局（保底，实践中几乎不会触发）。
func _rig_deck(rig_seat: int, base_seed: int) -> void:
	var seats := _deal_order()
	var n := players.size()
	var best_cards: Array[Card] = []
	var best_beaten := -1
	for attempt in RIG_MAX_ATTEMPTS:
		if attempt > 0:
			# 派生种子保证同一 base_seed 下洗牌序列可复现；base_seed 为 0 时本来就是随机
			deck.shuffle(base_seed + attempt if base_seed != 0 else 0)
		var beaten := _showdown_beaten_count(rig_seat, seats)
		if beaten == n - 1:
			return  # 命中：全场唯一最强
		if beaten > best_beaten:
			best_beaten = beaten
			best_cards = deck.cards.duplicate()
	deck.cards = best_cards


## 底牌发牌座位顺序（与 _deal_hole 一致：小盲位开始顺时针，单挑时按钮位先发）。
func _deal_order() -> Array[int]:
	var seats: Array[int] = []
	var seat := _next_seat_after(button_seat if players.size() > 2 else button_seat - 1)
	for _j in players.size():
		seats.append(seat)
		seat = _next_seat_after(seat)
	return seats


## 按当前牌堆模拟完整发牌，返回 rig_seat 假定摊牌严格击败的对手数。
## 牌堆顶为数组末尾：第 k 张摸走的是 cards[size-1-k]，前 2n 张为底牌，之后 5 张公共牌。
func _showdown_beaten_count(rig_seat: int, seats: Array[int]) -> int:
	var n := players.size()
	var top := deck.cards.size() - 1
	var community_sim: Array[Card] = []
	for k in range(2 * n, 2 * n + 5):
		community_sim.append(deck.cards[top - k])
	var rig_idx := seats.find(rig_seat)
	var rig_seven: Array[Card] = [deck.cards[top - rig_idx], deck.cards[top - n - rig_idx]]
	rig_seven.append_array(community_sim)
	var rig_rank := HandEvaluator.evaluate(rig_seven)
	var beaten := 0
	for i in n:
		if i == rig_idx:
			continue
		var seven: Array[Card] = [deck.cards[top - i], deck.cards[top - n - i]]
		seven.append_array(community_sim)
		if HandEvaluator.compare(HandEvaluator.evaluate(seven), rig_rank) >= 0:
			return beaten  # 有人不弱于玩家，本次洗牌不成立（短路）
		beaten += 1
	return beaten


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
					"best": HandEvaluator.best_five(seven),
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
		events.append(Events.pot_award(a.seat, a.amount, a.pot_index, hand_name, p.chips))
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
	events.append(Events.pot_award(winner.seat_index, total, 0, "", winner.chips))
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

## 位置系数 -1（按钮后第一位，最差）~ +1（按钮位，最好）。
## 按本手参与者从按钮顺时针的步数归一，供 AI 位置意识调制入局阈值。
func _position_factor(seat: int) -> float:
	var n := players.size()
	if n <= 1:
		return 0.0
	var k := 0
	var s := button_seat
	while s != seat:
		s = _next_seat_after(s)
		k += 1
	return 1.0 - 2.0 * float(k) / float(n - 1)


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
