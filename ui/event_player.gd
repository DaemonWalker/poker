class_name EventPlayer extends Node
## 事件队列播放器（TECH_DESIGN 6.2/6.3）：逐条消费逻辑层事件，分发到 table_scene 的
## on_xxx 函数（Tween 动画 + finished 推进队列）。A9 AI 思考延迟在本层 PLAYER_ACTION 分支。

signal queue_drained
## table_scene 收到人类动作（玩家点击或超时自动）后调 deliver_human_action 触发。
signal human_action(action: Dictionary)

const DELAY_SHORT := 0.25
const DELAY_NORMAL := 0.45
const DELAY_LONG := 1.0
const DELAY_HAND_END := 0.8
const DELAY_AUTO := 0.03

var tm: TournamentManager
var table: TableScene
var auto_play := false
## 跳过本局（人类弃牌后点"跳过本局"置位）：省略思考延迟与事件间隔，瞬间播完剩余事件。
var fast_forward := false

var _queue: Array[Dictionary] = []
var _playing := false


## 追加事件并启动消费（若未在播）。
func play_events(events: Array[Dictionary]) -> void:
	_queue.append_array(events)
	if not _playing:
		_drain()


## table_scene 转交的人类动作。
func deliver_human_action(action: Dictionary) -> void:
	human_action.emit(action)


func _drain() -> void:
	_playing = true
	while not _queue.is_empty():
		var event: Dictionary = _queue.pop_front()
		await _dispatch(event)
	_playing = false
	queue_drained.emit()


func _dispatch(event: Dictionary) -> void:
	match event.type:
		Events.Type.HAND_START:
			await table.on_hand_start(event)
			await _wait(DELAY_NORMAL)
		Events.Type.DEAL_HOLE:
			await table.on_deal_hole(event)
			await _wait(DELAY_SHORT)
		Events.Type.PLAYER_ACTION:
			# A9 思考中：AI 行动前随机延迟 + 省略号动效（GDD 4.3）
			if not auto_play and not fast_forward and not tm.players[event.seat].is_human:
				await table.play_thinking(event.seat, randf_range(0.5, 1.5))
			await table.on_player_action(event)
			await _wait(DELAY_NORMAL)
		Events.Type.DEAL_FLOP, Events.Type.DEAL_TURN, Events.Type.DEAL_RIVER:
			await table.on_deal_community(event)
			await _wait(DELAY_NORMAL)
		Events.Type.ROUND_END:
			await table.on_round_end(event)
			await _wait(DELAY_SHORT)
		Events.Type.SHOWDOWN:
			await table.on_showdown(event)
			await _wait(DELAY_LONG)
		Events.Type.POT_AWARD:
			await table.on_pot_award(event)
			await _wait(DELAY_LONG)
		Events.Type.ELIMINATED:
			await table.on_eliminated(event)
			await _wait(DELAY_NORMAL)
		Events.Type.BLIND_UP:
			await table.on_blind_up(event)
			await _wait(DELAY_LONG)
		Events.Type.HAND_END:
			await table.on_hand_end(event)
			await _wait(DELAY_HAND_END)
		Events.Type.TOURNAMENT_WIN, Events.Type.TOURNAMENT_LOSE:
			table.on_tournament_end(event)
		Events.Type.ACTION_REQUIRED:
			await _play_action_required(event)
		_:
			push_warning("EventPlayer: 未处理的事件类型 %s" % event.type)


## ACTION_REQUIRED：停住队列，等玩家提交（或超时/自动代打），提交后新事件入队继续。
func _play_action_required(event: Dictionary) -> void:
	table.on_action_required(event)
	var action: Dictionary
	if auto_play:
		action = _auto_choose(event.legal_actions)
	else:
		action = await human_action
	if tm.submit_human_action(action):
		_queue.append_array(tm.pop_events())
	else:
		push_error("EventPlayer: 人类动作被拒绝 %s" % action)


## 冒烟调试用自动代打：能过牌就过牌，否则跟注，再不行弃牌。
func _auto_choose(legal: Dictionary) -> Dictionary:
	if legal.can_check:
		return {"type": BettingRound.ActionType.CHECK, "amount": 0}
	if legal.can_call:
		return {"type": BettingRound.ActionType.CALL, "amount": legal.call_amount}
	return {"type": BettingRound.ActionType.FOLD, "amount": 0}


func _wait(sec: float) -> void:
	await get_tree().create_timer(DELAY_AUTO if (auto_play or fast_forward) else sec).timeout
