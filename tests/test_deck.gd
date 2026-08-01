extends "res://tests/test_base.gd"
## Deck 与 Card 的基础测试。


func test_deck_has_52_unique_cards() -> void:
	var deck := Deck.new()
	expect_eq(deck.size(), 52, "新牌堆应为 52 张")
	var seen := {}
	for c in deck.cards:
		seen[c.to_string_short()] = true
	expect_eq(seen.size(), 52, "52 张牌应互不相同")


func test_draw_pops_from_top() -> void:
	var deck := Deck.new()
	var top := deck.cards[deck.cards.size() - 1]
	expect_eq(deck.draw(), top, "draw 应弹出牌堆顶")
	expect_eq(deck.size(), 51, "抽一张后剩 51 张")


func test_shuffle_same_seed_reproducible() -> void:
	var a := Deck.new()
	var b := Deck.new()
	a.shuffle(42)
	b.shuffle(42)
	var sa := []
	var sb := []
	for c in a.cards:
		sa.append(c.to_string_short())
	for c in b.cards:
		sb.append(c.to_string_short())
	expect_eq(sa, sb, "同种子洗牌结果应相同")
	# 洗牌后不应仍是原始顺序
	var orig := []
	var plain := Deck.new()
	for c in plain.cards:
		orig.append(c.to_string_short())
	check(sa != orig, "洗牌后顺序应发生变化（极大概率）")


func test_card_string_roundtrip() -> void:
	for s in ["As", "Td", "2c", "Kh", "Qs", "9d", "Jh"]:
		expect_eq(Card.from_string(s).to_string_short(), s.capitalize(), "牌面字符串应互逆: " + s)
