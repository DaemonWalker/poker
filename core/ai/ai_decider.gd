class_name AIDecider extends RefCounted
## AI 决策（TECH_DESIGN 4.6）：评分 → 风格调制 → 动作选择，三步启发式。
## decide(ctx) 的返回永远在 ctx.legal_actions 允许的集合内（末尾做钳制校验）。

## 剩余筹码低于该倍数大盲时触发全下倾向
const SHORT_STACK_BB := 8.0
## 跟注额超过剩余筹码该比例时视为"贵注"
const EXPENSIVE_CALL_RATIO := 0.25

var rng := RandomNumberGenerator.new()


func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()


## ctx: {hole_cards, community, legal_actions, pot_size, call_amount, street, big_blind, chips, profile}
## 返回 {type: BettingRound.ActionType, amount: int}
func decide(ctx: Dictionary) -> Dictionary:
	var legal: Dictionary = ctx.legal_actions
	var profile: Dictionary = AIProfiles.get_profile(ctx.get("profile", AIProfiles.PROFILE_TAG))
	var looseness: float = profile.looseness
	var aggression: float = profile.aggression
	var bluff: float = profile.bluff_frequency

	var s := HandStrength.score(ctx.hole_cards, ctx.community)
	var bb: int = maxi(ctx.get("big_blind", 20), 1)
	var chips: int = ctx.get("chips", 0)
	var call_amount: int = ctx.get("call_amount", 0)
	var pot: int = ctx.get("pot_size", 0)

	# 风格调制：松度降低入局门槛，低筹码触发全下倾向
	var entry_threshold := 0.55 - looseness * 0.35  # 值得"投入"的评分线
	var short_stack := float(chips) < SHORT_STACK_BB * float(bb)

	var action := {}
	if short_stack and s >= entry_threshold * 0.7 and legal.can_all_in:
		# 低筹码：够看的牌直接全下
		action = {"type": BettingRound.ActionType.ALL_IN}
	elif s >= 0.78:
		# 强牌：按激进度加注，否则跟注/过牌
		if legal.can_raise and rng.randf() < aggression:
			action = _make_raise(ctx, aggression, 1.0)
		else:
			action = _call_or_check(legal)
	elif s >= entry_threshold:
		# 中牌：可跟则跟，便宜加注偶尔施压
		if legal.can_raise and call_amount == 0 and rng.randf() < aggression * 0.35:
			action = _make_raise(ctx, aggression, 0.6)
		elif _can_afford_call(legal, call_amount, chips):
			action = _call_or_check(legal)
		elif legal.can_check:
			action = {"type": BettingRound.ActionType.CHECK}
		else:
			action = {"type": BettingRound.ActionType.FOLD}
	elif rng.randf() < bluff and legal.can_raise and call_amount == 0:
		# 诈唬：无人下注时下注施压
		action = _make_raise(ctx, aggression, 0.5)
	elif profile == AIProfiles.PROFILES[AIProfiles.PROFILE_STATION] and _can_afford_call(legal, call_amount, chips):
		# 跟注站：弱牌也爱跟便宜注
		action = _call_or_check(legal)
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


## 跟注站纪律：跟注额不超过剩余筹码 ¼ 或 2 倍大盲即"便宜"。
func _can_afford_call(legal: Dictionary, call_amount: int, chips: int) -> bool:
	if not legal.can_call:
		return legal.can_check
	return float(call_amount) <= EXPENSIVE_CALL_RATIO * float(maxi(chips, 1))


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
