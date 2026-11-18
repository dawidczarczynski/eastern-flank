extends TestCase
## `objective_changed` events (TASK-165, TASK-177): holder flips, NATO's link open / cut, the
## corridor open / closed, its closed-round counter, the journal entry and its save round trip.

const Victory := preload("res://tests/unit/test_operation_victory.gd")

var _events: Array[Dictionary] = []


func _sim(s: OperationalState) -> OperationalSimulation:
	_events.clear()
	var sim := OperationalSimulation.new(s)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	return sim


func _changes(kind: StringName) -> Array[Dictionary]:
	return _events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"objective_changed" and e["kind"] == kind
	)


## A command that takes `hexes` for `side` (what a move or a won battle does).
class TakeCommand:
	extends OperationalCommand
	var hexes: Array[Vector2i] = []
	var side: int = 1

	func validate(_state: OperationalState) -> String:
		return ""

	func apply(state: OperationalState) -> Array[Dictionary]:
		var events: Array[Dictionary] = []
		for hex in hexes:
			events.append_array(HexControl.take(state, hex, side))
		return events


func _take(s: OperationalState, hexes: Array[Vector2i], side: int) -> void:
	var c := TakeCommand.new()
	c.hexes = hexes
	c.side = side
	var sim := _sim(s)
	assert_true(sim.execute(c))


func test_holder_flip_emits_one_event() -> void:
	var s := Victory._state()
	Victory._hold(s, Vector2i(0, 8), 0)
	_take(s, [Vector2i(0, 8)] as Array[Vector2i], 1)
	var list := _changes(&"holder")
	assert_eq(list.size(), 1)
	assert_eq(list[0]["objective_id"], &"grodno")
	assert_eq(list[0]["old"], 0)
	assert_eq(list[0]["new"], 1)
	assert_eq(list[0]["round"], s.turn)
	_take(s, [Vector2i(0, 8)] as Array[Vector2i], 1)
	assert_eq(_changes(&"holder").size(), 0, "unchanged holder")


func test_two_objective_hexes_two_events() -> void:
	var s := Victory._state()
	Victory._hold(s, Vector2i(0, 8), 0)
	Victory._hold(s, Vector2i(0, 7), 0)
	_take(s, [Vector2i(0, 8), Vector2i(0, 7)] as Array[Vector2i], 1)
	assert_eq(_changes(&"holder").size(), 2)


func test_route_hex_alone_is_not_a_holder_event() -> void:
	var s := Victory._state()
	_take(s, [Vector2i(5, 3)] as Array[Vector2i], 1)
	_take(s, [Victory.CORRIDOR[0]] as Array[Vector2i], 1)
	assert_eq(_changes(&"holder").size(), 0)
	assert_eq(_changes(&"gap").size(), 0, "a detour exists")
	assert_eq(_changes(&"corridor").size(), 0, "corridor still open")
	assert_true(HexControl.is_objective_hex(s, Vector2i(5, 3)), "any land hex may matter")
	s.definition.nato_link_to = Vector2i.MAX
	s.definition.corridor_to_country = &""
	assert_false(HexControl.is_objective_hex(s, Vector2i(5, 3)), "no connection objective")


func test_gap_link_cut_and_open() -> void:
	var s := Victory._state()
	var wall := Victory.WALL
	Victory._hold_all(s, wall.slice(0, wall.size() - 1), 1)
	s.definition.corridor_to_country = &""  # only NATO's link in this test
	s.definition.corridor_from_country = &""
	_take(s, [wall[-1]] as Array[Vector2i], 1)
	var cut := _changes(&"gap")
	assert_eq(cut.size(), 1)
	assert_eq(cut[0]["objective_id"], &"gap")
	assert_eq(cut[0]["old"], &"open")
	assert_eq(cut[0]["new"], &"cut")
	assert_eq(_changes(&"corridor").size(), 0)
	_take(s, [wall[1]] as Array[Vector2i], 1)
	assert_eq(_changes(&"gap").size(), 0, "already cut")
	_take(s, [wall[2], wall[3]] as Array[Vector2i], 0)
	var opened := _changes(&"gap")
	assert_eq(opened.size(), 1, "one event per command")
	assert_eq(opened[0]["old"], &"cut")
	assert_eq(opened[0]["new"], &"open")


func test_corridor_closes_and_opens() -> void:
	var s := Victory._state()
	var last := Victory.CORRIDOR.size() - 1
	Victory._hold_corridor(s, 1, last)
	_take(s, [Victory.CORRIDOR[last]] as Array[Vector2i], 1)
	var closed := _changes(&"corridor")
	assert_eq(closed.size(), 1)
	assert_eq(closed[0]["objective_id"], &"corridor")
	assert_eq(closed[0]["old"], &"open")
	assert_eq(closed[0]["new"], &"closed")
	_take(s, [Victory.CORRIDOR[0]] as Array[Vector2i], 0)
	var opened := _changes(&"corridor")
	assert_eq(opened.size(), 1)
	assert_eq(opened[0]["old"], &"closed")
	assert_eq(opened[0]["new"], &"open")


