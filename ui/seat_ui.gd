class_name SeatUI extends PanelContainer
## 单个座位角色卡：大头像框 + 名字/状态/筹码信息列 + 两张底牌。
## RPG 预留：头像框描边可承载职业/稀有度色；_skill_row 为技能图标槽位（默认隐藏）。

const WIDTH := 170.0

const COLOR_BORDER := Color(0.30, 0.33, 0.37)
const COLOR_HIGHLIGHT := Color(0.95, 0.78, 0.30)

var seat_index: int = -1

var _avatar_frame: PanelContainer
var _avatar: TextureRect
var _name_label: Label
var _chips_label: Label
var _bet_label: Label
var _status_label: Label
var _dealer_badge: Control
var _thinking_label: Label
var _skill_row: HBoxContainer
var _cards: Array[CardUI] = []
var _bg: StyleBoxFlat
var _highlight_tween: Tween
var _thinking_tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(0.10, 0.11, 0.14, 0.92)
	_bg.set_corner_radius_all(10)
	_bg.set_border_width_all(2)
	_bg.border_color = COLOR_BORDER
	_bg.content_margin_left = 8
	_bg.content_margin_right = 8
	_bg.content_margin_top = 6
	_bg.content_margin_bottom = 6
	add_theme_stylebox_override("panel", _bg)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# 第一行：头像框 + 信息列
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	# 头像框（RPG 预留：描边色未来可表达职业/稀有度，当前统一中性描边）
	_avatar_frame = PanelContainer.new()
	_avatar_frame.custom_minimum_size = Vector2(56, 56)
	var af_style := StyleBoxFlat.new()
	af_style.bg_color = Color(0.07, 0.08, 0.10)
	af_style.set_corner_radius_all(10)
	af_style.set_border_width_all(2)
	af_style.border_color = Color(0.40, 0.43, 0.47)
	_avatar_frame.add_theme_stylebox_override("panel", af_style)
	_avatar_frame.visible = false
	top.add_child(_avatar_frame)

	# 头像（assets/avatars/<avatar_id>.png，找不到文件时连框隐藏不报错）
	_avatar = TextureRect.new()
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar_frame.add_child(_avatar)

	# 信息列：名字行（D 徽章 + 名字 + 状态 + 思考中）+ 筹码行（筹码 + 本轮下注）
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(info)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	info.add_child(name_row)

	# 庄家徽章：Blender 渲染 dealer puck（assets/ui/dealer_puck.png），缺失时降级为白圆底 + 黑色 D 文字
	if ResourceLoader.exists("res://assets/ui/dealer_puck.png"):
		var puck := TextureRect.new()
		puck.texture = load("res://assets/ui/dealer_puck.png")
		puck.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		puck.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		puck.custom_minimum_size = Vector2(18, 18)
		puck.visible = false
		name_row.add_child(puck)
		_dealer_badge = puck
	else:
		_dealer_badge = PanelContainer.new()
		_dealer_badge.custom_minimum_size = Vector2(18, 18)
		var d_style := StyleBoxFlat.new()
		d_style.bg_color = Color(0.93, 0.93, 0.90)
		d_style.set_corner_radius_all(9)
		_dealer_badge.add_theme_stylebox_override("panel", d_style)
		_dealer_badge.visible = false
		name_row.add_child(_dealer_badge)
		var d_label := Label.new()
		d_label.text = "D"
		d_label.add_theme_font_size_override("font_size", 11)
		d_label.add_theme_color_override("font_color", Color(0.10, 0.10, 0.12))
		d_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_dealer_badge.add_child(d_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	name_row.add_child(_name_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	name_row.add_child(_status_label)

	# A9 思考中省略号
	_thinking_label = Label.new()
	_thinking_label.text = "…"
	_thinking_label.add_theme_font_size_override("font_size", 15)
	_thinking_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1))
	_thinking_label.visible = false
	name_row.add_child(_thinking_label)

	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 6)
	info.add_child(chips_row)

	_chips_label = Label.new()
	_chips_label.add_theme_font_size_override("font_size", 14)
	_chips_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.40))
	_chips_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips_row.add_child(_chips_label)

	_bet_label = Label.new()
	_bet_label.add_theme_font_size_override("font_size", 13)
	_bet_label.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	chips_row.add_child(_bet_label)

	# RPG 技能槽（预留）：默认隐藏，set_skill_slots(n) 显示 n 个空槽位
	_skill_row = HBoxContainer.new()
	_skill_row.add_theme_constant_override("separation", 4)
	_skill_row.visible = false
	root.add_child(_skill_row)
	for i in 4:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(20, 20)
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.07, 0.08, 0.10)
		s.set_corner_radius_all(4)
		s.set_border_width_all(1)
		s.border_color = Color(0.28, 0.30, 0.33)
		slot.add_theme_stylebox_override("panel", s)
		_skill_row.add_child(slot)

	# 底牌行
	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 6)
	root.add_child(card_row)
	for i in 2:
		var c := CardUI.new()
		card_row.add_child(c)
		_cards.append(c)
	hide_cards()


