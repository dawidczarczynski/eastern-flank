extends TestCase
## TASK-131b: the range overlay sets (effective / extended / blocked) of a selected unit and the
## range texts.

const Fixtures := preload("res://tests/fixtures.gd")
const T72B3 := preload("res://data/units/t72b3.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const URAGAN := preload("res://data/units/bm27_uragan.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const RU_SQUAD := preload("res://data/units/ru_motor_rifle.tres")


func _flat_state(radius: int) -> GameState:
	var grid := Fixtures.plains_grid(radius)
	for c in grid.coords():
		grid.set_elevation(c, 0.0)
	return GameState.new(grid, 2, 1)


func _distances(coords: Array) -> Array[int]:
	var result: Array[int] = []
	for c: Vector2i in coords:
		if not result.has(Hex.distance(Vector2i.ZERO, c)):
			result.append(Hex.distance(Vector2i.ZERO, c))
	result.sort()
	return result


func test_tank_on_open_plains_has_the_8_and_12_rings_and_nothing_blocked() -> void:
	var state := _flat_state(14)
	var unit := state.add_unit(1, T72B3, Vector2i.ZERO)
	var sets := RangeOverlayModel.build(state, unit)
	assert_eq(_distances(sets["effective"]), [1, 2, 3, 4, 5, 6, 7, 8] as Array[int])
	assert_eq(_distances(sets["extended"]), [9, 10, 11, 12] as Array[int])
	assert_true((sets["blocked"] as Array).is_empty())


func test_a_forest_blocks_the_hexes_behind_it_for_a_tank_but_not_for_homar() -> void:
	var state := _flat_state(14)
	state.grid.set_terrain(Vector2i(2, 0), Terrain.Type.FOREST)
	var tank := state.add_unit(1, T72B3, Vector2i.ZERO)
	var sets := RangeOverlayModel.build(state, tank)
	assert_true((sets["blocked"] as Array).has(Vector2i(5, 0)))
	assert_false((sets["blocked"] as Array).has(Vector2i(1, 0)))
	var homar := state.add_unit(0, HOMAR, Vector2i(0, 5))
	assert_true((RangeOverlayModel.build(state, homar)["blocked"] as Array).is_empty())


func test_artillery_covers_every_map_hex_outside_the_minimum_range() -> void:
	var state := _flat_state(6)
	var unit := state.add_unit(0, URAGAN, Vector2i.ZERO)
	var sets := RangeOverlayModel.build(state, unit)
	var covered := {}
	for key: String in ["effective", "extended"]:
		for c: Vector2i in sets[key]:
			assert_true(state.grid.has_tile(c), "off-map hex %s" % c)
			covered[c] = true
	for c in state.grid.coords():
		assert_eq(covered.has(c), Hex.distance(Vector2i.ZERO, c) >= 3, str(c))


func test_range_texts() -> void:
	assert_eq(RangeText.line(T72B3), "2.0 km (8 hex), max 3.0 km")
	assert_eq(RangeText.line(RU_SQUAD), "500 m (2 hex), max 750 m")
	assert_eq(RangeText.line(URAGAN), "35 km (whole map), min 750 m")
	assert_eq(RangeText.short_text(URAGAN), "35 km (whole map)")
	assert_eq(RangeText.distance(6), "6 hex (1.5 km)")
	assert_eq(RangeText.falloff(0.75), "-25 %")
	assert_eq(RangeText.falloff(0.5), "-50 %")
	assert_eq(RangeText.falloff(1.0), "")


func test_catalog_range_matches_the_data_for_every_unit() -> void:
	for path: String in DirAccess.get_files_at("res://data/units"):
		if not path.ends_with(".tres"):
			continue
		var d := load("res://data/units/" + path) as UnitDefinition
		var text := RangeText.line(d)
		assert_true(
			text.contains(RangeText.metres(d.effective_range_m)) or RangeText.is_whole_map(d), path
		)
		assert_true(text.contains(RangeText.metres(d.max_range_m)), path)


func test_ring_reason_texts_for_sight_and_minimum_range() -> void:
	var state := _flat_state(10)
	state.grid.set_terrain(Vector2i(2, 0), Terrain.Type.FOREST)
	var tank := state.add_unit(0, T72B3, Vector2i.ZERO)
	var hidden := state.add_unit(1, SQUAD, Vector2i(5, 0))
	assert_eq(TargetRingModel.attack_reason(state, tank.id, hidden.id), "NO LINE OF SIGHT")
	var gun := state.add_unit(0, URAGAN, Vector2i(0, 6))
	var close := state.add_unit(1, SQUAD, Vector2i(0, 8))
	assert_eq(TargetRingModel.attack_reason(state, gun.id, close.id), "TARGET TOO CLOSE")
	assert_false(AttackCommand.valid_targets(state, tank.id).has(hidden.id))


func test_map_view_draws_and_clears_the_overlay_in_two_meshes() -> void:
	var view := Fixtures.map_view(_flat_state(3).grid)
	var near: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	var far: Array[Vector2i] = [Vector2i(2, 0)]
	view.show_attack_range(near, far, near)
	for instance: MeshInstance3D in [view._range_fill, view._range_line]:
		assert_true(instance.visible)
		var arrays := (instance.mesh as ArrayMesh).surface_get_arrays(0)
		assert_eq(
			(arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size(),
			(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		)
	view.clear_attack_range()
	assert_false(view._range_fill.visible)
	assert_false(view._range_line.visible)
	view.free()
