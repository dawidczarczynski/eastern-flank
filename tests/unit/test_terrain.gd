extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")


func test_defense_bonus_loaded_from_data() -> void:
	assert_eq(Terrain.definition(Terrain.Type.PLAINS).defense_bonus, 0)
	assert_eq(Terrain.definition(Terrain.Type.FOREST).defense_bonus, 1)
	assert_eq(Terrain.definition(Terrain.Type.HILLS).defense_bonus, 2)
	assert_eq(Terrain.definition(Terrain.Type.WATER).defense_bonus, 0)


func test_water_is_impassable_in_data() -> void:
	assert_true(Terrain.definition(Terrain.Type.WATER).impassable)
	assert_false(Terrain.definition(Terrain.Type.PLAINS).impassable)


func test_every_type_has_a_definition_with_matching_id() -> void:
	var ids: Array[StringName] = [
		&"plains", &"forest", &"hills", &"water", &"fields", &"urban", &"marsh"
	]
	for t: int in Terrain.Type.values():
		var definition := Terrain.definition(t as Terrain.Type)
		assert_true(definition != null)
		assert_eq(definition.id, ids[t])


func test_grid_move_cost_derives_from_definitions() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i(0, 0), Terrain.Type.PLAINS)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(2, 0), Terrain.Type.HILLS)
	grid.set_terrain(Vector2i(3, 0), Terrain.Type.WATER)
	assert_eq(grid.move_cost(Vector2i(0, 0)), 1)
	assert_eq(grid.move_cost(Vector2i(1, 0)), 2)
	assert_eq(grid.move_cost(Vector2i(2, 0)), 2)
	assert_eq(grid.move_cost(Vector2i(3, 0)), Terrain.IMPASSABLE)


func test_grid_defense_bonus() -> void:
	var grid := Fixtures.plains_grid(2)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(0, 1), Terrain.Type.HILLS)
	assert_eq(grid.defense_bonus(Vector2i(0, 0)), 0)
	assert_eq(grid.defense_bonus(Vector2i(1, 0)), 1)
	assert_eq(grid.defense_bonus(Vector2i(0, 1)), 2)


func test_defense_bonus_off_map_is_zero() -> void:
	assert_eq(Fixtures.plains_grid(1).defense_bonus(Vector2i(9, 9)), 0)


# --- TASK-108: real-terrain types ---


func test_real_terrain_types_from_data() -> void:
	var expected := {
		Terrain.Type.FIELDS: ["Fields", 1, 0, 0.2],
		Terrain.Type.URBAN: ["Urban", 1, 2, 0.2],
		Terrain.Type.MARSH: ["Marsh", 2, 0, 0.1],
	}
	for t: Terrain.Type in expected:
		var definition := Terrain.definition(t)
		var values: Array = expected[t]
		assert_eq(definition.display_name, values[0])
		assert_eq(definition.move_cost, values[1], values[0])
		assert_eq(definition.defense_bonus, values[2], values[0])
		assert_false(definition.impassable, values[0])
		assert_true(absf(definition.default_elevation - float(values[3])) < 1e-6, values[0])


func test_old_types_keep_their_values() -> void:
	assert_eq(Terrain.move_cost(Terrain.Type.PLAINS), 1)
	assert_eq(Terrain.move_cost(Terrain.Type.FOREST), 2)
	assert_eq(Terrain.move_cost(Terrain.Type.HILLS), 2)
	assert_eq(Terrain.move_cost(Terrain.Type.WATER), Terrain.IMPASSABLE)


func test_new_types_are_appended_to_the_enum() -> void:
	assert_eq(Terrain.Type.PLAINS, 0)
	assert_eq(Terrain.Type.WATER, 3)
	assert_eq(Terrain.Type.FIELDS, 4)
	assert_eq(Terrain.Type.URBAN, 5)
	assert_eq(Terrain.Type.MARSH, 6)


func test_damage_on_real_terrain() -> void:
	var expected := {Terrain.Type.URBAN: 2, Terrain.Type.FIELDS: 4, Terrain.Type.MARSH: 4}
	for t: Terrain.Type in expected:
		var grid := Fixtures.plains_grid(2)
		grid.set_terrain(Vector2i(1, 0), t)
		var state := GameState.new(grid, 2, 1)
		var attacker := state.add_unit(0, ABRAMS, Vector2i.ZERO)
		var defender := state.add_unit(1, SQUAD, Vector2i(1, 0))
		assert_eq(AttackCommand.compute_damage(state, attacker, defender), expected[t], str(t))


func test_unit_card_shows_the_urban_defense() -> void:
	var grid := Fixtures.plains_grid(2)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.URBAN)
	var state := GameState.new(grid, 2, 1)
	var unit := state.add_unit(0, SQUAD, Vector2i(1, 0))
	var model := UnitPopupModel.build(state, unit, 0)
	var found := false
	for stat: Dictionary in model["stats"]:
		if stat.values().has("Defense"):
			found = true
			assert_true(stat.values().has("5 (3+2)"), str(stat))
	assert_true(found, "defense stat")
