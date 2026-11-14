extends TestCase
## View models of battle conditions (TASK-099b): the contact notice lines, the reduced flags and
## the fire-support button state.

const Fixtures := preload("res://tests/fixtures.gd")

var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


func _conditions(fire_support: int) -> BattleSetup.Conditions:
	var conditions := BattleSetup.Conditions.new()
	conditions.fire_support = fire_support
	return conditions


func test_lines_of_full_conditions() -> void:
	var full := _conditions(2)
	assert_eq(ConditionsModel.fire_support_text(full), "Fire support 2")


func test_none() -> void:
	var open := _conditions(0)
	assert_eq(ConditionsModel.fire_support_text(open), "Fire support none")


func test_reduced_flags() -> void:
	assert_true(ConditionsModel.fire_support_reduced(_conditions(1)))
	assert_false(ConditionsModel.fire_support_reduced(_conditions(2)))


func _state() -> GameState:
	var state := GameState.new(Fixtures.plains_grid(5), 2, 7)
	state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	state.fire_support_left[0] = 2
	return state


func test_counter_follows_missions_left() -> void:
	var state := _state()
	assert_eq(FireSupportModel.counter_text(state, 0), "2")
	state.fire_support_left[0] = 1
	assert_eq(FireSupportModel.counter_text(state, 0), "1")


func test_counter_hidden_without_missions_at_the_start() -> void:
	assert_false(FireSupportModel.shown(0))
	assert_true(FireSupportModel.shown(2))


func test_problems() -> void:
	var state := _state()
	assert_eq(FireSupportModel.problem(state, 0), "")
	assert_eq(FireSupportModel.problem(state, 1), "NOT YOUR TURN")
	state.fire_support_used_turn[0] = true
	assert_eq(FireSupportModel.problem(state, 0), "FIRE SUPPORT ALREADY USED THIS TURN")
	state.fire_support_left[0] = 0
	assert_eq(FireSupportModel.problem(state, 0), "NO FIRE SUPPORT LEFT")


func test_targets_are_visible_enemies_only() -> void:
	var state := _state()
	var enemy := state.units_of(1)[0]
	assert_eq(FireSupportModel.targets(state, 0), [enemy.id] as Array[int])
	assert_eq(FireSupportModel.targets(state, 1), [state.units_of(0)[0].id] as Array[int])


func test_click_on_a_visible_enemy_sends_the_command_with_its_id() -> void:
	var state := _state()
	var enemy := state.units_of(1)[0]
	var command := FireSupportModel.click_command(state, 0, enemy.coord)
	assert_true(command != null)
	assert_eq(command.target_id, enemy.id)
	assert_eq(command.player, 0)
	var sim := GameSimulation.new(state)
	assert_true(sim.execute(command), "a visible enemy is a legal target")
	assert_eq(state.fire_support_left[0], 1)


func test_click_on_empty_or_own_tile_sends_nothing() -> void:
	var state := _state()
	assert_true(FireSupportModel.click_command(state, 0, Vector2i(1, 1)) == null)
	assert_true(FireSupportModel.click_command(state, 0, state.units_of(0)[0].coord) == null)


func test_report_mentions_missions_used() -> void:
	var state := _state()
	assert_eq(FireSupportModel.report_text(state, 0, 2), "")
	state.fire_support_left[0] = 1
	assert_eq(FireSupportModel.report_text(state, 0, 2), "FIRE SUPPORT USED 1")


func test_fire_support_battle_gives_both_sides_missions() -> void:
	var state := Scenario.build("fire_support_battle", 3, FactionRegistry.DEFAULT_IDS)
	assert_eq(state.fire_support_left, [2, 2] as Array[int])
	var plain := Scenario.default_battle(3)
	assert_eq(plain.fire_support_left, [0, 0] as Array[int], "other scenarios stay unchanged")
