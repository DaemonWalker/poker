class_name SaveManager extends RefCounted
## 锦标赛进度存档（TECH_DESIGN 4.8）：JSON，手牌边界保存，带 version 字段。
## 路径默认 user://save/tournament.save，测试可注入临时路径。

const DEFAULT_PATH := "user://save/tournament.save"

var path: String


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


func has_save() -> bool:
	return FileAccess.file_exists(path)


## 无存档或 JSON 损坏返回 {}。版本校验由 TournamentManager.from_dict 负责。
func load() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func save(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "无法写入存档: " + path)
	f.store_string(JSON.stringify(data, "\t"))


func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(path)