## 绑定玩家数据（座位初始化与每手开始刷新用）。
func bind_player(p: PlayerState) -> void:
	seat_index = p.seat_index
	_name_label.text = p.name
	set_avatar(p.avatar_id)
	set_chips(p.chips)
	set_bet(0)
	refresh_status(p)


## 按 avatar_id 更新头像；贴图缺失时连框隐藏（保留原无头像占位，不报错）。
func set_avatar(avatar_id: String) -> void:
	var path := "res://assets/avatars/%s.png" % avatar_id
	if avatar_id != "" and ResourceLoader.exists(path):
		_avatar.texture = load(path)
		_avatar_frame.visible = true
	else:
		_avatar_frame.visible = false


## 按 PlayerState 刷新状态标签与整体置灰。
func refresh_status(p: PlayerState) -> void:
	set_status(p.status)


## 按状态值刷新状态标签与整体置灰（事件回放用快照值，不读实时 PlayerState）。
func set_status(status: int) -> void:
	match status:
		PlayerState.Status.FOLDED:
			_status_label.text = "弃牌"
			_status_label.add_theme_color_override("font_color", Color(0.62, 0.65, 0.68))
		PlayerState.Status.ALL_IN:
			_status_label.text = "全下！"
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.30))
		PlayerState.Status.OUT:
			_status_label.text = "出局"
			_status_label.add_theme_color_override("font_color", Color(0.55, 0.57, 0.60))
		_:
			_status_label.text = ""
	modulate = Color(1, 1, 1, 0.35) if status == PlayerState.Status.OUT else Color.WHITE


func set_chips(chips: int) -> void:
	_chips_label.text = "¥%d" % chips


## 本轮下注额；0 清空。
func set_bet(amount: int) -> void:
	_bet_label.text = "下注 %d" % amount if amount > 0 else ""


func set_dealer(on: bool) -> void:
	_dealer_badge.visible = on


## RPG 预留：显示 count 个技能空槽（0 或负数隐藏整行），图标接入后替换槽位内容。
func set_skill_slots(count: int) -> void:
	_skill_row.visible = count > 0
	for i in _skill_row.get_child_count():
		_skill_row.get_child(i).visible = i < count


## 当前行动者高亮（A6：金色描边呼吸动画）。
func set_highlight(on: bool) -> void:
	if _highlight_tween:
		_highlight_tween.kill()
		_highlight_tween = null
	if on:
		_bg.border_color = COLOR_HIGHLIGHT
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(_bg, "border_color", Color(1, 0.95, 0.60), 0.6)
		_highlight_tween.tween_property(_bg, "border_color", COLOR_HIGHLIGHT, 0.6)
	else:
		_bg.border_color = COLOR_BORDER


## A9 思考中：省略号呼吸动效。
func set_thinking(on: bool) -> void:
	if _thinking_tween:
		_thinking_tween.kill()
		_thinking_tween = null
	_thinking_label.visible = on
	if on:
		_thinking_label.modulate = Color.WHITE
		_thinking_tween = create_tween().set_loops()
		_thinking_tween.tween_property(_thinking_label, "modulate:a", 0.25, 0.5)
		_thinking_tween.tween_property(_thinking_label, "modulate:a", 1.0, 0.5)
	else:
		_thinking_label.modulate = Color.WHITE


## 人类：亮牌面。
func show_hole(cards: Array) -> void:
	for i in 2:
		if i < cards.size() and cards[i] is Card:
			_cards[i].set_card(cards[i])
		else:
			_cards[i].hide_card()


## AI：显示牌背。
func show_backs() -> void:
	for c in _cards:
		c.set_back()


## 摊牌：公开 AI 牌面。
func reveal(cards: Array) -> void:
	show_hole(cards)


## A5 摊牌翻面动画：牌背逐张翻成牌面（dur 为半程时长）。
func flip_reveal(cards: Array, dur: float) -> void:
	for i in 2:
		if i < cards.size() and cards[i] is Card:
			await _cards[i].flip_to_card(cards[i], dur)
		else:
			_cards[i].hide_card()


## A7 淘汰：座位灰化淡出。
func fade_out(dur: float) -> void:
	var t := create_tween()
	t.tween_property(self, "modulate", Color(1, 1, 1, 0.35), dur)
	await t.finished


func hide_cards() -> void:
	for c in _cards:
		c.hide_card()
