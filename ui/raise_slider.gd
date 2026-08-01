class_name RaiseSlider extends HBoxContainer
## 加注滑条：范围 [min_raise_to, max_raise_to]，附带快捷按钮与金额显示。

signal value_changed(amount: int)

var _slider: HSlider
var _amount_label: Label
var _min_to: int = 0
var _max_to: int = 0
var _step: int = 1
var _pot: int = 0


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(160, 0)
	_slider.value_changed.connect(_on_slider_changed)
	add_child(_slider)

	_amount_label = Label.new()
	_amount_label.custom_minimum_size = Vector2(70, 0)
	_amount_label.add_theme_font_size_override("font_size", 15)
	add_child(_amount_label)

	for cfg in [["½池", 0.5], ["¾池", 0.75], ["1池", 1.0]]:
		var btn := Button.new()
		btn.text = cfg[0]
		var frac: float = cfg[1]
		btn.pressed.connect(_on_quick.bind(frac))
		add_child(btn)


func setup(min_to: int, max_to: int, step: int, pot: int) -> void:
	_min_to = min_to
	_max_to = max_to
	_step = maxi(step, 1)
	_pot = pot
	_slider.min_value = min_to
	_slider.max_value = maxi(max_to, min_to)
	_slider.step = _step
	_slider.value = min_to
	_update_label(int(_slider.value))


func current_amount() -> int:
	return int(_slider.value)


func _on_slider_changed(value: float) -> void:
	_update_label(int(value))
	value_changed.emit(int(value))


func _on_quick(frac: float) -> void:
	var target := int(round(_pot * frac))
	target = clampi(target, _min_to, _max_to)
	# 对齐步进
	target = _min_to + int(round(float(target - _min_to) / _step)) * _step
	target = clampi(target, _min_to, _max_to)
	_slider.value = target


func _update_label(amount: int) -> void:
	_amount_label.text = "¥%d" % amount
