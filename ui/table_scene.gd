class_name TableScene extends Node2D
## 牌桌控制器（TECH_DESIGN 6.2）：持有 TournamentManager，驱动主循环，
## 把 EventPlayer 分发的事件映射为座位/公共牌/底池/顶栏的占位 UI 更新。

const AI_COUNT := 5
const SEAT_OFFSET := Vector2(-85, -65)
## 座位布局椭圆：N 个座位沿椭圆等角均匀分布，0 号（人类）固定在正下方。
const SEAT_CENTER := Vector2(640, 307)
const SEAT_RADIUS := Vector2(463, 193)
const COMMUNITY_OFFSET := Vector2(-28, -40)
## 全局动画速度系数（标准 1.0 / 快速 0.5），所有 tween 时长乘此系数；
## _ready 时从设置读取（GameSettings.anim_speed）。
var ANIM_SPEED := 1.0
## 桌面中央下注区（A3/A4 筹码动画终点/起点）。
const POT_POS := Vector2(640, 300)

const ACTION_NAMES := {
	BettingRound.ActionType.FOLD: "弃牌",
	BettingRound.ActionType.CHECK: "过牌",
	BettingRound.ActionType.CALL: "跟注",
	BettingRound.ActionType.RAISE: "加注",
	BettingRound.ActionType.ALL_IN: "全下",
}
const STREET_NAMES := {
	HandController.Street.PREFLOP: "翻牌前",
	HandController.Street.FLOP: "翻牌",
	HandController.Street.TURN: "转牌",
	HandController.Street.RIVER: "河牌",
}

var tm: TournamentManager
var event_player: EventPlayer
## auto（--auto 冒烟）模式下关闭动画，保证无头快速跑完。
var anim_enabled := true

var seats: Array[SeatUI] = []
var community_cards: Array[CardUI] = []
var _pending_legal: Dictionary = {}
## 请求在手牌边界返回主菜单（顶栏"主菜单"按钮置位，主循环检查后生效）。
var _exit_to_menu := false

## "跳过本局"：人类弃牌后显示按钮，点击后快进播完本手剩余事件并弹摘要弹窗。
var _skip_button: Button
var _skip_active := false
## 摘要按街分节：[{title, lines: Array[String]}]，弹窗按段落渲染。
var _skip_sections: Array[Dictionary] = []
## 摘要弹窗（_build_skip_popup 创建）：确认后 emit skip_popup_confirmed。
var _skip_popup: ColorRect
var _skip_popup_text: RichTextLabel
signal skip_popup_confirmed

## 当前街（_set_street 维护）与本手已发公共牌，供跳过摘要分节/摊牌段使用。
var _street: int = HandController.Street.PREFLOP
var _community_dealt: Array[Card] = []

const SUIT_SYMBOLS := ["♠", "♥", "♣", "♦"]

## 顶栏胶囊徽章：级别 / 盲注 / 距升级（_build_top_bar 创建）。
var _badge_level: Label
var _badge_blinds: Label
var _badge_hands: Label

@onready var _community_slots: Node2D = $CommunitySlots
@onready var _deck_slot: Marker2D = $DeckSlot
@onready var _top_bar: HBoxContainer = $UILayer/TopBar
@onready var _street_label: Label = $UILayer/StreetLabel
@onready var _pot_label: Label = $UILayer/PotLabel
@onready var _message_label: Label = $UILayer/MessageLabel
@onready var _blind_banner: Label = $UILayer/BlindBanner
@onready var _action_panel: ActionPanel = $UILayer/ActionPanel
@onready var _menu_button: Button = $UILayer/MenuButton


