class_name EquityCalculator extends RefCounted
## 观战模式胜率计算（全静态、纯逻辑、可无头单测）。
## 已知全部在局玩家手牌 + 已发公共牌，未知公共牌按剩余牌堆补齐：
## 未知 ≤2 张（翻牌圈起）精确枚举，未知 ≥3 张（翻牌前）蒙特卡洛抽样。
## 多人平分底池按份额计入胜率，各座位胜率之和恒为 1。

## 蒙特卡洛每批迭代数：逐批累积并暴露中间结果，供表现层渐进刷新显示。
const MONTE_CARLO_BATCH := 200


## 后台任务句柄：表现层把 run_job 放进 Thread 执行，UI 线程经 equity() 轮询中间结果；
## 局面变化或手牌结束时置 cancelled 请求停止（批间响应）。
class Job extends RefCounted:
	var mutex := Mutex.new()
	var cancelled := false  # 置 true 请求尽快停止
	var max_iterations := 0  # 蒙特卡洛迭代上限，0 = 直到 cancelled
	var iterations := 0  # 已完成迭代数（蒙特卡洛）或已枚举组合数（精确）
	var wins := {}  # seat -> 累积胜场份额
	var exact := false  # true = 精确枚举结果（非抽样估计）
	var done := false  # 任务结束（枚举完成 / 达到上限 / 被取消）

	## 当前胜率快照 {seat: 0~1}；尚无样本时返回空表。
	func equity() -> Dictionary:
		mutex.lock()
		var out := {}
		if iterations > 0:
			for seat in wins:
				out[seat] = wins[seat] / iterations
		mutex.unlock()
		return out


## 在调用线程内执行 job 直至结束（表现层应放 Thread 中调用；测试直接同步调用）。
## holes: {seat: Array[Card]}，只含仍在局的玩家（弃牌/出局者须先剔除）。
static func run_job(job: Job, holes: Dictionary, community: Array[Card], rng_seed: int) -> void:
	if holes.size() <= 1:
		job.mutex.lock()
		for seat in holes:
			job.wins[seat] = 1.0
		job.iterations = 1
		job.exact = true
		job.mutex.unlock()
		job.done = true
		return
	var pool := _remaining_pool(holes, community)
	# 预置全部座位，零胜场座位在 equity() 中也返回 0.0 而不是缺键
	job.mutex.lock()
	for seat in holes:
		job.wins[seat] = 0.0
	job.mutex.unlock()
	if 5 - community.size() <= 2:
		_run_exact(job, holes, community, pool)
	else:
		_run_monte_carlo(job, holes, community, pool, rng_seed)


# ---- 内部 ----

## 52 张牌中剔除所有已见牌（手牌 + 公共牌）后的剩余牌堆。
static func _remaining_pool(holes: Dictionary, community: Array[Card]) -> Array[Card]:
	var used := {}
	for seat in holes:
		for c: Card in holes[seat]:
			used[c.suit * 16 + c.rank] = true
	for c in community:
		used[c.suit * 16 + c.rank] = true
	var pool: Array[Card] = []
	for suit in 4:
		for rank in range(2, 15):
			if not used.has(suit * 16 + rank):
				pool.append(Card.new(suit, rank))
	return pool


## 已发公共牌 + 补上的未知牌 → 完整牌面（保证返回类型化数组）。
static func _with_cards(community: Array[Card], extras: Array) -> Array[Card]:
	var board: Array[Card] = community.duplicate()
	for c in extras:
		board.append(c)
	return board


## 比较一次完整牌面下各玩家的胜负，胜场份额累积进 wins。
static func _accumulate(wins: Dictionary, holes: Dictionary, board: Array[Card]) -> void:
	var best = null
	var winners: Array = []
	for seat in holes:
		var cards: Array[Card] = []
		cards.assign(holes[seat])
		cards.append_array(board)
		var rank := HandEvaluator.evaluate(cards)
		if best == null:
			best = rank
			winners = [seat]
		else:
			var cmp: int = HandEvaluator.compare(rank, best)
			if cmp > 0:
				best = rank
				winners = [seat]
			elif cmp == 0:
				winners.append(seat)
	var share := 1.0 / winners.size()
	for seat in winners:
		wins[seat] = wins.get(seat, 0.0) + share


static func _flush(job: Job, batch_wins: Dictionary, batch_count: int) -> void:
	job.mutex.lock()
	for seat in batch_wins:
		job.wins[seat] = job.wins.get(seat, 0.0) + batch_wins[seat]
	job.iterations += batch_count
	job.mutex.unlock()


static func _run_monte_carlo(job: Job, holes: Dictionary, community: Array[Card],
		pool: Array[Card], rng_seed: int) -> void:
	var need := 5 - community.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	while not job.cancelled and (job.max_iterations <= 0 or job.iterations < job.max_iterations):
		var batch_wins := {}
		for i in MONTE_CARLO_BATCH:
			# 部分 Fisher-Yates：只做 need 次交换采样未知公共牌
			for k in need:
				var j: int = rng.randi_range(k, pool.size() - 1)
				var tmp: Card = pool[k]
				pool[k] = pool[j]
				pool[j] = tmp
			_accumulate(batch_wins, holes, _with_cards(community, pool.slice(0, need)))
		_flush(job, batch_wins, MONTE_CARLO_BATCH)
	job.done = true


## 精确枚举全部未知公共牌组合。仅在街切换等局面变化时被中途取消（部分结果按序枚举
## 有偏，直接丢弃，表现层取消后本来也会废弃该 job）。
static func _run_exact(job: Job, holes: Dictionary, community: Array[Card], pool: Array[Card]) -> void:
	job.exact = true
	var need := 5 - community.size()
	var batch_wins := {}
	var count := 0
	if need == 0:
		_accumulate(batch_wins, holes, community)
		count = 1
	elif need == 1:
		for i in pool.size():
			_accumulate(batch_wins, holes, _with_cards(community, [pool[i]]))
			count += 1
	else:  # need == 2
		for a in range(pool.size() - 1):
			if job.cancelled:
				break
			for b in range(a + 1, pool.size()):
				_accumulate(batch_wins, holes, _with_cards(community, [pool[a], pool[b]]))
				count += 1
			# 精确枚举量大（翻牌圈 9 人约 561 组合），每外层循环响应一次取消
	if not job.cancelled:
		_flush(job, batch_wins, count)
	job.done = true
