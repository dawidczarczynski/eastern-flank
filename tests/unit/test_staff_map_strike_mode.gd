# gdlint: disable=max-public-methods
extends TestCase
## The strike mode on the staff map (TASK-097b): S, means, targets, confirm card, raise-and-strike,
## result, trail, and the mode for the second side. Reads the shipped Suwalki operation.

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
	var state := _map.simulation().state
	Fixtures.add_generic_strike_means(state)  # code-built `cruise` / `strike_drone`, either side
	state.air_defence_types.clear()  # no interception
	for id: StringName in state.strike_means.keys():  # copies: the shipped data stays as is
		var means: StrikeMeansDefinition = state.strike_means[id].duplicate()
		means.accuracy_pct = 100
		state.strike_means[id] = means


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func before_each() -> void:
	var state := _map.simulation().state
	_map.strike_hud().close()
	_map.strike_hud().trail().clear()
	_map.strike_hud().reports().clear()
	_map.viewer_player = 0
	state.current_player = 0
	state.escalation_level = 1
	state.decisions_left = 1
	state.strikes_left = 2
	state.stand_down_until = [-1, -1]
	state.pending_battles.clear()
	for installation in state.installations:
		installation.integrity = 100
	for player in 2:
		for id: StringName in state.strike_means:
			state.strike_stock[player][id] = 8
	for country in state.countries:
		country.breached_by = [false, false] as Array[bool]


func _airfield(player: int) -> StringName:
	for target in StrikeRules.targets(_map.simulation().state, player):
		if target["class_id"] == &"airfield":
			return target["id"]
	return &""


func _open(means: StringName) -> StaffMapStrikeHud:
	var hud := _map.strike_hud()
	hud.close()
	assert_true(hud.toggle(), "mode opens")
	hud.pick_means(means)
	return hud


func test_s_opens_the_mode_and_esc_leaves() -> void:
	var hud := _map.strike_hud()
	assert_false(hud.is_open())
	_map.toggle_strike_mode()
	assert_true(hud.is_open())
	assert_true(hud.panel().visible)
	assert_eq(hud.panel().strikes_line(), "STRIKES: 2/2")
	assert_true(hud.panel().means_button(&"cruise") != null)
	assert_true(hud.panel().row_text(&"cruise").contains("8"), "stock shown")
	assert_true(hud.panel().row_text(&"cruise").contains("50"), "range shown")
	assert_true(
		_map.action_bar().button(StaffMap.ACTION_STRIKE).button_pressed, "the button is lit"
	)
	assert_true(hud.handle_key(KEY_ESCAPE))
	assert_false(hud.is_open())
	assert_false(hud.panel().visible)
	assert_false(_map.action_bar().button(StaffMap.ACTION_STRIKE).button_pressed)


func test_cannot_open_when_not_your_turn_or_battle_pending_or_over() -> void:
	var state := _map.simulation().state
	var hud := _map.strike_hud()
	state.current_player = 1
	assert_false(hud.toggle())
	assert_eq(_map.toast().message(), "Not your turn")
	state.current_player = 0
	state.pending_battles.append(BattleSetup.new())
	assert_false(hud.toggle())
	assert_eq(_map.toast().message(), "Resolve the pending battle first")
	state.pending_battles.clear()
	state.result = {"winner": 0, "reason": &"test"}
	assert_false(hud.toggle())
	assert_eq(_map.toast().message(), "The operation is over")
	state.result = {}
	assert_false(hud.is_open())


func test_glow_dim_and_reasons() -> void:
	var state := _map.simulation().state
	var hud := _open(&"cruise")
	var layer := hud.layer()
	assert_true(layer.target_count() > 0)
	var airfield := _airfield(0)
	var coord: Vector2i = state.get_installation(airfield).coord
	state.decisions_left = 0  # no raise-and-strike: the closed sanctuary is dimmed
	hud.refresh()
	assert_eq(layer.status_at(coord), &"illegal")
	hud.set_hover(airfield)
	assert_true(hud.panel().hover_text().contains("Closed soil"), hud.panel().hover_text())
	assert_true(hud.hover_note(airfield).contains("Closed soil"))
	state.escalation_level = 2
	hud.refresh()
	assert_eq(layer.status_at(coord), &"legal")
	assert_eq(hud.hover_note(airfield), "")


