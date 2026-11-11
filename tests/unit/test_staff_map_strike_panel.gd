extends TestCase
## The named-weapon strike panel and trace layer (TASK-141b): the means list model (side, order,
## greyed stock 0, km, interceptability words), the text helpers, the panel (rows, detail card with
## the model or the glyph fallback, X, greyed rows) and a smoke test of the heads the layer draws.

const Strikes := preload("res://tests/unit/test_strikes.gd")
const A1 := &"a1"

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


## A state that holds every shipped weapon; NATO stock as in the shipped operation (Storm Shadow
## and Tomahawk at 0), Russian stock everywhere.
static func _state() -> OperationalState:
	var state := Strikes._state(Strikes._definition())
	state.strike_means = StrikeMeansDefinition.shipped()
	for player in 2:
		state.strike_stock[player].clear()
		for id: StringName in state.strike_means:
			var means: StrikeMeansDefinition = state.strike_means[id]
			if means.usable_by(player):
				state.strike_stock[player][id] = 0 if means.side == 0 and id in _allied() else 5
	return state


static func _allied() -> Array[StringName]:
	return [&"storm_shadow", &"tomahawk"]


static func _ids(list: Array[Dictionary]) -> Array:
	return list.map(func(entry: Dictionary) -> Variant: return entry["id"])


# --- list model ---


func test_each_side_lists_only_its_own_weapons() -> void:
	var state := _state()
	var nato := _ids(StaffMapStrike.means_list(state, 0))
	var russia := _ids(StaffMapStrike.means_list(state, 1))
	assert_false(nato.has(&"iskander_m"), "no Iskander-M for NATO")
	assert_false(russia.has(&"jassm_er"))
	for id: StringName in [
		&"jassm_er", &"homar_k", &"atacms", &"prsm", &"warmate", &"storm_shadow"
	]:
		assert_true(nato.has(id), "NATO has %s" % id)
	assert_eq(nato.size(), 7, str(nato))
	for id: StringName in [&"iskander_m", &"kinzhal", &"kalibr", &"kh101", &"geran_2"]:
		assert_true(russia.has(id), "Russia has %s" % id)
	assert_eq(russia.size(), 5, str(russia))


func test_order_is_stock_first_then_range_descending_then_id() -> void:
	var list := StaffMapStrike.means_list(_state(), 0)
	assert_eq(
		_ids(list),
		[&"jassm_er", &"prsm", &"atacms", &"homar_k", &"warmate", &"tomahawk", &"storm_shadow"]
	)
	for entry in list:
		assert_eq(entry["enabled"], entry["stock"] > 0)
	assert_false(list[5]["enabled"], "Tomahawk is listed greyed, not hidden")
	assert_false(list[6]["enabled"])
	var state := _state()
	state.strike_stock[0][&"storm_shadow"] = 2
	assert_eq(StaffMapStrike.means_list(state, 0)[1]["id"], &"storm_shadow", "stock sorts up")


func test_entry_carries_the_card_data() -> void:
	var jassm: Dictionary = StaffMapStrike.means_list(_state(), 0)[0]
	assert_eq(jassm["name"], "JASSM-ER")
	assert_eq(jassm["designation"], "AGM-158B")
	assert_eq(jassm["class_text"], "Cruise")
	assert_eq(jassm["glyph"], &"missile")
	assert_eq(jassm["range_km"], jassm["range_hexes"] * 5)
	assert_eq(jassm["range_text"], "925 km", "always km, no whole-map text")
	var atacms: Dictionary = StaffMapStrike.means_list(_state(), 0)[2]
	assert_eq(atacms["range_text"], "300 km")
	assert_eq(atacms["glyph"], &"ballistic")


func test_range_and_interceptability_words() -> void:
	assert_eq(StaffMapStrike.range_text(60), "300 km")
	assert_eq(StaffMapStrike.range_text(120), "600 km")
	assert_eq(StaffMapStrike.range_text(500), "2500 km")
	assert_eq(StaffMapStrike.intercept_text(50), "hard to intercept")
	assert_eq(StaffMapStrike.intercept_text(51), "normal")
	assert_eq(StaffMapStrike.intercept_text(110), "normal")
	assert_eq(StaffMapStrike.intercept_text(111), "easy to intercept")
	assert_eq(StaffMapStrike.intercept_word(45), "hard")
	assert_eq(StaffMapStrike.intercept_word(150), "easy")


# --- texts ---


func test_salvo_line_names_the_weapon() -> void:
	assert_eq(StaffMapStrikeText.salvo_line("JASSM-ER", 3), "3 × JASSM-ER")
	assert_eq(
		StaffMapStrikeText.salvo_line("JASSM-ER", 3, "Chernyakhovsk airfield"),
		"3 × JASSM-ER on Chernyakhovsk airfield"
	)


