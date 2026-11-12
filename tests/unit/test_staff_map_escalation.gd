extends TestCase
## Escalation ladder on the staff map (TASK-115): chip, ladder card, toasts, end notice.

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


func _emit(events: Array[Dictionary]) -> void:
	for event in events:
		_map.simulation().event_emitted.emit(event)


func test_raise_stops_at_cap_and_nuclear_use_ends_the_operation() -> void:
	var state := _map.simulation().state
	var chip := _map.turn_bar().escalation_chip()
	assert_eq(state.escalation_level, 1)
	assert_true(chip.text.begins_with("1 · "), "chip shows the number: " + chip.text)
	assert_eq(chip.tick_count(), state.ladder.levels.size())
	assert_eq(chip.lit_ticks(), 2)
	assert_false(_map.turn_bar().end_button().disabled)
	assert_false(_map.escalation_hud().end_notice().visible)
	# The chip opens the Politics screen (the ladder lives there).
	chip.pressed.emit()
	assert_true(_map.decisions_hud().is_open(), "chip opens the Politics screen")
	_map.decisions_hud().close()
	# One step: a toast with the cause and the chip follows.
	_emit(EscalationRules.raise(state, 0, &"decision"))
	assert_eq(chip.lit_ticks(), 3)
	assert_true(_map.toast().message().contains("NATO"), _map.toast().message())
	# Raises stop at the cap (TASK-140): the operation goes on.
	_emit(EscalationRules.raise(state, 0, &"decision", 9))
	assert_eq(state.escalation_level, state.ladder.cap())
	assert_true(state.result.is_empty())
	assert_false(_map.escalation_hud().end_notice().visible)
	assert_false(_map.turn_bar().end_button().disabled)
	# The nuclear attack: the user's side (NATO) wins.
	_emit(EscalationRules.nuclear_use(state, 1))
	assert_false(state.result.is_empty())
	var notice := _map.escalation_hud().end_notice()
	assert_true(notice.visible, "notice shown")
	assert_true(notice.line_text(0).contains("RUSSIA"), notice.line_text(0))
	assert_eq(notice.line_text(1), "NOBODY WINS.")
	assert_true(_map.turn_bar().end_button().disabled, "End turn is off")
	assert_false(_map.end_turn(), "the simulation rejects it")


func test_calm_toast_text() -> void:
	var state := OperationalState.new()
	state.player_sides = [&"nato", &"russia"]
	state.escalation_level = 1
	var text := StaffMapEscalation.change_text(
		state, {"level": 1, "previous": 2, "by": -1, "cause": &"calm"}
	)
	assert_eq(text, "Calm: level 2 → 1")


func test_chip_has_seven_ticks_lit_up_to_the_level() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	var chip := StaffMapEscalationChip.new()
	state.escalation_level = 0
	chip.show_state(state, StaffMapPalette.new())
	assert_eq(chip.tick_count(), 7)
	assert_eq(chip.lit_ticks(), 1)
	state.escalation_level = state.ladder.cap()
	chip.show_state(state, StaffMapPalette.new())
	assert_eq(chip.lit_ticks(), 6)
	chip.free()


func test_collapse_strip_text_and_flag() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	var russia := 1
	state.fielded_strength[russia] = CollapseRules.present_strength(state, russia) * 100 / 72
	for formation in state.formations:
		if formation.owner_id == russia:
			formation.readiness = 80
	var strip := StaffMapEscalation.collapse_strip(state, russia)
	assert_eq(
		strip["text"],
		(
			"Russia · strength %d %% · readiness 80 · collapse at ≤ 35 %%"
			% CollapseRules.strength_pct(state, russia)
		)
	)
	assert_false(strip["collapse"])
	state.fielded_strength[russia] = CollapseRules.present_strength(state, russia) * 3
	assert_true(StaffMapEscalation.collapse_strip(state, russia)["collapse"])
	# The same rule for the other side (mirror).
	state.fielded_strength[0] = CollapseRules.present_strength(state, 0) * 3
	assert_true(StaffMapEscalation.collapse_strip(state, 0)["collapse"])
	assert_true(String(StaffMapEscalation.collapse_strip(state, 0)["text"]).begins_with("NATO"))


func test_end_lines_for_nuclear_use() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	var lines := StaffMapEscalation.end_lines(
		state, {"type": &"operation_ended", "reason": &"nuclear_use", "by": 1, "winner": -1}
	)
	assert_eq(lines[0], "Russia used a nuclear weapon. The operation ends.")
	assert_eq(lines[1], "Nobody wins.")
	for line in lines:
		assert_false(line.to_lower().contains("threshold"), line)
