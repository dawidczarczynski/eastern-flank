extends TestCase
## Formation counters and panel on the staff map (TASK-092b): view rules (StaffMapFormations),
## the viewer swap on a counter, translations of the shipped names, and a scene smoke test that
## builds the staff map with the shipped operation (one build shared by the scene tests).

const CSV_PATH := "res://assets/i18n/strings.csv"

static var _map: StaffMap
static var _previous_locale: String

var _palette: StaffMapPalette


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func before_each() -> void:
	_palette = load(StaffMapPalette.PATH) as StaffMapPalette


func test_viewer_relation() -> void:
	assert_eq(StaffMapFormations.viewer_relation(0, 0), StaffMapFormations.OWN)
	assert_eq(StaffMapFormations.viewer_relation(1, 0), StaffMapFormations.ENEMY)
	assert_eq(StaffMapFormations.viewer_relation(1, 1), StaffMapFormations.OWN)
	assert_eq(StaffMapFormations.viewer_relation(0, 1), StaffMapFormations.ENEMY)


func test_strength_segments() -> void:
	var lit: Array[int] = []
	for strength in [40, 30, 20, 10]:
		lit.append(StaffMapFormations.lit_segments(strength, 40))
	assert_eq(lit, [5, 4, 3, 1] as Array[int])
	assert_eq(StaffMapFormations.lit_segments(0, 40), 0)
	assert_eq(StaffMapFormations.lit_segments(1, 40), 1, "anything left lights one")
	assert_eq(StaffMapFormations.lit_segments(18, 18), 5)


func test_strength_colours_and_low_state() -> void:
	assert_eq(StaffMapFormations.strength_colour(30, 40, _palette), _palette.strength_high)
	assert_eq(StaffMapFormations.strength_colour(29, 40, _palette), _palette.strength_mid)
	assert_eq(StaffMapFormations.strength_colour(20, 40, _palette), _palette.strength_mid)
	assert_eq(StaffMapFormations.strength_colour(19, 40, _palette), _palette.ui_alert)
	assert_false(StaffMapFormations.is_low(20, 40))
	assert_true(StaffMapFormations.is_low(19, 40))


func test_designation() -> void:
	assert_eq(
		StaffMapFormations.designation("1st Mechanised Battalion", "15th Mechanised Brigade"),
		"1/15"
	)
	assert_eq(StaffMapFormations.designation("2nd MLRS Battalion", "1st Guards Tank Army"), "2/1")
	assert_eq(StaffMapFormations.designation("Recon", "11th Army Corps"), "11")
	assert_eq(StaffMapFormations.designation("3rd Battalion", ""), "3")


func test_viewer_from_args() -> void:
	var sides: Array[StringName] = [&"nato", &"russia"]
	assert_eq(StaffMapFormations.viewer_from_args(PackedStringArray(), sides), 0)
	assert_eq(StaffMapFormations.viewer_from_args(PackedStringArray(["--side=russia"]), sides), 1)
	assert_eq(StaffMapFormations.viewer_from_args(PackedStringArray(["--side=NATO"]), sides), 0)
	var reversed: Array[StringName] = [&"russia", &"nato"]
	assert_eq(StaffMapFormations.viewer_from_args(PackedStringArray(), reversed), 1)


func test_stack_leaders_group_same_owner_only() -> void:
	var points: Array[Vector2] = [
		Vector2(100, 100), Vector2(110, 105), Vector2(300, 100), Vector2(105, 100)
	]
	var owners: Array[int] = [0, 0, 0, 1]
	var leaders := StaffMapFormations.stack_leaders(points, owners)
	assert_eq(leaders, PackedInt32Array([0, 0, 2, 3]))


func test_next_in_cycle() -> void:
	var ids: Array[StringName] = [&"a", &"b", &"c"]
	assert_eq(StaffMapFormations.next_in_cycle(ids, &""), &"a")
	assert_eq(StaffMapFormations.next_in_cycle(ids, &"b"), &"c")
	assert_eq(StaffMapFormations.next_in_cycle(ids, &"c"), &"a")
	assert_eq(StaffMapFormations.next_in_cycle([] as Array[StringName], &"a"), &"")


