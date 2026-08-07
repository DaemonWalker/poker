extends "res://tests/test_base.gd"
## 观战胜率（EquityCalculator）：蒙特卡洛收敛、精确枚举、平分份额、取消语义。


func test_remaining_pool_excludes_seen_cards() -> void:
	var holes := {0: cards("As Ah"), 1: cards("Kd Kc"), 2: cards("Qs Js")}
	expect_eq(EquityCalculator._remaining_pool(holes, cards("")).size(), 46, "翻牌前 3 人剩余 46 张")
	expect_eq(EquityCalculator._remaining_pool(holes, cards("2d 7h Tc")).size(), 43, "翻牌圈剩余 43 张")


func test_mc_preflop_aa_vs_kk() -> void:
	var holes := {0: cards("As Ah"), 1: cards("Kd Kc")}
	var job := EquityCalculator.Job.new()
	job.max_iterations = 4000
	EquityCalculator.run_job(job, holes, cards(""), 7)
	check(job.done, "达到迭代上限后应结束")
	check(not job.exact, "翻牌前应走蒙特卡洛")
	expect_eq(job.iterations, 4000, "迭代数应达上限")
	var eq := job.equity()
	# AA vs KK 翻牌前理论值约 81% / 19%（平局约 0.4%）；4000 次抽样标准差约 0.6%
	check(eq[0] > 0.74 and eq[0] < 0.88, "AA 胜率 %.3f 应在 0.74~0.88" % eq[0])
	check(absf(eq[0] + eq[1] - 1.0) < 0.001, "胜率之和应为 1")


func test_mc_reproducible_same_seed() -> void:
	var holes := {0: cards("As Ah"), 1: cards("Kd Kc"), 2: cards("Qs Js")}
	var a := EquityCalculator.Job.new()
	a.max_iterations = 1000
	EquityCalculator.run_job(a, holes, cards(""), 42)
	var b := EquityCalculator.Job.new()
	b.max_iterations = 1000
	EquityCalculator.run_job(b, holes, cards(""), 42)
	expect_eq(a.equity(), b.equity(), "同种子蒙特卡洛结果应完全一致")


func test_exact_river_decided() -> void:
	var holes := {0: cards("As Ah"), 1: cards("Kd Kc")}
	var job := EquityCalculator.Job.new()
	EquityCalculator.run_job(job, holes, cards("2d 7h 9c Jd 3s"), 1)
	check(job.exact and job.done, "河牌应走精确枚举")
	var eq := job.equity()
	expect_eq(eq[0], 1.0, "AA 对已定格牌面必胜")
	expect_eq(eq[1], 0.0, "KK 对已定格牌面必败")


func test_exact_river_board_tie() -> void:
	var holes := {0: cards("2c 3d"), 1: cards("4h 5s")}
	var job := EquityCalculator.Job.new()
	EquityCalculator.run_job(job, holes, cards("As Ks Qs Js Ts"), 1)
	var eq := job.equity()
	expect_eq(eq[0], 0.5, "牌面皇家同花顺两家平分")
	expect_eq(eq[1], 0.5, "牌面皇家同花顺两家平分")


func test_exact_turn_drawing_dead() -> void:
	# 0 号位转牌圈已成皇家同花顺，对手无任何出路
	var holes := {0: cards("Ts 3d"), 1: cards("9h 8h")}
	var job := EquityCalculator.Job.new()
	EquityCalculator.run_job(job, holes, cards("As Ks Qs Js"), 1)
	check(job.exact, "转牌应走精确枚举")
	expect_eq(job.iterations, 44, "剩余 44 张各枚举一次")
	var eq := job.equity()
	expect_eq(eq[0], 1.0, "皇家同花顺无对手出路")
	expect_eq(eq[1], 0.0, "无出路")


func test_exact_flop_combination_count_and_sum() -> void:
	var holes := {0: cards("As Ah"), 1: cards("Kd Kc"), 2: cards("Qs Js")}
	var job := EquityCalculator.Job.new()
	EquityCalculator.run_job(job, holes, cards("2d 7h Tc"), 1)
	check(job.exact, "翻牌圈应走精确枚举")
	expect_eq(job.iterations, 903, "C(43,2) = 903 种转河组合")
	var eq := job.equity()
	var sum := 0.0
	for seat in eq:
		sum += eq[seat]
		check(eq[seat] >= 0.0 and eq[seat] <= 1.0, "胜率应在 0~1")
	check(absf(sum - 1.0) < 0.001, "胜率之和应为 1")


func test_mc_matches_exact_on_turn() -> void:
	var holes := {0: cards("As Ks"), 1: cards("Qh Qd")}
	var community := cards("Js Ts 2d 9c")
	var job_exact := EquityCalculator.Job.new()
	EquityCalculator.run_job(job_exact, holes, community, 1)
	var eq_exact := job_exact.equity()
	# 同局面强制走蒙特卡洛，应与精确值接近（6000 次标准差约 0.6%）
	var pool := EquityCalculator._remaining_pool(holes, community)
	var job_mc := EquityCalculator.Job.new()
	job_mc.max_iterations = 6000
	EquityCalculator._run_monte_carlo(job_mc, holes, community, pool, 123)
	var eq_mc := job_mc.equity()
	check(absf(eq_mc[0] - eq_exact[0]) < 0.05,
			"蒙特卡洛 %.3f 应接近精确值 %.3f" % [eq_mc[0], eq_exact[0]])


func test_cancel_stops_immediately() -> void:
	var holes := {0: cards("As Ah"), 1: cards("Kd Kc")}
	var job := EquityCalculator.Job.new()
	job.cancelled = true
	EquityCalculator.run_job(job, holes, cards(""), 1)
	check(job.done, "取消后应结束")
	expect_eq(job.iterations, 0, "预取消不应产生迭代")


func test_single_player_equity() -> void:
	var job := EquityCalculator.Job.new()
	EquityCalculator.run_job(job, {0: cards("As Kd")}, cards(""), 1)
	check(job.done and job.exact, "单人直接判胜")
	expect_eq(job.equity()[0], 1.0, "唯一在局者胜率 100%")
