class_name ActionPanel extends PanelContainer
## 人类玩家操作面板：弃牌 / 过牌·跟注 / 加注(滑条) / 全下(二次确认) + 倒计时条。
## 由 ACTION_REQUIRED 事件的 legal_actions 驱动。

signal action_submitted(action: Dictionary)
signal timed_out()

var _fold_btn: Button
var _check_call_btn: Button
var _raise_btn: Button
var _all_in_btn: Button
var _slider: RaiseSlider
var _timer_bar: ProgressBar

var _legal: Dictionary = {}
var _deadline_ms: int = 0
var _start_ms: int = 0
var _active: bool = false
var _all_in_armed: bool = false


func _ready() -> void:
	UITheme.apply(self)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.95)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	_timer_bar = ProgressBar.new()
	_timer_bar.min_value = 0
	_timer_bar.max_value = 1000
	_timer_bar.value = 1000
	_timer_bar.custom_minimum_size = Vector2(0, 8)
	_timer_bar.show_percentage = false
	vbox.add_child(_timer_bar)

	_slider = RaiseSlider.new()
	vbox.add_child(_slider)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)

	_fold_btn = _make_btn(row, "弃牌")
	_fold_btn.pressed.connect(_submit.bind({"type": BettingRound.ActionType.FOLD, "amount": 0}))
	_style_btn(_fold_btn, Color(0.26, 0.15, 0.16), Color(0.55, 0.30, 0.30), Color(0.95, 0.85, 0.85))

	_check_call_btn = _make_btn(row, "过牌")
	_check_call_btn.pressed.connect(_on_check_call)
	_style_btn(_check_call_btn, Color(0.15, 0.32, 0.20), Color(0.32, 0.60, 0.38), Color(0.88, 1.0, 0.90))

	_raise_btn = _make_btn(row, "加注")
	_raise_btn.pressed.connect(_on_raise)
	_style_btn(_raise_btn, Color(0.55, 0.42, 0.12), Color(0.90, 0.72, 0.28), Color(0.10, 0.08, 0.02))

	_all_in_btn = _make_btn(row, "全下")
	_all_in_btn.pressed.connect(_on_all_in)
	_style_btn(_all_in_btn, Color(0.48, 0.13, 0.13), Color(0.85, 0.32, 0.30), Color(1.0, 0.92, 0.90))

	_slider.value_changed.connect(_on_slider_value_changed)

	visible = false


func _make_btn(parent: Control, text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 42)
	btn.add_theme_font_size_override("font_size", 16)
	parent.add_child(btn)
	return btn


## 动作按钮色阶分级：弃牌暗红 / 过牌·跟注绿 / 加注金 / 全下正红。
## hover/pressed 由基准色推导，保持三色观感统一。
func _style_btn(btn: Button, base: Color, border: Color, font_color: Color) -> void:
	btn.add_theme_stylebox_override("normal", _btn_box(base, border))
	btn.add_theme_stylebox_override("hover", _btn_box(base.lightened(0.12), border.lightened(0.15)))
	btn.add_theme_stylebox_override("pressed", _btn_box(base.darkened(0.15), border.darkened(0.10)))
	btn.add_theme_stylebox_override("disabled", _btn_box(base.darkened(0.4), border.darkened(0.4)))
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color.lightened(0.2))
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))


func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = border
	return s


## 由 legal_actions 驱动面板；pot/bb 供滑条与快捷按钮使用。
func show_for(legal_actions: Dictionary, pot: int, deadline_ms: int, bb: int) -> void:
	_legal = legal_actions
	_all_in_armed = false
	_all_in_btn.text = "全下"

	_check_call_btn.visible = legal_actions.can_check or legal_actions.can_call
	if legal_actions.can_check:
		_check_call_btn.text = "过牌"
	else:
		_check_call_btn.text = "跟注 ¥%d" % legal_actions.call_amount

	var can_raise: bool = legal_actions.can_raise
	_raise_btn.visible = can_raise
	_slider.visible = can_raise
	if can_raise:
		_slider.setup(legal_actions.min_raise_to, legal_actions.max_raise_to, bb, pot)
		_raise_btn.text = "加注到 ¥%d" % _slider.current_amount()

	# 不足额全下（被封锁或不够最小加注）时也由全下按钮承担
	_all_in_btn.visible = legal_actions.can_all_in

	_deadline_ms = deadline_ms
	_timer_bar.visible = deadline_ms > 0  # 倒计时关闭（0）时隐藏进度条、不计时
	_start_ms = Time.get_ticks_msec()
	_timer_bar.value = 1000
	_active = true
	visible = true


func hide_panel() -> void:
	_active = false
	visible = false


func _process(_delta: float) -> void:
	if not _active or _deadline_ms <= 0:
		return
	var elapsed := Time.get_ticks_msec() - _start_ms
	var remain := _deadline_ms - elapsed
	_timer_bar.value = clampf(float(remain) / _deadline_ms, 0.0, 1.0) * 1000.0
	if remain <= 0:
		_active = false
		timed_out.emit()


func _on_check_call() -> void:
	if _legal.can_check:
		_submit({"type": BettingRound.ActionType.CHECK, "amount": 0})
	elif _legal.can_call:
		_submit({"type": BettingRound.ActionType.CALL, "amount": _legal.call_amount})


func _on_raise() -> void:
	_submit({"type": BettingRound.ActionType.RAISE, "amount": _slider.current_amount()})


## 全下二次确认：首次点击只"上膛"（确认点击的音效在 _submit）。
func _on_all_in() -> void:
	if not _all_in_armed:
		AudioManager.play(&"click")  # S10 按钮点击
		_all_in_armed = true
		_all_in_btn.text = "确认全下？"
		return
	_submit({"type": BettingRound.ActionType.ALL_IN, "amount": 0})


func _submit(action: Dictionary) -> void:
	if not _active:
		return
	_active = false
	AudioManager.play(&"click")  # S10 按钮点击
	action_submitted.emit(action)


func _on_slider_value_changed(amount: int) -> void:
	_raise_btn.text = "加注到 ¥%d" % amount
