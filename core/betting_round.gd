class_name BettingRound extends RefCounted
## 单轮下注状态机（无限注）。盲注在构造前已计入各玩家 current_bet。
##
## 核心规则：
## - 最小加注到 current_high + last_raise_increment（翻牌前即 2 倍大盲）。
## - 加注额不足最小加注的全下不重新开启已行动玩家的加注权（只能跟注或弃牌）。
## - 所有未弃牌未全下玩家下注齐平且均已行动，或仅剩一名可行动玩家且无注可跟时，轮次结束。

enum ActionType { FOLD, CHECK, CALL, RAISE, ALL_IN }

var players: Array[PlayerState]
var big_blind: int
var order: Array[int] = []  # 行动顺序（座位号，从 first_to_act_seat 起顺时针）
var cursor: int = 0
var current_high: int = 0  # 本轮最高下注额
var last_raise_increment: int  # 当前最小加注增量
var acted: Dictionary = {}  # seat -> bool（自上次全额加注以来是否已行动）
var raise_blocked: Dictionary = {}  # seat -> bool（被不足额全下封锁再加注权）


## p_players 含全部在局玩家（含盲注已全下者）；first_to_act_seat 为翻牌前 UTG / 翻牌后小盲方向第一位。
func _init(p_players: Array[PlayerState], first_to_act_seat: int, p_big_blind: int) -> void:
	players = p_players
	big_blind = p_big_blind
	last_raise_increment = p_big_blind
	var seats: Array[int] = []
	for p in players:
		# 最高下注额统计所有在局玩家（含盲注全下者）
		if p.status != PlayerState.Status.OUT:
			current_high = maxi(current_high, p.current_bet)
		if p.status == PlayerState.Status.ACTIVE:
			seats.append(p.seat_index)
	seats.sort()
	var start := 0
	while start < seats.size() and seats[start] < first_to_act_seat:
		start += 1
	for i in seats.size():
		order.append(seats[(start + i) % seats.size()])


## 当前行动者；轮次已结束返回 null。
func current_actor() -> PlayerState:
	if is_round_complete() or order.is_empty():
		return null
	for i in order.size():
		var p := _by_seat(order[(cursor + i) % order.size()])
		if p.status == PlayerState.Status.ACTIVE \
				and (not acted.get(p.seat_index, false) or p.current_bet != current_high):
			cursor = (cursor + i) % order.size()
			return p
	return null


func get_legal_actions(p: PlayerState) -> Dictionary:
	var diff := current_high - p.current_bet  # 需跟注差额
	var max_to := p.current_bet + p.chips  # 全下时的总下注额
	var min_to := current_high + last_raise_increment
	return {
		"can_check": diff <= 0,
		"can_call": diff > 0 and p.chips > 0,
		"call_amount": mini(maxi(diff, 0), p.chips),
		"can_raise": p.chips > 0 and max_to >= min_to and not raise_blocked.get(p.seat_index, false),
		"min_raise_to": min_to,
		"max_raise_to": max_to,
		# 被不足额全下封锁时，只有不超过当前最高注的全下（等同跟注）合法
		"can_all_in": p.chips > 0 and (max_to <= current_high or not raise_blocked.get(p.seat_index, false)),
	}


## 校验并执行动作；非法动作 push_error 并拒绝（返回 false）。
func apply_action(p: PlayerState, action: Dictionary) -> bool:
	var actor := current_actor()
	if actor == null:
		return _reject("下注轮已结束，不能再行动")
	if actor != p:
		return _reject("尚未轮到座位 %d 行动" % p.seat_index)

	var legal := get_legal_actions(p)
	var type: int = action.get("type", -1)
	var amount: int = action.get("amount", 0)
	match type:
		ActionType.FOLD:
			p.status = PlayerState.Status.FOLDED
		ActionType.CHECK:
			if not legal.can_check:
				return _reject("当前需跟注 %d，不能过牌" % legal.call_amount)
		ActionType.CALL:
			if not legal.can_call:
				return _reject("当前无需跟注")
			_pay(p, legal.call_amount)
		ActionType.RAISE:
			if not legal.can_raise:
				return _reject("当前不能加注")
			if amount < legal.min_raise_to or amount > legal.max_raise_to:
				return _reject("加注到 %d 超出合法范围 [%d, %d]" % [amount, legal.min_raise_to, legal.max_raise_to])
			_pay(p, amount - p.current_bet)
			_register_raise(p, amount)
		ActionType.ALL_IN:
			if p.chips <= 0:
				return _reject("没有筹码可全下")
			var total := p.current_bet + p.chips
			if total > current_high and raise_blocked.get(p.seat_index, false):
				return _reject("不足额全下后，已行动玩家只能跟注或弃牌")
			_pay(p, p.chips)
			if total > current_high:
				_register_raise(p, total)
		_:
			return _reject("未知动作类型: %d" % type)

	acted[p.seat_index] = true
	if p.status == PlayerState.Status.ACTIVE and p.chips == 0:
		p.status = PlayerState.Status.ALL_IN
	cursor = (cursor + 1) % maxi(order.size(), 1)
	return true


## 所有未弃牌未全下者下注齐平且均已行动；或仅剩一名可行动玩家且无注可跟。
func is_round_complete() -> bool:
	var active: Array[PlayerState] = []
	for p in players:
		if p.status == PlayerState.Status.ACTIVE:
			active.append(p)
	if active.is_empty():
		return true
	# 仅剩一人能行动且无注可跟（其余均弃牌或全下），无事可做
	if active.size() == 1 and active[0].current_bet == current_high:
		return true
	for p in active:
		if not acted.get(p.seat_index, false):
			return false
		if p.current_bet != current_high:
			return false
	return true


func _pay(p: PlayerState, amount: int) -> void:
	var actual := mini(amount, p.chips)
	p.chips -= actual
	p.current_bet += actual
	p.hand_total_bet += actual


## 登记一次加注（总下注额超过 current_high）。
func _register_raise(p: PlayerState, to_amount: int) -> void:
	var inc := to_amount - current_high
	current_high = to_amount
	if inc >= last_raise_increment:
		# 全额加注：重新开启所有可行动玩家的行动权
		last_raise_increment = inc
		for q in players:
			if q != p and q.status == PlayerState.Status.ACTIVE:
				acted[q.seat_index] = false
				raise_blocked[q.seat_index] = false
	else:
		# 不足额（仅全下可能出现）：已行动者须回应，但失去再加注权
		for q in players:
			if q != p and q.status == PlayerState.Status.ACTIVE and acted.get(q.seat_index, false):
				acted[q.seat_index] = false
				raise_blocked[q.seat_index] = true


func _by_seat(seat: int) -> PlayerState:
	for p in players:
		if p.seat_index == seat:
			return p
	return null


func _reject(msg: String) -> bool:
	push_error("BettingRound: " + msg)
	return false
