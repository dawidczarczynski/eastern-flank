extends TestCase
## The counters' slide and the turn report on the staff map (TASK-092e), driven by hand: the state
## is final the moment End turn is pressed, the slide is cosmetic – playing it, skipping it and
## running the same commands without any view must end in the same state.

static var _map: StaffMap
static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 1  # the human side moves first: Russia, as these tests were written
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


## Gives every formation of the side to play an order three hexes east (rejected ones are fine).
func _order_everyone() -> int:
	var sim := _map.simulation()
	var given := 0
	for f in sim.state.formations:
		if f.owner_id != sim.state.current_player:
			continue
		for dq in [4, -4, 3, -3]:
			if sim.execute(IssueOrderCommand.new(f.id, f.coord + Vector2i(dq, 0), &"march")):
				given += 1
				break
	return given


func _fresh_state() -> OperationalState:
	var definition := OperationDefinition.find(_map.operation_id)
	var imported := ImportedMap.find(definition.map_id)
	return Operation.from_definition(
		definition, _map.seed_value, imported.to_grid(), Operation.map_countries(imported)
	)


func test_end_turn_is_off_while_sliding_and_skip_ends_it() -> void:
	var sim := _map.simulation()
	_map.set_viewer(sim.state.current_player)
	assert_true(_order_everyone() > 0, "some orders were accepted")
	assert_true(_map.end_turn())
	assert_true(_map.is_sliding(), "formations moved, so the counters slide")
	assert_false(_map.end_turn(), "End turn is refused during the slide")
	assert_true(_map.turn_bar().end_button().disabled, "and its button is off")
	assert_true(_map.skip_slide())
	assert_false(_map.is_sliding())
	assert_false(_map.turn_bar().end_button().disabled)
	for f in sim.state.formations:
		var at := _map.counter_screen_position(f.id)
		assert_eq(_map.hex_at_screen(at), f.coord, "counter %s stands on its hex" % f.id)


func test_six_turns_with_orders_match_a_run_without_any_view() -> void:
	var sim := _map.simulation()
	for turn in 6:
		_order_everyone()
		assert_true(_map.end_turn())
		if turn % 2 == 0:
			_map.advance_slide(100.0)  # played to the end
		else:
			_map.skip_slide()  # skipped
		assert_false(_map.is_sliding())
	var pure := OperationalSimulation.new(_fresh_state())
	for command in sim.history:
		assert_true(pure.execute(command))
	assert_eq(pure.state.snapshot(), sim.state.snapshot(), "same final state")
	# The counters stand on the hexes of the state.
	for f in sim.state.formations:
		var c := _map.counters().counter(f.id)
		assert_true(c != null)


func test_moved_counters_and_the_report_after_the_slide() -> void:
	var sim := _map.simulation()
	var mover := sim.state.current_player
	_map.set_viewer(mover)
	assert_true(_order_everyone() > 0)
	assert_true(_map.end_turn())
	_map.advance_slide(100.0)
	var any_moved := false
	for f in sim.state.formations:
		if f.owner_id == mover:
			var flagged := _map.counters().counter(f.id).moved
			assert_eq(flagged, _map.turn_marks().is_moved(f.id))
			any_moved = any_moved or flagged
	assert_true(any_moved, "an own counter is marked moved")
	var report := _map.turn_report()
	assert_true(report.visible, "the report opens by itself")
	assert_true(report.entry_count() > 0)
	var row := report.row_text(0)
	assert_true(row.contains(" KM ") or row.contains("HEX"), row)
	report.click_row(0)
	assert_true(_map.selected_formation() != &"", "clicking an entry selects the formation")
	_map.toggle_report()
	assert_false(report.visible, "R closes it")
	_map.toggle_report()
	assert_true(report.visible, "and reopens it")
