extends TestCase
## The view-model of an ended move (TASK-092e): moved / in-contact marks, the turn report and the
## timing of the counters' slide. Pure – no nodes.


func _formation(id: StringName, owner: int, coord: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = coord
	f.definition = FormationDefinition.new()
	return f


## Own "a" (player 0) on (3, 0), enemy "e" (player 1) on (4, 0), own "b" far away on (9, 5).
func _state() -> OperationalState:
	var state := OperationalState.new()
	state.formations.append(_formation(&"a", 0, Vector2i(3, 0)))
	state.formations.append(_formation(&"e", 1, Vector2i(4, 0)))
	state.formations.append(_formation(&"b", 0, Vector2i(9, 5)))
	return state


func _moved(id: StringName, to: Vector2i) -> Dictionary:
	return {"type": &"formation_moved", "formation_id": id, "from": Vector2i.ZERO, "to": to}


func test_moved_mark_lasts_until_the_owners_next_move() -> void:
	var state := _state()
	var marks := StaffMapTurnMarks.new()
	marks.on_event(state, _moved(&"a", Vector2i(3, 0)))
	assert_true(marks.is_moved(&"a"))
	assert_false(marks.is_moved(&"b"))
	marks.on_event(state, {"type": &"operational_turn_ended", "player": 0})
	marks.on_event(state, {"type": &"operational_turn_started", "player": 1, "turn": 1})
	assert_true(marks.is_moved(&"a"), "the other side's move does not clear it")
	marks.on_event(state, {"type": &"operational_turn_started", "player": 0, "turn": 2})
	assert_false(marks.is_moved(&"a"), "cleared when the owner's next move starts")


func test_contact_marks_the_halted_formation_and_the_adjacent_enemy() -> void:
	var state := _state()
	var marks := StaffMapTurnMarks.new()
	marks.on_event(
		state,
		{
			"type": &"formation_halted",
			"formation_id": &"a",
			"at": Vector2i(3, 0),
			"reason": &"contact"
		}
	)
	assert_true(marks.in_contact(&"a"))
	assert_true(marks.in_contact(&"e"))
	assert_false(marks.in_contact(&"b"))
	# The ring lives as long as the contact does.
	marks.on_event(state, {"type": &"operational_turn_started", "player": 1, "turn": 1})
	assert_true(marks.in_contact(&"e"))
	state.get_formation(&"a").coord = Vector2i(0, 0)
	marks.on_event(state, {"type": &"operational_turn_started", "player": 0, "turn": 2})
	assert_false(marks.in_contact(&"a"))
	assert_false(marks.in_contact(&"e"))


func test_report_lists_each_outcome_once_and_is_taken_once() -> void:
	var state := _state()
	var marks := StaffMapTurnMarks.new()
	marks.on_event(state, _moved(&"a", Vector2i(3, 0)))
	marks.on_event(
		state,
		{
			"type": &"formation_halted",
			"formation_id": &"a",
			"at": Vector2i(3, 0),
			"reason": &"contact"
		}
	)
	marks.on_event(state, _moved(&"b", Vector2i(9, 5)))
	marks.on_event(
		state,
		{"type": &"formation_order_completed", "formation_id": &"b", "destination": Vector2i(9, 5)}
	)
	var entries := marks.report_of(0)
	assert_eq(entries.size(), 2, "one entry per formation")
	assert_eq(entries[0]["kind"], StaffMapTurnMarks.HALTED)
	assert_eq(entries[1]["kind"], StaffMapTurnMarks.ARRIVED)
	assert_true(marks.take_unseen(0))
	assert_false(marks.take_unseen(0), "shown once")
	assert_true(marks.report_of(1).is_empty())


func test_interruption_keeps_its_reason_and_a_new_move_starts_a_new_report() -> void:
	var state := _state()
	var marks := StaffMapTurnMarks.new()
	(
		marks
		. on_event(
			state,
			{
				"type": &"formation_order_interrupted",
				"formation_id": &"b",
				"reason": &"no_route",
				"at": Vector2i(9, 5),
			}
		)
	)
	assert_eq(marks.report_of(0)[0]["reason"], &"no_route")
	marks.on_event(state, {"type": &"operational_turn_started", "player": 1, "turn": 1})
	marks.on_event(state, _moved(&"a", Vector2i(3, 0)))
	assert_eq(marks.report_of(0).size(), 1, "the old report is replaced")
	assert_eq(marks.report_of(0)[0]["id"], &"a")


func test_slide_takes_04_s_per_hex_capped_at_25_s() -> void:
	var slide := StaffMapMoveAnimation.new()
	slide.add_walk(&"short", Vector2i(0, 0), [Vector2i(1, 0), Vector2i(2, 0)])
	var long_path: Array[Vector2i] = []
	for q in range(1, 11):
		long_path.append(Vector2i(q, 0))
	slide.add_walk(&"long", Vector2i(0, 0), long_path)
	assert_true(is_equal_approx(slide.duration_of(&"short"), 0.8))
	assert_true(is_equal_approx(slide.duration_of(&"long"), StaffMapMoveAnimation.MAX_SECONDS))
	assert_true(is_equal_approx(slide.total(), StaffMapMoveAnimation.MAX_SECONDS))
	assert_false(slide.is_finished(1.0))
	assert_true(slide.is_finished(2.5))


func test_slide_position_walks_the_path_and_ends_on_the_last_hex() -> void:
	var slide := StaffMapMoveAnimation.new()
	slide.add_walk(&"f", Vector2i(0, 0), [Vector2i(1, 0), Vector2i(2, 0)])
	var start := slide.position_at(&"f", 0.0)
	var middle := slide.position_at(&"f", 0.4)  # exactly on the first hex entered
	var end := slide.position_at(&"f", 99.0)
	var w1 := Hex.to_world(Vector2i(1, 0), 1.0)
	var w2 := Hex.to_world(Vector2i(2, 0), 1.0)
	assert_true(start.is_equal_approx(Vector2(Hex.to_world(Vector2i(0, 0), 1.0).x, 0.0)))
	assert_true(middle.is_equal_approx(Vector2(w1.x, w1.z)))
	assert_true(end.is_equal_approx(Vector2(w2.x, w2.z)))
	var between := slide.position_at(&"f", 0.2)
	assert_true(between.x > start.x and between.x < middle.x, "halfway in between")
