extends Node
## AudioManager（自动加载单例，TECH_DESIGN 6.4）：音效名 → 资源映射播放。
## 音量持久化到 user://save/settings.cfg；音量之外的设置项见 ui/game_settings.gd。

const SETTINGS_PATH := "user://save/settings.cfg"
const POOL_SIZE := 8

## GDD 第 7 章音效清单 S1~S10 → 资源路径。
const SFX := {
	&"deal_card": "res://assets/audio/deal_card.ogg",       # S1 发牌
	&"flip_card": "res://assets/audio/flip_card.ogg",       # S2 翻牌
	&"chip_bet": "res://assets/audio/chip_bet.ogg",         # S3 筹码下注
	&"all_in": "res://assets/audio/all_in.ogg",             # S4 全下
	&"pot_win": "res://assets/audio/pot_win.ogg",           # S5 收池
	&"fold": "res://assets/audio/fold.ogg",                 # S6 弃牌
	&"blind_up": "res://assets/audio/blind_up.ogg",         # S7 盲注升级
	&"eliminated": "res://assets/audio/eliminated.ogg",     # S8 淘汰
	&"win": "res://assets/audio/win.ogg",                   # S9 夺冠
	&"click": "res://assets/audio/click.ogg",               # S10 按钮点击
}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	_apply_volume(_load_volume())


## 播放音效；未知名称只警告不报错（表现层不允许因音效崩溃）。
func play(sfx: StringName) -> void:
	var stream: AudioStream = _streams.get(sfx)
	if stream == null:
		var path: String = SFX.get(sfx, "")
		if path.is_empty():
			push_warning("AudioManager: 未知音效 %s" % sfx)
			return
		stream = load(path)
		_streams[sfx] = stream
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.play()


## 线性音量 0.0~1.0，应用到 Master 总线并持久化。
func set_volume(linear: float) -> void:
	_apply_volume(linear)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 保留其他段
	cfg.set_value("audio", "volume", clampf(linear, 0.0, 1.0))
	var dir := SETTINGS_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	cfg.save(SETTINGS_PATH)


func get_volume() -> float:
	return _load_volume()


func _load_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return clampf(float(cfg.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	return 1.0


func _apply_volume(linear: float) -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if linear <= 0.0:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(linear))
