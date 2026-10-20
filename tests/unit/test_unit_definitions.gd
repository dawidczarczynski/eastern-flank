extends TestCase
## The six real units of TASK-039a (GDD "Stat derivation rules", "First rosters").

const Fixtures := preload("res://tests/fixtures.gd")
const UNITS_DIR := "res://data/units"
## id -> [display_name, short_name, unit_class, mobility, max_hp, move, attack, defense, range]
const TABLE := {
	&"m1a2_sepv3": ["M1A2 SEPv3 Abrams", "M1A2", &"tank", &"tracked", 10, 5, 7, 4, 1],
	&"t72b3": ["T-72B3", "T-72B3", &"tank", &"tracked", 8, 5, 6, 4, 1],
	&"homar_k": ["Homar-K", "HOMAR", &"mlrs", &"wheeled", 6, 3, 6, 1, 6],
	&"bm27_uragan": ["9K57 Uragan", "BM-27", &"mlrs", &"wheeled", 6, 3, 6, 1, 5],
	&"pl_mech_infantry": ["Mechanised Infantry Squad", "INF", &"infantry", &"foot", 10, 3, 4, 3, 1],
	&"ru_motor_rifle": ["Motor Rifle Squad", "INF", &"infantry", &"foot", 10, 3, 4, 3, 1],
}


func _definitions() -> Array[UnitDefinition]:
	var result: Array[UnitDefinition] = []
	for file in DirAccess.get_files_at(UNITS_DIR):
		if file.ends_with(".tres"):
			result.append(load(UNITS_DIR.path_join(file)) as UnitDefinition)
	return result


func _unit(id: StringName) -> UnitDefinition:
	return load("%s/%s.tres" % [UNITS_DIR, id]) as UnitDefinition


func test_exactly_the_six_real_units_exist() -> void:
	var ids: Array[StringName] = []
	for definition in _definitions():
		ids.append(definition.id)
	ids.sort()
	var expected: Array[StringName] = []
	expected.assign(TABLE.keys())
	expected.sort()
	assert_eq(ids, expected)
	for old in ["infantry", "cavalry", "rocket_artillery"]:
		assert_false(FileAccess.file_exists("%s/%s.tres" % [UNITS_DIR, old]), old + " deleted")


func test_definitions_match_the_table() -> void:
	for id: StringName in TABLE:
		var d := _unit(id)
		assert_true(d != null, "%s loads" % id)
		if d == null:
			continue
		assert_eq(d.id, id)
		assert_eq(
			[
				d.display_name,
				d.short_name,
				d.unit_class,
				d.mobility,
				d.max_hp,
				d.move_points,
				d.attack,
				d.defense,
				d.attack_range
			],
			TABLE[id],
			String(id)
		)


func test_short_names_fit_the_label() -> void:
	for definition in _definitions():
		assert_true(definition.short_name.length() <= 6, String(definition.id))


func test_class_labels_translate() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("pl")
	assert_eq(String(TranslationServer.translate("TNK")), "CZOŁ")
	assert_eq(String(TranslationServer.translate("CLASS_TANK")), "Czołg")
	assert_eq(String(TranslationServer.translate("CLASS_MLRS")), "Artyleria rakietowa")
	assert_eq(String(TranslationServer.translate("CLASS_INFANTRY")), "Piechota")
	TranslationServer.set_locale("en")
	assert_eq(String(TranslationServer.translate("TNK")), "TNK")
	assert_eq(String(TranslationServer.translate("CLASS_TANK")), "Tank")
	TranslationServer.set_locale(previous)


## Damage of `attacker_id` hitting `defender_id` standing on `terrain`.
func _damage(
	attacker_id: StringName, defender_id: StringName, terrain := Terrain.Type.PLAINS
) -> int:
	var state := GameState.new(Fixtures.plains_grid(2), 2, 1)
	state.grid.set_terrain(Vector2i(1, 0), terrain)
	var attacker := state.add_unit(0, _unit(attacker_id), Vector2i.ZERO)
	var defender := state.add_unit(1, _unit(defender_id), Vector2i(1, 0))
	return AttackCommand.compute_damage(state, attacker, defender)


func test_damage_spot_checks() -> void:
	assert_eq(_damage(&"m1a2_sepv3", &"t72b3"), 3)
	assert_eq(_damage(&"t72b3", &"m1a2_sepv3"), 2)
	assert_eq(_damage(&"m1a2_sepv3", &"bm27_uragan"), 6)
	assert_eq(_damage(&"homar_k", &"bm27_uragan"), 5)
	assert_eq(_damage(&"ru_motor_rifle", &"m1a2_sepv3"), 1)
	assert_eq(_damage(&"t72b3", &"pl_mech_infantry"), 3)
	assert_eq(_damage(&"m1a2_sepv3", &"ru_motor_rifle", Terrain.Type.HILLS), 2)
