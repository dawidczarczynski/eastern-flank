extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var state: GameState
var markers: ObjectiveMarkers


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	var no_conditions: Array[VictoryCondition] = []
	state.set_objectives(
		Fixtures.objectives(8, [Vector2i(1, 0), Vector2i(-1, 1)], [1, -1], no_conditions)
	)
	markers = ObjectiveMarkers.new()
	markers.build(state, 1.0, func(_x: float, _z: float) -> float: return 0.0)


func after_each() -> void:
	markers.free()


func test_one_marker_per_objective_hex_in_its_owner_colour() -> void:
	assert_eq(markers.get_child_count(), 2)
	assert_eq(markers.color_of(Vector2i(1, 0)), UiPalette.faction_color(state, 1))
	assert_eq(markers.color_of(Vector2i(-1, 1)), UiPalette.NEUTRAL_FACTION)


func test_capture_recolours_the_hex() -> void:
	var event := {
		"type": &"objective_captured", "coord": Vector2i(-1, 1), "player": 0, "previous_owner": -1
	}
	markers.on_captured(state, event)
	assert_eq(markers.color_of(Vector2i(-1, 1)), UiPalette.faction_color(state, 0))
	assert_eq(markers.color_of(Vector2i(1, 0)), UiPalette.faction_color(state, 1))


func test_debug_result_states_are_ended() -> void:
	var draw := DebugResult.ended_state("objective_battle", 7, "draw")
	assert_true(draw.is_over())
	assert_eq(HudModel.result_banner(draw, 0), "DRAW")
	assert_eq(draw.turn, 8)
	var victory := DebugResult.ended_state("default_battle", 7, "victory")
	assert_eq(HudModel.result_reason(victory, 0), "OBJECTIVES TAKEN")
