extends "res://tests/test_base.gd"
## BettingRound：合法动作集合、最小加注边界、跟注全下、不足额全下封锁再加注、轮次完成判定。


# 翻牌前场景：座位 0=SB(10)，1=BB(20)，2=UTG 先行动。大盲 20。
func _preflop() -> Array:
	var players: Array[PlayerState] = [
		make_player(0, 990, 10),
		make_player(1, 980, 20),
		make_player(2, 1000),
	]
	return [players, BettingRound.new(players, 2, 20)]


func test_legal_actions_preflop_utg() -> void:
	var ctx := _preflop()
	var round: BettingRound = ctx[1]
	var utg: PlayerState = ctx[0][2]
	var legal := round.get_legal_actions(utg)
	check(not legal.can_check, "UTG 面对大盲不能过牌")
	check(legal.can_call, "UTG 应能跟注")
	expect_eq(legal.call_amount, 20, "跟注额应为大盲")
	expect_eq(legal.min_raise_to, 40, "翻牌前最小加注到 2 倍大盲")
	expect_eq(legal.max_raise_to, 1000, "最大加注为全部筹码")
	check(legal.can_raise, "UTG 应能加注")
	check(legal.can_all_in, "UTG 应能全下")


func test_min_raise_boundary() -> void:
	var ctx := _preflop()
	var round: BettingRound = ctx[1]
	var players: Array = ctx[0]
	var utg: PlayerState = players[2]
	check(not round.apply_action(utg, raise_to(39)), "加注到 39 应被拒绝（小于最小加注）")
	expect_eq(utg.chips, 1000, "非法动作不应扣筹码")
	check(round.apply_action(utg, raise_to(40)), "加注到 40 应被接受")
	expect_eq(utg.chips, 960, "加注到 40 应扣 40")
	expect_eq(round.current_high, 40, "最高下注应变为 40")
	expect_eq(round.last_raise_increment, 20, "加注增量仍为 20")
	var legal_sb := round.get_legal_actions(players[0])
	expect_eq(legal_sb.min_raise_to, 60, "下一家最小加注到 60")
	expect_eq(legal_sb.call_amount, 30, "SB 需补 30")


func test_raise_reopens_action() -> void:
	var ctx := _preflop()
	var round: BettingRound = ctx[1]
	var players: Array = ctx[0]
	var utg: PlayerState = players[2]
	var sb: PlayerState = players[0]
	var bb: PlayerState = players[1]
	check(round.apply_action(utg, raise_to(40)), "UTG 加注")
	check(round.apply_action(sb, call_action()), "SB 跟注")
	check(round.apply_action(bb, call_action()), "BB 跟注")
	check(round.is_round_complete(), "三家齐平后轮次应结束")


func test_preflop_bb_option() -> void:
	# 全部跟注后大盲仍有行动权（option）
	var ctx := _preflop()
	var round: BettingRound = ctx[1]
	var players: Array = ctx[0]
	check(round.apply_action(players[2], call_action()), "UTG 跟注")
	check(round.apply_action(players[0], call_action()), "SB 补齐")
	check(not round.is_round_complete(), "BB 未行动，轮次不应结束")
	check(round.apply_action(players[1], check_action()), "BB 过牌")
	check(round.is_round_complete(), "BB 过牌后轮次结束")


func test_call_all_in_short_stack() -> void:
	var players: Array[PlayerState] = [
		make_player(0, 1000),
		make_player(1, 15),  # 短筹码
	]
	var round := BettingRound.new(players, 0, 20)
	check(round.apply_action(players[0], raise_to(100)), "P0 加注到 100")
	var legal := round.get_legal_actions(players[1])
	expect_eq(legal.call_amount, 15, "短筹码跟注额被截断为全部筹码")
	check(not legal.can_raise, "短筹码无力加注")
	check(round.apply_action(players[1], call_action()), "跟注即全下")
	expect_eq(players[1].status, PlayerState.Status.ALL_IN, "跟光筹码应为全下状态")
	check(round.is_round_complete(), "P0 无注可跟，轮次应结束")


