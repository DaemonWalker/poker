class_name ResultUI extends Control
## 结算界面：名次表（冠军置顶高亮）+ 夺冠奖杯/彩带粒子（A10 自 TableScene 迁移）
## + 再来一局（同配置）/ 返回主菜单。StatsManager 由逻辑层自动记录，本界面零写入。

var _ai_count := 5
var _config: TournamentManager.TournamentConfig = null


## 由 Main.change_scene 传入：{win, rank, total, standings[{rank,name,is_human}], ai_count, config}
func setup(params: Dictionary) -> void:
	_ai_count = int(params.get("ai_count", 5))
	_config = params.get("config")
	_build(params)


func _ready() -> void:
	if get_child_count() == 0:
		# 无参数直接运行（调试用）：占位展示
		_build({"win": false, "rank": 1, "total": 0, "standings": []})


func _build(params: Dictionary) -> void:
	var win: bool = params.get("win", false)
	var rank: int = int(params.get("rank", 0))
	var total: int = int(params.get("total", 0))
	var standings: Array = params.get("standings", [])

	UITheme.apply(self)
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
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	# 冠军奖杯视觉（占位：大号 🏆 标题，素材替换属 M8）
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if win:
		title.text = "🏆 夺冠！"
		title.add_theme_font_size_override("font_size", 48)
		title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	else:
		title.text = "第 %d 名 / 共 %d 人" % [rank, total]
		title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	# 名次表：冠军置顶高亮，人类行蓝字标"（你）"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	vbox.add_child(list)
	for entry in standings:
		var e_rank: int = entry.rank
		var e_name: String = entry.name
		var row := Label.new()
		row.text = "第 %d 名 · %s" % [e_rank, e_name]
		if entry.is_human:
			row.text += "（你）"
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if e_rank == 1:
			row.text = "🏆 " + row.text
			row.add_theme_font_size_override("font_size", 22)
			row.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		elif entry.is_human:
			row.add_theme_color_override("font_color", Color(0.6, 0.9, 1))
		list.add_child(row)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var again_btn := Button.new()
	again_btn.text = "再来一局"
	again_btn.custom_minimum_size = Vector2(160, 44)
	btn_row.add_child(again_btn)
	again_btn.pressed.connect(_on_again)

	var menu_btn := Button.new()
	menu_btn.text = "返回主菜单"
	menu_btn.custom_minimum_size = Vector2(160, 44)
	btn_row.add_child(menu_btn)
	menu_btn.pressed.connect(_on_menu)

	if win:
		# A10 夺冠：彩带粒子 + S9 音效
		AudioManager.play(&"win")
		_spawn_confetti()


## A10：彩带粒子（参数自 TableScene._spawn_confetti 原样迁移）。
func _spawn_confetti() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(640, -10)
	p.amount = 64
	p.lifetime = 2.0
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 300.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.0
	p.color = Color(1, 0.85, 0.2)
	add_child(p)
	p.emitting = true


func _on_again() -> void:
	AudioManager.play(&"click")
	var m := get_parent() as Main
	if m != null:
		m.start_new_tournament(_ai_count, _config)


func _on_menu() -> void:
	AudioManager.play(&"click")
	var m := get_parent() as Main
	if m != null:
		m.change_scene("main_menu")