func _ready() -> void:
	var auto := "--auto" in OS.get_cmdline_user_args()
	anim_enabled = not auto
	ANIM_SPEED = GameSettings.anim_speed()

	tm = TournamentManager.new()
	var resumed := false
	var main := get_parent() as Main
	if auto or main == null:
		# --auto 冒烟/独立运行：保持原行为（有存档继续，否则默认 5 AI 开新局）
		resumed = tm.load_save()
		if not resumed:
			tm.start_new(TournamentManager.TournamentConfig.default(), AI_COUNT)
	elif main.table_intent == Main.TableIntent.CONTINUE:
		resumed = tm.load_save()
		if not resumed:
			# 无存档兜底（主菜单在无存档时已禁用"继续"）
			tm.start_new(GameSettings.make_config(), main.table_ai_count)
	else:
		var config: TournamentManager.TournamentConfig = main.table_config
		if config == null:
			config = GameSettings.make_config()
		tm.start_new(config, main.table_ai_count)

	# 按参赛人数沿椭圆均匀摆座位（人少时不再挤在左半边）
	var count := tm.players.size()
	for i in count:
		var seat := SeatUI.new()
		seat.position = _seat_position(i, count) + SEAT_OFFSET
		add_child(seat)
		seat.bind_player(tm.players[i])
		seats.append(seat)
	var c_slots := _community_slots.get_children()
	for slot in c_slots:
		var c := CardUI.new()
		c.position = slot.position + COMMUNITY_OFFSET
		add_child(c)
		community_cards.append(c)

	event_player = EventPlayer.new()
	event_player.tm = tm
	event_player.table = self
	event_player.auto_play = auto
	add_child(event_player)

	_action_panel.action_submitted.connect(_on_panel_action)
	_action_panel.timed_out.connect(_on_panel_timeout)
	_menu_button.pressed.connect(_on_menu_button)
	# 菜单按钮只对路由进入的正式对局有意义（--auto/独立运行隐藏）
	_menu_button.visible = not auto and main != null

	_build_skip_button()
	_build_skip_popup()

	_build_top_bar()
	_style_center_labels()
	_refresh_top_bar()
	_message_label.text = "继续锦标赛…" if resumed else "锦标赛开始！"
	if auto:
		print("[Table] auto_play 开启，开始锦标赛")
	_run_tournament()


## 主循环：逐手进行，事件播完再开下一手，直到锦标赛结束或请求返回主菜单。
## 返回主菜单在手牌边界生效（进度已自动保存，GDD 8.1），避免中途释放场景打断 await。
func _run_tournament() -> void:
	while not tm.finished and not _exit_to_menu:
		tm.run_next_hand()
		event_player.play_events(tm.pop_events())
		await event_player.queue_drained
		# 本手按过"跳过本局"：弹摘要弹窗，确认后再开下一手
		if _skip_has_content() and not tm.finished and not _exit_to_menu:
			_show_skip_summary()
			await skip_popup_confirmed
	if _exit_to_menu and not tm.finished:
		(get_parent() as Main).change_scene("main_menu")


# ---- 事件 → UI 映射（EventPlayer 回调） ----

func on_hand_start(event: Dictionary) -> void:
	_pot_label.text = ""
	_skip_button.hide()
	_skip_sections.clear()
	_community_dealt.clear()
	_message_label.text = "第 %d 手 · 盲注 %d/%d" % [event.hand_no, event.sb, event.bb]
	for c in community_cards:
		c.clear()
	for seat in seats:
		var p := tm.players[seat.seat_index]
		seat.bind_player(p)
		# 状态须用手牌开始时的快照（事件回放时整手已跑完，本手被淘汰者实时状态已是 OUT）
		var start_status: int = PlayerState.Status.ACTIVE if event.alive_seats.has(seat.seat_index) \
				else PlayerState.Status.OUT
		seat.set_status(start_status)
		seat.hide_cards()
		seat.set_dealer(p.seat_index == event.button_seat)
		seat.set_highlight(false)
	_refresh_top_bar()
	_set_street(HandController.Street.PREFLOP)


