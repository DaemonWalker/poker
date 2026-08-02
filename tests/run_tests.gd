extends SceneTree
## 无头模式测试运行器：godot --headless --script tests/run_tests.gd
## 顺序执行各测试套件中所有 test_ 开头的方法，失败计数，非零退出。

func _init() -> void:
	var suites := [
		preload("res://tests/test_deck.gd").new(),
		preload("res://tests/test_hand_evaluator.gd").new(),
		preload("res://tests/test_betting_round.gd").new(),
		preload("res://tests/test_pot_manager.gd").new(),
		preload("res://tests/test_hand_controller.gd").new(),
		preload("res://tests/test_tournament.gd").new(),
		preload("res://tests/test_save_load.gd").new(),
		preload("res://tests/test_easy_mode.gd").new(),
	]
	var total_checks := 0
	var total_failures := 0
	for suite in suites:
		for m in suite.get_method_list():
			if m.name.begins_with("test_"):
				suite.current = m.name
				suite.call(m.name)
		total_checks += suite.checks
		total_failures += suite.failures
		var suite_name: String = suite.get_script().resource_path.get_file()
		print("%s: %d 项断言，%d 个失败" % [suite_name, suite.checks, suite.failures])
	print("----------------------------------------")
	if total_failures == 0:
		print("全部通过：%d 项断言" % total_checks)
		quit(0)
	else:
		printerr("失败 %d / %d 项断言" % [total_failures, total_checks])
		quit(1)
