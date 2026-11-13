extends TestCase
## The unit variant of the bottom-bar strip (TASK-151): what the left slot shows for a hovered
## counter, the selected own formation or neither, and what a hostile formation reveals.

static var _map: StaffMap
static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 1
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func after_each() -> void:
	for formation in _map.simulation().state.formations:
		formation.order = null
		formation.posture = &"defend"
	_map.select_formation(&"")
	_map.card().hide()
	_map.unit_strip().hide()


func _formation(own: bool) -> Formation:
	var state := _map.simulation().state
	for formation in state.formations:
		if (formation.owner_id == _map.viewer_player) == own:
			return formation
	return null


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_map._unhandled_input(event)


func test_the_selected_own_formation_fills_the_slot_when_the_cursor_is_on_nothing() -> void:
	var own := _formation(true)
	assert_eq(_map.unit_strip_target(), &"", "nothing selected")
	_map.select_formation(own.id)
	assert_eq(_map.unit_strip_target(), own.id)
	_map._sync_unit_strip(false)
	var strip := _map.unit_strip()
	assert_true(strip.visible)
	assert_true(strip.tab_text().ends_with("OWN"))
	assert_true(strip.has_gauge())
	assert_eq(strip.value_text(0), "%d / %d" % [own.strength(), own.max_strength()])
	assert_eq(strip.value_text(1), "DEFEND")
	assert_false(_map.card().visible)


func test_a_hovered_hex_keeps_the_slot_over_the_selection() -> void:
	_map.select_formation(_formation(true).id)
	_map.card().show()
	assert_eq(_map.unit_strip_target(), &"")
	_map._sync_unit_strip(false)
	assert_false(_map.unit_strip().visible)


func test_a_hovered_counter_wins_over_hex_and_selection() -> void:
	var enemy := _formation(false)
	_map.select_formation(_formation(true).id)
	_map.card().show()
	_map.counters().set_hovered(enemy.id)
	assert_eq(_map.unit_strip_target(), enemy.id)
	_map._sync_unit_strip(false)
	assert_true(_map.unit_strip().visible)
	assert_false(_map.card().visible, "the strip took the slot")
	_map.counters().set_hovered(&"")


func test_a_hostile_formation_shows_only_what_intel_allows() -> void:
	var enemy := _formation(false)
	enemy.posture = &"advance"
	_map.debug_unit_strip(enemy.id)
	var strip := _map.unit_strip()
	assert_true(strip.tab_text().ends_with("HOSTILE"))
	assert_false(strip.has_gauge())
	assert_eq(strip.value_text(0), "EST.")
	assert_eq(strip.value_text(1), "?")
	assert_eq(strip.value_text(2), "?")


func test_an_own_formation_without_order_says_so() -> void:
	_map.debug_unit_strip(_formation(true).id)
	assert_eq(_map.unit_strip().value_text(2), "– NO ORDER –")


func test_no_slot_content_while_a_window_idles_the_map() -> void:
	_map.select_formation(_formation(true).id)
	assert_eq(_map.unit_strip_target(true), &"")


func test_an_armed_posture_shows_in_the_posture_column() -> void:
	var own := _formation(true)
	_map.select_formation(own.id)
	_key(KEY_2)
	_map._sync_unit_strip(false)
	assert_eq(_map.unit_strip().value_text(1), "ATTACK")
	_key(KEY_ESCAPE)
	_map._sync_unit_strip(false)
	assert_eq(_map.unit_strip().value_text(1), "DEFEND")