func on_deal_hole(event: Dictionary) -> void:
	var seat := seats[event.seat]
	if anim_enabled:
		# A1 发牌：牌背从牌堆标记点逐张飞入座位（S1 每张一声）
		for i in 2:
			var fly := _spawn_fly_card(_deck_slot.position)
			AudioManager.play(&"deal_card")
			var target := seat.position + Vector2(16 + 62 * i, 46)
			var t := create_tween()
			t.tween_property(fly, "position", target, 0.15 * ANIM_SPEED)
			await t.finished
			fly.queue_free()
	# 盲注在发底牌前静默扣除，这里顺带刷新筹码与下注显示；状态用发牌时的快照
	var p := tm.players[event.seat]
	seat.set_chips(p.chips)
	seat.set_bet(p.current_bet)
	var deal_status: int = event.status
	seat.set_status(deal_status)
	if event.cards.is_empty():
		seat.show_backs()
	else:
		seat.show_hole(event.cards)


func on_player_action(event: Dictionary) -> void:
	var seat := seats[event.seat]
	var p := tm.players[event.seat]
	# A3 筹码下注 / S3、S4、S6 音效（动画播完再更新数字）
	if anim_enabled:
		match event.action:
			BettingRound.ActionType.CALL, BettingRound.ActionType.RAISE:
				AudioManager.play(&"chip_bet")
				await _anim_chip_to_pot(seat, event.amount)
			BettingRound.ActionType.ALL_IN:
				AudioManager.play(&"all_in")
				await _anim_chip_to_pot(seat, event.amount)
			BettingRound.ActionType.FOLD:
				AudioManager.play(&"fold")
	seat.set_chips(event.chips_left)
	seat.set_bet(p.current_bet)
	var action_status: int = event.status
	seat.set_status(action_status)
	for s in seats:
		s.set_highlight(s.seat_index == event.seat)
	var text: String = ACTION_NAMES.get(event.action, "?")
	if event.action == BettingRound.ActionType.CALL or event.action == BettingRound.ActionType.RAISE:
		text += " ¥%d" % event.amount
	_message_label.text = "%s：%s" % [p.name, text]
	if _skip_active:
		_skip_add_line("%s：%s" % [p.name, text])
	# 人类弃牌后提供"跳过本局"：快进播完本手剩余事件（auto 代打不显示）
	elif not event_player.auto_play and p.is_human \
			and event.action == BettingRound.ActionType.FOLD:
		_skip_button.show()


## A9 思考中：AI 行动前延迟并显示省略号（由 EventPlayer 调用）。
func play_thinking(seat_idx: int, dur: float) -> void:
	for s in seats:
		s.set_highlight(s.seat_index == seat_idx)
	seats[seat_idx].set_thinking(true)
	await get_tree().create_timer(dur * ANIM_SPEED).timeout
	seats[seat_idx].set_thinking(false)


func on_deal_community(event: Dictionary) -> void:
	# A2 公共牌翻开（S2 每张一声）；auto 模式直接落牌
	match event.type:
		Events.Type.DEAL_FLOP:
			for i in 3:
				await _flip_community(i, event.cards[i])
			_set_street(HandController.Street.FLOP)
			_community_dealt.append_array(event.cards)
			if _skip_active:
				_skip_section("翻牌  " + _cards_text(event.cards))
		Events.Type.DEAL_TURN:
			await _flip_community(3, event.card)
			_set_street(HandController.Street.TURN)
			_community_dealt.append(event.card)
			if _skip_active:
				_skip_section("转牌  " + _card_text(event.card))
		Events.Type.DEAL_RIVER:
			await _flip_community(4, event.card)
			_set_street(HandController.Street.RIVER)
			_community_dealt.append(event.card)
			if _skip_active:
				_skip_section("河牌  " + _card_text(event.card))
	_refresh_pot()


## 单张公共牌入场：动画开时翻面，否则直接显示。
func _flip_community(idx: int, card: Card) -> void:
	if anim_enabled:
		AudioManager.play(&"flip_card")
		await community_cards[idx].flip_to_card(card, 0.12 * ANIM_SPEED)
	else:
		community_cards[idx].set_card(card)


func on_round_end(event: Dictionary) -> void:
	_refresh_pot()
	for seat in seats:
		seat.set_bet(0)
		seat.set_highlight(false)


