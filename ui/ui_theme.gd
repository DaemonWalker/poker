class_name UITheme extends RefCounted
## 共享 UI 主题（M8）：炭黑暗底 + 高对比文字，按钮/滑条/面板/输入控件风格统一，
## 金色只作焦点强调（滑条拖块 / 倒计时 / 输入聚焦），暗底衬托角色头像与牌面。
## 代码构建，UITheme.apply(root) 应用到场景根。

static var _theme: Theme = null


## 把共享主题应用到场景根（子控件自动继承）。
static func apply(root: Control) -> void:
	root.theme = get_theme()


## 单例式构建一次复用。
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var t := Theme.new()

	# 文字：高对比浅色，统一字号
	t.set_color("font_color", "Label", Color(0.92, 0.93, 0.90))
	t.set_font_size("font_size", "Label", 15)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", Color(0.94, 0.94, 0.90))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(0.85, 0.88, 0.82))
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_color("font_color", "CheckBox", Color(0.92, 0.93, 0.90))
	t.set_font_size("font_size", "CheckBox", 15)
	t.set_color("font_color", "LineEdit", Color(0.95, 0.95, 0.92))
	t.set_color("font_color", "OptionButton", Color(0.94, 0.94, 0.90))
	t.set_color("font_hover_color", "OptionButton", Color(1, 1, 1))
	t.set_color("font_disabled_color", "OptionButton", Color(1, 1, 1, 0.35))
	t.set_font_size("font_size", "OptionButton", 15)

	# 按钮（OptionButton 复用同一组观感）：炭黑底 + 细描边，加大内边距
	var btn_normal := _box(Color(0.14, 0.16, 0.19), Color(0.33, 0.36, 0.39), 8)
	var btn_hover := _box(Color(0.19, 0.22, 0.25), Color(0.58, 0.61, 0.56), 8)
	var btn_pressed := _box(Color(0.09, 0.11, 0.13), Color(0.48, 0.52, 0.48), 8)
	var btn_disabled := _box(Color(0.11, 0.13, 0.15, 0.7), Color(0.28, 0.30, 0.31, 0.6), 8)
	for box in [btn_normal, btn_hover, btn_pressed, btn_disabled]:
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 6
		box.content_margin_bottom = 6
	for type_name in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type_name, btn_normal)
		t.set_stylebox("hover", type_name, btn_hover)
		t.set_stylebox("pressed", type_name, btn_pressed)
		t.set_stylebox("disabled", type_name, btn_disabled)
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())

	# 面板
	t.set_stylebox("panel", "PanelContainer",
			_box(Color(0.09, 0.10, 0.13, 0.95), Color(0.30, 0.33, 0.36), 10))

	# 输入框（SpinBox 内部 LineEdit 继承）
	var edit_normal := _box(Color(0.07, 0.08, 0.10), Color(0.36, 0.39, 0.39), 6)
	var edit_focus := _box(Color(0.08, 0.10, 0.12), Color(0.85, 0.70, 0.25), 6)
	t.set_stylebox("normal", "LineEdit", edit_normal)
	t.set_stylebox("focus", "LineEdit", edit_focus)

	# 滑条：轨道深色，拖块金色
	var slider_bg := _box(Color(0.08, 0.10, 0.12), Color(0, 0, 0, 0), 3)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	var grabber := _box(Color(0.85, 0.70, 0.25), Color(0, 0, 0, 0), 8)
	grabber.content_margin_left = 8
	grabber.content_margin_right = 8
	grabber.content_margin_top = 8
	grabber.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", grabber)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber)

	# 进度条（倒计时条）
	var bar_bg := _box(Color(0.08, 0.10, 0.12), Color(0, 0, 0, 0), 4)
	var bar_fill := _box(Color(0.85, 0.70, 0.25), Color(0, 0, 0, 0), 4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)

	# 弹窗（确认对话框）
	t.set_stylebox("panel", "Window",
			_box(Color(0.09, 0.10, 0.13), Color(0.40, 0.44, 0.44), 8))
	return t


## 圆角平底 StyleBox（bg 底色 + border 描边）。
static func _box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	return s
