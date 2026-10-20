extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

const VIEWPORT := Vector2(1280, 720)
const CARD := Vector2(320, 330)

## The GDD calibration units (generic infantry and cavalry), local to the tests.
var _infantry := Fixtures.generic_infantry()
var _tank := Fixtures.generic_tank()


func _state() -> GameState:
	return GameState.new(Fixtures.plains_grid(3), 2, 1)


func _stat(model: Dictionary, label: String) -> Dictionary:
	for stat: Dictionary in model["stats"]:
		if stat["label"] == label:
			return stat
	return {}


func test_fresh_own_infantry() -> void:
	var state := _state()
	var unit := state.add_unit(0, _infantry, Vector2i.ZERO)
	var m := UnitPopupModel.build(state, unit, 0)
	assert_eq(m["type"], "CLASS_INFANTRY")
	assert_eq(m["name"], "Infantry")
	assert_eq(m["faction"], "Poland")
	assert_eq(m["color"], state.faction_of(0).color)
	assert_eq(m["hp"], 10)
	assert_eq(m["max_hp"], 10)
	var segments: Array[Color] = m["segments"]
	assert_eq(segments.size(), 10)
	for c in segments:
		assert_eq(c, UiPalette.HP_HIGH)
	assert_eq(_stat(m, "Attack")["value"], "4")
	assert_true(is_equal_approx(_stat(m, "Attack")["fill"], 0.4))
	assert_eq(_stat(m, "Defense")["value"], "3")
	assert_true(is_equal_approx(_stat(m, "Defense")["fill"], 0.3))
	assert_eq(_stat(m, "Moves")["value"], "3/3")
	assert_true(is_equal_approx(_stat(m, "Moves")["fill"], 0.5))
	assert_eq(_stat(m, "Range")["value"], "1")
	assert_true(is_equal_approx(_stat(m, "Range")["fill"], 1.0 / 6.0))
	assert_eq(m["status"], "Ready")
	assert_eq(m["status_color"], UiPalette.HP_HIGH)


## Header = the class, below it the real name – never the same text twice.
func test_abrams_shows_class_and_real_name() -> void:
	var state := _state()
	var unit := state.add_unit(0, load("res://data/units/m1a2_sepv3.tres"), Vector2i.ZERO)
	var m := UnitPopupModel.build(state, unit, 0)
	assert_eq(m["type"], "CLASS_TANK")
	assert_eq(m["name"], "M1A2 SEPv3 Abrams")


func test_defense_includes_terrain_bonus() -> void:
	var state := _state()
	state.grid.set_terrain(Vector2i.ZERO, Terrain.Type.FOREST)
	state.grid.set_terrain(Vector2i(1, 0), Terrain.Type.HILLS)
	var in_forest := state.add_unit(0, _infantry, Vector2i.ZERO)
	var on_hills := state.add_unit(0, _infantry, Vector2i(1, 0))
	var forest_bonus := state.grid.defense_bonus(Vector2i.ZERO)
	var hills_bonus := state.grid.defense_bonus(Vector2i(1, 0))
	var m := UnitPopupModel.build(state, in_forest, 0)
	var stat := _stat(m, "Defense")
	assert_eq(stat["value"], "%d (3+%d)" % [3 + forest_bonus, forest_bonus])
	assert_true(is_equal_approx(stat["fill"], (3 + forest_bonus) / 10.0))
	assert_eq(_stat(m, "Terrain defense"), {}, "terrain bonus is folded into Defense")
	stat = _stat(UnitPopupModel.build(state, on_hills, 0), "Defense")
	assert_eq(stat["value"], "%d (3+%d)" % [3 + hills_bonus, hills_bonus])


func test_damaged_cavalry_segments() -> void:
	var state := _state()
	var unit := state.add_unit(0, _tank, Vector2i.ZERO)
	unit.hp = 3
	var segments: Array[Color] = UnitPopupModel.build(state, unit, 0)["segments"]
	assert_eq(segments.size(), 8)
	for i in 8:
		assert_eq(segments[i], UiPalette.HP_MID if i < 3 else UiPalette.HP_EMPTY)
	unit.hp = 2
	segments = UnitPopupModel.build(state, unit, 0)["segments"]
	assert_eq(segments[0], UiPalette.HP_LOW)
	assert_eq(segments[1], UiPalette.HP_LOW)
	assert_eq(segments[2], UiPalette.HP_EMPTY)


func test_done_and_attacked_status() -> void:
	var state := _state()
	var unit := state.add_unit(0, _infantry, Vector2i.ZERO)
	unit.moves_left = 0
	unit.has_attacked = true
	var m := UnitPopupModel.build(state, unit, 0)
	assert_eq(m["status"], "Done this turn")
	assert_eq(m["status_color"], Color("#a19f95"))
	unit.moves_left = 2
	assert_eq(UnitPopupModel.build(state, unit, 0)["status"], "Ready · already attacked")


func test_enemy_status() -> void:
	var state := _state()
	var unit := state.add_unit(1, _tank, Vector2i.ZERO)
	var m := UnitPopupModel.build(state, unit, 0)
	assert_eq(m["status"], "Enemy unit")
	assert_eq(m["status_color"], state.faction_of(1).color)
	assert_eq(m["faction"], "Russia")


func test_placement() -> void:
	assert_eq(UnitPopupModel.placement(Vector2(100, 300), VIEWPORT, CARD), Vector2(124, 220))
	assert_eq(UnitPopupModel.placement(Vector2(1100, 300), VIEWPORT, CARD), Vector2(756, 220))
	assert_eq(UnitPopupModel.placement(Vector2(10, 50), VIEWPORT, CARD), Vector2(34, 96))
	assert_eq(UnitPopupModel.placement(Vector2(600, 700), VIEWPORT, CARD), Vector2(624, 374))


func test_placement_clamps_left_and_tall_card() -> void:
	assert_eq(UnitPopupModel.placement(Vector2(1275, 300), VIEWPORT, CARD).x, 931.0)
	assert_eq(UnitPopupModel.placement(Vector2(300, 300), Vector2(1280, 400), CARD).y, 96.0)


func _csv_keys() -> Dictionary:
	var keys := {}
	var file := FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	assert_true(file != null, "cannot open strings.csv")
	if file == null:
		return keys
	while not file.eof_reached():
		keys[file.get_csv_line()[0]] = true
	return keys


func test_all_model_strings_are_translation_keys() -> void:
	var keys := _csv_keys()
	var state := _state()
	var fresh := state.add_unit(0, _infantry, Vector2i.ZERO)
	var attacked := state.add_unit(0, _tank, Vector2i(1, 0))
	attacked.has_attacked = true
	var done := state.add_unit(0, _infantry, Vector2i(0, 1))
	done.moves_left = 0
	done.has_attacked = true
	var enemy := state.add_unit(1, _tank, Vector2i(-1, 0))
	for pair: Array in [[fresh, 0], [attacked, 0], [done, 0], [enemy, 0]]:
		var m := UnitPopupModel.build(state, pair[0], pair[1])
		var texts: Array[String] = [m["type"], m["faction"], m["name"], m["status"]]
		for stat: Dictionary in m["stats"]:
			texts.append(stat["label"])
		for text in texts:
			assert_true(keys.has(text), "missing CSV key '%s'" % text)
