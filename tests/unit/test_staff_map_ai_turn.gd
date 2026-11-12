extends TestCase
## The staff map lets the AI play its side once per turn (TASK-102c).

static var _map: StaffMap
static var _calls: Array[int] = []


func before_all() -> void:
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null


func _stub(sim: OperationalSimulation, player: int) -> Dictionary:
	_calls.append(player)
	sim.execute(EndOperationalTurnCommand.new())
	return {}


func test_ai_turn_runs_once_for_the_ai_side_and_never_for_the_human() -> void:
	_calls.clear()
	var state := _map.simulation().state
	_map.ai_turn = _stub
	_map.ai_side = 1 - _map.viewer_player
	state.current_player = _map.viewer_player
	assert_false(_map.play_ai_turn_if_due(), "human's turn")
	state.current_player = _map.ai_side
	assert_true(_map.play_ai_turn_if_due())
	assert_eq(_calls, [_map.ai_side] as Array[int])
	state.current_player = _map.ai_side
	assert_false(_map.play_ai_turn_if_due(), "not twice in the same turn")
	assert_eq(_calls.size(), 1)


func test_no_ai_turn_while_a_battle_is_pending_or_in_hot_seat() -> void:
	_calls.clear()
	var state := _map.simulation().state
	_map.ai_turn = _stub
	state.turn += 5
	state.current_player = _map.ai_side
	state.pending_battles.append(BattleSetup.new())
	assert_false(_map.play_ai_turn_if_due())
	state.pending_battles.clear()
	_map.ai_side = -1
	assert_false(_map.play_ai_turn_if_due(), "hot-seat")
	assert_eq(_calls.size(), 0)
