class_name TournamentManager extends RefCounted
## 锦标赛调度（TECH_DESIGN 4.7）：驱动 HandController 逐手进行，
## 处理淘汰/按钮移动/盲注升级/自动存档，产生 TOURNAMENT_WIN/LOSE。

const SAVE_VERSION := 1

## 锦标赛配置（GDD 3.2）。
class TournamentConfig extends RefCounted:
	var starting_chips: int = 1000
	var blind_levels: Array = [  # 每级 [小盲, 大盲]
		[10, 20], [15, 30], [20, 40], [30, 60], [40, 80],
		[60, 120], [80, 160], [100, 200], [150, 300], [200, 400],
	]
	var hands_per_level: int = 10
	## 简单模式：洗牌偏向人类（起手更强、公共牌更有利），仅对新建锦标赛生效。
	var easy_mode: bool = false

	static func default() -> TournamentConfig:
		return TournamentConfig.new()

	## 超出表后每级翻倍。
	func blinds_at(level: int) -> Array:
		if level < blind_levels.size():
			return blind_levels[level]
		var base: Array = blind_levels.back()
		var factor := 1 << (level - blind_levels.size() + 1)
		return [base[0] * factor, base[1] * factor]

	func to_dict() -> Dictionary:
		return {"starting_chips": starting_chips, "blind_levels": blind_levels,
				"hands_per_level": hands_per_level, "easy_mode": easy_mode}

	func from_dict(d: Dictionary) -> void:
		starting_chips = d.get("starting_chips", starting_chips)
		blind_levels = d.get("blind_levels", blind_levels)
		hands_per_level = d.get("hands_per_level", hands_per_level)
		easy_mode = d.get("easy_mode", easy_mode)


var config: TournamentConfig
var players: Array[PlayerState] = []
var button_seat: int = 0
var blind_level: int = 0
var hands_played: int = 0  # 本级别已进行手数
var hand_count_total: int = 0
var eliminated: Array[int] = []  # 淘汰顺序（先淘汰者在前）
var finished: bool = false

var hand: HandController
var save_manager: SaveManager
var stats_manager: StatsManager

var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []


func _init(p_save_manager: SaveManager = null, p_stats_manager: StatsManager = null) -> void:
	save_manager = p_save_manager if p_save_manager != null else SaveManager.new()
	stats_manager = p_stats_manager if p_stats_manager != null else StatsManager.new()


## 新开锦标赛：人类坐 0 号位，1~8 个 AI 随机分配身份与风格（尽量不重复）。
func start_new(p_config: TournamentConfig, ai_count: int, rng_seed: int = 0) -> void:
	assert(ai_count >= 1 and ai_count <= 8, "AI 数量须在 1~8")
	config = p_config
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()

	players.clear()
	eliminated.clear()
	blind_level = 0
	hands_played = 0
	hand_count_total = 0
	finished = false

	var human := PlayerState.new()
	human.seat_index = 0
	human.name = "你"
	human.avatar_id = "avatar_human"
	human.is_human = true
	human.chips = config.starting_chips
	players.append(human)

	# 身份随机洗牌，风格按身份习惯配对（AIProfiles.IDENTITY_PREFERRED_PROFILE），尽量避免重复
	var identities: Array = AIProfiles.IDENTITIES.duplicate()
	_shuffle(identities)
	for i in ai_count:
		var ai := PlayerState.new()
		ai.seat_index = i + 1
		ai.name = identities[i].name
		ai.avatar_id = identities[i].avatar_id
		ai.ai_profile = AIProfiles.IDENTITY_PREFERRED_PROFILE.get(ai.name, AIProfiles.PROFILE_TAG)
		ai.chips = config.starting_chips
		players.append(ai)

	button_seat = _rng.randi_range(0, players.size() - 1)
	_autosave()


## 执行下一手牌。人类在局中时可能挂起（is_waiting_for_human()）。
func run_next_hand() -> void:
	if finished:
		push_error("TournamentManager: 锦标赛已结束")
		return
	var in_hand: Array[PlayerState] = []
	for p in players:
		if p.status != PlayerState.Status.OUT:
			in_hand.append(p)
	if in_hand.size() < 2:
		push_error("TournamentManager: 存活玩家不足，无法开始手牌")
		return

	hand_count_total += 1
	hands_played += 1
	var blinds: Array = config.blinds_at(blind_level)
	# AI 决策器按手牌种子播种：同一手牌种子 → 同一决策序列，存档恢复后可复现
	var deck_seed := _rng.randi()
	# 简单模式：洗牌偏向人类座位（人类已淘汰则锦标赛已结束，这里必然找得到）
	var rig_seat := -1
	if config.easy_mode:
		for p in in_hand:
			if p.is_human:
				rig_seat = p.seat_index
	hand = HandController.new(in_hand, button_seat, blinds[0], blinds[1],
			deck_seed, AIDecider.new(deck_seed), hand_count_total, rig_seat)
	hand.start()
	var hand_events := hand.pop_events()
	_events.append_array(hand_events)
	if hand.is_finished():
		_after_hand_end(hand_events)


