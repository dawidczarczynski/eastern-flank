extends TestCase
## The operational journal window on the staff map (TASK-148b): the JRN button and J, the left
## dock, rows / headers / filters / empty states, click -> centre + ring, unseen bars, the strike
## report's Enter, hot-seat flip, and a long operation opening fast. One StaffMap is shared.

const Fixtures := preload("res://tests/fixtures.gd")

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
	Fixtures.add_generic_strike_means(_map.simulation().state)
	_map.simulation().state.air_defence_types.clear()


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func before_each() -> void:
	_map.close_docked_windows()
	_map.journal_window().close()
	_map.set_viewer(0)
	_map.simulation().state.journal.entries.clear()
	_map.simulation().state.turn = 3


func _add(
	turn: int,
	category: StringName,
	kind: StringName,
	actor: int,
	coord: Variant = null,
	args := {},
	involved: Array[int] = []
) -> OperationalJournal.Entry:
	var e := OperationalJournal.Entry.new()
	e.turn = turn
	e.category = category
	e.kind = kind
	e.actor = actor
	e.args = args
	e.involved = involved
	if coord is Vector2i:
		e.coord = coord
		e.has_coord = true
	_map.simulation().state.journal.entries.append(e)
	return e


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_map._unhandled_input(event)


func _sample() -> void:
	var f := _map.simulation().state.formations[0]
	_add(
		1,
		&"move",
		&"order_completed",
		f.owner_id,
		Vector2i(2, 2),
		{"formation_id": String(f.id)},
		[f.owner_id]
	)
	_add(1, &"politics", &"sanctuary_breach", -1, null, {"country": "x"})
	_add(
		2,
		&"strike",
		&"strike",
		0,
		Vector2i(3, 3),
		{"means": "x", "count": 1, "class_id": "airfield", "hits": 1}
	)
	_add(3, &"battle", &"battle_consequences", -1, null, {"losses": [1, 2], "field_holder": 0})


func test_the_jrn_button_and_key_j_open_and_close_it_on_the_left_dock() -> void:
	var button := _map.action_bar().button(StaffMap.ACTION_JOURNAL)
	assert_true(button != null, "JRN button")
	var window := _map.journal_window()
	assert_false(window.is_open())
	_key(KEY_J)
	assert_true(window.is_open(), "J opens")
	assert_true(button.button_pressed, "button lit while open")
	assert_eq(window.position, Vector2(16, 110))
	assert_eq(window.size.x, StaffMapWindow.WIDTH_REPORT)
	assert_true(window.tab_text.begins_with("JOURNAL"), window.tab_text)
	_key(KEY_J)
	assert_false(window.is_open(), "J closes")
	assert_false(button.button_pressed)
	button.pressed.emit()
	assert_true(window.is_open(), "the button opens")
	_key(KEY_ESCAPE)
	assert_false(window.is_open(), "Esc closes")
	_key(KEY_J)
	window.close_button().pressed.emit()
	assert_false(window.is_open(), "X closes")


func test_one_left_window_at_a_time() -> void:
	var window := _map.journal_window()
	_map.toggle_journal()
	_map.toggle_options()
	assert_false(window.is_open(), "map options take the dock")
	_map.toggle_journal()
	assert_true(window.is_open())
	assert_false(_map.options_window().is_open(), "and the journal takes it back")
	_map.close_docked_windows()
	assert_false(window.is_open(), "a click on the map closes it")


func test_rows_are_grouped_by_turn_newest_first_with_now_on_the_current_turn() -> void:
	_sample()
	var window := _map.journal_window()
	_map.open_journal()
	assert_eq(window.header_count(), 3)
	assert_eq(window.header_title(0), "TURN 3")
	assert_eq(window.header_title(1), "TURN 2")
	assert_eq(window.header_title(2), "TURN 1")
	assert_true(window.header_text(0).contains("DAY"), window.header_text(0))
	assert_true(window.find_child("Now", true, false) != null, "NOW on the current turn")
	assert_eq(window.row_count(), 4)
	assert_true(window.row_text(0).begins_with("Losses"), window.row_text(0))
	assert_true(window.row_text(1).begins_with("We struck"), window.row_text(1))
	assert_eq(window.scroll_container().scroll_vertical, 0, "opens at the current turn")


func test_filter_chips_and_the_empty_states() -> void:
	var window := _map.journal_window()
	_map.open_journal()
	assert_eq(window.empty_text(), StaffMapJournalText.empty_text(), "nothing yet")
	_sample()
	_map.open_journal()
	assert_eq(window.filter(), &"", "ALL by default")
	assert_true(window.chip(&"").button_pressed)
	window.chip(&"strike").pressed.emit()
	assert_eq(window.row_count(), 1)
	assert_true(window.chip(&"strike").button_pressed)
	assert_false(window.chip(&"").button_pressed, "one chip at a time")
	window.chip(&"move").pressed.emit()
	assert_eq(window.row_count(), 1)
	window.set_filter(&"battle")
	assert_eq(window.row_count(), 1)
	_map.simulation().state.journal.entries.clear()
	window.set_filter(&"battle")
	assert_eq(window.empty_text(), "Nothing under this filter")
	window.set_filter(&"")


