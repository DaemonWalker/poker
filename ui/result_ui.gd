class_name ResultUI extends Control
## 结算界面：名次表（冠军置顶高亮）+ 夺冠奖杯/彩带粒子（A10 自 TableScene 迁移）
## + 再来一局（同配置）/ 返回主菜单。StatsManager 由逻辑层自动记录，本界面零写入。

const SPIN_FPS := 12.0

var _ai_count := 5
var _config: TournamentManager.TournamentConfig = null
## 观战模式（params.spectator）：冠军是 AI，标题换措辞，"再来一局"仍走观战。
var _spectator := false
var _trophy_rect: TextureRect = null
var _spin_frames: Array[Texture2D] = []
var _spin_time := 0.0


## 由 Main.change_scene 传入：{win, rank, total, standings[{rank,name,is_human}], ai_count, config, spectator}
func setup(params: Dictionary) -> void:
	_ai_count = int(params.get("ai_count", 5))
	_config = params.get("config")
	_spectator = bool(params.get("spectator", false))
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

	# 冠军奖杯视觉：Blender 渲染；有旋转帧序列（assets/trophy/spin/）则逐帧播放，
	# 否则用静态图（assets/trophy/trophy.png），均缺失时降级为 🏆 文本
	var trophy_tex: Texture2D = null
	if win:
		if ResourceLoader.exists("res://assets/trophy/spin/trophy_spin_00.png"):
			for i in range(16):
				_spin_frames.append(load("res://assets/trophy/spin/trophy_spin_%02d.png" % i))
			trophy_tex = _spin_frames[0]
		elif ResourceLoader.exists("res://assets/trophy/trophy.png"):
			trophy_tex = load("res://assets/trophy/trophy.png")
	if trophy_tex != null:
		var trophy := TextureRect.new()
		trophy.texture = trophy_tex
		trophy.custom_minimum_size = Vector2(128, 128)
		trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(trophy)
		_trophy_rect = trophy
		set_process(true)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if win:
		if _spectator and not standings.is_empty():
			# 观战模式冠军是 AI（standings 首名即冠军）
			title.text = "%s 夺冠" % standings[0].name
		else:
			title.text = "夺冠！" if trophy_tex != null else "🏆 夺冠！"
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
## 有彩带贴图（assets/ui/confetti_*.png，Blender 渲染）时替换默认方块并加随机旋转。
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
	if ResourceLoader.exists("res://assets/ui/confetti_01.png"):
		p.texture = load("res://assets/ui/confetti_0%d.png" % (randi() % 4 + 1))
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.3
		p.angle_min = -180.0
		p.angle_max = 180.0
	else:
		p.scale_amount_min = 3.0
		p.scale_amount_max = 5.0
	p.color = Color(1, 0.85, 0.2)
	add_child(p)
	p.emitting = true


## 奖杯旋转帧序列循环播放。
func _process(delta: float) -> void:
	if _spin_frames.is_empty() or _trophy_rect == null:
		set_process(false)
		return
	_spin_time += delta
	var idx := int(_spin_time * SPIN_FPS) % _spin_frames.size()
	_trophy_rect.texture = _spin_frames[idx]


func _on_again() -> void:
	AudioManager.play(&"click")
	var m := get_parent() as Main
	if m == null:
		return
	if _spectator:
		# 观战"再来一局"：同人数重开全 AI 局（配置由 TableScene 按设置重新构造）
		m.start_spectator(_ai_count)
	else:
		m.start_new_tournament(_ai_count, _config)


func _on_menu() -> void:
	AudioManager.play(&"click")
	var m := get_parent() as Main
	if m != null:
		m.change_scene("main_menu")