func on_showdown(event: Dictionary) -> void:
	var names: Array[String] = []
	if _skip_active:
		_skip_section("摊牌")
		_skip_add_line("公共牌：" + _cards_text(_community_dealt))
	for reveal in event.reveals:
		# A5 摊牌：AI 手牌翻面（S2）
		if anim_enabled:
			AudioManager.play(&"flip_card")
			await seats[reveal.seat].flip_reveal(reveal.cards, 0.12 * ANIM_SPEED)
		else:
			seats[reveal.seat].reveal(reveal.cards)
		names.append("%s：%s" % [tm.players[reveal.seat].name, reveal.hand_name])
		if _skip_active:
			# 展示最佳五张组合（含公共牌），方便判断各牌手倾向
			_skip_add_line("%s 手牌 %s → %s（%s）" % [
				tm.players[reveal.seat].name, _cards_text(reveal.cards),
				_cards_text(reveal.best), reveal.hand_name])
	_message_label.text = "摊牌 · " + "，".join(names)


func on_pot_award(event: Dictionary) -> void:
	var p := tm.players[event.seat]
	# A4 收池：筹码移向赢家座位（S5）
	if anim_enabled:
		AudioManager.play(&"pot_win")
		await _anim_chip_to_seat(seats[event.seat], event.amount)
	seats[event.seat].set_chips(p.chips)
	_message_label.text = "%s 赢得 ¥%d（%s）" % [p.name, event.amount, event.hand_name]
	if _skip_active:
		_skip_add_line("[color=gold]★ %s 赢得 ¥%d（%s）[/color]" % [p.name, event.amount, event.hand_name])


func on_eliminated(event: Dictionary) -> void:
	var p := tm.players[event.seat]
	# A7 淘汰：座位灰化淡出（S8）
	if anim_enabled:
		AudioManager.play(&"eliminated")
		await seats[event.seat].fade_out(0.5 * ANIM_SPEED)
	seats[event.seat].refresh_status(p)
	_message_label.text = "%s 淘汰，第 %d 名" % [p.name, event.rank]
	if _skip_active:
		_skip_add_line("[color=gray]✖ %s 淘汰，第 %d 名[/color]" % [p.name, event.rank])


func on_blind_up(event: Dictionary) -> void:
	_blind_banner.text = "盲注升级！级别 %d：%d/%d" % [event.level, event.sb, event.bb]
	_message_label.text = _blind_banner.text
	if _skip_active:
		_skip_section("盲注升级")
		_skip_add_line("级别 %d：%d/%d" % [event.level, event.sb, event.bb])
	# A8 顶部横幅滑入滑出（S7）
	if anim_enabled:
		AudioManager.play(&"blind_up")
		var t := create_tween()
		t.tween_property(_blind_banner, "position:y", 70.0, 0.3 * ANIM_SPEED)
		t.tween_interval(1.0 * ANIM_SPEED)
		t.tween_property(_blind_banner, "position:y", -40.0, 0.3 * ANIM_SPEED)
		await t.finished
	_refresh_top_bar()


func on_hand_end(_event: Dictionary) -> void:
	_pot_label.text = ""
	for seat in seats:
		seat.set_highlight(false)
		seat.set_bet(0)
	# 跳过模式只覆盖一手：恢复动画与事件节奏，摘要弹窗在主循环 queue_drained 后弹出
	if _skip_active:
		_skip_active = false
		event_player.fast_forward = false
		anim_enabled = not event_player.auto_play


## 人类回合：显示操作面板并挂起事件队列。
func on_action_required(event: Dictionary) -> void:
	_pending_legal = event.legal_actions
	for seat in seats:
		seat.set_highlight(seat.seat_index == event.seat)
	if event_player.auto_play:
		return  # 面板不显示，EventPlayer 直接代打
	var bb: int = tm.config.blinds_at(tm.blind_level)[1]
	_action_panel.show_for(event.legal_actions, tm.hand.pot_size(), event.deadline_ms, bb)


