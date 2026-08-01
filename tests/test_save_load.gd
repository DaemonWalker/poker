extends "res://tests/test_base.gd"
## 存档/恢复测试：手牌边界存档 → 重新加载 → 状态逐项一致，继续打结果可复现。

const TEST_SAVE := "user://save/test_saveload.save"
const TEST_STATS := "user://save/test_saveload_stats.save"


func _init() -> void:
	DirAccess.remove_absolute(TEST_SAVE)
	DirAccess.remove_absolute(TEST_STATS)


func _new_tm() -> TournamentManager:
	return TournamentManager.new(SaveManager.new(TEST_SAVE), StatsManager.new(TEST_STATS))


func _run_hands(tm: TournamentManager, n: int) -> void:
	for _i in n:
		if tm.finished:
			return
		tm.run_next_hand()
		# 人类代打决策器按手数播种，保证存档前后决策序列一致
		drive_waiting(tm, AIDecider.new(tm.hand_count_total))
		tm.pop_events()


func test_save_load_roundtrip() -> void:
	var tm := _new_tm()
	tm.start_new(TournamentManager.TournamentConfig.default(), 4, 77)
	_run_hands(tm, 3)
	check(tm.save_manager.has_save(), "手牌边界应自动存档")

	var reloaded := _new_tm()
	check(reloaded.load_save(), "应能加载存档")

	# 状态字段逐项一致
	var a := tm.to_dict()
	var b := reloaded.to_dict()
	expect_eq(b.button_seat, a.button_seat, "按钮位置")
	expect_eq(b.blind_level, a.blind_level, "盲注级别")
	expect_eq(b.hands_played, a.hands_played, "本级别手数")
	expect_eq(b.hand_count_total, a.hand_count_total, "总手数")
	expect_eq(b.eliminated, a.eliminated, "淘汰顺序")
	expect_eq(b.rng_state, a.rng_state, "RNG 状态（下一手种子序列）")
	expect_eq(b.players.size(), a.players.size(), "玩家数")
	for i in a.players.size():
		var pa: Dictionary = a.players[i]
		var pb: Dictionary = b.players[i]
		for key in ["seat_index", "name", "avatar_id", "is_human", "ai_profile", "chips", "status"]:
			expect_eq(pb[key], pa[key], "玩家 %d 字段 %s" % [i, key])


func test_load_continue_reproducible() -> void:
	# 深筹码保证 5 手内锦标赛不会结束（否则结束态不参与"继续打"对比）
	var cfg := TournamentManager.TournamentConfig.default()
	cfg.starting_chips = 100000
	var tm := _new_tm()
	tm.start_new(cfg, 4, 88)
	_run_hands(tm, 3)
	check(not tm.finished, "前置：3 手后锦标赛未结束")
	var snapshot := tm.to_dict()

	# 原实例继续打 2 手
	_run_hands(tm, 2)

	# 从存档恢复的新实例继续打 2 手：结果应与原实例一致
	var reloaded := _new_tm()
	check(reloaded.from_dict(snapshot), "应从字典恢复")
	_run_hands(reloaded, 2)

	var a := tm.to_dict()
	var b := reloaded.to_dict()
	expect_eq(b.hand_count_total, a.hand_count_total, "总手数一致")
	expect_eq(b.eliminated, a.eliminated, "淘汰顺序一致")
	for i in a.players.size():
		expect_eq(b.players[i].chips, a.players[i].chips, "玩家 %d 筹码一致" % i)


func test_version_mismatch_discarded() -> void:
	var tm := _new_tm()
	tm.start_new(TournamentManager.TournamentConfig.default(), 2, 5)
	_run_hands(tm, 1)
	var d := tm.save_manager.load()
	d.version = 999
	tm.save_manager.save(d)

	var reloaded := _new_tm()
	check(not reloaded.load_save(), "版本不匹配应拒绝加载")


func test_clear_save() -> void:
	var tm := _new_tm()
	tm.start_new(TournamentManager.TournamentConfig.default(), 2, 5)
	check(tm.save_manager.has_save(), "开局即自动存档")
	tm.save_manager.clear()
	check(not tm.save_manager.has_save(), "清除后无存档")
	check(not _new_tm().load_save(), "无存档时加载失败")