func test_toast_and_reason_use_the_weapon_name() -> void:
	var state := _state()
	var event := {
		"type": &"strike_resolved",
		"player": 1,
		"means": &"iskander_m",
		"target": A1,
		"count": 2,
		"intercepted": 0,
		"hits": 2,
		"misses": 0,
		"damage_dealt": 0,
		"target_destroyed": false,
	}
	assert_true(StaffMapStrikeText.resolved(state, event).begins_with("Iskander-M ×2 on "))
	assert_eq(
		StaffMapStrike.reason_text(state, 0, A1, &"iskander_m", "out_of_range"),
		"Out of range of Iskander-M"
	)


# --- panel ---


func _panel(state: OperationalState, picked := &"") -> StaffMapStrikePanel:
	var panel := StaffMapStrikePanel.new()
	panel.set_side("NATO", Color("#5b93d6"), Color("#6f95ab"))
	panel.show_state(StaffMapStrike.means_list(state, 0), picked, 2, 4, "Strikes: 1/2", "hint")
	return panel


func test_panel_rows_follow_the_list_and_grey_stock_zero() -> void:
	var panel := _panel(_state())
	assert_eq(panel.row_ids().size(), 7)
	assert_eq(panel.row_ids()[0], &"jassm_er")
	assert_eq(panel.size.x, 420.0, "420 px window")
	assert_true(panel.row_text(&"jassm_er").contains("AGM-158B · CRUISE · 925 KM"))
	assert_true(panel.row_text(&"atacms").contains("300 KM"))
	var greyed := panel.row_text(&"tomahawk")
	assert_true(greyed.contains("ALLIES ONLY") and greyed.contains("0"), greyed)
	assert_true(panel.row(&"tomahawk").modulate.a < 0.5, "45 % opacity")
	assert_eq(panel.row(&"jassm_er").modulate.a, 1.0)
	assert_eq(panel.row(&"jassm_er").custom_minimum_size.y, 46.0)
	assert_eq(panel.tab_text, "STRIKE · NATO")
	panel.free()


func test_clicking_a_greyed_row_does_not_pick_it() -> void:
	var panel := _panel(_state())
	var picks: Array[StringName] = []
	panel.means_picked.connect(func(id: StringName) -> void: picks.append(id))
	panel.row(&"tomahawk").pressed.emit()
	assert_eq(picks, [] as Array[StringName])
	panel.row(&"atacms").pressed.emit()
	assert_eq(picks, [&"atacms"] as Array[StringName])
	panel.free()


func test_picked_row_and_salvo_slider() -> void:
	var panel := _panel(_state(), &"atacms")
	assert_true(panel.row(&"atacms").picked)
	assert_false(panel.row(&"jassm_er").picked)
	assert_eq(panel.salvo_text(), "2")
	assert_eq(panel.strikes_line(), "STRIKES: 1/2")
	var slider := panel.salvo_slider()
	assert_eq(slider.min_value, 1.0)
	assert_eq(slider.max_value, 4.0, "max = the salvo limit")
	assert_eq(slider.value, 2.0)
	assert_true(slider.editable)
	var counts: Array[int] = []
	panel.salvo_set.connect(func(count: int) -> void: counts.append(count))
	slider.value = 3.0
	slider.value_changed.emit(slider.value)  # a panel outside the tree gets no signal from Range
	assert_eq(counts, [3] as Array[int])
	assert_eq(panel.salvo_text(), "3")
	slider.value = 3.4
	assert_eq(slider.value, 3.0, "snaps to integers")
	panel.show_state(StaffMapStrike.means_list(_state(), 0), &"", 1, 0, "Strikes: 1/2", "hint")
	assert_false(panel.salvo_slider().editable, "nothing picked: the slider is off")
	assert_eq(counts, [3] as Array[int], "show_state does not emit")
	panel.free()


func test_x_closes_the_panel() -> void:
	var panel := _panel(_state())
	var closed := [false]
	panel.close_requested.connect(func() -> void: closed[0] = true)
	panel.close_button().pressed.emit()
	assert_true(closed[0])
	panel.free()


func test_preview_is_hover_then_picked_then_first() -> void:
	var order: Array[StringName] = [&"a", &"b", &"c"]
	assert_eq(StaffMapStrikePanel.previewed_id(order, &"", &""), &"a")
	assert_eq(StaffMapStrikePanel.previewed_id(order, &"b", &""), &"b")
	assert_eq(StaffMapStrikePanel.previewed_id(order, &"b", &"c"), &"c")
	assert_eq(StaffMapStrikePanel.previewed_id(order, &"b", &"zzz"), &"b")
	assert_eq(StaffMapStrikePanel.previewed_id([] as Array[StringName], &"", &""), &"")


