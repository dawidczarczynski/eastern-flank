# gdlint: disable=max-public-methods
extends TestCase
## The air defence view on the staff map (TASK-098b): the coverage overlay and its key, the
## suppressed marker, the hover card lines, the odds line in the confirm card and the strike
## panel, and the report line, on the shipped Suwalki operation.

const WEAPON := &"jassm_er"
const AD_RU := &"ru_ad_kaliningrad"
const C2_RU := &"ru_c2_kaliningrad"
const LIDA := &"ru_airfield_lida"

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
	var means: StrikeMeansDefinition = state.strike_means[WEAPON].duplicate()
	means.accuracy_pct = 100  # a salvo of one always hits
	state.strike_means[WEAPON] = means


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func before_each() -> void:
	var state := _map.simulation().state
	var hud := _map.strike_hud()
	hud.close()
	hud.reports().clear()
	hud.trail().clear()
	_map.viewer_player = 0
	state.current_player = 0
	for country in state.countries:  # Lida's country is an open enemy for these tests
		if country.definition.id == state.country_at(state.get_installation(LIDA).coord):
			country.stance = CountryState.BELLIGERENT
			country.side = 1
			country.breached_by = [true, true] as Array[bool]
	state.escalation_level = 0
	for level in state.ladder.levels.size():
		state.escalation_level = level  # the lowest level that allows all three targets
		var open := true
		for id: StringName in [C2_RU, AD_RU, LIDA]:
			open = open and StrikeRules.target_problem(state, 0, id, WEAPON) == ""
		if open:
			break
	state.decisions_left = 1
	state.strikes_left = 3
	state.stand_down_until = [-1, -1]
	state.pending_battles.clear()
	for installation in state.installations:
		installation.integrity = 100
		installation.suppressed_rounds = 0
	state.strike_stock[0][WEAPON] = 20
	_map.installations().refresh()
	_map.simulation().state.result = {}
	if _map.air_defence_cover().is_shown():
		_map.toggle_air_defence_cover()


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_map._unhandled_input(event)


func _open() -> StaffMapStrikeHud:
	var hud := _map.strike_hud()
	assert_true(hud.toggle(), "mode opens")
	hud.pick_means(WEAPON)
	return hud


# --- overlay ---


