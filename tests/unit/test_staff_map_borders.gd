extends TestCase
## Texts and markers of the border rules on the staff map (TASK-116 view).

const Borders := preload("res://tests/unit/test_borders_movement.gd")


func _en() -> void:
	TranslationServer.set_locale("en")


func test_closed_info_names_country_and_reason() -> void:
	_en()
	var state := Borders._quad()
	var f := Borders._add(state, &"F", 0, Vector2i(0, 0))
	var sanctuary := StaffMapBorders.closed_info(state, f, Vector2i(7, 0))
	assert_eq(sanctuary["title"], "RUSSIA · CLOSED")
	assert_eq(sanctuary["reason"], "Sanctuary – opens at escalation 2 (Open war)")
	assert_eq(
		StaffMapBorders.closed_info(state, f, Vector2i(7, 3))["reason"],
		"Hostile – closed to your side"
	)
	assert_true(StaffMapBorders.closed_info(state, f, Vector2i(3, 3)).is_empty())


func test_unreachable_reason_is_closed_before_occupied() -> void:
	var state := Borders._quad()
	var f := Borders._add(state, &"F", 0, Vector2i(0, 0))
	Borders._add(state, &"R", 1, Vector2i(7, 0))
	assert_eq(
		StaffMapRoute.unreachable_reason(state, f, Vector2i(7, 0), false),
		StaffMapRoute.REASON_CLOSED
	)


func test_warnings_breach_and_end() -> void:
	_en()
	var state := Borders._quad()
	state.escalation_level = 2
	var f := Borders._add(state, &"F", 0, Vector2i(3, 0))
	var route: Array[Vector2i] = [Vector2i(4, 0), Vector2i(5, 0)]
	var warnings := StaffMapBorders.warnings(state, f, route)
	assert_eq(warnings.size(), 1)
	assert_eq(warnings[0]["at"], Vector2i(4, 0))
	assert_true("Enters Russia: escalation +1" in warnings[0]["text"])
	assert_false(warnings[0].has("ends"), "no incident ends the operation (TASK-140)")
	assert_eq(warnings[0]["chip"], "+1")
	assert_eq(warnings[0]["tag"], "ESCALATION +1")
	assert_eq(warnings[0]["sentence"], "Enters Russia")
	state.escalation_level = state.ladder.cap()
	warnings = StaffMapBorders.warnings(state, f, route)
	assert_false("This ends the operation" in warnings[0]["text"])
	assert_eq(
		warnings[0]["text"], "Enters Russia: Already at the highest level – no further escalation"
	)
	assert_eq(
		warnings[0]["sentence"],
		"Enters Russia. Already at the highest level – no further escalation"
	)
	assert_eq(warnings[0]["chip"], "+0")


func test_warnings_casus_belli() -> void:
	_en()
	var state := Borders._line()
	var r := Borders._add(state, &"R", 1, Vector2i(4, 0))
	var route: Array[Vector2i] = [Vector2i(3, 0), Vector2i(2, 0)]
	var warnings := StaffMapBorders.warnings(state, r, route)
	assert_eq(warnings.size(), 1)
	assert_eq(warnings[0]["at"], Vector2i(2, 0))
	assert_true("casus belli for" in warnings[0]["text"])
	assert_eq(warnings[0]["chip"], "CB")


func test_no_warnings_inside_own_countries() -> void:
	var state := Borders._quad()
	var f := Borders._add(state, &"F", 0, Vector2i(0, 0))
	var route: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	assert_true(StaffMapBorders.warnings(state, f, route).is_empty())


func test_order_warnings_only_for_incident_orders() -> void:
	var state := Borders._quad()
	state.escalation_level = 2
	var f := Borders._add(state, &"F", 0, Vector2i(3, 0))
	assert_eq(
		(
			StaffMapBorders
			. order_warnings(state, IssueOrderCommand.new(f.id, Vector2i(5, 0), &"march"))
			. size()
		),
		1
	)
	assert_true(
		(
			StaffMapBorders
			. order_warnings(state, IssueOrderCommand.new(f.id, Vector2i(1, 0), &"march"))
			. is_empty()
		)
	)


func test_report_text_for_forbidden_contact() -> void:
	_en()
	var state := Borders._line()
	var f := Borders._add(state, &"F", 0, Vector2i(2, 0))
	var marks := StaffMapTurnMarks.new()
	marks.on_event(
		state,
		{
			"type": &"contact_forbidden",
			"attacker_id": f.id,
			"defender_id": &"R",
			"at": Vector2i(3, 0),
			"country": &"belarus"
		}
	)
	var entries := marks.report_of(0)
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["kind"], StaffMapTurnMarks.HALTED)
	assert_eq(
		StaffMapTurnReport.entry_text(entries[0], state), "Halted – cannot attack into Belarus"
	)


func test_interrupted_closed_country_has_words() -> void:
	_en()
	assert_eq(
		StaffMapTurnReport.kind_text(StaffMapTurnMarks.INTERRUPTED, &"closed_country"),
		"Order dropped: country closed"
	)


func test_casus_belli_event_text() -> void:
	_en()
	var state := Borders._line()
	var text := StaffMapBorders.casus_belli_event_text(
		state, {"country": &"belarus", "player": 0, "formation_id": &"R", "at": Vector2i(2, 0)}
	)
	assert_true("out of Belarus" in text)