func test_click_centres_the_map_and_rings_the_hex() -> void:
	_sample()
	var window := _map.journal_window()
	_map.open_journal()
	var ring := _map.journal_ring()
	assert_false(ring.is_active())
	window.click_row(1)  # the strike with a place
	assert_true(ring.is_active())
	assert_eq(ring.hex, Vector2i(3, 3))
	ring.tick(1.0, func(_c: Vector2i) -> Vector2: return Vector2(5, 5))
	assert_true(ring.is_active(), "still on after 1 s")
	ring.tick(1.5, func(_c: Vector2i) -> Vector2: return Vector2(5, 5))
	assert_false(ring.is_active(), "gone after 2 s")
	assert_false(ring.visible)
	var seen := [false]
	window.entry_chosen.connect(func(_c: Vector2i) -> void: seen[0] = true)
	window.click_row(0)  # no place: nothing to centre on
	assert_false(seen[0])


func test_unseen_entries_carry_a_bar_until_hovered_and_close_marks_them_seen() -> void:
	_sample()
	var window := _map.journal_window()
	_map.open_journal()
	_map.close_journal()
	_add(3, &"battle", &"battle_consequences", -1, null, {"losses": [0, 0]})
	_map.open_journal()
	assert_eq(window.unseen_count(), 1, "only the entry added since the last close")
	for i in window.row_count():
		if window.row(i).unseen:
			window.row(i).mouse_entered.emit()
	assert_eq(window.unseen_count(), 0, "hover clears the bar")
	_map.close_journal()
	_map.open_journal()
	assert_eq(window.unseen_count(), 0)


func test_new_events_while_open_rebuild_once_per_frame() -> void:
	_sample()
	var window := _map.journal_window()
	_map.open_journal()
	assert_eq(window.row_count(), 4)
	_add(3, &"battle", &"battle_consequences", -1, null, {"losses": [0, 0]})
	_map.simulation().event_emitted.emit({"type": &"unit_noise"})
	assert_eq(window.row_count(), 4, "not rebuilt inside the event")
	_map.call(&"_tick_journal", 0.016)
	assert_eq(window.row_count(), 5, "rebuilt on the next frame")
	_map.call(&"_tick_journal", 0.016)
	_map.close_journal()
	_add(3, &"battle", &"battle_consequences", -1, null, {"losses": [0, 0]})
	_map.simulation().event_emitted.emit({"type": &"unit_noise"})
	_map.call(&"_tick_journal", 0.016)
	assert_eq(window.row_count(), 5, "a closed window is not rebuilt")


func test_the_hot_seat_flip_shows_the_other_side() -> void:
	var f := _map.simulation().state.formations[0]
	_add(
		1,
		&"move",
		&"order_completed",
		f.owner_id,
		null,
		{"formation_id": String(f.id)},
		[f.owner_id]
	)
	var window := _map.journal_window()
	_map.open_journal()
	var tab := window.tab_text
	assert_eq(window.row_count(), 1)
	_map.set_viewer(1 - f.owner_id)
	assert_true(window.is_open())
	assert_eq(window.row_count(), 0, "the other side never saw it")
	assert_false(window.tab_text == tab, "the tab names the other side")


func test_a_long_operation_opens_fast() -> void:
	var f := _map.simulation().state.formations[0]
	for i in 500:
		_add(
			1 + i / 10,
			&"move",
			&"order_completed",
			f.owner_id,
			Vector2i(2, 2),
			{"formation_id": String(f.id)},
			[f.owner_id]
		)
	var start := Time.get_ticks_msec()
	_map.open_journal()
	var elapsed := Time.get_ticks_msec() - start
	var window := _map.journal_window()
	assert_true(elapsed < 50, "opened in %d ms" % elapsed)
	assert_eq(window.entry_count(), 500, "all entries are kept")
	assert_true(window.row_count() < 500, "built a page at a time")
	_map.close_journal()


func test_enter_on_a_strike_report_opens_the_journal_at_the_strike_entry() -> void:
	var state := _map.simulation().state
	state.current_player = 0
	state.escalation_level = 2
	state.decisions_left = 1
	state.strikes_left = 2
	state.pending_battles.clear()
	state.strike_stock[0][&"cruise"] = 8
	var hud := _map.strike_hud()
	hud.reports().clear()
	hud.close()
	assert_true(hud.toggle())
	hud.pick_means(&"cruise")
	for target in StrikeRules.targets(state, 0):
		if target["class_id"] == &"airfield":
			hud.click(target["id"])
			break
	hud.confirm()
	hud.reports().tick(10.0)  # revealed after the impact (TASK-147)
	assert_true(hud.reports().card_visible())
	assert_true(hud.handle_report_key(KEY_ENTER))
	var window := _map.journal_window()
	assert_true(window.is_open(), "Enter opens the journal")
	assert_false(hud.reports().card_visible(), "and the card steps aside")
	var lit := -1
	for i in window.row_count():
		if window.row(i).lit:
			lit = i
	assert_true(lit >= 0, "the strike line is lit")
	assert_true(window.row_text(lit).begins_with("We struck"), window.row_text(lit))