func test_out_of_range_shows_the_means_name() -> void:
	var state := _map.simulation().state
	state.escalation_level = 2
	var means: StrikeMeansDefinition = state.strike_means[&"strike_drone"].duplicate()
	means.range_hexes = 1
	state.strike_means[&"strike_drone"] = means
	var hud := _open(&"strike_drone")
	var airfield := _airfield(0)
	hud.set_hover(airfield)
	assert_true(hud.panel().hover_text().contains("Out of range of Strike drone"))
	hud.click(airfield)
	assert_false(hud.is_confirming(), "an out-of-range target cannot be confirmed")
	assert_true(_map.toast().message().contains("Out of range"), _map.toast().message())
	means.range_hexes = 20
	state.strike_means[&"strike_drone"] = means


func test_closed_target_cannot_be_confirmed() -> void:
	var state := _map.simulation().state
	var hud := _open(&"cruise")
	state.decisions_left = 0
	hud.click(_airfield(0))
	assert_false(hud.is_confirming())
	assert_true(_map.toast().message().begins_with("Closed soil"), _map.toast().message())
	assert_eq(StrikeRules.stock(state, 0, &"cruise"), 8, "nothing changed")


func test_salvo_slider_sets_the_salvo_within_the_limit() -> void:
	var hud := _open(&"cruise")
	hud.set_salvo(3)
	assert_eq(hud.salvo(), 3)
	assert_eq(hud.panel().salvo_text(), "3")
	assert_true(hud.panel().hint_text().begins_with("3 × "), hud.panel().hint_text())
	hud.set_salvo(99)
	assert_eq(hud.salvo(), StaffMapStrike.salvo_max(_map.simulation().state, 0, &"cruise"))
	hud.set_salvo(0)
	assert_eq(hud.salvo(), 1)


func test_confirm_strikes_and_updates_the_view() -> void:
	var state := _map.simulation().state
	state.escalation_level = 2
	var hud := _open(&"cruise")
	var airfield := _airfield(0)
	hud.step_salvo(1)
	assert_eq(hud.salvo(), 2)
	hud.click(airfield)
	assert_true(hud.is_confirming())
	var card := hud.confirm_card()
	assert_eq(card.means_text(), "2 × CRUISE MISSILE")
	assert_eq(card.raise_text(), "")
	assert_true(card.line_texts()[0].contains("sanctuary: +1 escalation"), str(card.line_texts()))
	hud.cancel()
	assert_false(hud.is_confirming())
	assert_true(hud.is_open(), "Cancel returns to the mode")
	hud.click(airfield)
	hud.confirm()
	var installation := state.get_installation(airfield)
	assert_true(installation.integrity < 100, "the bar drops")
	assert_eq(_map.installations().marker(airfield).bar_fraction(), installation.integrity / 100.0)
	assert_eq(StrikeRules.stock(state, 0, &"cruise"), 6)
	assert_false(hud.is_open(), "the made strike closed the mode")
	assert_true(hud.toggle(), "S opens it again")
	assert_true(hud.panel().row_text(&"cruise").contains("6"), "stock line follows")
	assert_eq(hud.panel().strikes_line(), "STRIKES: 1/2")
	assert_eq(state.escalation_level, 3, "the sanctuary breach")
	var reports := hud.reports()
	assert_eq(reports.count(), 1, "the result report replaces the toast")
	reports.tick(10.0)  # revealed after the impact on the map
	assert_true(reports.card_visible())
	var texts := reports.card().texts()
	assert_true(texts.has("CRUISE MISSILE"), str(texts))
	assert_true(texts.has("+1 sanctuary breach"), "escalation lines on the card: " + str(texts))
	assert_true(reports.card().footer_text().contains("STOCK 8 → 6"), reports.card().footer_text())
	assert_true(reports.card().footer_text().contains("STRIKES LEFT 1 / 2"))
	assert_true(hud.trail().trace_count() >= 1)
	assert_true(hud.trail().burst_count() >= 1)


