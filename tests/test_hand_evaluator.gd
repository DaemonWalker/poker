extends "res://tests/test_base.gd"
## HandEvaluator：全部 10 种牌型识别、踢脚比较、A2345 顺子、7 选 5 最优、平局判定。


func _cat(s: String) -> int:
	return HandEvaluator.evaluate(cards(s)).category


func test_all_categories() -> void:
	var C := HandEvaluator.Category
	expect_eq(_cat("As Ks Qs Js Ts"), C.ROYAL_FLUSH, "皇家同花顺")
	expect_eq(_cat("9h 8h 7h 6h 5h"), C.STRAIGHT_FLUSH, "同花顺")
	expect_eq(_cat("5h 4h 3h 2h Ah"), C.STRAIGHT_FLUSH, "A2345 同花顺")
	expect_eq(_cat("Ks Kd Kc Kh 2s"), C.FOUR_OF_A_KIND, "四条")
	expect_eq(_cat("Qs Qd Qc 9h 9s"), C.FULL_HOUSE, "葫芦")
	expect_eq(_cat("Ah Jh 8h 5h 2h"), C.FLUSH, "同花")
	expect_eq(_cat("9s 8d 7c 6h 5s"), C.STRAIGHT, "顺子")
	expect_eq(_cat("Ts Td Th 5c 2s"), C.THREE_OF_A_KIND, "三条")
	expect_eq(_cat("Js Jd 8c 8h 3s"), C.TWO_PAIR, "两对")
	expect_eq(_cat("7s 7d Kc 4h 2s"), C.ONE_PAIR, "一对")
	expect_eq(_cat("As Qd 9c 5h 2s"), C.HIGH_CARD, "高牌")


func test_wheel_straight() -> void:
	# A-2-3-4-5 是顺子，高点为 5，小于 6 高顺子
	var wheel := HandEvaluator.evaluate(cards("As 2d 3c 4h 5s"))
	expect_eq(wheel.category, HandEvaluator.Category.STRAIGHT, "A2345 应识别为顺子")
	expect_eq(wheel.tiebreakers, [5], "A2345 高点为 5")
	var six_high := HandEvaluator.evaluate(cards("2s 3d 4c 5h 6s"))
	expect_eq(HandEvaluator.compare(six_high, wheel), 1, "6 高顺子应大于轮子")
	# A-K-Q-J-T 是最大顺子而非别的
	var broadway := HandEvaluator.evaluate(cards("As Kd Qc Jh Ts"))
	expect_eq(broadway.tiebreakers, [14], "Broadway 高点为 A")


func test_tiebreakers() -> void:
	var E := HandEvaluator
	# 同牌型比点数
	expect_eq(E.compare(E.evaluate(cards("As Ac 5d 4h 2s")), E.evaluate(cards("Ks Kc Ad 4h 2s"))), 1, "对A 应大于对K")
	# 同对子比踢脚
	expect_eq(E.compare(E.evaluate(cards("As Ac Kd 4h 2s")), E.evaluate(cards("Ah Ad Qc 4h 2s"))), 1, "对A K踢脚应大于 Q踢脚")
	# 两对比小对子
	expect_eq(E.compare(E.evaluate(cards("9s 9d 2c 2h As")), E.evaluate(cards("8s 8d 7c 7h As"))), 1, "两对先比大对")
	expect_eq(E.compare(E.evaluate(cards("As Ad 3c 3h 2s")), E.evaluate(cards("Ks Kd Qc Qh As"))), 1, "AA33 应大于 KKQQ")
	# 葫芦比三条的点数
	expect_eq(E.compare(E.evaluate(cards("2s 2d 2c Ah As")), E.evaluate(cards("Ks Kd Kc 2h 2s"))), -1, "三条2葫芦应小于三条K葫芦")
	# 顺子比高点
	expect_eq(E.compare(E.evaluate(cards("Ts 9d 8c 7h 6s")), E.evaluate(cards("9s 8d 7c 6h 5s"))), 1, "T 高顺子应大于 9 高顺子")
	# 同花比最大牌
	expect_eq(E.compare(E.evaluate(cards("Ah 2h 3h 4h 6h")), E.evaluate(cards("Kh Qh Jh 9h 8h"))), 1, "A 高同花应大于 K 高同花")


func test_best_of_seven() -> void:
	# 7 张中最优 5 张：牌面能凑出同花顺
	var r := HandEvaluator.evaluate(cards("As Ks Qs Js Ts 2d 3c"))
	expect_eq(r.category, HandEvaluator.Category.ROYAL_FLUSH, "7 选 5 应找出皇家同花顺")
	# 6 张输入也支持
	var r6 := HandEvaluator.evaluate(cards("Ks Kd Kc 2h 2s 3d"))
	expect_eq(r6.category, HandEvaluator.Category.FULL_HOUSE, "6 张输入应支持")
	# 踢脚从 7 张中选优：对A + K 踢脚
	var r7 := HandEvaluator.evaluate(cards("As Ad Kh 7c 5s 3d 2c"))
	expect_eq(r7.tiebreakers, [14, 13, 7, 5], "踢脚应从 7 张中取最优")


func test_best_five_cards() -> void:
	var five := HandEvaluator.best_five(cards("As Ks Qs Js Ts 2d 3c"))
	expect_eq(five.size(), 5, "best_five 应返回 5 张")
	var names := []
	for c in five:
		names.append(c.to_string_short())
	names.sort()
	expect_eq(names, ["As", "Js", "Ks", "Qs", "Ts"], "best_five 应返回同花顺五张")


func test_tie() -> void:
	# 公共牌组成最优五张，双方平局
	var a := HandEvaluator.evaluate(cards("As Kd Qc Jh Ts 2d 3c"))
	var b := HandEvaluator.evaluate(cards("As Kd Qc Jh Ts 9d 9c"))
	expect_eq(HandEvaluator.compare(a, b), 0, "同样 Broadway 应平局")
	# 完全相同的对子+踢脚
	var c1 := HandEvaluator.evaluate(cards("Ah Ad Ks Qd 2c"))
	var c2 := HandEvaluator.evaluate(cards("As Ac Kh Qc 2d"))
	expect_eq(HandEvaluator.compare(c1, c2), 0, "同点同踢脚应平局")
