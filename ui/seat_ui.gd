class_name SeatUI extends PanelContainer
## 单个座位组件：名字 / 筹码 / 本轮下注 / 状态标签 / 庄家标记 / 两张底牌。
## 占位图形阶段：PanelContainer + Label + CardUI。

const WIDTH := 150.0

var seat_index: int = -1

var _name_label: Label
var _avatar: TextureRect
var _chips_label: Label
var _bet_label: Label
var _status_label: Label
var _dealer_label: Label
var _thinking_label: Label
var _cards: Array[CardUI] = []
var _bg: StyleBoxFlat
var _highlight_tween: Tween
var _thinking_tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	_bg.set_corner_radius_all(8)
	_bg.set_border_width_all(2)
	_bg.border_color = Color(0.3, 0.32, 0.36)
	add_theme_stylebox_override("panel", _bg)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	# 第一行：头像 + 庄家标记 + 名字 + 状态
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)

	# 头像（assets/avatars/<avatar_id>.png，找不到文件时隐藏不报错）
	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = Vector2(28, 28)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.visible = false
	top.add_child(_avatar)

	_dealer_label = Label.new()
	_dealer_label.text = "D"
	_dealer_label.add_theme_font_size_override("font_size", 14)
	_dealer_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_dealer_label.visible = false
	top.add_child(_dealer_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	top.add_child(_status_label)

	# A9 思考中省略号
	_thinking_label = Label.new()
	_thinking_label.text = "…"
	_thinking_label.add_theme_font_size_override("font_size", 15)
	_thinking_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1))
	_thinking_label.visible = false
	top.add_child(_thinking_label)

	# 第二行：筹码 + 本轮下注
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	root.add_child(mid)

	_chips_label = Label.new()
	_chips_label.add_theme_font_size_override("font_size", 14)
	_chips_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	_chips_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_chips_label)

	_bet_label = Label.new()
	_bet_label.add_theme_font_size_override("font_size", 13)
	_bet_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1))
	mid.add_child(_bet_label)

	# 第三行：底牌
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


## 按 avatar_id 更新头像；贴图缺失时隐藏（保留原无头像占位，不报错）。
func set_avatar(avatar_id: String) -> void:
	var path := "res://assets/avatars/%s.png" % avatar_id
	if avatar_id != "" and ResourceLoader.exists(path):
		_avatar.texture = load(path)
		_avatar.visible = true
	else:
		_avatar.visible = false


## 按 PlayerState 刷新状态标签与整体置灰。
func refresh_status(p: PlayerState) -> void:
	match p.status:
		PlayerState.Status.FOLDED:
			_status_label.text = "弃牌"
		PlayerState.Status.ALL_IN:
			_status_label.text = "全下！"
		PlayerState.Status.OUT:
			_status_label.text = "出局"
		_:
			_status_label.text = ""
	modulate = Color(1, 1, 1, 0.35) if p.status == PlayerState.Status.OUT else Color.WHITE


func set_chips(chips: int) -> void:
	_chips_label.text = "¥%d" % chips


## 本轮下注额；0 清空。
func set_bet(amount: int) -> void:
	_bet_label.text = "下注 %d" % amount if amount > 0 else ""


func set_dealer(on: bool) -> void:
	_dealer_label.visible = on


## 当前行动者高亮（A6：光圈呼吸动画）。
func set_highlight(on: bool) -> void:
	if _highlight_tween:
		_highlight_tween.kill()
		_highlight_tween = null
	if on:
		_bg.border_color = Color(1, 0.85, 0.2)
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(_bg, "border_color", Color(1, 0.97, 0.55), 0.6)
		_highlight_tween.tween_property(_bg, "border_color", Color(1, 0.85, 0.2), 0.6)
	else:
		_bg.border_color = Color(0.3, 0.32, 0.36)


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