func test_third_strike_is_refused() -> void:
	var state := _map.simulation().state
	state.escalation_level = 2
	var hud := _open(&"strike_drone")
	state.strikes_left = 0
	hud.click(_airfield(0))
	assert_false(hud.is_confirming())
	assert_eq(_map.toast().message(), "No strikes left this turn")


func test_raise_and_strike() -> void:
	var state := _map.simulation().state
	var hud := _open(&"cruise")
	var airfield := _airfield(0)
	hud.set_hover(airfield)
	assert_true(hud.panel().hover_text().contains("Needs Open war – raise the level first"))
	assert_eq(hud.layer().status_at(state.get_installation(airfield).coord), &"conditional")
	hud.click(airfield)
	assert_true(hud.is_confirming())
	var card := hud.confirm_card()
	assert_eq(card.raise_text(), "Escalate to Open war (uses this turn's decision)")
	assert_true(card.line_texts().back().ends_with("Regional war"), str(card.line_texts()))
	hud.confirm()
	assert_eq(state.decisions_left, 0)
	assert_eq(StrikeRules.stock(state, 0, &"cruise"), 7)
	assert_true(state.get_installation(airfield).integrity < 100)
	assert_eq(state.escalation_level, 3, "raised to 2, then the breach")


func test_failed_strike_after_a_successful_raise_says_so() -> void:
	var state := _map.simulation().state
	var hud := _open(&"cruise")
	hud.click(_airfield(0))
	assert_true(hud.is_confirming())
	state.strike_stock[0][&"cruise"] = 0  # the strike will be refused, Escalate is fine
	hud.confirm()
	assert_eq(state.escalation_level, 2, "the level was raised")
	assert_eq(state.decisions_left, 0)
	assert_eq(_map.toast().message(), "Level raised, but the strike failed: out_of_stock")


func test_rejected_escalate_strikes_nothing() -> void:
	var state := _map.simulation().state
	var hud := _open(&"cruise")
	var airfield := _airfield(0)
	hud.click(airfield)
	state.decisions_left = 0  # spent between the card and Confirm
	hud.confirm()
	assert_eq(state.escalation_level, 1)
	assert_eq(StrikeRules.stock(state, 0, &"cruise"), 8, "nothing struck")
	assert_eq(state.get_installation(airfield).integrity, 100)


func test_no_threshold_line_on_the_card() -> void:
	# TASK-140: a strike never reaches the top; near the cap the card names the capped level.
	var state := _map.simulation().state
	state.escalation_level = state.ladder.cap() - 1
	var hud := _open(&"cruise")
	hud.click(_airfield(0))
	assert_true(hud.is_confirming())
	assert_eq(hud.confirm_card().line_texts().back(), "Escalation level: Strategic alert")
	hud.cancel()


func test_the_mode_works_for_the_second_side() -> void:
	var state := _map.simulation().state
	state.current_player = 1
	_map.viewer_player = 1
	state.escalation_level = 2
	state.strikes_left = 2
	var hud := _open(&"cruise")
	var airfield := _airfield(1)
	assert_true(airfield != &"")
	hud.click(airfield)
	assert_true(hud.is_confirming())
	hud.confirm()
	assert_eq(StrikeRules.stock(state, 1, &"cruise"), 7)
	assert_true(state.get_installation(airfield).integrity < 100)
	assert_true(hud.trail().trace_count() >= 1)
	assert_eq(hud.trail().traces[0]["player"], 1)


func test_enemy_strike_leaves_a_trace_until_the_viewers_next_turn() -> void:
	var state := _map.simulation().state
	state.current_player = 1
	state.escalation_level = 2
	var own_target := &""
	for target in StrikeRules.targets(state, 1):
		if target["class_id"] == &"airfield":
			own_target = target["id"]
			break
	assert_true(_map.simulation().execute(StrikeCommand.new(&"cruise", own_target, 1)))
	var trail := _map.strike_hud().trail()
	assert_true(trail.trace_count() >= 1, "the viewer sees the enemy's strike")
	_map.simulation().event_emitted.emit({"type": &"operational_turn_started", "player": 0})
	assert_eq(trail.trace_count(), 0, "gone at the viewer's turn start")
	assert_eq(trail.burst_count(), 0)


