class_name AIDecider extends RefCounted
## AI 决策（TECH_DESIGN 4.6）：评分 → 风格+情绪+对手调制 → 动作选择，三步启发式。
## 有效参数 = 静态风格（AIProfiles）+ tilt_level × 人格 tilt 方向 + adaptability × 对手偏移
## （后两项均来自 AIMemory，可选；为零时逐比特退化为一期行为）。
## decide(ctx) 的返回永远在 ctx.legal_actions 允许的集合内（末尾做钳制校验）。

## 入局阈值基准：实际阈值 = BASE_ENTRY - 有效松度 × 0.35，再按位置/对手数微调
const BASE_ENTRY := 0.55
## 强牌分数线（≥ 按激进度加注，否则跟注/过牌）
const STRONG_HAND := 0.78
## tilt 对松度/诈唬的最大调制幅度
const TILT_LOOSENESS_SCALE := 0.35
const TILT_BLUFF_SCALE := 0.30

## 对手调制（二期）：统计量基准（理论均值，偏离量以此为零点）
const OPP_BASE_VPIP := 0.3
const OPP_BASE_AGGR := 0.4
const OPP_BASE_SHOWDOWN := 0.5
## 样本完成度：观察手数达到该值后调制满幅（不足时线性缩放，避免开局乱调）
const OPP_FULL_CONFIDENCE_HANDS := 10.0
## 对手调制各项偏移系数
const OPP_LOOSENESS_SCALE := 0.30
const OPP_BLUFF_SCALE := 0.40
const OPP_AGGR_SCALE := 0.40
const OPP_CALL_SCALE := 0.40

var rng := RandomNumberGenerator.new()


func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()


## ctx: {hole_cards, community, legal_actions, pot_size, call_amount, street, big_blind, chips, profile,
##       position(可选 -1~1，按钮位为 1), active_opponents(可选), memory(可选 AIMemory，只读)}
## profile 为身份名；也可直接传参数表 Dictionary（测试注入用，如 adaptability=0 的回归对照）。
## 返回 {type: BettingRound.ActionType, amount: int}
func decide(ctx: Dictionary) -> Dictionary:
	var legal: Dictionary = ctx.legal_actions
	var profile: Dictionary
	var p = ctx.get("profile", AIProfiles.DEFAULT_PROFILE)
	if p is Dictionary:
		profile = p
	else:
		profile = AIProfiles.get_profile(p)
	var tightness := float(profile.tightness)
	var aggression := float(profile.aggression)
	var risk := float(profile.risk_tolerance)

	# 情绪调制：tilt=0 时等价基础参数；memory 只读，不在决策期更新
	var tilt := 0.0
	var mem: AIMemory = ctx.get("memory")
	if mem != null:
		tilt = mem.tilt_level
	var eff_looseness := clampf(1.0 - tightness + tilt * float(profile.tilt_looseness_dir) * TILT_LOOSENESS_SCALE, 0.0, 1.0)
	var eff_bluff := clampf(float(profile.bluff_frequency) + tilt * float(profile.tilt_bluff_dir) * TILT_BLUFF_SCALE, 0.0, 1.0)

	# 对手调制（二期）：读人类行为统计，偏移量 = adaptability × 统计量偏离基准 × 系数 × 样本完成度。
	# 对手松 → 收紧等他撞、少诈；对手紧 → 多偷池；对手被动 → 多加注施压；对手摊牌弱 → 多跟其加注。
	# adaptability=0 或无样本时全部偏移为 0（无新增 rng 消耗），行为与一期逐比特一致。
	var eff_aggression := aggression
	var eff_calling := float(profile.calling_tendency)
	var adapt := float(profile.get("adaptability", 0.0))
	if mem != null and adapt > 0.0:
		var st: Dictionary = mem.opponent_stats
		var confidence := minf(float(st.get("hands_seen", 0)) / OPP_FULL_CONFIDENCE_HANDS, 1.0)
		if confidence > 0.0:
			var k := adapt * confidence
			var vpip_dev := float(st.get("vpip", OPP_BASE_VPIP)) - OPP_BASE_VPIP
			var aggr_dev := float(st.get("aggression", OPP_BASE_AGGR)) - OPP_BASE_AGGR
			var show_dev := float(st.get("showdown_strength", OPP_BASE_SHOWDOWN)) - OPP_BASE_SHOWDOWN
			eff_looseness = clampf(eff_looseness - k * vpip_dev * OPP_LOOSENESS_SCALE, 0.0, 1.0)
			eff_bluff = clampf(eff_bluff - k * vpip_dev * OPP_BLUFF_SCALE, 0.0, 1.0)
			eff_aggression = clampf(eff_aggression - k * aggr_dev * OPP_AGGR_SCALE, 0.0, 1.0)
			eff_calling = clampf(eff_calling - k * show_dev * OPP_CALL_SCALE, 0.0, 1.0)

	var s := HandStrength.score(ctx.hole_cards, ctx.community)
	var bb: int = maxi(ctx.get("big_blind", 20), 1)
	var chips: int = ctx.get("chips", 0)
	var call_amount: int = ctx.get("call_amount", 0)

	# 入局阈值：松度为主；位置意识使后位放宽/前位收紧；多人底池收紧
	var entry := BASE_ENTRY - eff_looseness * 0.35
	entry -= float(profile.position_awareness) * 0.12 * float(ctx.get("position", 0.0))
	var opps: int = ctx.get("active_opponents", 1)
	entry += 0.03 * float(mini(opps - 1, 3))

	# 短筹码触发线：4BB（保守）~ 12BB（激进），由风险承受决定
	var short_stack := float(chips) < (4.0 + risk * 8.0) * float(bb)

	var action := {}
	if short_stack and s >= entry * 0.7 and legal.can_all_in:
		# 低筹码：够看的牌直接全下
		action = {"type": BettingRound.ActionType.ALL_IN}
	elif s >= STRONG_HAND:
		# 强牌：按激进度加注，否则跟注/过牌
		if legal.can_raise and rng.randf() < eff_aggression:
			action = _make_raise(ctx, eff_aggression, 1.0)
		else:
			action = _call_or_check(legal)
	elif s >= entry:
		# 中牌：可跟则跟，便宜加注偶尔施压
		if legal.can_raise and call_amount == 0 and rng.randf() < eff_aggression * 0.35:
			action = _make_raise(ctx, eff_aggression, 0.6)
		elif _can_afford_call(legal, call_amount, chips, risk):
			action = _call_or_check(legal)
		elif legal.can_check:
			action = {"type": BettingRound.ActionType.CHECK}
		else:
			action = {"type": BettingRound.ActionType.FOLD}
	elif call_amount > 0 and _can_afford_call(legal, call_amount, chips, risk) and rng.randf() < eff_calling:
		# 跟注倾向：弱牌也愿意跟便宜注（跟注站风格的核心维度）
		action = {"type": BettingRound.ActionType.CALL}
	elif rng.randf() < eff_bluff and legal.can_raise and call_amount == 0:
		# 诈唬：无人下注时下注施压
		action = _make_raise(ctx, eff_aggression, 0.5)
	elif legal.can_check:
		action = {"type": BettingRound.ActionType.CHECK}
	else:
		action = {"type": BettingRound.ActionType.FOLD}

	return _clamp(action, legal)


