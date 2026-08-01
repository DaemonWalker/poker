class_name StatsManager extends RefCounted
## 战绩统计（TECH_DESIGN 4.9 / GDD 8.2）：JSON 持久化，字段对应战绩界面。

const DEFAULT_PATH := "user://save/stats.save"
const STATS_VERSION := 1

## 战绩数据（全部字段在 to_dict/from_dict 中逐项序列化）。
class StatsData extends RefCounted:
	var games_played: int = 0   # 参赛场次
	var wins: int = 0           # 夺冠次数
	var top3: int = 0           # 前三次数
	var total_hands: int = 0    # 总手牌数
	var pots_won: int = 0       # 总赢池次数
	var chip_peak: int = 0      # 最高单局筹码峰值
	var rank_distribution: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]  # 第 1~9 名次数

	func to_dict() -> Dictionary:
		return {
			"games_played": games_played, "wins": wins, "top3": top3,
			"total_hands": total_hands, "pots_won": pots_won,
			"chip_peak": chip_peak, "rank_distribution": rank_distribution.duplicate(),
		}

	func from_dict(d: Dictionary) -> void:
		games_played = d.get("games_played", 0)
		wins = d.get("wins", 0)
		top3 = d.get("top3", 0)
		total_hands = d.get("total_hands", 0)
		pots_won = d.get("pots_won", 0)
		chip_peak = d.get("chip_peak", 0)
		rank_distribution.clear()
		var rd: Array = d.get("rank_distribution", [])
		for i in 9:
			rank_distribution.append(rd[i] if i < rd.size() else 0)


var path: String
var data := StatsData.new()


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	self.load()


func load() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.get("version", -1) == STATS_VERSION:
		data.from_dict(parsed.get("stats", {}))


func save() -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "无法写入战绩: " + path)
	f.store_string(JSON.stringify({"version": STATS_VERSION, "stats": data.to_dict()}, "\t"))


## 锦标赛结束（人类名次 rank，总人数 player_count）时更新。
func record_tournament_finish(rank: int, player_count: int) -> void:
	data.games_played += 1
	if rank == 1:
		data.wins += 1
	if rank <= 3:
		data.top3 += 1
	if rank >= 1 and rank <= data.rank_distribution.size():
		data.rank_distribution[rank - 1] += 1
