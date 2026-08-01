extends "res://tests/test_base.gd"
## TournamentManager 全场模拟测试：全 AI（人类座位由 AI 代打）跑完整锦标赛。

const TEST_SAVE := "user://save/test_tournament.save"
const TEST_STATS := "user://save/test_stats.save"
const MAX_HANDS := 2000  # 死循环保护


func _new_tm() -> TournamentManager:
	return TournamentManager.new(SaveManager.new(TEST_SAVE), StatsManager.new(TEST_STATS))


## 跑完整场锦标赛，返回 {hands, end_event}
func _run_tournament(seed: int, ai_count: int, cfg: TournamentManager.TournamentConfig = null) -> Dictionary:
	if cfg == null:
		cfg = TournamentManager.TournamentConfig.default()
	var tm := _new_tm()
	tm.start_new(cfg, ai_count, seed)
	var total_chips := cfg.starting_chips * (ai_count + 1)
	var hands := 0
	var end_event := {}
	while not tm.finished and hands < MAX_HANDS:
		tm.run_next_hand()
		drive_waiting(tm, AIDecider.new(tm.hand_count_total))
		hands += 1
		# 每手结束校验
		var sum := 0
		for p in tm.players:
			sum += p.chips
		expect_eq(sum, total_chips, "筹码守恒（第 %d 手后）" % hands)
		for e in tm.pop_events():
			if e.type == Events.Type.TOURNAMENT_WIN or e.type == Events.Type.TOURNAMENT_LOSE:
				end_event = e
	check(hands < MAX_HANDS, "锦标赛应在 %d 手内结束" % MAX_HANDS)
	check(tm.finished, "锦标赛应产生胜负")
	return {"hands": hands, "end_event": end_event, "tm": tm}


## 完整锦标赛：冠军产生、淘汰顺序合法、统计更新
func test_full_tournament() -> void:
	var r := _run_tournament(42, 5)
	var tm: TournamentManager = r.tm
	check(not r.end_event.is_empty(), "应有 TOURNAMENT_WIN/LOSE 事件")

	# 淘汰顺序合法：座位不重复
	var seen := {}
	for s in tm.eliminated:
		check(not seen.has(s), "淘汰座位不应重复: %d" % s)
		seen[s] = true

	if r.end_event.type == Events.Type.TOURNAMENT_WIN:
		expect_eq(tm.alive_count(), 1, "夺冠时应仅剩人类")
		expect_eq(tm.eliminated.size(), tm.players.size() - 1, "其余全部淘汰")
		expect_eq(tm.stats_manager.data.wins, 1, "战绩：夺冠次数")
	else:
		expect_eq(tm.human().status, PlayerState.Status.OUT, "人类应已出局")
		expect_eq(r.end_event.rank, tm.players.size() - tm.eliminated.find(0), "出局名次")
		expect_eq(tm.stats_manager.data.rank_distribution[r.end_event.rank - 1], 1, "战绩：名次分布")

	expect_eq(tm.stats_manager.data.games_played, 1, "战绩：参赛场次")
	expect_eq(tm.stats_manager.data.total_hands, r.hands, "战绩：总手数")
	check(not tm.save_manager.has_save(), "锦标赛结束后应清除进度存档")


## 多场不同种子锦标赛均能正常产生冠军
func test_multiple_tournaments() -> void:
	for seed in [7, 199, 2026]:
		var r := _run_tournament(seed, 8)
		check(not r.end_event.is_empty(), "种子 %d 应有胜负" % seed)


## 盲注升级：hands_per_level=1 时每手后升一级
func test_blind_up() -> void:
	var cfg := TournamentManager.TournamentConfig.default()
	cfg.hands_per_level = 1
	var tm := _new_tm()
	tm.start_new(cfg, 2, 9)
	tm.run_next_hand()
	drive_waiting(tm, AIDecider.new(1))
	var blind_up_seen := false
	for e in tm.pop_events():
		if e.type == Events.Type.BLIND_UP:
			blind_up_seen = true
			expect_eq(e.level, 1, "升到第 1 级")
			expect_eq([e.sb, e.bb], [15, 30], "第 1 级盲注")
	if not tm.finished:
		check(blind_up_seen, "一手后应触发 BLIND_UP")
		expect_eq(tm.blind_level, 1, "盲注级别应为 1")
		expect_eq(tm.hands_played, 0, "升级后本级别手数归零")


## 盲注级别表超出后翻倍
func test_blind_table_overflow() -> void:
	var cfg := TournamentManager.TournamentConfig.default()
	expect_eq(cfg.blinds_at(0), [10, 20], "第 0 级")
	expect_eq(cfg.blinds_at(9), [200, 400], "第 9 级")
	expect_eq(cfg.blinds_at(10), [400, 800], "第 10 级翻倍")
	expect_eq(cfg.blinds_at(12), [1600, 3200], "第 12 级再翻倍")


## 开局结构：人类坐 0 号位，AI 身份不重复，筹码一致
func test_start_new_layout() -> void:
	var tm := _new_tm()
	tm.start_new(TournamentManager.TournamentConfig.default(), 8, 5)
	expect_eq(tm.players.size(), 9, "9 人桌")
	check(tm.players[0].is_human, "0 号位为人类")
	expect_eq(tm.players[0].name, "你", "人类名字")
	var names := {}
	for i in range(1, 9):
		var p := tm.players[i]
		check(not names.has(p.name), "AI 身份不重复: " + p.name)
		names[p.name] = true
		expect_eq(p.chips, 1000, "起始筹码")
		check(AIProfiles.PROFILES.has(p.ai_profile), "AI 风格合法: " + p.ai_profile)


func _init() -> void:
	# 测试存档路径专用，开始前清理避免上次运行残留
	DirAccess.remove_absolute(TEST_SAVE)
	DirAccess.remove_absolute(TEST_STATS)
