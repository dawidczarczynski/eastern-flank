extends TestCase
## The escalation ladder window of the staff map (TASK-143): matrix texts per level, the current
## level, the collapse tag per side, the three close paths and the one-window-at-a-time rule.

static var _map: StaffMap
static var _previous_locale: String


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


func _window() -> StaffMapLadderWindow:
	return _map.escalation_hud().card()


func _open() -> StaffMapLadderWindow:
	_map.escalation_hud().close_card()
	_map.escalation_hud().toggle_card()
	return _window()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_map._unhandled_input(event)


func test_matrix_texts_per_level() -> void:
	var window := _open()
	var state := _map.simulation().state
	assert_eq(window.columns().size(), 7)
	# Formations: allowed from level 0 (new there), then inherited, none at the top.
	assert_eq(window.row_texts(0), PackedStringArray(["✓ NEW", "✓", "✓", "✓", "✓", "✓", ""]))
	# Air defence and depots unlock at level 1, airfields and command posts at 2.
	assert_eq(window.row_texts(1), PackedStringArray(["—", "✓ NEW", "✓", "✓", "✓", "✓", ""]))
	assert_eq(window.row_texts(2), PackedStringArray(["—", "✓ NEW", "✓", "✓", "✓", "✓", ""]))
	assert_eq(window.row_texts(3), PackedStringArray(["—", "—", "✓ NEW", "✓", "✓", "✓", ""]))
	assert_eq(window.row_texts(4), PackedStringArray(["—", "—", "✓ NEW", "✓", "✓", "✓", ""]))
	assert_eq(window.columns()[5]["name"], "Strategic alert")
	assert_eq(window.trigger_chips(state.ladder.sanctuary_open_level)[0], "SANCTUARY OPENS")
	assert_eq(window.trigger_chips(state.ladder.allies_join_level)[0], "ALLIES JOIN")
	assert_eq(window.trigger_chips(state.ladder.cap())[0], "▲ CAP")
	assert_eq(window.trigger_chips(state.ladder.top())[0], "✕ END")
	assert_eq(window.trigger_chips(0).size(), 0)
	assert_true(window.sub_text().contains("level 1 of 6"), window.sub_text())
	assert_true(window.sub_text().contains("stops at 5"), window.sub_text())


func test_current_level_marker_and_tooltip() -> void:
	var state := _map.simulation().state
	var window := _open()
	assert_eq(window.columns()[state.escalation_level]["kind"], &"current")
	assert_eq(window.columns()[0]["kind"], &"reached")
	assert_eq(window.columns()[3]["kind"], &"above")
	assert_eq(window.columns()[6]["kind"], &"end")
	var tip := window.tip_of(6)
	assert_eq(tip["title"], "Requires all of")
	assert_eq(tip["text"], "level 5 · Russia in collapse · Russia's own decision")
	window.move_focus(1)
	assert_eq(window.focused_level(), state.escalation_level + 1)
	window.close()


func test_collapse_tag_per_side() -> void:
	var state := _map.simulation().state
	var window := _open()
	assert_eq(window.strips().size(), 2)
	assert_eq(window.strips()[1]["name"], "Russia")
	assert_false(window.strips()[0]["collapse"])
	assert_false(window.strips()[1]["collapse"])
	var saved := state.fielded_strength.duplicate()
	state.fielded_strength[1] = CollapseRules.present_strength(state, 1) * 2
	window.refresh()
	assert_true(window.strips()[1]["collapse"], "Russia tagged")
	assert_false(window.strips()[0]["collapse"], "NATO not")
	state.fielded_strength[1] = saved[1]
	state.fielded_strength[0] = CollapseRules.present_strength(state, 0) * 2
	window.refresh()
	assert_true(window.strips()[0]["collapse"], "the mirror: NATO tagged")
	state.fielded_strength = saved
	window.close()


func test_three_close_paths() -> void:
	var window := _open()
	assert_true(window.visible)
	# Esc.
	_key(KEY_ESCAPE)
	assert_false(window.visible, "Esc closes")
	# X button.
	window = _open()
	window.get_node("Plate/Close").pressed.emit()
	assert_false(window.visible, "X closes")
	# A click on the dimmed map, outside the plate; a click on the plate does nothing.
	window = _open()
	window.size = Vector2(1440, 900)
	window._layout()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(700, 400)
	window._gui_input(click)
	assert_true(window.visible, "inside the plate: stays open")
	click.position = Vector2(20, 20)
	window._gui_input(click)
	assert_false(window.visible, "outside closes")


func test_keys_do_not_reach_the_map_while_open() -> void:
	var window := _open()
	_map.turn_report().hide()
	_key(KEY_R)  # the turn report key
	assert_true(window.visible, "still open")
	assert_false(_map.turn_report().visible, "the key did not reach the map")
	window.close()


func test_mutual_exclusion_with_other_windows() -> void:
	var window := _open()
	assert_true(window.visible)
	_map.toggle_decisions()
	assert_false(window.visible, "the decisions sheet closes the ladder")
	assert_true(_map.decisions_hud().is_open())
	_map.escalation_hud().toggle_card()
	assert_true(window.visible)
	assert_false(_map.decisions_hud().is_open(), "the ladder closes the decisions sheet")
	_map.open_country_card(_map.simulation().state.countries[0].id)
	assert_false(window.visible, "the country card closes the ladder")
	assert_true(_map.country_card().visible)
	_map.escalation_hud().toggle_card()
	assert_true(window.visible)
	assert_false(_map.country_card().visible, "the ladder closes the country card")
	window.close()