func test_swapping_the_viewer_swaps_shape_but_not_colour() -> void:
	var formation := Operation.build(&"suwalki_gap", 1).formations[0]
	assert_eq(formation.owner_id, 0)
	var counter := StaffMapCounter.new()
	counter.setup(formation, 0, _palette)
	var corner := Vector2(18, 11)  # inside the 40 x 26 rectangle, outside the 38 x 38 diamond
	var tip := Vector2(0, -18)  # inside the diamond, above the rectangle
	assert_true(counter.is_own())
	assert_eq(counter.fill_colour(), _palette.side_own)
	assert_eq(counter.ink_colour(), _palette.side_own_ink)
	assert_true(counter.hits(corner))
	assert_false(counter.hits(tip))
	counter.set_viewer(formation.owner_id, 1)
	assert_false(counter.is_own())
	assert_eq(counter.fill_colour(), _palette.side_own, "NATO stays blue for either viewer")
	assert_eq(counter.ink_colour(), _palette.side_own_ink)
	assert_false(counter.hits(corner))
	assert_true(counter.hits(tip))
	var russian := Operation.build(&"suwalki_gap", 1).formations[-1]
	assert_eq(russian.owner_id, 1)
	counter.setup(russian, 0, _palette)
	assert_eq(counter.fill_colour(), _palette.side_enemy, "Russia is always red")
	counter.set_viewer(1, 1)
	assert_true(counter.is_own())
	assert_eq(counter.fill_colour(), _palette.side_enemy, "also when it is the viewer's side")
	counter.free()


func test_shipped_formation_texts_are_translation_keys() -> void:
	var keys := {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		keys[row[0]] = true
	var state := Operation.build(&"suwalki_gap", 1)
	for formation in state.formations:
		for text in [formation.display_name, formation.parent, formation.definition.display_name]:
			assert_true(keys.has(text), "'%s' is not in the CSV" % text)
	for side_id in state.player_sides:
		assert_true(keys.has(SideDefinition.find(side_id).display_name), String(side_id))
	TranslationServer.set_locale("pl")
	assert_eq(tr("1st Mechanised Battalion"), "1. Batalion Zmechanizowany")
	TranslationServer.set_locale("en")


func test_scene_has_one_counter_per_formation() -> void:
	var state := _map.simulation().state
	assert_eq(state.formations.size(), 18)
	assert_eq(_map.counters().counter_count(), state.formations.size())
	for formation in state.formations:
		var node := _map.counters().get_node_or_null(String(formation.id))
		assert_true(node is StaffMapCounter, String(formation.id))
	assert_true(_map.counters().shown_ids().size() > 0, "some counters on screen")


func test_scene_selecting_fills_the_panel() -> void:
	var panel := _map.formation_panel()
	_map.select_formation(&"pl_mech_1")
	assert_true(panel.visible)
	assert_eq(_map.selected_formation(), &"pl_mech_1")
	assert_true(_map.counters().counter(&"pl_mech_1").selected)
	assert_eq(panel.name_text(), "1ST MECHANISED BATTALION")
	assert_eq(panel.parent_text(), "20th Mechanised Brigade")
	assert_eq(panel.value_text("STRENGTH"), "40 / 40")
	assert_false(panel.hostile)
	assert_eq(panel.company_count(), 4)
	assert_true(panel.company_text(3).contains("pl_mech_1/4"), panel.company_text(3))
	assert_true(panel.company_text(3).contains("Abrams"), panel.company_text(3))
	_map.select_formation(&"ru_mr_1")
	assert_true(panel.hostile, "enemy formations are marked hostile")
	assert_eq(panel.value_text("STRENGTH"), "38 / 38")
	_map.select_formation(&"")
	assert_false(panel.visible)
	assert_false(_map.counters().counter(&"pl_mech_1").selected)


func test_scene_click_picks_a_counter_and_empty_map_deselects() -> void:
	var shown := _map.counters().shown_ids()
	var id: StringName = shown[0]
	_map.click_at(_map.counter_screen_position(id))
	assert_eq(_map.selected_formation(), id)
	_map.click_at(Vector2(-1000, -1000))
	assert_eq(_map.selected_formation(), &"")
	assert_false(_map.formation_panel().visible)


func test_scene_viewer_swap() -> void:
	assert_true(_map.counters().counter(&"pl_mech_1").is_own())
	assert_false(_map.counters().counter(&"ru_mr_1").is_own())
	_map.set_viewer(1)
	assert_false(_map.counters().counter(&"pl_mech_1").is_own())
	assert_true(_map.counters().counter(&"ru_mr_1").is_own())
	assert_eq(_map.counters().own_ids().size(), 10)
	_map.set_viewer(0)
	assert_eq(_map.counters().own_ids().size(), 8)