func on_tournament_end(event: Dictionary) -> void:
	_action_panel.hide_panel()
	_skip_button.hide()
	_skip_popup.hide()
	var win: bool = event.type == Events.Type.TOURNAMENT_WIN
	var rank: int = 1 if win else int(event.rank)
	print("[Table] 锦标赛结束：%s" % ("夺冠" if win else "第 %d 名" % rank))
	if event_player.auto_play:
		# --auto 冒烟：打完整场自动 quit，不进结算界面
		get_tree().quit()
		return
	var main := get_parent() as Main
	if main != null:
		main.change_scene("result", {
			"win": win,
			"rank": rank,
			"total": tm.players.size(),
			"standings": _build_standings(),
			"ai_count": tm.players.size() - 1,
			"config": tm.config,
		})


## 名次表（冠军→首轮出局者）：冠军是未被淘汰的存活者，
## 其余按淘汰顺序倒序（后淘汰者名次靠前），名次 = 总人数 - eliminated.find(seat)。
func _build_standings() -> Array:
	var standings: Array = []
	var total := tm.players.size()
	for p in tm.players:
		if not tm.eliminated.has(p.seat_index):
			standings.append({"rank": 1, "name": p.name, "is_human": p.is_human})
	for i in range(tm.eliminated.size() - 1, -1, -1):
		var seat: int = tm.eliminated[i]
		standings.append({
			"rank": total - tm.eliminated.find(seat),
			"name": tm.players[seat].name,
			"is_human": tm.players[seat].is_human,
		})
	return standings


# ---- 操作面板回调 ----

func _on_panel_action(action: Dictionary) -> void:
	_action_panel.hide_panel()
	event_player.deliver_human_action(action)


## 超时：能过牌则过牌，否则弃牌。
func _on_panel_timeout() -> void:
	var action: Dictionary
	if _pending_legal.get("can_check", false):
		action = {"type": BettingRound.ActionType.CHECK, "amount": 0}
	else:
		action = {"type": BettingRound.ActionType.FOLD, "amount": 0}
	_on_panel_action(action)


## 顶栏"主菜单"按钮：置标志位，主循环在手牌边界切场景（S10 点击音）。
func _on_menu_button() -> void:
	AudioManager.play(&"click")
	_exit_to_menu = true


# ---- 显示辅助 ----

## A1：生成一张牌背飞行牌（动画结束由调用方 queue_free）。
func _spawn_fly_card(pos: Vector2) -> CardUI:
	var c := CardUI.new()
	c.position = pos - CardUI.SIZE / 2
	add_child(c)
	c.set_back()
	return c


## A3：筹码从座位移到中央下注区。
func _anim_chip_to_pot(seat: SeatUI, amount: int) -> void:
	var chip := _spawn_chip(_seat_center(seat), amount, true)
	var t := create_tween()
	t.tween_property(chip, "position", POT_POS, 0.3 * ANIM_SPEED)
	await t.finished
	chip.queue_free()


## A4：筹码从中央下注区移到赢家座位。
func _anim_chip_to_seat(seat: SeatUI, amount: int) -> void:
	var chip := _spawn_chip(POT_POS, amount, true)
	var t := create_tween()
	t.tween_property(chip, "position", _seat_center(seat), 0.35 * ANIM_SPEED)
	await t.finished
	chip.queue_free()


## 筹码贴图（assets/chips/，按金额区间着色：白<100 红<500 蓝<1000 黑≥1000）；
## tilt 为 true 时优先用 45° 斜视版（飞行动画用，缺失回落顶视版）；
## 贴图缺失时降级为金色小圆块。
func _spawn_chip(pos: Vector2, amount: int = 0, tilt: bool = false) -> Control:
	var tex := _chip_texture(amount, tilt)
	if tex != null:
		var chip := TextureRect.new()
		chip.texture = tex
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.custom_minimum_size = Vector2(28, 28)
		chip.position = pos - Vector2(14, 14)
		add_child(chip)
		return chip
	var fallback := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.8, 0.25)
	style.set_corner_radius_all(12)
	fallback.add_theme_stylebox_override("panel", style)
	fallback.custom_minimum_size = Vector2(24, 24)
	fallback.position = pos - Vector2(12, 12)
	add_child(fallback)
	return fallback