func test_key_c_toggles_the_zones_of_both_sides() -> void:
	var cover := _map.air_defence_cover()
	var state := _map.simulation().state
	var expected := StrikeRules.coverage(state, 0).size() + StrikeRules.coverage(state, 1).size()
	assert_eq(expected, 6)
	assert_false(cover.is_shown(), "default off")
	assert_false(cover.visible)
	_key(KEY_C)
	assert_true(cover.is_shown())
	assert_true(cover.visible)
	assert_eq(cover.zone_count(), expected)
	assert_eq(cover.shape_count(), expected)
	_key(KEY_C)
	assert_false(cover.is_shown())
	assert_eq(cover.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never blocks the mouse")


func test_options_row_follows_the_toggle() -> void:
	var options := _map.options_window()
	assert_true(options.option(StaffMap.ACTION_COVER) != null, "sixth row")
	assert_eq(options.ids().size(), 6)
	assert_false(options.option(StaffMap.ACTION_COVER).button_pressed)
	options.option_toggled.emit(StaffMap.ACTION_COVER)
	assert_true(_map.air_defence_cover().is_shown())
	assert_true(options.option(StaffMap.ACTION_COVER).button_pressed)
	_key(KEY_C)
	assert_false(options.option(StaffMap.ACTION_COVER).button_pressed)


func test_country_card_moved_to_k() -> void:
	_key(KEY_K)
	assert_false(_map.air_defence_cover().is_shown(), "K is not the cover key")


func test_zones_are_cached_between_frames() -> void:
	var cover := _map.air_defence_cover()
	_key(KEY_C)
	var before := cover.rebuild_count()
	for i in 30:
		cover.queue_redraw()
	assert_eq(cover.rebuild_count(), before, "redraws replay the cached shapes")
	var shape := cover.shape(0)
	assert_eq((shape["fill"] as PackedVector2Array).size(), StaffMapAirDefence.RING_SEGMENTS)


func test_suppressed_zone_is_dashed_and_hatched() -> void:
	var state := _map.simulation().state
	state.get_installation(AD_RU).suppressed_rounds = 2
	_key(KEY_C)
	var cover := _map.air_defence_cover()
	cover.set_zones(StaffMapAirDefence.zones(state))
	var suppressed := 0
	for i in cover.shape_count():
		var shape := cover.shape(i)
		if shape["suppressed"]:
			suppressed += 1
			assert_true((shape["dashes"] as Array).size() > 10)
			assert_true((shape["hatch"] as PackedVector2Array).size() > 20)
		else:
			assert_true((shape["dashes"] as Array).is_empty())
	assert_eq(suppressed, 1)


func test_strike_mode_shows_the_cover_and_restores_the_toggle() -> void:
	var cover := _map.air_defence_cover()
	var hud := _map.strike_hud()
	assert_true(hud.toggle())
	assert_false(cover.is_shown(), "open, no weapon yet")
	hud.pick_means(WEAPON)
	assert_true(cover.is_shown(), "a weapon is picked")
	hud.close()
	assert_false(cover.is_shown(), "restored to off")
	_key(KEY_C)
	_open()
	assert_true(cover.is_shown())
	hud.close()
	assert_true(cover.is_shown(), "restored to on")


func test_zones_follow_the_camera_without_blocking_picking() -> void:
	var cover := _map.air_defence_cover()
	_key(KEY_C)
	var before := cover.rebuild_count()
	_map.get_viewport()  # layout is driven by the camera; call it as a move would
	cover.layout()
	assert_eq(cover.rebuild_count(), before + 1, "rebuilt once for a moved camera")
	var marker := _map.installations().marker(AD_RU)
	assert_true(
		marker != null and _map.installations().marker_at(marker.global_position) in [AD_RU, &""]
	)


# --- marker, card ---


func test_marker_shows_suppression_from_events() -> void:
	var state := _map.simulation().state
	var marker := _map.installations().marker(AD_RU)
	var other := _map.installations().marker(&"ru_depot_kaliningrad")
	assert_false(marker.is_suppressed())
	state.strike_means[WEAPON].interceptability_pct = 0
	var hud := _open()
	hud.click(AD_RU)
	assert_true(hud.is_confirming())
	hud.confirm()
	assert_eq(state.get_installation(AD_RU).suppressed_rounds, state.suppression_rounds)
	assert_true(marker.is_suppressed(), "grey plate, badge")
	assert_eq(marker.suppressed_rounds, state.suppression_rounds)
	assert_false(other.is_suppressed(), "other markers untouched")
	assert_eq(other.suppressed_rounds, 0)
	var rounds := state.suppression_rounds
	for round_index in rounds:
		_end_round()
	assert_eq(state.get_installation(AD_RU).suppressed_rounds, 0)
	assert_false(marker.is_suppressed(), "back to normal after the countdown")
	state.strike_means[WEAPON].interceptability_pct = 100


func _end_round() -> void:
	for side in 2:
		_map.advance_slide(10.0)
		assert_true(_map.end_turn(), "turn ends")
	_map.advance_slide(10.0)


func test_marker_ignores_suppression_on_other_classes() -> void:
	var marker := _map.installations().marker(C2_RU)
	marker.set_suppressed(3)
	assert_false(marker.is_suppressed())


func test_hover_card_lines() -> void:
	var state := _map.simulation().state
	var info := StaffMapInstallations.info(state, state.get_installation(AD_RU))
	var card := StaffMapInstallationCard.new()
	card.show_info(info)
	assert_true(card.type_text().begins_with("Long-range air defence"), card.type_text())
	assert_eq(card.reach_text(), "radius 30 hexes (150 km)")
	assert_eq(card.suppressed_text(), "")
	state.get_installation(AD_RU).suppressed_rounds = 2
	card.show_info(StaffMapInstallations.info(state, state.get_installation(AD_RU)))
	assert_eq(card.suppressed_text(), "▲ SUPPRESSED – 2 rounds left")
	card.show_info(StaffMapInstallations.info(state, state.get_installation(C2_RU)))
	assert_eq(card.type_text(), "")
	assert_eq(card.suppressed_text(), "")
	card.free()


# --- odds ---


func test_confirm_card_shows_the_odds_and_updates_with_the_weapon() -> void:
	var state := _map.simulation().state
	var hud := _open()
	hud.click(C2_RU)
	assert_eq(StrikeRules.target_problem(state, 0, C2_RU, WEAPON), "")
	assert_true(hud.is_confirming(), _map.toast().message())
	var core := StrikeRules.interception_chance(
		state, 0, WEAPON, state.get_installation(C2_RU).coord
	)
	assert_true(core > 0)
	var card := hud.confirm_card()
	assert_eq(card.odds_text(), "Interception ~%d%% per missile" % core)
	assert_eq(card.odds_kind(), StaffMapAirDefence.ODDS_SOME)
	hud.cancel()
	hud.click(LIDA)
	assert_true(hud.is_confirming())
	assert_eq(card.odds_text(), "No air defence cover")
	assert_eq(card.odds_kind(), StaffMapAirDefence.ODDS_NONE)
	hud.cancel()


func test_confirm_card_shows_the_forecast_and_follows_the_salvo() -> void:
	var state := _map.simulation().state
	var hud := _open()
	var card := hud.confirm_card()
	hud.click(LIDA)
	var one := StrikeRules.forecast(state, 0, WEAPON, 1, LIDA)
	assert_eq(card.forecast_texts(), StaffMapStrikeText.forecast_rows(one))
	assert_eq(card.forecast_texts().size(), 2)
	assert_true(card.forecast_texts()[0].begins_with("Expected hits "))
	assert_true(card.forecast_texts()[1].begins_with("Expected integrity 100"))
	hud.cancel()
	hud.step_salvo(2)
	hud.click(LIDA)
	var three := StrikeRules.forecast(state, 0, WEAPON, 3, LIDA)
	assert_eq(card.forecast_texts(), StaffMapStrikeText.forecast_rows(three))
	assert_true(card.forecast_texts()[0].contains(" of 3 "))
	hud.cancel()
	state.strike_stock[0][WEAPON] = 2
	hud.refresh()
	hud.click(LIDA)
	assert_true(card.forecast_texts()[0].contains(" of 2 "), "capped by the stock")
	hud.cancel()
	var formation := &""
	for target in StrikeRules.targets(state, 0):
		if (
			target["kind"] == &"formation"
			and StrikeRules.target_problem(state, 0, target["id"], WEAPON) == ""
		):
			formation = target["id"]
			break
	if formation != &"":
		hud.click(formation)
		assert_true(card.forecast_texts()[1].begins_with("Expected loss"))
		hud.cancel()
	state.escalation_level = 0
	hud.click(LIDA)
	assert_false(hud.is_confirming())
	assert_true(card.forecast_texts().is_empty() or not card.visible)


func test_confirm_card_says_suppressed() -> void:
	var state := _map.simulation().state
	for installation in state.installations:
		if installation.class_id == &"air_defence" and installation.owner == 1:
			installation.suppressed_rounds = 2
	var hud := _open()
	hud.click(C2_RU)
	assert_eq(hud.confirm_card().odds_text(), "Air defence suppressed")
	hud.cancel()


func test_panel_chip_for_the_hovered_legal_target() -> void:
	var state := _map.simulation().state
	var hud := _open()
	var panel := hud.panel()
	assert_eq(panel.odds_text(), "", "hidden with no target hovered")
	hud.set_hover(C2_RU)
	var core := StrikeRules.interception_chance(
		state, 0, WEAPON, state.get_installation(C2_RU).coord
	)
	assert_eq(panel.odds_text(), "Interception ~%d%% per missile" % core)
	hud.set_hover(&"")
	assert_eq(panel.odds_text(), "")
	state.escalation_level = 0  # closed sanctuary or ROE: no longer a legal target
	hud.refresh()
	hud.set_hover(C2_RU)
	assert_eq(panel.odds_text(), "", "no odds on a target that is not legal")
	assert_true(panel.hover_text() != "")


func test_report_line_after_the_hit() -> void:
	var state := _map.simulation().state
	state.strike_means[WEAPON].interceptability_pct = 0
	var hud := _open()
	hud.click(AD_RU)
	hud.confirm()
	var reports := hud.reports()
	reports.tick(0.5)
	assert_true(reports.card_visible())
	var found := false
	for text in reports.card().texts():
		found = found or text.contains("Suppressed for %d rounds" % state.suppression_rounds)
	assert_true(found, str(reports.card().texts()))
	state.strike_means[WEAPON].interceptability_pct = 100
