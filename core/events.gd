class_name Events extends RefCounted
## 逻辑层 → 表现层的事件定义（TECH_DESIGN 第 5 章）。
## 事件即 Dictionary：{type, ...payload}，统一用本类工厂函数构造以保证字段名一致。

enum Type {
	HAND_START,        # {hand_no, button_seat, sb, bb}
	DEAL_HOLE,         # {seat, cards(仅人类可见，AI 为 [])}
	ACTION_REQUIRED,   # {seat, legal_actions, deadline_ms}（人类玩家回合，队列停住）
	PLAYER_ACTION,     # {seat, action, amount, chips_left}
	DEAL_FLOP,         # {cards: Array[Card](3)}
	DEAL_TURN,         # {card}
	DEAL_RIVER,        # {card}
	ROUND_END,         # {pot}(收拢本轮下注后的底池总额)
	SHOWDOWN,          # {reveals: [{seat, cards, hand_name}]}
	POT_AWARD,         # {seat, amount, pot_index, hand_name}
	ELIMINATED,        # {seat, rank}
	BLIND_UP,          # {level, sb, bb}
	HAND_END,          # {}
	TOURNAMENT_WIN,    # {}
	TOURNAMENT_LOSE,   # {rank}
}

## 人类行动倒计时（毫秒）；设置界面可改写（0 = 关闭倒计时，见 ActionPanel）。
static var DEFAULT_DEADLINE_MS := 30000


static func hand_start(hand_no: int, button_seat: int, sb: int, bb: int) -> Dictionary:
	return {"type": Type.HAND_START, "hand_no": hand_no, "button_seat": button_seat, "sb": sb, "bb": bb}


static func deal_hole(seat: int, cards: Array = []) -> Dictionary:
	return {"type": Type.DEAL_HOLE, "seat": seat, "cards": cards}


## deadline_ms 传负值（默认）时取当前 DEFAULT_DEADLINE_MS（默认参数须为常量，故用哨兵值）。
static func action_required(seat: int, legal_actions: Dictionary, deadline_ms: int = -1) -> Dictionary:
	if deadline_ms < 0:
		deadline_ms = DEFAULT_DEADLINE_MS
	return {"type": Type.ACTION_REQUIRED, "seat": seat, "legal_actions": legal_actions, "deadline_ms": deadline_ms}


static func player_action(seat: int, action: int, amount: int, chips_left: int) -> Dictionary:
	return {"type": Type.PLAYER_ACTION, "seat": seat, "action": action, "amount": amount, "chips_left": chips_left}


static func deal_flop(cards: Array) -> Dictionary:
	return {"type": Type.DEAL_FLOP, "cards": cards}


static func deal_turn(card: Card) -> Dictionary:
	return {"type": Type.DEAL_TURN, "card": card}


static func deal_river(card: Card) -> Dictionary:
	return {"type": Type.DEAL_RIVER, "card": card}


static func round_end(pot: int) -> Dictionary:
	return {"type": Type.ROUND_END, "pot": pot}


static func showdown(reveals: Array) -> Dictionary:
	return {"type": Type.SHOWDOWN, "reveals": reveals}


static func pot_award(seat: int, amount: int, pot_index: int, hand_name: String) -> Dictionary:
	return {"type": Type.POT_AWARD, "seat": seat, "amount": amount, "pot_index": pot_index, "hand_name": hand_name}


static func eliminated(seat: int, rank: int) -> Dictionary:
	return {"type": Type.ELIMINATED, "seat": seat, "rank": rank}


static func blind_up(level: int, sb: int, bb: int) -> Dictionary:
	return {"type": Type.BLIND_UP, "level": level, "sb": sb, "bb": bb}


static func hand_end() -> Dictionary:
	return {"type": Type.HAND_END}


static func tournament_win() -> Dictionary:
	return {"type": Type.TOURNAMENT_WIN}


static func tournament_lose(rank: int) -> Dictionary:
	return {"type": Type.TOURNAMENT_LOSE, "rank": rank}