func test_short_all_in_blocks_reraise() -> void:
	# 翻牌后：P0 下注 20，P1 跟注，P2 不足额全下到 30
	var players: Array[PlayerState] = [
		make_player(0, 1000),
		make_player(1, 1000),
		make_player(2, 30),
	]
	var round := BettingRound.new(players, 0, 20)
	check(round.apply_action(players[0], raise_to(20)), "P0 下注 20")
	check(round.apply_action(players[1], call_action()), "P1 跟注 20")
	check(round.apply_action(players[2], all_in()), "P2 全下 30（不足最小加注）")
	expect_eq(players[2].status, PlayerState.Status.ALL_IN, "P2 应为全下状态")
	expect_eq(round.current_high, 30, "最高下注应变为 30")
	expect_eq(round.last_raise_increment, 20, "不足额全下不改变加注增量")
	# P0 已行动过：须回应 10，但失去再加注权
	var legal0 := round.get_legal_actions(players[0])
	expect_eq(legal0.call_amount, 10, "P0 需补 10")
	check(not legal0.can_raise, "P0 被封锁再加注权")
	check(not round.apply_action(players[0], raise_to(60)), "P0 加注应被拒绝")
	check(round.apply_action(players[0], call_action()), "P0 跟注")
	var legal1 := round.get_legal_actions(players[1])
	check(not legal1.can_raise, "P1 同样被封锁再加注权")
	check(round.apply_action(players[1], call_action()), "P1 跟注")
	check(round.is_round_complete(), "全部齐平后轮次结束")


func test_full_raise_after_short_all_in_reopens() -> void:
	# P2 不足额全下到 30 后，未行动过的玩家仍可正常加注
	var players: Array[PlayerState] = [
		make_player(0, 1000),
		make_player(1, 1000),
		make_player(2, 30),
		make_player(3, 1000),
	]
	var round := BettingRound.new(players, 0, 20)
	check(round.apply_action(players[0], raise_to(20)), "P0 下注")
	check(round.apply_action(players[1], call_action()), "P1 跟注")
	check(round.apply_action(players[2], all_in()), "P2 不足额全下到 30")
	var legal3 := round.get_legal_actions(players[3])
	check(legal3.can_raise, "P3 未行动过，仍可加注")
	expect_eq(legal3.min_raise_to, 50, "P3 最小加注到 30+20")
	check(round.apply_action(players[3], raise_to(50)), "P3 加注到 50")
	# 全额加注后，之前被封锁的玩家恢复加注权
	var legal0 := round.get_legal_actions(players[0])
	check(legal0.can_raise, "全额加注后 P0 恢复加注权")


func test_fold_to_single_player_completes() -> void:
	var players: Array[PlayerState] = [
		make_player(0, 1000),
		make_player(1, 1000),
		make_player(2, 1000),
	]
	var round := BettingRound.new(players, 0, 20)
	check(round.apply_action(players[0], fold()), "P0 弃牌")
	check(round.apply_action(players[1], fold()), "P1 弃牌")
	check(round.is_round_complete(), "仅剩一人时轮次应立即结束")


func test_out_of_turn_rejected() -> void:
	var ctx := _preflop()
	var round: BettingRound = ctx[1]
	var players: Array = ctx[0]
	check(not round.apply_action(players[0], fold()), "未轮到 SB，动作应被拒绝")
	expect_eq(players[0].status, PlayerState.Status.ACTIVE, "被拒动作不应改变状态")


func test_postflop_all_check() -> void:
	var players: Array[PlayerState] = [
		make_player(0, 1000),
		make_player(1, 1000),
	]
	var round := BettingRound.new(players, 0, 20)
	var legal := round.get_legal_actions(players[0])
	check(legal.can_check, "无人下注应可过牌")
	check(not legal.can_call, "无需跟注")
	expect_eq(legal.min_raise_to, 20, "翻牌后最小下注为大盲")
	check(round.apply_action(players[0], check_action()), "P0 过牌")
	check(not round.is_round_complete(), "P1 未行动")
	check(round.apply_action(players[1], check_action()), "P1 过牌")
	check(round.is_round_complete(), "双方过牌后轮次结束")


func test_hand_total_bet_accumulates() -> void:
	var ctx := _preflop()
	var round: BettingRound = ctx[1]
	var players: Array = ctx[0]
	var sb: PlayerState = players[0]
	check(round.apply_action(players[2], call_action()), "UTG 跟注")
	check(round.apply_action(sb, call_action()), "SB 补齐")
	expect_eq(sb.hand_total_bet, 20, "SB 本手累计应为 20（盲注 10 + 补 10）")
	expect_eq(sb.chips, 980, "SB 剩余筹码应为 980")
