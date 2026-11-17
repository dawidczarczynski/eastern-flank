extends TestCase
## `objective_changed` events (TASK-165): holder flips, the Gap opening / closing, the closed-round
## counter, the journal entry and its save round trip.

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


func test_chain_hex_alone_is_not_a_holder_event() -> void:
	var s := Victory._state()
	_take(s, [Victory.CHAIN[0]] as Array[Vector2i], 1)
	assert_eq(_changes(&"holder").size(), 0)
	assert_eq(_changes(&"gap").size(), 0, "chain still open")


func test_gap_closes_and_opens() -> void:
	var s := Victory._state()
	Victory._hold_chain(s, 1, 3)
	_take(s, [Victory.CHAIN[3]] as Array[Vector2i], 1)
	var closed := _changes(&"gap")
	assert_eq(closed.size(), 1)
	assert_eq(closed[0]["old"], &"open")
	assert_eq(closed[0]["new"], &"closed")
	_take(s, [Victory.CHAIN[1]] as Array[Vector2i], 0)
	var opened := _changes(&"gap")
	assert_eq(opened.size(), 1)
	assert_eq(opened[0]["old"], &"closed")
	assert_eq(opened[0]["new"], &"open")


func test_counter_events_at_end_of_round() -> void:
	var s := Victory._state()
	var need := s.definition.closed_rounds_to_win
	Victory._hold_chain(s, 1)
	for count in need - 1:
		var events := OperationVictory.end_round(s, 7 + count)
		assert_eq(events.size(), 1)
		assert_eq(events[0]["kind"], &"gap_counter")
		assert_eq(events[0]["old"], count)
		assert_eq(events[0]["new"], count + 1)
		assert_eq(events[0]["round"], 7 + count)
	var last := OperationVictory.end_round(s, 7 + need - 1)
	assert_eq(last.size(), 2)
	assert_eq(last[0]["type"], &"objective_changed", "counter before the end notice")
	assert_eq(last[0]["new"], need)
	assert_eq(last[1]["type"], &"operation_ended")


func test_counter_reset_and_idle() -> void:
	var s := Victory._state()
	assert_eq(OperationVictory.end_round(s, 1), [] as Array[Dictionary], "0 to 0 is silent")
	Victory._hold_chain(s, 1)
	OperationVictory.end_round(s, 2)
	Victory._hold(s, Victory.CHAIN[2], 0)
	var events := OperationVictory.end_round(s, 3)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["old"], 1)
	assert_eq(events[0]["new"], 0)


func test_same_commands_same_events() -> void:
	var runs: Array = []
	for i in 2:
		var s := Victory._state()
		Victory._hold(s, Vector2i(0, 8), 0)
		Victory._hold_chain(s, 1, 3)
		_take(s, [Vector2i(0, 8), Victory.CHAIN[3]] as Array[Vector2i], 1)
		runs.append(_events.duplicate(true))
	assert_eq(runs[0], runs[1])
	assert_eq(runs[0].size(), 2)


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
