class_name AIMemory extends RefCounted
## AI 情绪状态（TECH_DESIGN 4.6）：跨手存活，每个 AI 一份，由 TournamentManager 持有。
## 唯一动态量 tilt_level（0~1，"上头"程度）：输掉大锅时按人格 tilt_sensitivity 上涨，
## 每手按 tilt_recovery 自然衰减。决策时经 AIDecider 换算为松度/诈唬偏移。
## 只在手牌边界更新（与存档点一致）；决策期间只读。

## 大锅判定：损失超过本手开始前筹码的该比例
const BIG_LOSS_CHIPS_RATIO := 0.20
## 大锅判定：或超过该倍数大盲（深筹码时比比例更紧，取两者较小者）
const BIG_LOSS_BB := 15.0
## 每手衰减系数：tilt *= (1 - recovery × 该值)
const TILT_RECOVERY_SCALE := 0.3

var tilt_level: float = 0.0
var last_big_loss: int = 0  # 最近一次大锅损失额（调试用）


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


func to_dict() -> Dictionary:
	return {"tilt_level": tilt_level, "last_big_loss": last_big_loss}


func from_dict(d: Dictionary) -> void:
	tilt_level = d.get("tilt_level", 0.0)
	last_big_loss = d.get("last_big_loss", 0)
