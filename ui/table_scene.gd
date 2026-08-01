class_name TableScene extends Node2D
## 牌桌控制器（TECH_DESIGN 6.2）：持有 TournamentManager，驱动主循环，
## 把 EventPlayer 分发的事件映射为座位/公共牌/底池/顶栏的占位 UI 更新。

const AI_COUNT := 5
const SEAT_OFFSET := Vector2(-75, -65)
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

@onready var _seat_slots: Node2D = $SeatSlots
@onready var _community_slots: Node2D = $CommunitySlots
@onready var _deck_slot: Marker2D = $DeckSlot
@onready var _top_bar: Label = $UILayer/TopBar
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

	# 按参赛人数启用前 N 个手摆座位槽位
	var slots := _seat_slots.get_children()
	for i in tm.players.size():
		var seat := SeatUI.new()
		seat.position = slots[i].position + SEAT_OFFSET
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
	if _exit_to_menu and not tm.finished:
		(get_parent() as Main).change_scene("main_menu")


# ---- 事件 → UI 映射（EventPlayer 回调） ----

func on_hand_start(event: Dictionary) -> void:
	_pot_label.text = ""
	_message_label.text = "第 %d 手 · 盲注 %d/%d" % [event.hand_no, event.sb, event.bb]
	for c in community_cards:
		c.clear()
	for seat in seats:
		var p := tm.players[seat.seat_index]
		seat.bind_player(p)
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
	# 盲注在发底牌前静默扣除，这里顺带刷新筹码与下注显示
	var p := tm.players[event.seat]
	seat.set_chips(p.chips)
	seat.set_bet(p.current_bet)
	seat.refresh_status(p)
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
	seat.refresh_status(p)
	for s in seats:
		s.set_highlight(s.seat_index == event.seat)
	var text: String = ACTION_NAMES.get(event.action, "?")
	if event.action == BettingRound.ActionType.CALL or event.action == BettingRound.ActionType.RAISE:
		text += " ¥%d" % event.amount
	_message_label.text = "%s：%s" % [p.name, text]


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
		Events.Type.DEAL_TURN:
			await _flip_community(3, event.card)
			_set_street(HandController.Street.TURN)
		Events.Type.DEAL_RIVER:
			await _flip_community(4, event.card)
			_set_street(HandController.Street.RIVER)
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
	for reveal in event.reveals:
		# A5 摊牌：AI 手牌翻面（S2）
		if anim_enabled:
			AudioManager.play(&"flip_card")
			await seats[reveal.seat].flip_reveal(reveal.cards, 0.12 * ANIM_SPEED)
		else:
			seats[reveal.seat].reveal(reveal.cards)
		names.append("%s：%s" % [tm.players[reveal.seat].name, reveal.hand_name])
	_message_label.text = "摊牌 · " + "，".join(names)


func on_pot_award(event: Dictionary) -> void:
	var p := tm.players[event.seat]
	# A4 收池：筹码移向赢家座位（S5）
	if anim_enabled:
		AudioManager.play(&"pot_win")
		await _anim_chip_to_seat(seats[event.seat], event.amount)
	seats[event.seat].set_chips(p.chips)
	_message_label.text = "%s 赢得 ¥%d（%s）" % [p.name, event.amount, event.hand_name]


func on_eliminated(event: Dictionary) -> void:
	var p := tm.players[event.seat]
	# A7 淘汰：座位灰化淡出（S8）
	if anim_enabled:
		AudioManager.play(&"eliminated")
		await seats[event.seat].fade_out(0.5 * ANIM_SPEED)
	seats[event.seat].refresh_status(p)
	_message_label.text = "%s 淘汰，第 %d 名" % [p.name, event.rank]


func on_blind_up(event: Dictionary) -> void:
	_blind_banner.text = "盲注升级！级别 %d：%d/%d" % [event.level, event.sb, event.bb]
	_message_label.text = _blind_banner.text
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
	var chip := _spawn_chip(_seat_center(seat), amount)
	var t := create_tween()
	t.tween_property(chip, "position", POT_POS, 0.3 * ANIM_SPEED)
	await t.finished
	chip.queue_free()


## A4：筹码从中央下注区移到赢家座位。
func _anim_chip_to_seat(seat: SeatUI, amount: int) -> void:
	var chip := _spawn_chip(POT_POS, amount)
	var t := create_tween()
	t.tween_property(chip, "position", _seat_center(seat), 0.35 * ANIM_SPEED)
	await t.finished
	chip.queue_free()


## 筹码贴图（assets/chips/，按金额区间着色：白<100 红<500 蓝<1000 黑≥1000）；
## 贴图缺失时降级为金色小圆块。
func _spawn_chip(pos: Vector2, amount: int = 0) -> Control:
	var tex := _chip_texture(amount)
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


## 按金额区间选筹码贴图；文件缺失返回 null（调用方走降级圆块）。
static func _chip_texture(amount: int) -> Texture2D:
	var chip_name := "chip_white"
	if amount >= 1000:
		chip_name = "chip_black"
	elif amount >= 500:
		chip_name = "chip_blue"
	elif amount >= 100:
		chip_name = "chip_red"
	var path := "res://assets/chips/%s.png" % chip_name
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _seat_center(seat: SeatUI) -> Vector2:
	return seat.position + Vector2(SeatUI.WIDTH / 2.0, 40)


func _refresh_top_bar() -> void:
	var blinds: Array = tm.config.blinds_at(tm.blind_level)
	var remain: int = tm.config.hands_per_level - tm.hands_played
	_top_bar.text = "盲注级别 %d（%d/%d） · 距升级 %d 手" % [tm.blind_level + 1, blinds[0], blinds[1], remain]


func _refresh_pot() -> void:
	if tm.hand != null:
		_pot_label.text = "底池 ¥%d" % tm.hand.pot_size()


func _set_street(street: HandController.Street) -> void:
	_street_label.text = STREET_NAMES.get(street, "")
