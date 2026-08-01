class_name Card extends RefCounted
## 单张扑克牌：花色（0~3）+ 点数（2~14，11=J 12=Q 13=K 14=A）。

enum Suit { SPADES, HEARTS, CLUBS, DIAMONDS }

const RANK_CHARS := "23456789TJQKA"
const SUIT_CHARS := "shcd"

var suit: int
var rank: int


func _init(p_suit: int = 0, p_rank: int = 2) -> void:
	suit = p_suit
	rank = p_rank


## 如 "As"、"Td"。
func to_string_short() -> String:
	return RANK_CHARS[rank - 2] + SUIT_CHARS[suit]


## to_string_short 的逆运算，便于测试用例书写（接受 "As"/"aS" 等大小写混合）。
static func from_string(s: String) -> Card:
	s = s.strip_edges()
	assert(s.length() == 2, "非法牌面字符串: " + s)
	var rank_idx := RANK_CHARS.find(s[0].to_upper())
	var suit_idx := SUIT_CHARS.find(s[1].to_lower())
	assert(rank_idx >= 0 and suit_idx >= 0, "非法牌面字符串: " + s)
	return Card.new(suit_idx, rank_idx + 2)


func _to_string() -> String:
	return to_string_short()
