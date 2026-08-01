class_name Deck extends RefCounted
## 52 张标准扑克牌牌堆。牌堆顶为数组末尾。

var cards: Array[Card] = []


func _init() -> void:
	reset()


func reset() -> void:
	cards.clear()
	for suit in 4:
		for rank in range(2, 15):
			cards.append(Card.new(suit, rank))


## Fisher-Yates 洗牌。seed != 0 时用固定种子（可复现），seed == 0 时随机。
func shuffle(rng_seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


## 弹出牌堆顶。
func draw() -> Card:
	assert(not cards.is_empty(), "牌堆已空")
	return cards.pop_back()


func size() -> int:
	return cards.size()
