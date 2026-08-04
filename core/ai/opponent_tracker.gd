class_name OpponentTracker extends RefCounted
## 对手建模（二期）：从整手事件流解析指定座位（人类玩家）的行为统计增量。
## 纯函数、不改 HandController，供 TournamentManager 手牌收尾时调用与单元测试。
## 注意红线：盲注静默扣除无 PLAYER_ACTION 事件——BB 白看牌不算入局，
## SB 补盲发出的 CALL 算主动入局（跟注即算）。

## 解析整手事件（HAND_START ~ HAND_END，允许跨多次 pop 累积），返回一手行为增量：
##   hands     0/1          该座位是否参与本手（vpip 的分母）
##   vpip      bool         翻牌前是否有 call/raise/all_in（主动入池）
##   pfr       bool         翻牌前是否有 raise/all_in
##   aggression  float|null 翻牌后攻击性 raise/(raise+call)；无翻牌后 call/raise 为 null
##   showdown    float|null 摊牌牌力（HandStrength 口径 0~1）；未摊牌为 null
## null 表示本手无该样本，AIMemory 不做对应 EWMA 更新。
static func parse_hand(events: Array, seat: int) -> Dictionary:
	var inc := {"hands": 0, "vpip": false, "pfr": false, "aggression": null, "showdown": null}
	var street := HandController.Street.PREFLOP
	var community: Array[Card] = []
	var post_raises := 0
	var post_calls := 0
	for e in events:
		var t: int = e.get("type", -1)
		match t:
			Events.Type.HAND_START:
				var alive: Array = e.get("alive_seats", [])
				if alive.has(seat):
					inc["hands"] = 1
			Events.Type.DEAL_FLOP:
				street = HandController.Street.FLOP
				for c in e.get("cards", []):
					community.append(c)
			Events.Type.DEAL_TURN:
				street = HandController.Street.TURN
				var turn: Card = e.get("card")
				community.append(turn)
			Events.Type.DEAL_RIVER:
				street = HandController.Street.RIVER
				var river: Card = e.get("card")
				community.append(river)
			Events.Type.PLAYER_ACTION:
				if int(e.get("seat", -1)) != seat:
					continue
				var a: int = e.get("action", -1)
				if street == HandController.Street.PREFLOP:
					if a == BettingRound.ActionType.CALL or a == BettingRound.ActionType.RAISE \
							or a == BettingRound.ActionType.ALL_IN:
						inc["vpip"] = true
					if a == BettingRound.ActionType.RAISE or a == BettingRound.ActionType.ALL_IN:
						inc["pfr"] = true
				elif a == BettingRound.ActionType.RAISE or a == BettingRound.ActionType.ALL_IN:
					post_raises += 1
				elif a == BettingRound.ActionType.CALL:
					post_calls += 1
			Events.Type.SHOWDOWN:
				for r in e.get("reveals", []):
					if int(r.get("seat", -1)) == seat:
						var hole: Array[Card] = r.get("cards", [])
						inc["showdown"] = HandStrength.score(hole, community)
	if post_raises + post_calls > 0:
		inc["aggression"] = float(post_raises) / float(post_raises + post_calls)
	return inc
