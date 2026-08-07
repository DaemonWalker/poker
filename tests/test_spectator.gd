extends "res://tests/test_base.gd"
## 观战模式（config.spectator）：全 AI 开局、DEAL_HOLE 公开手牌、
## 无 ACTION_REQUIRED 挂起、不写进度存档、不计战绩。

const TEST_SAVE := "user://save/test_spectator.save"
const TEST_STATS := "user://save/test_spectator_stats.save"


func _init() -> void:
	DirAccess.remove_absolute(TEST_SAVE)
	DirAccess.remove_absolute(TEST_STATS)


func _config() -> TournamentManager.TournamentConfig:
	var config := TournamentManager.TournamentConfig.default()
	config.spectator = true
	return config


func _new_tm() -> TournamentManager:
	return TournamentManager.new(SaveManager.new(TEST_SAVE), StatsManager.new(TEST_STATS))


func test_spectator_all_ai() -> void:
	var tm := _new_tm()
	tm.start_new(_config(), 4, 42)
	expect_eq(tm.players.size(), 5, "观战总人数 = ai_count + 1")
	var all_ai := true
	for p in tm.players:
		if p.is_human:
			all_ai = false
	check(all_ai, "观战模式不应有人类玩家")
	check(tm.human() == null, "human() 应返回 null")
	# 显示身份仍不重复（含 0 号位）
	var names := {}
	for p in tm.players:
		check(not names.has(p.name), "AI 显示身份不应重复: " + p.name)
		names[p.name] = true


func test_spectator_deal_hole_reveals_all() -> void:
	var tm := _new_tm()
	tm.start_new(_config(), 2, 42)
	tm.run_next_hand()
	for e in tm.pop_events():
		if e.type == Events.Type.DEAL_HOLE:
			expect_eq(e.cards.size(), 2, "观战模式 DEAL_HOLE 应公开全部手牌")


func test_spectator_full_tournament_isolated() -> void:
	var sm := SaveManager.new(TEST_SAVE)
	var stm := StatsManager.new(TEST_STATS)
	var tm := TournamentManager.new(sm, stm)
	tm.start_new(_config(), 2, 99)
	var saw_win := false
	var guard := 0
	while not tm.finished:
		guard += 1
		assert(guard < 5000, "观战锦标赛超出手数上限（疑似死循环）")
		tm.run_next_hand()
		check(not tm.is_waiting_for_human(), "观战模式不应挂起等待人类")
		for e in tm.pop_events():
			check(e.type != Events.Type.ACTION_REQUIRED, "观战模式不应出现 ACTION_REQUIRED")
			check(e.type != Events.Type.TOURNAMENT_LOSE, "观战模式不应出现 TOURNAMENT_LOSE")
			if e.type == Events.Type.TOURNAMENT_WIN:
				saw_win = true
	check(tm.finished, "观战锦标赛应能打完")
	check(saw_win, "观战锦标赛应以 TOURNAMENT_WIN 结束")
	expect_eq(tm.alive_count(), 1, "应仅剩一名冠军")
	check(not sm.has_save(), "观战模式不应写进度存档")
	expect_eq(stm.data.total_hands, 0, "观战模式不应记战绩手数")
	expect_eq(stm.data.games_played, 0, "观战模式不应记战绩场次")


func test_spectator_config_serialization() -> void:
	var config := _config()
	var restored := TournamentManager.TournamentConfig.new()
	restored.from_dict(config.to_dict())
	check(restored.spectator, "spectator 应随配置序列化往返保留")


func test_normal_mode_unaffected() -> void:
	# 普通模式 DEAL_HOLE 对 AI 仍为 []，human() 仍为 0 号位
	var tm := _new_tm()
	tm.start_new(TournamentManager.TournamentConfig.default(), 2, 42)
	check(tm.human() != null and tm.human().is_human, "普通模式 human() 应为人类")
	tm.run_next_hand()
	for e in tm.pop_events():
		if e.type == Events.Type.DEAL_HOLE:
			var expected := 2 if e.seat == 0 else 0
			expect_eq(e.cards.size(), expected, "普通模式只有人类手牌公开")
