class_name SettingsUI extends Control
## 设置界面：音量 / 行动倒计时 / 动画速度 / 盲注参数（高级）。
## 全部持久化到 user://save/settings.cfg（GameSettings 与 AudioManager 各管各的段）。

var _deadline_check: CheckBox
var _deadline_spin: SpinBox
var _chips_spin: SpinBox
var _hands_spin: SpinBox


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
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 音量（0~100%，接线 AudioManager，即时生效并持久化）
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 8)
	vbox.add_child(vol_row)
	vol_row.add_child(_make_label("音量"))
	var volume_slider := HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.custom_minimum_size = Vector2(260, 0)
	volume_slider.value = AudioManager.get_volume() * 100.0
	vol_row.add_child(volume_slider)
	var vol_val := _make_label("%d%%" % int(volume_slider.value))
	vol_row.add_child(vol_val)
	volume_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_volume(v / 100.0)
		vol_val.text = "%d%%" % int(v)
	)

	# 行动倒计时：开关 + 秒数（关闭 = deadline_ms 0，面板无进度条不计时）
	var dl_row := HBoxContainer.new()
	dl_row.add_theme_constant_override("separation", 8)
	vbox.add_child(dl_row)
	_deadline_check = CheckBox.new()
	_deadline_check.text = "行动倒计时"
	dl_row.add_child(_deadline_check)
	_deadline_spin = SpinBox.new()
	_deadline_spin.min_value = GameSettings.MIN_DEADLINE_SEC
	_deadline_spin.max_value = GameSettings.MAX_DEADLINE_SEC
	_deadline_spin.suffix = " 秒"
	dl_row.add_child(_deadline_spin)
	var deadline_ms := GameSettings.get_deadline_ms()
	_deadline_check.button_pressed = deadline_ms > 0
	if deadline_ms > 0:
		_deadline_spin.value = clampi(deadline_ms / 1000,
				GameSettings.MIN_DEADLINE_SEC, GameSettings.MAX_DEADLINE_SEC)
	else:
		_deadline_spin.value = 30
	_deadline_spin.editable = deadline_ms > 0
	_deadline_check.toggled.connect(_on_deadline_toggled)
	_deadline_spin.value_changed.connect(_on_deadline_changed)

	# 动画速度：标准（1.0）/ 快速（0.5），进入牌桌时生效
	var anim_row := HBoxContainer.new()
	anim_row.add_theme_constant_override("separation", 8)
	vbox.add_child(anim_row)
	anim_row.add_child(_make_label("动画速度"))
	var anim_option := OptionButton.new()
	anim_option.add_item("标准")
	anim_option.add_item("快速")
	anim_option.selected = 1 if GameSettings.is_anim_fast() else 0
	anim_row.add_child(anim_option)
	anim_option.item_selected.connect(_on_anim_selected)

	# 盲注参数（高级）：起始筹码 / 每级手数，仅对之后新建的锦标赛生效
	vbox.add_child(HSeparator.new())
	var adv := _make_label("盲注参数（高级，仅对之后新建的锦标赛生效）")
	vbox.add_child(adv)

	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 8)
	vbox.add_child(chips_row)
	chips_row.add_child(_make_label("起始筹码"))
	_chips_spin = SpinBox.new()
	_chips_spin.min_value = GameSettings.MIN_STARTING_CHIPS
	_chips_spin.max_value = GameSettings.MAX_STARTING_CHIPS
	_chips_spin.step = 100
	_chips_spin.value = GameSettings.get_starting_chips()
	chips_row.add_child(_chips_spin)
	_chips_spin.value_changed.connect(_on_blinds_changed)

	var hands_row := HBoxContainer.new()
	hands_row.add_theme_constant_override("separation", 8)
	vbox.add_child(hands_row)
	hands_row.add_child(_make_label("每级手数"))
	_hands_spin = SpinBox.new()
	_hands_spin.min_value = GameSettings.MIN_HANDS_PER_LEVEL
	_hands_spin.max_value = GameSettings.MAX_HANDS_PER_LEVEL
	_hands_spin.value = GameSettings.get_hands_per_level()
	hands_row.add_child(_hands_spin)
	_hands_spin.value_changed.connect(_on_blinds_changed)

	var back_btn := Button.new()
	back_btn.text = "返回主菜单"
	back_btn.custom_minimum_size = Vector2(240, 44)
	vbox.add_child(back_btn)
	back_btn.pressed.connect(_on_back)


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _on_deadline_toggled(on: bool) -> void:
	AudioManager.play(&"click")
	_deadline_spin.editable = on
	_apply_deadline()


func _on_deadline_changed(_v: float) -> void:
	_apply_deadline()


func _apply_deadline() -> void:
	if _deadline_check.button_pressed:
		GameSettings.set_deadline_ms(int(_deadline_spin.value) * 1000)
	else:
		GameSettings.set_deadline_ms(0)


func _on_anim_selected(idx: int) -> void:
	AudioManager.play(&"click")
	GameSettings.set_anim_fast(idx == 1)


## 盲注参数：SpinBox 限定合法范围，写入时再 clamp 一次双保险。
func _on_blinds_changed(_v: float) -> void:
	GameSettings.set_blind_params(int(_chips_spin.value), int(_hands_spin.value))


func _on_back() -> void:
	AudioManager.play(&"click")
	var m := get_parent() as Main
	if m != null:
		m.change_scene("main_menu")
