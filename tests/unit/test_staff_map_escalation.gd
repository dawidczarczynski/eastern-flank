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


func test_raise_to_threshold_shows_end_notice_and_disables_end_turn() -> void:
	var state := _map.simulation().state
	var chip := _map.turn_bar().escalation_chip()
	assert_eq(state.escalation_level, 1)
	assert_true(chip.text.begins_with("1 · "), "chip shows the number: " + chip.text)
	assert_eq(chip.tick_count(), state.ladder.levels.size())
	assert_eq(chip.lit_ticks(), 2)
	assert_false(_map.turn_bar().end_button().disabled)
	assert_false(_map.escalation_hud().end_notice().visible)
	# Open the card from the chip.
	chip.pressed.emit()
	var card := _map.escalation_hud().card()
	assert_true(card.visible, "card opens")
	assert_eq(card.row_texts().size(), state.ladder.levels.size())
	assert_true(card.row_texts()[0].contains("STRATEGIC THRESHOLD"), str(card.row_texts()))
	assert_true(card.row_texts()[0].contains("Nothing"), str(card.row_texts()))
	assert_true(_map.escalation_hud().close_card(), "closes")
	# One step: a toast with the cause and the chip follows.
	_emit(EscalationRules.raise(state, 0, &"decision"))
	assert_eq(chip.lit_ticks(), 3)
	assert_true(_map.toast().message().contains("NATO"), _map.toast().message())
	# Up to the top: the other side wins.
	_emit(EscalationRules.raise(state, 0, &"decision", 5))
	assert_false(state.result.is_empty())
	var notice := _map.escalation_hud().end_notice()
	assert_true(notice.visible, "notice shown")
	assert_true(notice.line_text(0).contains("NATO"), notice.line_text(0))
	assert_true(notice.line_text(1).begins_with("DEFEAT"), notice.line_text(1))
	assert_true(notice.line_text(2).begins_with("VICTORY"), notice.line_text(2))
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
