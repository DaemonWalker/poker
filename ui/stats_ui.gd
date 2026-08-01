class_name StatsUI extends Control
## 战绩统计界面：只读展示 StatsManager.data 全部字段（GDD 8.2）。


func _ready() -> void:
	UITheme.apply(self)
	var data := StatsManager.new().data

	var bg := TextureRect.new()
	bg.texture = load("res://assets/bg/menu_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "战绩统计"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	if data.games_played == 0:
		var empty := _make_line("还没有参加过锦标赛，去开一局吧！")
		vbox.add_child(empty)
	else:
		var lines: Array[String] = [
			"参赛场次：%d" % data.games_played,
			"夺冠次数：%d" % data.wins,
			"前三次数：%d" % data.top3,
			"总手牌数：%d" % data.total_hands,
			"总赢池次数：%d" % data.pots_won,
			"最高单局筹码峰值：¥%d" % data.chip_peak,
		]
		for line in lines:
			vbox.add_child(_make_line(line))

		vbox.add_child(HSeparator.new())
		var dist_title := _make_line("名次分布")
		vbox.add_child(dist_title)
		var has_dist := false
		for i in data.rank_distribution.size():
			var count: int = data.rank_distribution[i]
			if count == 0:
				continue
			has_dist = true
			vbox.add_child(_make_line("第 %d 名：%d 次 %s" % [i + 1, count, "▮".repeat(mini(count, 20))]))
		if not has_dist:
			vbox.add_child(_make_line("暂无记录"))

	var back_btn := Button.new()
	back_btn.text = "返回主菜单"
	back_btn.custom_minimum_size = Vector2(240, 44)
	vbox.add_child(back_btn)
	back_btn.pressed.connect(_on_back)


func _make_line(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


func _on_back() -> void:
	AudioManager.play(&"click")
	var m := get_parent() as Main
	if m != null:
		m.change_scene("main_menu")