func test_closing_the_corridor_also_cuts_the_link() -> void:
	var s := Victory._state()
	var wall := Victory.WALL
	Victory._hold_all(s, wall.slice(0, wall.size() - 1), 1)
	_take(s, [wall[-1]] as Array[Vector2i], 1)
	assert_eq(_changes(&"gap").size(), 1, "the link is cut")
	assert_eq(_changes(&"corridor").size(), 1, "the corridor is closed")
	assert_eq(_changes(&"holder").size(), 0)


func test_no_status_event_without_a_holder_change() -> void:
	var s := Victory._state()
	Victory._hold_corridor(s, 1)
	_take(s, [] as Array[Vector2i], 1)
	assert_eq(_changes(&"corridor").size(), 0, "closed before the command, closed after it")


func test_counter_events_at_end_of_round() -> void:
	var s := Victory._state()
	var need := s.definition.closed_rounds_to_win
	Victory._hold_corridor(s, 1)
	for count in need - 1:
		var events := OperationVictory.end_round(s, 7 + count)
		assert_eq(events.size(), 1)
		assert_eq(events[0]["kind"], &"corridor_counter")
		assert_eq(events[0]["objective_id"], &"corridor")
		assert_eq(events[0]["old"], count)
		assert_eq(events[0]["new"], count + 1)
		assert_eq(events[0]["round"], 7 + count)
	var last := OperationVictory.end_round(s, 7 + need - 1)
	assert_eq(last.size(), 2)
	assert_eq(last[0]["type"], &"objective_changed", "counter before the end notice")
	assert_eq(last[0]["new"], need)
	assert_eq(last[1]["type"], &"operation_ended")
	assert_eq(last[1]["reason"], &"corridor_closed")


func test_counter_reset_and_idle() -> void:
	var s := Victory._state()
	assert_eq(OperationVictory.end_round(s, 1), [] as Array[Dictionary], "0 to 0 is silent")
	Victory._hold_corridor(s, 1)
	OperationVictory.end_round(s, 2)
	Victory._hold(s, Victory.CORRIDOR[2], 0)
	var events := OperationVictory.end_round(s, 3)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["old"], 1)
	assert_eq(events[0]["new"], 0)


func test_corridor_held_one_round_short_then_broken_resets() -> void:
	var s := Victory._state()
	var need := s.definition.closed_rounds_to_win
	Victory._hold_corridor(s, 1)
	for count in need - 1:
		OperationVictory.end_round(s, 7 + count)
	Victory._hold(s, Victory.CORRIDOR[1], 0)
	var events := OperationVictory.end_round(s, 7 + need)
	assert_eq(events.size(), 1, "no ending")
	assert_eq(events[0]["kind"], &"corridor_counter")
	assert_eq(events[0]["old"], need - 1)
	assert_eq(events[0]["new"], 0)
	assert_eq(s.corridor_closed_rounds, 0)
	assert_true(s.result.is_empty())


func test_same_commands_same_events() -> void:
	var runs: Array = []
	for i in 2:
		var s := Victory._state()
		Victory._hold(s, Vector2i(0, 8), 0)
		Victory._hold_all(s, Victory.WALL.slice(1), 1)
		_take(s, [Vector2i(0, 8), Victory.WALL[0]] as Array[Vector2i], 1)
		runs.append(_events.duplicate(true))
	assert_eq(runs[0], runs[1])
	assert_eq(runs[0].size(), 3, "holder, gap, corridor")


func test_journal_records_for_both_sides_and_round_trips() -> void:
	var s := Victory._state()
	Victory._hold(s, Vector2i(0, 8), 0)
	_take(s, [Vector2i(0, 8)] as Array[Vector2i], 1)
	assert_true(&"objective" in OperationalJournal.KINDS)
	for side in 2:
		var list := s.journal.entries_for(side).filter(
			func(e: OperationalJournal.Entry) -> bool: return e.kind == &"objective"
		)
		assert_eq(list.size(), 1, "side %d sees it" % side)
	var e: OperationalJournal.Entry = s.journal.entries[0]
	assert_eq(e.category, &"move")
	assert_eq(e.args["kind"], "holder")
	assert_eq(e.args["objective_id"], "grodno")
	assert_eq(e.args["old"], 0)
	assert_eq(e.args["new"], 1)
	assert_eq(e.args["round"], s.turn)
	var back := OperationalJournal.from_dict(JSON.parse_string(JSON.stringify(s.journal.to_dict())))
	assert_true(back != null)
	assert_eq(back.entries[0].to_dict(), e.to_dict())
