class_name AIMemory extends RefCounted
## AI 情绪状态（TECH_DESIGN 4.6）：跨手存活，每个 AI 一份，由 TournamentManager 持有。
## 唯一动态量 tilt_level（0~1，"上头"程度）：输掉大锅时按人格 tilt_sensitivity 上涨，
## 每手按 tilt_recovery 自然衰减。决策时经 AIDecider 换算为松度/诈唬偏移。
## 对手建模（二期）：opponent_stats 统计人类玩家的行为特征（EWMA 指数衰减平均），
## 决策时经 AIDecider 按 adaptability 换算为松度/诈唬/加注/跟注偏移。
## 只在手牌边界更新（与存档点一致）；决策期间只读。

## 大锅判定：损失超过本手开始前筹码的该比例
const BIG_LOSS_CHIPS_RATIO := 0.20
## 大锅判定：或超过该倍数大盲（深筹码时比比例更紧，取两者较小者）
const BIG_LOSS_BB := 15.0
## 每手衰减系数：tilt *= (1 - recovery × 该值)
const TILT_RECOVERY_SCALE := 0.3
## 对手统计 EWMA 衰减系数（近期加权，约 6~7 手形成主要印象）
const OPP_ALPHA := 0.15

var tilt_level: float = 0.0
var last_big_loss: int = 0  # 最近一次大锅损失额（调试用）

## 对手建模统计（只针对人类玩家）。初值取理论基准，偏离 = 0 即无调制；
## 样本不足时由 AIDecider 按 hands_seen 线性缩放。aggression/showdown_strength
## 只在有样本的手（翻牌后有 call/raise、走到摊牌）才参与 EWMA。
var opponent_stats := {
	"hands_seen": 0,          # 观察到的手数（人类参与的分母）
	"vpip": 0.3,              # 主动入池率（翻牌前 call/raise/all_in 占比）
	"pfr": 0.15,              # 翻牌前加注率
	"aggression": 0.4,        # 翻牌后攻击性（raise / (raise + call)）
	"showdown_strength": 0.5, # 摊牌平均牌力（HandStrength 口径 0~1）
}


## 手牌结束结算：delta 为本手筹码净变化（负为输），chips_before 为本手开始前筹码。
## 每手先自然衰减，再判定大锅损失。赢牌不影响 tilt。
func notify_hand_result(delta: int, chips_before: int, big_blind: int,
		sensitivity: float, recovery: float) -> void:
	tilt_level *= (1.0 - recovery * TILT_RECOVERY_SCALE)
	if chips_before <= 0 or delta >= 0:
		return
	var threshold := minf(BIG_LOSS_CHIPS_RATIO * chips_before, BIG_LOSS_BB * big_blind)
	if float(-delta) >= threshold:
		tilt_level = clampf(tilt_level + sensitivity * float(-delta) / float(chips_before), 0.0, 1.0)
		last_big_loss = -delta


## 对手建模更新：inc 为 OpponentTracker.parse_hand 解析出的一手行为增量
## {hands, vpip(bool), pfr(bool), aggression(float|null), showdown(float|null)}。
## 人类未参与本手（hands=0）时不更新；null 字段表示本手无该样本，不参与 EWMA。
func notify_opponent_hand(inc: Dictionary) -> void:
	if int(inc.get("hands", 0)) <= 0:
		return
	opponent_stats["hands_seen"] = int(opponent_stats["hands_seen"]) + 1
	opponent_stats["vpip"] = _ewma(float(opponent_stats["vpip"]), 1.0 if inc.get("vpip", false) else 0.0)
	opponent_stats["pfr"] = _ewma(float(opponent_stats["pfr"]), 1.0 if inc.get("pfr", false) else 0.0)
	var aggr = inc.get("aggression")
	if aggr != null:
		opponent_stats["aggression"] = _ewma(float(opponent_stats["aggression"]), float(aggr))
	var show = inc.get("showdown")
	if show != null:
		opponent_stats["showdown_strength"] = _ewma(float(opponent_stats["showdown_strength"]), float(show))


static func _ewma(old: float, sample: float) -> float:
	return old * (1.0 - OPP_ALPHA) + sample * OPP_ALPHA


func to_dict() -> Dictionary:
	return {"tilt_level": tilt_level, "last_big_loss": last_big_loss,
			"opponent_stats": {
				"hands_seen": int(opponent_stats["hands_seen"]),
				"vpip": float(opponent_stats["vpip"]),
				"pfr": float(opponent_stats["pfr"]),
				"aggression": float(opponent_stats["aggression"]),
				"showdown_strength": float(opponent_stats["showdown_strength"]),
			}}


func from_dict(d: Dictionary) -> void:
	tilt_level = d.get("tilt_level", 0.0)
	last_big_loss = d.get("last_big_loss", 0)
	var os: Dictionary = d.get("opponent_stats", {})
	for key in opponent_stats:
		if os.has(key):
			opponent_stats[key] = os[key]