## 按金额区间选筹码贴图；tilt 为 true 时优先 _tilt 斜视版；文件缺失返回 null（调用方走降级圆块）。
static func _chip_texture(amount: int, tilt: bool = false) -> Texture2D:
	var chip_name := "chip_white"
	if amount >= 1000:
		chip_name = "chip_black"
	elif amount >= 500:
		chip_name = "chip_blue"
	elif amount >= 100:
		chip_name = "chip_red"
	if tilt:
		var tilt_path := "res://assets/chips/%s_tilt.png" % chip_name
		if ResourceLoader.exists(tilt_path):
			return load(tilt_path)
	var path := "res://assets/chips/%s.png" % chip_name
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _seat_center(seat: SeatUI) -> Vector2:
	return seat.position + Vector2(SeatUI.WIDTH / 2.0, 40)


## 座位 i/N 的桌面坐标：0 号在椭圆正下方，其余逆时针等角排布（9 人时与原手摆槽位一致）。
static func _seat_position(index: int, count: int) -> Vector2:
	var angle := deg_to_rad(90.0 + 360.0 * index / count)
	return SEAT_CENTER + Vector2(cos(angle), sin(angle)) * SEAT_RADIUS


## 顶栏胶囊徽章：级别 / 盲注 / 距升级 三个药丸（替代原来的整行纯文本）。
func _build_top_bar() -> void:
	_top_bar.add_theme_constant_override("separation", 8)
	_badge_level = _add_badge()
	_badge_blinds = _add_badge()
	_badge_hands = _add_badge()


## 创建一个药丸形徽章（圆角暗底 + 细描边），返回内部 Label 供更新文本。
func _add_badge() -> Label:
	var capsule := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.10, 0.13, 0.85)
	s.set_corner_radius_all(12)
	s.set_border_width_all(1)
	s.border_color = Color(0.30, 0.33, 0.36)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	capsule.add_theme_stylebox_override("panel", s)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	capsule.add_child(label)
	_top_bar.add_child(capsule)
	return label


## 桌心标签样式：街名小字压公共牌上方，底池金色大字，消息条药丸底，盲注横幅金底。
func _style_center_labels() -> void:
	_street_label.add_theme_font_size_override("font_size", 13)
	_street_label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.72))

	_pot_label.add_theme_font_size_override("font_size", 20)
	_pot_label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.35))

	var msg_style := StyleBoxFlat.new()
	msg_style.bg_color = Color(0.08, 0.09, 0.11, 0.78)
	msg_style.set_corner_radius_all(12)
	msg_style.content_margin_left = 14
	msg_style.content_margin_right = 14
	msg_style.content_margin_top = 4
	msg_style.content_margin_bottom = 4
	_message_label.add_theme_stylebox_override("normal", msg_style)

	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.32, 0.23, 0.06, 0.95)
	banner_style.set_corner_radius_all(12)
	banner_style.set_border_width_all(1)
	banner_style.border_color = Color(0.85, 0.70, 0.25)
	banner_style.content_margin_left = 16
	banner_style.content_margin_right = 16
	banner_style.content_margin_top = 6
	banner_style.content_margin_bottom = 6
	_blind_banner.add_theme_stylebox_override("normal", banner_style)
	_blind_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))


func _refresh_top_bar() -> void:
	var blinds: Array = tm.config.blinds_at(tm.blind_level)
	var remain: int = tm.config.hands_per_level - tm.hands_played
	_badge_level.text = "级别 %d" % (tm.blind_level + 1)
	_badge_blinds.text = "盲注 %d/%d" % [blinds[0], blinds[1]]
	_badge_hands.text = "距升级 %d 手" % remain


func _refresh_pot() -> void:
	if tm.hand != null:
		_pot_label.text = "底池 ¥%d" % tm.hand.pot_size()