## 加注金额：½池 ~ 1池随机，受激进度缩放，钳制到合法范围。
func _make_raise(ctx: Dictionary, aggression: float, strength_scale: float) -> Dictionary:
	var legal: Dictionary = ctx.legal_actions
	var pot: int = maxi(ctx.get("pot_size", 0), ctx.get("big_blind", 20))
	var frac := (0.5 + rng.randf() * 0.5) * (0.6 + aggression * 0.4) * strength_scale
	var target: int = legal.min_raise_to + int(float(pot) * frac)
	target = clampi(target, legal.min_raise_to, legal.max_raise_to)
	if target >= legal.max_raise_to:
		return {"type": BettingRound.ActionType.ALL_IN}
	return {"type": BettingRound.ActionType.RAISE, "amount": target}


func _call_or_check(legal: Dictionary) -> Dictionary:
	if legal.can_call:
		return {"type": BettingRound.ActionType.CALL}
	return {"type": BettingRound.ActionType.CHECK}


## 跟注纪律：跟注额不超过剩余筹码的一定比例即"便宜"，比例由风险承受决定（10% ~ 40%）。
func _can_afford_call(legal: Dictionary, call_amount: int, chips: int, risk: float) -> bool:
	if not legal.can_call:
		return legal.can_check
	return float(call_amount) <= (0.1 + risk * 0.3) * float(maxi(chips, 1))


## 终点钳制：无论决策产出什么，都校验成合法动作。
func _clamp(action: Dictionary, legal: Dictionary) -> Dictionary:
	var type: int = action.get("type", BettingRound.ActionType.FOLD)
	match type:
		BettingRound.ActionType.CHECK:
			if legal.can_check:
				return action
		BettingRound.ActionType.CALL:
			if legal.can_call:
				return action
		BettingRound.ActionType.RAISE:
			var amount: int = action.get("amount", 0)
			if legal.can_raise and amount >= legal.min_raise_to and amount <= legal.max_raise_to:
				return action
			if legal.can_raise:
				return {"type": BettingRound.ActionType.RAISE, "amount": legal.min_raise_to}
		BettingRound.ActionType.ALL_IN:
			if legal.can_all_in:
				return action
		BettingRound.ActionType.FOLD:
			return action
	# 兜底优先级：过牌 > 跟注 > 弃牌
	if legal.can_check:
		return {"type": BettingRound.ActionType.CHECK}
	if legal.can_call:
		return {"type": BettingRound.ActionType.CALL}
	return {"type": BettingRound.ActionType.FOLD}