func test_card_shows_the_model_or_the_class_glyph_and_the_chips() -> void:
	var panel := _panel(_state(), &"jassm_er")
	var card := panel.card()
	assert_eq(card.shown_id(), &"jassm_er")
	assert_true(card.shows_model(), "JASSM-ER has a turntable model")
	assert_eq(card.chip_text("RANGE"), "925 KM")
	assert_eq(card.chip_text("SALVO").substr(0, 1), "≤")
	assert_true(card.chip_text("ACCURACY").ends_with("%"))
	assert_true(card.chip_text("INTERCEPT") in ["HARD", "NORMAL", "EASY"])
	assert_eq(card.tag_text(), "AGM-158B · CRUISE")
	panel.hover_row(&"atacms")
	assert_eq(card.shown_id(), &"atacms", "hover previews")
	assert_false(card.shows_model(), "no ATACMS model yet: the glyph stands in")
	assert_eq(card.chip_text("RANGE"), "300 KM")
	panel.hover_row(&"tomahawk")
	assert_true(card.platform_text().contains("allies"), card.platform_text())
	panel.hover_row(&"")
	assert_eq(card.shown_id(), &"jassm_er", "leaving the row returns to the picked weapon")
	panel.free()


# --- the layer: one head per flying missile, no node per missile ---


func _layer(state: OperationalState, means: StringName, count: int) -> Array:
	var layer := StaffMapStrikeLayer.new()
	var trail := StaffMapStrikeTrail.new()
	layer.setup(
		StaffMapPalette.new(), func(hex: Vector2i) -> Vector2: return Vector2(hex) * 40.0, trail
	)
	var coord := state.get_installation(A1).coord
	(
		trail
		. on_event(
			state,
			0,
			{
				"type": &"strike_launched",
				"player": 0,
				"means": means,
				"count": count,
				"target": A1,
				"coord": coord,
				"class_id": &"airfield",
			}
		)
	)
	(
		trail
		. on_event(
			state,
			0,
			{
				"type": &"strike_resolved",
				"player": 0,
				"means": means,
				"target": A1,
				"count": count,
				"intercepted": 0,
				"hits": count,
				"misses": 0,
			}
		)
	)
	for trace in trail.traces:
		trace["duration"] = 2.0  # all missiles of the salvo in the air at once
	return [layer, trail]


func test_salvo_heads_are_drawn_without_extra_nodes() -> void:
	var state := _state()
	for case: Array in [[&"kalibr", 4, 4], [&"geran_2", 6, 6], [&"geran_2", 16, 6]]:
		var made := _layer(state, case[0], case[1])
		var layer: StaffMapStrikeLayer = made[0]
		var trail: StaffMapStrikeTrail = made[1]
		assert_eq(layer.get_child_count(), 0)
		assert_eq(layer.heads().size(), 0, "nothing flies before the clock runs")
		trail.clock = 0.6
		var heads := layer.heads()
		assert_eq(heads.size(), case[2], "%s x%d" % [case[0], case[1]])
		assert_eq(layer.get_child_count(), 0, "no node per missile")
		assert_eq(
			(heads[0]["look"] as StrikeWeaponLook).glyph, StrikeWeaponLook.for_means(case[0]).glyph
		)
		trail.clock = 5.0
		assert_eq(layer.heads().size(), 0, "after impact the heads are gone")
		layer.free()


func test_weapon_without_a_look_still_flies_with_the_default() -> void:
	var made := _layer(_state(), &"home_made", 2)
	var trail: StaffMapStrikeTrail = made[1]
	trail.clock = 0.6
	assert_eq((made[0] as StaffMapStrikeLayer).heads().size(), 2)
	(made[0] as StaffMapStrikeLayer).free()


func test_faint_trace_keeps_the_weapon_arc() -> void:
	var made := _layer(_state(), &"iskander_m", 1)
	var layer: StaffMapStrikeLayer = made[0]
	var trail: StaffMapStrikeTrail = made[1]
	trail.clock = 5.0
	var trace := trail.traces[0]
	var points := layer._points(trace, 1.0)
	var chord_mid := (points[0] + points[points.size() - 1]) / 2.0
	var apex := chord_mid.y - points[points.size() / 2].y
	assert_true(apex > 0.0, "the arc is still bowed upward when the trace is faint")
	layer.free()