func is_waiting_for_human() -> bool:
	return hand != null and hand.is_waiting()


## 人类动作提交；成功且本手结束时做收尾。
func submit_human_action(action: Dictionary) -> bool:
	if not is_waiting_for_human():
		return false
	if not hand.submit_human_action(action):
		return false
	var hand_events := hand.pop_events()
	_events.append_array(hand_events)
	if hand.is_finished():
		_after_hand_end(hand_events)
	return true


func pop_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


## 存活玩家数。
func alive_count() -> int:
	var n := 0
	for p in players:
		if p.status != PlayerState.Status.OUT:
			n += 1
	return n


func human() -> PlayerState:
	return players[0]


# ---- 手牌收尾 ----

func _after_hand_end(hand_events: Array) -> void:
	# 记录淘汰：按 HandController ELIMINATED 事件的顺序（同手淘汰者已按名次排好）
	for e in hand_events:
		if e.type == Events.Type.ELIMINATED and not eliminated.has(e.seat):
			eliminated.append(e.seat)

	# 战绩：总手数、人类赢池、筹码峰值
	stats_manager.data.total_hands += 1
	for e in hand_events:
		if e.type == Events.Type.POT_AWARD and e.seat == 0:
			stats_manager.data.pots_won += 1
	stats_manager.data.chip_peak = maxi(stats_manager.data.chip_peak, human().chips)

	# 胜负判定
	var h := human()
	if h.status == PlayerState.Status.OUT:
		var rank := players.size() - eliminated.find(h.seat_index)
		_tournament_end(false, rank)
		return
	if alive_count() == 1:
		_tournament_end(true, 1)
		return

	# 按钮移动到下一个未淘汰座位
	button_seat = _next_alive_seat_after(button_seat)

	# 盲注升级
	if hands_played >= config.hands_per_level:
		blind_level += 1
		hands_played = 0
		var blinds: Array = config.blinds_at(blind_level)
		_events.append(Events.blind_up(blind_level, blinds[0], blinds[1]))

	stats_manager.save()
	_autosave()


func _tournament_end(win: bool, rank: int) -> void:
	finished = true
	if win:
		_events.append(Events.tournament_win())
	else:
		_events.append(Events.tournament_lose(rank))
	stats_manager.record_tournament_finish(rank, players.size())
	stats_manager.save()
	save_manager.clear()  # 锦标赛结束后不再保留进度存档


func _next_alive_seat_after(seat: int) -> int:
	var n := players.size()
	for i in range(1, n + 1):
		var s := (seat + i) % n
		if players[s].status != PlayerState.Status.OUT:
			return s
	return seat


func _autosave() -> void:
	if not finished:
		save_manager.save(to_dict())


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---- 序列化（手牌边界，TECH_DESIGN 4.8） ----

func to_dict() -> Dictionary:
	var player_dicts: Array = []
	for p in players:
		player_dicts.append({
			"seat_index": p.seat_index, "name": p.name, "avatar_id": p.avatar_id,
			"is_human": p.is_human, "ai_profile": p.ai_profile, "chips": p.chips,
			"status": p.status,  # 手牌边界：存活者均 ACTIVE，淘汰者 OUT
		})
	return {
		"version": SAVE_VERSION,
		"config": config.to_dict(),
		"players": player_dicts,
		"button_seat": button_seat,
		"blind_level": blind_level,
		"hands_played": hands_played,
		"hand_count_total": hand_count_total,
		"eliminated": eliminated.duplicate(),
		"rng_state": str(_rng.state),  # 64 位状态以字符串存（JSON 数字会丢精度）；恢复后下一手牌堆种子序列一致
	}


## 从存档恢复。版本不匹配返回 false。
func from_dict(d: Dictionary) -> bool:
	if d.get("version", -1) != SAVE_VERSION:
		return false
	config = TournamentConfig.new()
	config.from_dict(d.config)
	players.clear()
	for pd in d.players:
		var p := PlayerState.new()
		p.seat_index = pd.seat_index
		p.name = pd.name
		p.avatar_id = pd.avatar_id
		p.is_human = pd.is_human
		p.ai_profile = pd.ai_profile
		p.chips = pd.chips
		p.status = pd.status
		players.append(p)
	button_seat = d.button_seat
	blind_level = d.blind_level
	hands_played = d.hands_played
	hand_count_total = d.hand_count_total
	eliminated.clear()
	eliminated.append_array(d.eliminated)
	_rng.state = str(d.rng_state).to_int()
	finished = false
	hand = null
	return true


## 从 SaveManager 恢复锦标赛；无存档或版本不匹配返回 false。
func load_save() -> bool:
	var d := save_manager.load()
	if d.is_empty():
		return false
	return from_dict(d)
