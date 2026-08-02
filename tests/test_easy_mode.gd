extends "res://tests/test_base.gd"
## 简单模式（洗牌偏向人类）：假定摊牌全场最强、同种子可复现、端到端赢池。


func test_rig_human_wins_showdown_layout() -> void:
	for rng_seed in [11, 222, 3333]:
		var hc := _make_rigged_hand(rng_seed)
		var beaten: int = hc._showdown_beaten_count(0, hc._deal_order())
		expect_eq(beaten, hc.players.size() - 1, "seed=%d 玩家应假定摊牌全场最强" % rng_seed)


func test_rig_reproducible() -> void:
	var a := _make_rigged_hand(42)
	var b := _make_rigged_hand(42)
	expect_eq(a.deck.cards.size(), b.deck.cards.size(), "牌堆大小一致")
	var same := true
	for i in a.deck.cards.size():
		var ca: Card = a.deck.cards[i]
		var cb: Card = b.deck.cards[i]
		if ca.suit != cb.suit or ca.rank != cb.rank:
			same = false
	check(same, "同种子洗牌结果应完全一致")


## 玩家全程 过牌/跟注 走到摊牌：简单模式下应赢下底池。
func test_rig_end_to_end_human_wins_pot() -> void:
	for rng_seed in [7, 99, 12345]:
		var hc := _make_rigged_hand(rng_seed)
		hc.start()
		drive_hand(hc, func(_seat: int, legal: Dictionary) -> Dictionary:
			if legal.can_check:
				return check_action()
			if legal.can_call:
				return call_action()
			return all_in()
		)
		var human: PlayerState = hc.players[0]
		check(human.chips > 1000, "seed=%d 简单模式玩家应赢池（筹码 %d）" % [rng_seed, human.chips])


func test_rig_invalid_seat_ignored() -> void:
	var hc := HandController.new(_make_players(), 0, 10, 20, 5, AIDecider.new(5), 1, 99)
	expect_eq(hc.deck.size(), 52, "无效 rig 座位不应影响牌堆")


func test_config_easy_mode_serialization() -> void:
	var config := TournamentManager.TournamentConfig.default()
	config.easy_mode = true
	var restored := TournamentManager.TournamentConfig.new()
	restored.from_dict(config.to_dict())
	check(restored.easy_mode, "easy_mode 应随配置序列化往返保留")


func _make_players() -> Array[PlayerState]:
	var players: Array[PlayerState] = []
	for seat in 3:
		var p := make_player(seat, 1000)
		p.is_human = seat == 0
		players.append(p)
	return players


func _make_rigged_hand(rng_seed: int) -> HandController:
	return HandController.new(_make_players(), 0, 10, 20, rng_seed, AIDecider.new(rng_seed), 1, 0)
