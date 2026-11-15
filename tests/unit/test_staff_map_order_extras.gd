extends TestCase
## The preview extras of the order gesture (TASK-153 stage 2): destination ghost, alternative
## posture line, goal-conflict mark, far-zoom stub. Pure functions on a hand-made state.
const Fixtures := preload("res://tests/fixtures.gd")

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


static func _state(enemy_at := Vector2i(100, 100)) -> OperationalState:
	var grid := HexGrid.new()
	for q in range(0, 8):
		for r in range(0, 5):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	grid.set_terrain(Vector2i(6, 0), Terrain.Type.WATER)
	var state := OperationalState.new()
	state.grid = grid
	state.formations.append(Fixtures.formation(&"f", 0, Vector2i.ZERO))
	if enemy_at != Vector2i(100, 100):
		state.formations.append(Fixtures.formation(&"e", 1, enemy_at))
	return state


func _preview(state: OperationalState, hex: Vector2i, posture := &"march") -> Dictionary:
	return StaffMapRoute.preview_in_posture(state, state.formations[0], hex, posture)


# --- destination ghost ---


func test_ghost_stands_on_the_target_with_the_arrival_turn() -> void:
	var state := _state()
	var preview := _preview(state, Vector2i(4, 0))
	var ghost := StaffMapOrderExtras.ghost(preview, {"valid": true})
	assert_eq(ghost["hex"], Vector2i(4, 0))
	assert_eq(ghost["text"], "T+%d" % maxi(preview["turns"], 1))


func test_ghost_text_follows_the_forecast_turns() -> void:
	var state := _state()
	var near := StaffMapOrderExtras.ghost(_preview(state, Vector2i(1, 0)), {"valid": true})
	var far := StaffMapOrderExtras.ghost(_preview(state, Vector2i(5, 0)), {"valid": true})
	assert_eq(near["text"], "T+1")
	assert_true(int(far["text"].substr(2)) >= int(near["text"].substr(2)))


func test_ghost_is_hidden_for_an_invalid_target() -> void:
	var state := _state()
	var water := _preview(state, Vector2i(6, 0))
	var verdict := StaffMapRoutePreview.verdict_of(state, state.formations[0], water)
	assert_false(verdict["valid"])
	assert_true(StaffMapOrderExtras.ghost(water, verdict).is_empty())
	assert_true(StaffMapOrderExtras.ghost({}, {"valid": true}).is_empty())


# --- alternative posture line ---


func test_alternative_posture_pairs_march_and_advance() -> void:
	assert_eq(StaffMapOrderExtras.alternative_posture(&"march"), &"advance")
	assert_eq(StaffMapOrderExtras.alternative_posture(&"advance"), &"march")
	assert_eq(StaffMapOrderExtras.alternative_posture(&"defend"), &"")


func test_alternative_is_absent_when_the_routes_are_equal() -> void:
	var state := _state()
	var main := _preview(state, Vector2i(3, 0))
	assert_true(
		(
			StaffMapOrderExtras
			. alternative(state, state.formations[0], Vector2i(3, 0), &"march", main)
			. is_empty()
		)
	)


func test_alternative_appears_when_the_other_posture_routes_differently() -> void:
	# An enemy beside the straight line: march walks round its zone, advance goes through.
	var state := _state(Vector2i(2, 1))
	var formation := state.formations[0]
	var target := Vector2i(4, 0)
	var march := _preview(state, target, &"march")
	var advance := _preview(state, target, &"advance")
	var alt := StaffMapOrderExtras.alternative(state, formation, target, &"march", march)
	assert_false(alt.is_empty(), "zone of control bends the march route only")
	assert_eq(alt["posture"], &"advance")
	assert_eq(alt["preview"]["route"], advance["route"])


func test_alternative_leaves_the_state_untouched() -> void:
	var state := _state(Vector2i(2, 1))
	var before := state.snapshot()
	var main := _preview(state, Vector2i(4, 0))
	StaffMapOrderExtras.alternative(state, state.formations[0], Vector2i(4, 0), &"march", main)
	assert_eq(state.snapshot(), before)


# --- goal conflict ---


func test_conflict_names_another_own_formation_ordered_to_the_hex() -> void:
	var state := _state()
	var other := Fixtures.formation(&"g", 0, Vector2i(0, 2))
	other.display_name = "5th Brigade"
	other.order = FormationOrder.new(Vector2i(4, 0))
	state.formations.append(other)
	var found := StaffMapOrderExtras.conflict(state, state.formations[0], Vector2i(4, 0))
	assert_eq(found["formation_id"], &"g")
	assert_true(found["text"].contains("5TH BRIGADE"))


func test_conflict_ignores_other_hexes_enemies_and_self() -> void:
	var state := _state()
	var other := Fixtures.formation(&"g", 0, Vector2i(0, 2))
	other.order = FormationOrder.new(Vector2i(4, 0))
	state.formations.append(other)
	var enemy := Fixtures.formation(&"e", 1, Vector2i(7, 4))
	enemy.order = FormationOrder.new(Vector2i(3, 3))
	state.formations.append(enemy)
	assert_true(StaffMapOrderExtras.conflict(state, state.formations[0], Vector2i(3, 3)).is_empty())
	assert_true(StaffMapOrderExtras.conflict(state, state.formations[0], Vector2i(2, 2)).is_empty())
	assert_true(StaffMapOrderExtras.conflict(state, other, Vector2i(4, 0)).is_empty())


# --- far-zoom stub ---


func test_a_short_order_becomes_a_stub_of_at_least_8_px() -> void:
	var stub := StaffMapOrderExtras.stub(Vector2(100, 100), Vector2(108, 100))
	assert_false(stub.is_empty())
	assert_true(stub["from"].distance_to(stub["to"]) >= StaffMapOrderExtras.STUB_MIN_PX)
	assert_true(stub["to"].x > stub["from"].x, "points the way of the order")


func test_a_zero_length_order_still_has_a_stub() -> void:
	var stub := StaffMapOrderExtras.stub(Vector2(50, 50), Vector2(50, 50))
	assert_true(stub["from"].distance_to(stub["to"]) >= StaffMapOrderExtras.STUB_MIN_PX)


func test_a_long_order_keeps_its_line() -> void:
	assert_true(StaffMapOrderExtras.stub(Vector2.ZERO, Vector2(120, 0)).is_empty())
