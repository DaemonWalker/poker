extends SceneTree
## 独立锦标赛模拟脚本（AI 冒烟测试）：
##   godot --headless --path . --script tests/simulate.gd -- [场数] [起始种子]
## 全 AI（人类座位由 AI 代打）跑 N 场完整锦标赛，逐手校验筹码守恒，输出统计。

const MAX_HANDS := 2000  # 每场手数上限（死循环保护）
const SIM_SAVE := "user://save/sim_tournament.save"
const SIM_STATS := "user://save/sim_stats.save"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var count: int = args[0].to_int() if args.size() >= 1 else 100
	var base_seed: int = args[1].to_int() if args.size() >= 2 else 1

	DirAccess.remove_absolute(SIM_SAVE)
	DirAccess.remove_absolute(SIM_STATS)

	var failures := 0
	var total_hands := 0
	var min_hands := MAX_HANDS
	var max_hands := 0
	var human_wins := 0
	var human_rank_sum := 0
	var blind_levels_seen := {}

	for i in count:
		var seed := base_seed + i
		var tm := TournamentManager.new(SaveManager.new(SIM_SAVE), StatsManager.new(SIM_STATS))
		tm.start_new(TournamentManager.TournamentConfig.default(), 8, seed)
		var total_chips := tm.config.starting_chips * tm.players.size()
		var hands := 0
		while not tm.finished and hands < MAX_HANDS:
			tm.run_next_hand()
			_drive_waiting(tm)
			hands += 1
			var sum := 0
			for p in tm.players:
				sum += p.chips
			if sum != total_chips:
				printerr("[场 %d 种子 %d] 筹码不守恒：第 %d 手后 %d != %d" % [i, seed, hands, sum, total_chips])
				failures += 1
				break
			for e in tm.pop_events():
				if e.type == Events.Type.BLIND_UP:
					blind_levels_seen[e.level] = true

		if hands >= MAX_HANDS:
			printerr("[场 %d 种子 %d] 超过 %d 手未结束（疑似死循环）" % [i, seed, MAX_HANDS])
			failures += 1
			continue

		total_hands += hands
		min_hands = mini(min_hands, hands)
		max_hands = maxi(max_hands, hands)
		var human_rank := 1
		if tm.human().status == PlayerState.Status.OUT:
			human_rank = tm.players.size() - tm.eliminated.find(0)
		else:
			human_wins += 1
		human_rank_sum += human_rank

	print("----------------------------------------")
	print("模拟 %d 场完成：失败 %d" % [count, failures])
	if count > 0:
		print("手数：平均 %.1f，最少 %d，最多 %d" % [float(total_hands) / count, min_hands, max_hands])
		print("人类夺冠 %d 次（%.1f%%），平均名次 %.2f" % [human_wins, 100.0 * human_wins / count, float(human_rank_sum) / count])
		print("最高盲注级别：%d" % (blind_levels_seen.keys().max() if not blind_levels_seen.is_empty() else 0))

	DirAccess.remove_absolute(SIM_SAVE)
	DirAccess.remove_absolute(SIM_STATS)
	quit(1 if failures > 0 else 0)


## 用 AI 代打人类座位（模拟中无真实人类输入）。
func _drive_waiting(tm: TournamentManager) -> void:
	var decider := AIDecider.new(tm.hand_count_total)
	var guard := 0
	while tm.is_waiting_for_human():
		guard += 1
		if guard > 1000:
			printerr("人类代打超出步数上限（疑似死循环）")
			return
		var hc := tm.hand
		var seat := hc.waiting_seat
		var p: PlayerState = null
		for q in hc.players:
			if q.seat_index == seat:
				p = q
		var legal := hc.round.get_legal_actions(p)
		var action := decider.decide({
			"hole_cards": p.hole_cards, "community": hc.community,
			"legal_actions": legal, "pot_size": hc.pot_size(),
			"call_amount": legal.call_amount, "street": hc.street,
			"big_blind": hc.big_blind, "chips": p.chips,
			"profile": AIProfiles.PROFILE_TAG,
		})
		tm.submit_human_action(action)
