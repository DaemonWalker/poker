class_name PlayerState extends RefCounted
## 玩家数据（锦标赛 + 手牌两个维度），纯数据结构。

enum Status { ACTIVE, FOLDED, ALL_IN, OUT }  # OUT = 锦标赛淘汰

var seat_index: int = -1
var name: String = ""
var avatar_id: String = ""
var is_human: bool = false
var ai_profile: String = ""  # AI 风格标识，人类玩家为空
var chips: int = 0  # 剩余筹码
var hole_cards: Array[Card] = []
var status: Status = Status.ACTIVE
var current_bet: int = 0  # 本轮下注已投入
var hand_total_bet: int = 0  # 本手牌累计投入（边池计算用）
