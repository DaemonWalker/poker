class_name HandStrength extends RefCounted
## 牌力启发式评分（TECH_DESIGN 4.6），全部返回 0~1。
## 翻牌前：169 种起手牌归类的简化强度表（基于 Sklansky 分组的启发式公式）。
## 翻牌后：成牌强度（HandEvaluator）+ 听牌出路加成（同花听/顺子听补牌数 × 系数）。

## 翻牌前起手牌强度 0~1。hole 为 2 张底牌。
static func preflop_score(hole: Array[Card]) -> float:
	assert(hole.size() == 2, "底牌必须是 2 张")
	var hi: int = maxi(hole[0].rank, hole[1].rank)
	var lo: int = mini(hole[0].rank, hole[1].rank)
	var suited: bool = hole[0].suit == hole[1].suit

	if hi == lo:
		# 对子：22 ≈ 0.50，AA = 1.0
		return 0.50 + float(hi - 2) / 12.0 * 0.50

	# 非对子：两张高牌为主，同花/连张加成，断层扣分
	var score := (float(hi - 2) + float(lo - 2) * 0.6) / 18.0  # 两张牌合计 ≈ 0~0.75
	if suited:
		score += 0.08
	var gap := hi - lo
	if gap == 1:
		score += 0.06  # 连张
	elif gap == 2:
		score += 0.03
	elif gap >= 5:
		score -= 0.04
	return clampf(score, 0.0, 1.0)


## 翻牌后强度 0~1。hole 2 张 + community 3~5 张。
static func postflop_score(hole: Array[Card], community: Array[Card]) -> float:
	var all: Array[Card] = hole.duplicate()
	all.append_array(community)
	var rank := HandEvaluator.evaluate(all)

	# 成牌基础分：牌型映射 + 踢脚微调
	var base := float(rank.category) / float(HandEvaluator.Category.ROYAL_FLUSH)
	var kicker := 0.0
	if not rank.tiebreakers.is_empty():
		kicker = float(rank.tiebreakers[0] - 2) / 12.0 * 0.05
	var score := base + kicker

	# 听牌出路加成
	var outs := _count_outs(hole, community)
	score += float(outs) * 0.02
	return clampf(score, 0.0, 1.0)


## 自动评分：按公共牌数量分流。
static func score(hole: Array[Card], community: Array[Card]) -> float:
	if community.is_empty():
		return preflop_score(hole)
	return postflop_score(hole, community)


## 估算听牌补牌数：同花听 9，两头顺听 8，卡顺 4。仅按当前已知牌粗算（不减重复牌）。
static func _count_outs(hole: Array[Card], community: Array[Card]) -> int:
	var outs := 0
	# 同花听：某花色恰好 4 张
	var suit_counts := {}
	for c in hole:
		suit_counts[c.suit] = suit_counts.get(c.suit, 0) + 1
	for c in community:
		suit_counts[c.suit] = suit_counts.get(c.suit, 0) + 1
	for s in suit_counts:
		if suit_counts[s] == 4:
			outs = maxi(outs, 9)

	# 顺子听：收集点数（A 同时算 1 和 14），找 5 张窗口内恰有 4 张的情况
	var ranks := {}
	for c in hole:
		ranks[c.rank] = true
		if c.rank == 14:
			ranks[1] = true
	for c in community:
		ranks[c.rank] = true
		if c.rank == 14:
			ranks[1] = true
	for low in range(1, 11):  # 顺子最低点 1(A)~10
		var have := 0
		for r in range(low, low + 5):
			if ranks.has(r):
				have += 1
		if have == 4:
			# 缺的牌在两端 → 两头顺 8；在中间 → 卡顺 4
			var missing := -1
			for r in range(low, low + 5):
				if not ranks.has(r):
					missing = r
			var straight_outs := 8 if (missing == low or missing == low + 4) else 4
			outs = maxi(outs, straight_outs)
	return outs
