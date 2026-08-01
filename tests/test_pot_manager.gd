extends "res://tests/test_base.gd"
## PotManager：分层建池（单边池、多全下多层池、弃牌者贡献）与结算（平局分池、余数分配）。


func test_single_pot() -> void:
	var players: Array[PlayerState] = [
		make_player(0, 0, 0, 100),
		make_player(1, 0, 0, 100),
		make_player(2, 0, 0, 100),
	]
	var pots := PotManager.build_pots(players)
	expect_eq(pots.size(), 1, "等额下注只有一个池")
	expect_eq(pots[0].amount, 300, "池金额 300")
	expect_eq(pots[0].eligible, [0, 1, 2], "三家均有资格")


func test_multi_all_in_layers() -> void:
	# A 全下 50，B 全下 100，C 打满 200
	var players: Array[PlayerState] = [
		make_player(0, 0, 0, 50),
		make_player(1, 0, 0, 100),
		make_player(2, 0, 0, 200),
	]
	var pots := PotManager.build_pots(players)
	expect_eq(pots.size(), 3, "应拆出三层池")
	expect_eq(pots[0].amount, 150, "主池 50×3")
	expect_eq(pots[0].eligible, [0, 1, 2], "主池三家有资格")
	expect_eq(pots[1].amount, 100, "边池1 (100-50)×2")
	expect_eq(pots[1].eligible, [1, 2], "边池1 仅 B、C")
	expect_eq(pots[2].amount, 100, "边池2 (200-100)×1")
	expect_eq(pots[2].eligible, [2], "边池2 仅 C")


func test_folded_player_contributes_but_not_eligible() -> void:
	var a := make_player(0, 0, 0, 50)
	a.status = PlayerState.Status.FOLDED
	var players: Array[PlayerState] = [
		a,
		make_player(1, 0, 0, 100),
		make_player(2, 0, 0, 100),
	]
	var pots := PotManager.build_pots(players)
	expect_eq(pots.size(), 2, "弃牌者的下注层级仍参与拆池")
	expect_eq(pots[0].amount, 150, "主池含弃牌者的 50")
	expect_eq(pots[0].eligible, [1, 2], "弃牌者无资格赢池")
	expect_eq(pots[1].amount, 100, "边池 50×2")
	expect_eq(pots[1].eligible, [1, 2], "边池资格不变")


func _settle(pots: Array, players: Array[PlayerState], community: String, button: int) -> Array:
	return PotManager.settle(pots, players, cards(community), button)


func test_settle_layered_pots() -> void:
	# A 牌最大但只全下 50，只能赢主池；B 牌其次赢边池
	var a := make_player(0, 0, 0, 50)
	a.hole_cards = cards("As Ah")
	var b := make_player(1, 0, 0, 100)
	b.hole_cards = cards("Kd Kc")
	var c := make_player(2, 0, 0, 200)
	c.hole_cards = cards("2d 3d")
	var players: Array[PlayerState] = [a, b, c]
	var pots := PotManager.build_pots(players)
	# 公共牌无关联：A 一对A 最大，B 一对K 其次，C 高牌
	var awards := _settle(pots, players, "7h 8s 9c Td 4c", 0)
	expect_eq(awards.size(), 3, "三个池各产生一条结算")
	var by_pot := {}
	for aw in awards:
		by_pot[aw.pot_index] = aw
	expect_eq(by_pot[0].seat, 0, "主池归 A")
	expect_eq(by_pot[0].amount, 150, "主池 150")
	expect_eq(by_pot[1].seat, 1, "边池1 归 B")
	expect_eq(by_pot[1].amount, 100, "边池1 100")
	expect_eq(by_pot[2].seat, 2, "边池2 归 C（唯一有资格者）")
	expect_eq(by_pot[2].amount, 100, "边池2 100")


func test_settle_split_pot() -> void:
	# 公共牌 Broadway，两家平局分池
	var a := make_player(0, 0, 0, 100)
	a.hole_cards = cards("2d 3c")
	var b := make_player(1, 0, 0, 100)
	b.hole_cards = cards("4d 5c")
	var players: Array[PlayerState] = [a, b]
	var pots := PotManager.build_pots(players)
	var awards := _settle(pots, players, "As Kd Qc Jh Ts", 0)
	expect_eq(awards.size(), 2, "平局两家分池")
	expect_eq(awards[0].amount, 100, "平分 100")
	expect_eq(awards[1].amount, 100, "平分 100")


func test_settle_remainder_to_first_after_button() -> void:
	# 弃牌者贡献使池 40，三家平局：各 13，余 1 归按钮后第一位赢家
	var a := make_player(0, 0, 0, 10)
	a.hole_cards = cards("2d 3c")
	a.status = PlayerState.Status.FOLDED
	var b := make_player(1, 0, 0, 10)
	b.hole_cards = cards("4d 5c")
	var c := make_player(2, 0, 0, 10)
	c.hole_cards = cards("6d 8c")
	var d := make_player(3, 0, 0, 10)
	d.hole_cards = cards("9d Tc")
	var players: Array[PlayerState] = [a, b, c, d]
	var pots := PotManager.build_pots(players)
	expect_eq(pots.size(), 1, "单层池")
	expect_eq(pots[0].amount, 40, "池 40（含弃牌者 10）")
	expect_eq(pots[0].eligible, [1, 2, 3], "弃牌者无资格")
	var awards := _settle(pots, players, "As Kd Qc Jh Ts", 0)  # 按钮在座位 0
	var by_seat := {}
	for aw in awards:
		by_seat[aw.seat] = aw.amount
	expect_eq(by_seat[1], 14, "按钮（座位0）后第一位赢家座位 1 得余数")
	expect_eq(by_seat[2], 13, "座位 2 分 13")
	expect_eq(by_seat[3], 13, "座位 3 分 13")


func test_settle_hand_rank_returned() -> void:
	var a := make_player(0, 0, 0, 100)
	a.hole_cards = cards("As Ah")
	var players: Array[PlayerState] = [a]
	var pots := PotManager.build_pots(players)
	var awards := _settle(pots, players, "7h 8s 9c Td 4c", 0)
	expect_eq(awards.size(), 1, "单人结算")
	expect_eq(awards[0].hand_rank.category, HandEvaluator.Category.ONE_PAIR, "结算应带回牌型")
