class_name HandEvaluator extends RefCounted
## 7 选 5 牌力评估。枚举全部 5 张组合取最大，顺子特判 A-2-3-4-5（A 当 1）。

# 牌型枚举，顺序与 GDD 2.2 一致（从小到大）。
enum Category {
	HIGH_CARD,
	ONE_PAIR,
	TWO_PAIR,
	THREE_OF_A_KIND,
	STRAIGHT,
	FLUSH,
	FULL_HOUSE,
	FOUR_OF_A_KIND,
	STRAIGHT_FLUSH,
	ROYAL_FLUSH,
}

const CATEGORY_NAMES := [
	"高牌", "一对", "两对", "三条", "顺子",
	"同花", "葫芦", "四条", "同花顺", "皇家同花顺",
]


## 评估结果：牌型 + 按比较优先级排列的踢脚点数序列。
class HandRank extends RefCounted:
	var category: int = HandEvaluator.Category.HIGH_CARD
	var tiebreakers: Array[int] = []

	func _to_string() -> String:
		return "%s %s" % [HandEvaluator.CATEGORY_NAMES[category], str(tiebreakers)]


## 评估任意 5~7 张牌，返回最优 HandRank。
static func evaluate(cards: Array[Card]) -> HandRank:
	return _evaluate_five(best_five(cards))


## a > b 返回 1，a < b 返回 -1，相等返回 0。
static func compare(a: HandRank, b: HandRank) -> int:
	if a.category != b.category:
		return 1 if a.category > b.category else -1
	for i in mini(a.tiebreakers.size(), b.tiebreakers.size()):
		if a.tiebreakers[i] != b.tiebreakers[i]:
			return 1 if a.tiebreakers[i] > b.tiebreakers[i] else -1
	return 0


## 从 5~7 张牌中挑出最优的 5 张（摊牌展示用）。
static func best_five(cards: Array[Card]) -> Array[Card]:
	var n := cards.size()
	assert(n >= 5 and n <= 7, "只支持 5~7 张牌输入")
	var best_rank: HandRank = null
	var best_combo: Array[Card] = []
	for a in range(n - 4):
		for b in range(a + 1, n - 3):
			for c in range(b + 1, n - 2):
				for d in range(c + 1, n - 1):
					for e in range(d + 1, n):
						var combo: Array[Card] = [cards[a], cards[b], cards[c], cards[d], cards[e]]
						var r := _evaluate_five(combo)
						if best_rank == null or compare(r, best_rank) > 0:
							best_rank = r
							best_combo = combo
	return best_combo


static func category_name(category: int) -> String:
	return CATEGORY_NAMES[category]


## 精确评估 5 张牌。
static func _evaluate_five(five: Array[Card]) -> HandRank:
	var counts := {}  # rank -> 张数
	var suits := {}
	for c in five:
		counts[c.rank] = counts.get(c.rank, 0) + 1
		suits[c.suit] = true

	var is_flush := suits.size() == 1

	var ranks: Array[int] = []
	for r in counts:
		ranks.append(r)
	ranks.sort()
	ranks.reverse()  # 降序

	var straight_high := 0
	if ranks.size() == 5:
		if ranks[0] - ranks[4] == 4:
			straight_high = ranks[0]
		elif ranks == [14, 5, 4, 3, 2]:  # A-2-3-4-5 轮子，A 当 1
			straight_high = 5

	var result := HandRank.new()

	if is_flush and straight_high > 0:
		result.category = Category.ROYAL_FLUSH if straight_high == 14 else Category.STRAIGHT_FLUSH
		result.tiebreakers = [straight_high]
		return result

	# 按 (张数, 点数) 降序分组：[count, rank]
	var groups: Array = []
	for r in counts:
		groups.append([counts[r], r])
	groups.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] > b[1])

	if groups[0][0] == 4:
		result.category = Category.FOUR_OF_A_KIND
		result.tiebreakers = [groups[0][1], groups[1][1]]
	elif groups[0][0] == 3 and groups[1][0] == 2:
		result.category = Category.FULL_HOUSE
		result.tiebreakers = [groups[0][1], groups[1][1]]
	elif is_flush:
		result.category = Category.FLUSH
		result.tiebreakers.assign(ranks)
	elif straight_high > 0:
		result.category = Category.STRAIGHT
		result.tiebreakers = [straight_high]
	elif groups[0][0] == 3:
		result.category = Category.THREE_OF_A_KIND
		result.tiebreakers = [groups[0][1], groups[1][1], groups[2][1]]
	elif groups[0][0] == 2 and groups[1][0] == 2:
		result.category = Category.TWO_PAIR
		result.tiebreakers = [groups[0][1], groups[1][1], groups[2][1]]
	elif groups[0][0] == 2:
		result.category = Category.ONE_PAIR
		result.tiebreakers = [groups[0][1], groups[1][1], groups[2][1], groups[3][1]]
	else:
		result.category = Category.HIGH_CARD
		result.tiebreakers.assign(ranks)
	return result
