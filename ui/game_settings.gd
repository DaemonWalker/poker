class_name GameSettings extends RefCounted
## 游戏设置持久化：与 AudioManager 共用 user://save/settings.cfg，
## 各用各的 section；读写前先 load 保留其他段（参照 AudioManager.set_volume）。

const SETTINGS_PATH := "user://save/settings.cfg"

const DEFAULT_DEADLINE_MS := 30000
const MIN_DEADLINE_SEC := 5
const MAX_DEADLINE_SEC := 120

const DEFAULT_STARTING_CHIPS := 1000
const MIN_STARTING_CHIPS := 100
const MAX_STARTING_CHIPS := 100000
const DEFAULT_HANDS_PER_LEVEL := 10
const MIN_HANDS_PER_LEVEL := 1
const MAX_HANDS_PER_LEVEL := 100


## 启动时应用需要全局生效的运行时设置（行动倒计时）。
static func apply_runtime() -> void:
	Events.DEFAULT_DEADLINE_MS = get_deadline_ms()


# ---- 行动倒计时（gameplay/deadline_ms，0 = 关闭） ----

static func get_deadline_ms() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return maxi(0, int(cfg.get_value("gameplay", "deadline_ms", DEFAULT_DEADLINE_MS)))
	return DEFAULT_DEADLINE_MS


static func set_deadline_ms(ms: int) -> void:
	ms = maxi(0, ms)
	Events.DEFAULT_DEADLINE_MS = ms
	_save_value("gameplay", "deadline_ms", ms)


# ---- 动画速度（ui/anim_fast，快速 = 0.5，标准 = 1.0） ----

static func is_anim_fast() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return bool(cfg.get_value("ui", "anim_fast", false))
	return false


static func set_anim_fast(fast: bool) -> void:
	_save_value("ui", "anim_fast", fast)


static func anim_speed() -> float:
	return 0.5 if is_anim_fast() else 1.0


# ---- 盲注参数（blinds/*，仅生效于之后新建的锦标赛） ----

static func get_starting_chips() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return clampi(int(cfg.get_value("blinds", "starting_chips", DEFAULT_STARTING_CHIPS)),
				MIN_STARTING_CHIPS, MAX_STARTING_CHIPS)
	return DEFAULT_STARTING_CHIPS


static func get_hands_per_level() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return clampi(int(cfg.get_value("blinds", "hands_per_level", DEFAULT_HANDS_PER_LEVEL)),
				MIN_HANDS_PER_LEVEL, MAX_HANDS_PER_LEVEL)
	return DEFAULT_HANDS_PER_LEVEL


static func set_blind_params(starting_chips: int, hands_per_level: int) -> void:
	_save_value("blinds", "starting_chips",
			clampi(starting_chips, MIN_STARTING_CHIPS, MAX_STARTING_CHIPS))
	_save_value("blinds", "hands_per_level",
			clampi(hands_per_level, MIN_HANDS_PER_LEVEL, MAX_HANDS_PER_LEVEL))


## 按设置构造新锦标赛配置（blind_levels 表沿用默认）。
static func make_config() -> TournamentManager.TournamentConfig:
	var config := TournamentManager.TournamentConfig.default()
	config.starting_chips = get_starting_chips()
	config.hands_per_level = get_hands_per_level()
	return config


static func _save_value(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 保留其他段
	cfg.set_value(section, key, value)
	var dir := SETTINGS_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	cfg.save(SETTINGS_PATH)
