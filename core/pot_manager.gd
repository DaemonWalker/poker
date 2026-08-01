class_name PotManager extends RefCounted
## 底池/边池的分层建池与结算。
##
## 分层算法（TECH_DESIGN 4.3）：
## 1. 取所有 hand_total_bet > 0 的玩家，按 bet 升序去重得到层级 [L1, L2, ...]
## 2. 第 i 层池金额 = (Li - L(i-1)) × 该层及以上玩家数（含已弃牌者，弃牌者只贡献不赢池）
## 3. 每层池记录有资格玩家（bet >= Li 且未弃牌）

## 建池。返回 [{amount, eligible: Array[int](座位号), level}]
static func build_pots(players: Array[PlayerState]) -> Array:
	var levels: Array[int] = []
	for p in players:
		if p.hand_total_bet > 0 and not levels.has(p.hand_total_bet):
			levels.append(p.hand_total_bet)
	levels.sort()
	var pots: Array = []
	var prev := 0
	for l in levels:
		var amount := 0
		var eligible: Array[int] = []
		for p in players:
			if p.hand_total_bet >= l:
				amount += l - prev
				if p.status != PlayerState.Status.FOLDED:
					eligible.append(p.seat_index)
		pots.append({"amount": amount, "eligible": eligible, "level": l})
		prev = l
	return pots


## 结算。对每个池在有资格玩家中比牌，胜者平分；余数从按钮后第一位赢家起按座位顺时针依次分配。
## 返回 [{seat, amount, hand_rank, pot_index}]，供表现层播动画。
static func settle(pots: Array, players: Array[PlayerState], community: Array[Card], button_seat: int) -> Array:
	var awards: Array = []
	for pot_index in pots.size():
		var pot: Dictionary = pots[pot_index]
		var contenders: Array[PlayerState] = []
		for p in players:
			if pot.eligible.has(p.seat_index):
				contenders.append(p)
		if contenders.is_empty():
			continue

		var best: HandEvaluator.HandRank = null
		var winners: Array[PlayerState] = []
		var ranks := {}  # seat -> HandRank
		for p in contenders:
			var seven: Array[Card] = p.hole_cards.duplicate()
			seven.append_array(community)
			var r := HandEvaluator.evaluate(seven)
			ranks[p.seat_index] = r
			var cmp := 1 if best == null else HandEvaluator.compare(r, best)
			if cmp > 0:
				best = r
				winners = [p]
			elif cmp == 0:
				winners.append(p)

		var share: int = pot.amount / winners.size()
		var remainder: int = pot.amount % winners.size()
		# 余数分配顺序：从按钮后第一位赢家起顺时针
		var winner_seats: Array[int] = []
		for w in winners:
			winner_seats.append(w.seat_index)
		var extra := {}
		for i in remainder:
			extra[_rotate_after(winner_seats, button_seat)[i]] = 1

		for w in winners:
			awards.append({
				"seat": w.seat_index,
				"amount": share + extra.get(w.seat_index, 0),
				"hand_rank": ranks[w.seat_index],
				"pot_index": pot_index,
			})
	return awards


## 将升序座位列表轮转，使第一个元素为按钮位之后（大于 button_seat）的第一个座位。
static func _rotate_after(sorted_seats: Array[int], button_seat: int) -> Array[int]:
	sorted_seats.sort()
	var start := 0
	while start < sorted_seats.size() and sorted_seats[start] <= button_seat:
		start += 1
	if start == sorted_seats.size():
		start = 0
	var out: Array[int] = []
	for i in sorted_seats.size():
		out.append(sorted_seats[(start + i) % sorted_seats.size()])
	return out
