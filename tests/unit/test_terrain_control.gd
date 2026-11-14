extends TestCase
## The terrain control view model (TASK-152): occupied hexes, words, the layer
## rebuilding only on a change, and the simulation staying untouched.

static var _map: StaffMap


func before_all() -> void:
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null


func after_each() -> void:
	_map.simulation().state.hex_holders.clear()
	_map.set_viewer(0)


## A state with initial holders: q 0-2 side 0, q 3-5 side 1 (row 0).
static func _state() -> OperationalState:
	var state := OperationalState.new()
	state.player_sides = [&"nato", &"russia"] as Array[StringName]
	for q in 6:
		state.hex_initial[Vector2i(q, 0)] = 0 if q < 3 else 1
	return state


func test_untouched_start_is_empty() -> void:
	assert_eq(TerrainControl.occupied(_state()).size(), 0)


func test_a_hex_taken_by_the_enemy_appears_with_the_enemy_side() -> void:
	var state := _state()
	HexControl.take(state, Vector2i(1, 0), 1)
	assert_eq(TerrainControl.occupied(state), {Vector2i(1, 0): 1})


func test_ground_taken_from_the_enemy_is_ours() -> void:
	var state := _state()
	HexControl.take(state, Vector2i(4, 0), 0)
	assert_eq(TerrainControl.occupied(state), {Vector2i(4, 0): 0})


func test_retaken_by_the_original_side_disappears() -> void:
	var state := _state()
	HexControl.take(state, Vector2i(1, 0), 1)
	HexControl.take(state, Vector2i(1, 0), 0)
	assert_eq(TerrainControl.occupied(state).size(), 0)


func test_taking_your_own_hex_is_not_occupation() -> void:
	var state := _state()
	HexControl.take(state, Vector2i(0, 0), 0)
	assert_eq(TerrainControl.occupied(state).size(), 0)


func test_occupied_is_deterministic() -> void:
	var state := _state()
	HexControl.take(state, Vector2i(1, 0), 1)
	HexControl.take(state, Vector2i(4, 0), 0)
	assert_eq(TerrainControl.occupied(state), TerrainControl.occupied(state))
	assert_eq(TerrainControl.signature(state), TerrainControl.signature(state))


func test_words_for_the_card() -> void:
	var state := _state()
	HexControl.take(state, Vector2i(1, 0), 1)
	HexControl.take(state, Vector2i(4, 0), 0)
	assert_eq(TerrainControl.card_text(state, Vector2i(1, 0), 0), "Russia – occupied")
	assert_eq(TerrainControl.card_text(state, Vector2i(4, 0), 0), "NATO – captured from Russia")
	assert_eq(TerrainControl.card_text(state, Vector2i(2, 0), 0), "")
	assert_eq(StaffMapCard.control_word("NATO – captured from Russia"), "Captured")
	assert_eq(StaffMapCard.control_word("Russia – occupied"), "Occupied")


func test_the_layer_rebuilds_only_on_a_change() -> void:
	var layer := _map.terrain_control()
	var state := _map.simulation().state
	layer.refresh(state, 0)
	var before := layer.rebuild_count()
	layer.refresh(state, 0)
	assert_eq(layer.rebuild_count(), before, "nothing changed")
	var hex: Vector2i = state.hex_initial.keys()[0]
	var enemy := 1 - int(state.hex_initial[hex])
	state.hex_holders[hex] = enemy
	layer.refresh(state, 0)
	assert_eq(layer.rebuild_count(), before + 1, "an occupied hex rebuilds")
	assert_eq(layer.occupied(), {hex: enemy})
	_map.set_viewer(1)
	assert_true(layer.rebuild_count() >= before + 2, "a viewer change rebuilds")


func test_hatch_comes_with_z1_and_k_toggles() -> void:
	var layer := _map.terrain_control()
	layer.set_view(0)
	assert_false(layer.hatch_visible())
	layer.set_view(1)
	assert_true(layer.hatch_visible())
	layer.set_view(2)
	layer.set_view(1)
	var on := layer.is_enabled()
	layer.set_enabled(not on)
	assert_false(layer.visible if on else not layer.visible)
	layer.set_enabled(on)


func test_the_layer_never_changes_the_state() -> void:
	var state := _map.simulation().state
	var before := state.snapshot()
	_map.terrain_control().refresh(state, 1)
	_map.terrain_control().set_view(2)
	assert_eq(state.snapshot(), before)
