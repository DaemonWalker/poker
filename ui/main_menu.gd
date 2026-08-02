class_name MainMenu extends Control
## 主菜单：继续/新建锦标赛（AI 数量 1~8）、战绩统计、设置、退出。
## 布局在 _ready 代码构建（与 SeatUI/CardUI 同一惯例）。

var _continue_btn: Button
var _new_panel: HBoxContainer
var _ai_count_spin: SpinBox
var _confirm_dialog: ConfirmationDialog


func _ready() -> void:
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

	# 标题：Blender 渲染 3D 金字 Logo（assets/ui/logo.png），缺失时降级为文字
	if ResourceLoader.exists("res://assets/ui/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/ui/logo.png")
		logo.custom_minimum_size = Vector2(520, 72)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(logo)
	else:
		var title := Label.new()
		title.text = "德州扑克锦标赛"
		title.add_theme_font_size_override("font_size", 40)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)

	_continue_btn = _make_btn(vbox, "继续锦标赛")
	_continue_btn.disabled = not SaveManager.new().has_save()
	_continue_btn.pressed.connect(_on_continue)

	var new_btn := _make_btn(vbox, "新建锦标赛")
	new_btn.pressed.connect(_on_new_pressed)

	# 新建行：AI 数量选择 + 开始（默认折叠）
	_new_panel = HBoxContainer.new()
	_new_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_new_panel.add_theme_constant_override("separation", 8)
	_new_panel.visible = false
	vbox.add_child(_new_panel)
	var ai_label := Label.new()
	ai_label.text = "AI 数量"
	_new_panel.add_child(ai_label)
	_ai_count_spin = SpinBox.new()
	_ai_count_spin.min_value = 1
	_ai_count_spin.max_value = 8
	_ai_count_spin.value = 5
	_new_panel.add_child(_ai_count_spin)
	var start_btn := Button.new()
	start_btn.text = "开始"
	_new_panel.add_child(start_btn)
	start_btn.pressed.connect(_on_start_new)

	var stats_btn := _make_btn(vbox, "战绩统计")
	stats_btn.pressed.connect(_go.bind("stats"))

	var settings_btn := _make_btn(vbox, "设置")
	settings_btn.pressed.connect(_go.bind("settings"))

	var quit_btn := _make_btn(vbox, "退出")
	quit_btn.pressed.connect(_on_quit)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "覆盖旧存档"
	_confirm_dialog.dialog_text = "已有进行中的锦标赛存档。\n开始新锦标赛将覆盖旧存档，确定吗？"
	_confirm_dialog.ok_button_text = "覆盖并开局"
	_confirm_dialog.cancel_button_text = "取消"
	add_child(_confirm_dialog)
	_confirm_dialog.confirmed.connect(_on_overwrite_confirmed)


func _make_btn(parent: Control, text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 44)
	parent.add_child(btn)
	return btn


func _main() -> Main:
	return get_parent() as Main


func _on_continue() -> void:
	AudioManager.play(&"click")
	var m := _main()
	if m != null:
		m.continue_tournament()


func _on_new_pressed() -> void:
	AudioManager.play(&"click")
	_new_panel.visible = not _new_panel.visible


func _on_start_new() -> void:
	AudioManager.play(&"click")
	if SaveManager.new().has_save():
		_confirm_dialog.popup_centered()
	else:
		_start_new_game()


func _on_overwrite_confirmed() -> void:
	AudioManager.play(&"click")
	SaveManager.new().clear()
	_start_new_game()


func _start_new_game() -> void:
	var m := _main()
	if m != null:
		m.start_new_tournament(int(_ai_count_spin.value))


func _go(scene_name: String) -> void:
	AudioManager.play(&"click")
	var m := _main()
	if m != null:
		m.change_scene(scene_name)


func _on_quit() -> void:
	AudioManager.play(&"click")
	get_tree().quit()