func _set_street(street: HandController.Street) -> void:
	_street = street
	_street_label.text = STREET_NAMES.get(street, "")


# ---- 跳过本局（人类弃牌后快进 + 摘要弹窗） ----

## 右下角"跳过本局"按钮：默认隐藏，人类弃牌后由 on_player_action 显示。
func _build_skip_button() -> void:
	_skip_button = Button.new()
	_skip_button.text = "跳过本局 »"
	_skip_button.position = Vector2(1120, 646)
	_skip_button.size = Vector2(140, 40)
	_skip_button.visible = false
	_skip_button.pressed.connect(_on_skip_button)
	$UILayer.add_child(_skip_button)


## 点击跳过：本手剩余事件快进播放（关动画/音效，事件间隔压到最短），并收集文字摘要。
## 摘要从当前街起分节（翻牌前按下时也可能只余少量动作）。
func _on_skip_button() -> void:
	AudioManager.play(&"click")
	_skip_button.hide()
	_skip_active = true
	_skip_sections.clear()
	_skip_section(STREET_NAMES[_street])
	anim_enabled = false
	event_player.fast_forward = true
	_message_label.text = "快进本局剩余过程…"


## 摘要分节：新起一节（街名/摊牌/盲注升级等标题）。
func _skip_section(title: String) -> void:
	_skip_sections.append({"title": title, "lines": [] as Array[String]})


## 往当前节追加一行；无节时按当前街兜底建节。
func _skip_add_line(line: String) -> void:
	if _skip_sections.is_empty():
		_skip_section(STREET_NAMES[_street])
	var lines: Array = _skip_sections.back()["lines"]
	lines.append(line)


## 有实质内容（任一节带行）才弹摘要，避免按下后已无剩余事件时弹空弹窗。
func _skip_has_content() -> bool:
	for sec in _skip_sections:
		if not (sec["lines"] as Array).is_empty():
			return true
	return false


## 摘要弹窗：半透明遮罩 + 居中面板（标题 / 滚动文本 / 确认按钮），代码构建。
func _build_skip_popup() -> void:
	_skip_popup = ColorRect.new()
	_skip_popup.color = Color(0, 0, 0, 0.6)
	_skip_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skip_popup.visible = false
	$UILayer.add_child(_skip_popup)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.14, 0.98)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.38, 0.42)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(360, 140)
	panel.size = Vector2(560, 440)
	_skip_popup.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "本局跳过内容"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_skip_popup_text = RichTextLabel.new()
	_skip_popup_text.bbcode_enabled = true
	_skip_popup_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skip_popup_text.add_theme_font_size_override("normal_font_size", 15)
	_skip_popup_text.add_theme_font_size_override("bold_font_size", 16)
	vbox.add_child(_skip_popup_text)

	var confirm := Button.new()
	confirm.text = "继续下一局"
	confirm.pressed.connect(_on_skip_popup_confirm)
	vbox.add_child(confirm)


## 按街分节渲染：节标题加粗，行间缩进，节间空行分段。
func _show_skip_summary() -> void:
	var paragraphs: Array[String] = []
	for sec in _skip_sections:
		var chunk := "[b]【%s】[/b]" % sec["title"]
		for line in sec["lines"]:
			chunk += "\n　" + line
		paragraphs.append(chunk)
	_skip_popup_text.text = "\n\n".join(paragraphs)
	_skip_popup.show()


func _on_skip_popup_confirm() -> void:
	AudioManager.play(&"click")
	_skip_popup.hide()
	skip_popup_confirmed.emit()


## 单张牌的摘要写法：点数 + 花色符号（如 "A♠"）。
func _card_text(c: Card) -> String:
	return Card.RANK_CHARS[c.rank - 2] + SUIT_SYMBOLS[c.suit]


func _cards_text(cards: Array) -> String:
	var parts: Array[String] = []
	for c in cards:
		parts.append(_card_text(c))
	return " ".join(parts)
