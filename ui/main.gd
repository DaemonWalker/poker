class_name Main extends Node
## 常驻主场景：场景路由器（TECH_DESIGN 6.1）。
## 持有"开局意图"状态；TableScene 作为本节点子场景，_ready 时从此读取后据此开局。

const SCENES := {
	"main_menu": "res://scenes/main_menu.tscn",
	"settings": "res://scenes/settings.tscn",
	"result": "res://scenes/result.tscn",
	"stats": "res://scenes/stats.tscn",
	"table": "res://scenes/table.tscn",
}

## 开局意图：继续存档 / 新建锦标赛。
enum TableIntent { CONTINUE, NEW }

var table_intent: int = TableIntent.CONTINUE
var table_ai_count: int = 5
var table_config: TournamentManager.TournamentConfig = null

var _current: Node = null


func _ready() -> void:
	GameSettings.apply_runtime()
	if "--auto" in OS.get_cmdline_user_args():
		# 无头冒烟回归入口：直达牌桌（TableScene 内保持原 load_save/默认开局行为）
		change_scene("table")
	else:
		change_scene("main_menu")


## F11 全局切换全屏（持久化到设置，与设置界面勾选同一存储）。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F11:
		GameSettings.set_fullscreen(not GameSettings.is_fullscreen())


## 切换场景；params 会传给新场景的 setup(params)（若其实现了该方法）。
func change_scene(scene_name: String, params: Dictionary = {}) -> void:
	assert(SCENES.has(scene_name), "未知场景: " + scene_name)
	if _current != null:
		_current.queue_free()
		_current = null
	var packed: PackedScene = load(SCENES[scene_name])
	_current = packed.instantiate()
	if not params.is_empty() and _current.has_method("setup"):
		_current.setup(params)
	add_child(_current)


## 继续存档中的锦标赛。
func continue_tournament() -> void:
	table_intent = TableIntent.CONTINUE
	change_scene("table")


## 开新锦标赛（ai_count 1~8；config 为空则按设置里的盲注参数构造）。
func start_new_tournament(ai_count: int, config: TournamentManager.TournamentConfig = null) -> void:
	table_intent = TableIntent.NEW
	table_ai_count = ai_count
	table_config = config
	change_scene("table")