func test_a_strike_creates_one_report_card_and_x_dismisses_it() -> void:
	var state := _map.simulation().state
	state.escalation_level = 2
	var hud := _open(&"cruise")
	hud.click(_airfield(0))
	hud.confirm()
	var reports := hud.reports()
	assert_eq(reports.count(), 1)
	assert_false(reports.card_visible(), "the burst plays first")
	hud.tick(0.5)
	assert_false(reports.card_visible(), "TASK-147: the card waits for the launch and the flight")
	hud.tick(hud.trail().seconds_to_last_impact() + 0.9)
	assert_true(reports.card_visible(), "0.8 s after the last impact")
	assert_true(reports.card().get_global_rect().position.x >= 0.0)
	reports.card().close_button().pressed.emit()
	assert_false(reports.card_visible())
	assert_false(reports.chip_visible())
	assert_eq(reports.count(), 0)


func test_the_chip_goes_with_the_trail() -> void:
	var state := _map.simulation().state
	state.escalation_level = 2
	var hud := _open(&"cruise")
	hud.click(_airfield(0))
	hud.confirm()
	hud.tick(10.0)
	assert_false(hud.handle_report_key(KEY_J), "J is the journal's")
	hud.reports().collapse()
	assert_true(hud.reports().chip_visible())
	assert_true(
		hud.reports().chip().text_of().begins_with("STRIKE"), hud.reports().chip().text_of()
	)
	_map.simulation().event_emitted.emit({"type": &"operational_turn_started", "player": 0})
	assert_false(hud.reports().chip_visible(), "cleared with the trail at the viewer's turn start")
	assert_eq(hud.reports().count(), 0)


func test_enemy_strikes_queue_as_reports_without_stock() -> void:
	var state := _map.simulation().state
	state.current_player = 1
	state.escalation_level = 2
	var targets: Array[StringName] = []
	for target in StrikeRules.targets(state, 1):
		if target["class_id"] == &"airfield":
			targets.append(target["id"])
	assert_true(_map.simulation().execute(StrikeCommand.new(&"cruise", targets[0], 1)))
	assert_true(_map.simulation().execute(StrikeCommand.new(&"cruise", targets[0], 1)))
	var hud := _map.strike_hud()
	hud.tick(10.0)  # completes the last report and reveals the first
	var reports := hud.reports()
	assert_eq(reports.count(), 2)
	assert_true(reports.card_visible())
	assert_false(reports.card().texts().has("ENEMY STRIKE"), "the tab is drawn, not a label")
	assert_true(reports.card().footer_text().contains("UNKNOWN"), reports.card().footer_text())
	assert_false(reports.card().footer_text().contains("STRIKES LEFT"))
	assert_true(reports.card().footer_text().contains("1 OF 2"), reports.card().footer_text())
	hud.tick(3.6)
	assert_eq(reports.index(), 1, "the next enemy report after 3.5 s")


func test_x_closes_the_strike_panel_and_the_confirm_card() -> void:
	var state := _map.simulation().state
	state.escalation_level = 2
	var hud := _open(&"cruise")
	hud.panel().get_node("CloseHolder/Close").pressed.emit()
	assert_false(hud.is_open(), "X on the panel leaves the mode like Esc")
	hud = _open(&"cruise")
	hud.click(_airfield(0))
	assert_true(hud.is_confirming())
	hud.confirm_card().get_node("CloseHolder/Close").pressed.emit()
	assert_false(hud.is_confirming(), "X on the confirm card cancels like Esc")
	assert_true(hud.is_open(), "...back to the mode")
	assert_eq(StrikeRules.stock(state, 0, &"cruise"), 8, "nothing struck")
