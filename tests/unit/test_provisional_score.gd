extends TestCase
## ProvisionalScore (TASK-103a): the provisional winner by held AI goals at the round cap.


func _goal(id: StringName, player: int, coord: Vector2i, weight: int, install := &"") -> AiGoal:
	var goal := AiGoal.new()
	goal.id = id
	goal.player = player
	goal.coord = coord
	goal.weight = weight
	goal.installation_id = install
	return goal


func _state() -> OperationalState:
	var state := Operation.build(&"suwalki_gap", 1)
	state.ai_goals.clear()
	state.formations.clear()
	state.installations.clear()
	return state


func _put(state: OperationalState, owner: int, coord: Vector2i, id: StringName) -> void:
	var formation := Formation.new()
	formation.id = id
	formation.owner_id = owner
	formation.coord = coord
	state.formations.append(formation)


func _scored() -> OperationalState:
	var state := _state()
	state.ai_goals.append(_goal(&"a", 0, Vector2i(1, 1), 3))
	state.ai_goals.append(_goal(&"b", 0, Vector2i(2, 2), 2))
	state.ai_goals.append(_goal(&"c", 1, Vector2i(3, 3), 4))
	state.ai_goals.append(_goal(&"d", 1, Vector2i(4, 4), 9))
	_put(state, 0, Vector2i(1, 1), &"f1")
	_put(state, 0, Vector2i(2, 2), &"f2")
	_put(state, 1, Vector2i(3, 3), &"f3")
	return state


func test_totals_sum_held_goal_weights() -> void:
	assert_eq(ProvisionalScore.totals(_scored()), [5, 4] as Array[int])


func test_threshold_makes_a_small_lead_a_draw() -> void:
	var state := _scored()
	assert_eq(ProvisionalScore.evaluate(state, 2)["winner"], -1)
	assert_eq(ProvisionalScore.evaluate(state, 0)["winner"], 0)


func test_result_shape() -> void:
	var r := ProvisionalScore.evaluate(_scored(), 0)
	assert_eq(r["reason"], &"provisional")
	assert_eq(r["by"], -1)


func test_equal_totals_are_a_draw() -> void:
	var state := _scored()
	state.ai_goals[1].weight = 1
	state.ai_goals[2].weight = 4
	assert_eq(ProvisionalScore.evaluate(state, 0)["winner"], -1)


func test_threshold_defaults_to_the_state_data() -> void:
	var state := _scored()
	state.provisional_draw_threshold = 5
	assert_eq(ProvisionalScore.evaluate(state)["winner"], -1)
	state.provisional_draw_threshold = 0
	assert_eq(ProvisionalScore.evaluate(state)["winner"], 0)


func test_enemy_standing_on_a_goal_denies_it() -> void:
	var state := _scored()
	state.formations[0].owner_id = 1
	assert_eq(ProvisionalScore.totals(state), [2, 4] as Array[int])


func test_installation_goal_needs_friendly_control() -> void:
	var state := _state()
	var installation := Installation.new()
	installation.id = &"hq"
	installation.owner = 0
	installation.coord = Vector2i(5, 5)
	state.installations.append(installation)
	state.ai_goals.append(_goal(&"hq_goal", 0, Vector2i.ZERO, 3, &"hq"))
	assert_eq(ProvisionalScore.totals(state), [3, 0] as Array[int])
	_put(state, 1, Vector2i(5, 5), &"enemy")
	assert_eq(ProvisionalScore.totals(state), [0, 0] as Array[int])


func test_turn_cap_is_data() -> void:
	assert_eq(Operation.build(&"suwalki_gap", 1).turn_cap, 30)
