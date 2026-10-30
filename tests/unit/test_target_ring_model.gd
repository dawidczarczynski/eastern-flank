extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")

var state: GameState
var abrams: Unit
var squad: Unit  # enemy, adjacent
var far: Unit  # enemy, out of range
var own: Unit


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(5), 2, 1)
	abrams = state.add_unit(0, ABRAMS, Vector2i(0, 0))
	own = state.add_unit(0, SQUAD, Vector2i(-2, 0))
	squad = state.add_unit(1, SQUAD, Vector2i(1, 0))
	far = state.add_unit(1, SQUAD, Vector2i(4, 0))


func _attack_slot(attacker_id: int, target_id: int) -> Dictionary:
	return TargetRingModel.build(state, 0, attacker_id, target_id)["slots"][
		TargetRingModel.SLOT_ATTACK
	]


func test_six_slots_attack_and_info_then_four_empty() -> void:
	var slots: Array = TargetRingModel.build(state, 0, abrams.id, squad.id)["slots"]
	assert_eq(slots.size(), RadialRingGeometry.SLOT_COUNT)
	assert_eq(slots[0]["action"], &"attack")
	assert_eq(slots[0]["label"], ["ATTACK"])
	assert_true(slots[0]["enabled"])
	assert_eq(slots[0]["reason"], "")
	assert_eq(slots[1]["action"], &"info")
	assert_true(slots[1]["enabled"])
	for i in range(2, 6):
		assert_true(slots[i]["empty"])
		assert_false(slots[i]["enabled"])
	assert_eq(slots[3]["key"], 4)


func test_attack_disabled_without_a_selected_unit() -> void:
	var slot := _attack_slot(-1, squad.id)
	assert_false(slot["enabled"])
	assert_eq(slot["reason"], "NO UNIT SELECTED")


func test_attack_disabled_reasons_follow_validate() -> void:
	assert_eq(_attack_slot(abrams.id, far.id)["reason"], "TARGET OUT OF RANGE")
	# An own unit has no ATTACK slot; the reasons still map for any pair.
	assert_eq(TargetRingModel.attack_reason(state, abrams.id, own.id), "NOT AN ENEMY")
	assert_eq(TargetRingModel.attack_reason(state, squad.id, abrams.id), "NOT YOUR UNIT")
	abrams.has_attacked = true
	assert_eq(_attack_slot(abrams.id, squad.id)["reason"], "ALREADY ATTACKED THIS TURN")
	abrams.has_attacked = false
	state.set_command_points_per_turn([1, 1])
	state.command_points = 0
	assert_eq(_attack_slot(abrams.id, squad.id)["reason"], "NO COMMAND POINTS LEFT THIS TURN")
	state.command_points = 1
	squad.hp = 0
	assert_eq(_attack_slot(abrams.id, squad.id)["reason"], "UNIT NOT FOUND")
	squad.hp = 5
	state.finish(0, &"annihilation")
	assert_eq(_attack_slot(abrams.id, squad.id)["reason"], "THE BATTLE IS OVER")


func test_every_validate_reason_has_a_text() -> void:
	for reason: String in [
		"game_over",
		"unit_not_found",
		"not_your_unit",
		"no_command_points",
		"not_an_enemy",
		"already_attacked",
		"out_of_range",
	]:
		assert_true(TargetRingModel.REASON_TEXTS.has(reason), reason)
	assert_eq(TargetRingModel.reason_text("something_new"), "something_new")


func test_attack_detail_carries_the_forecast() -> void:
	var detail: Dictionary = TargetRingModel.build(state, 0, abrams.id, squad.id)["attack"]
	assert_false(detail["disabled"])
	assert_eq(detail["key"], 1)
	assert_eq(detail["title"], "ATTACK")
	var forecast: Dictionary = detail["forecast"]
	assert_eq(forecast["expected_text"], "4.0")
	assert_eq(forecast["range_text"], "2–6")
	assert_eq(forecast["low"], 2)
	assert_eq(forecast["high"], 6)
	assert_eq(forecast["max"], 10)  # the target's HP: the bar's scale
	var effects: Array[String] = []
	for line: Dictionary in detail["effects"]:
		effects.append(("%s %s" % [line["label"], line["value"]]).strip_edges())
	assert_eq(effects, ["DESTROY <1 %", "COUNTER 0.6 (0–2)"])
	assert_eq(detail["footer_label"], "COST")


func test_disabled_attack_detail_shows_the_reason_and_no_forecast() -> void:
	var detail: Dictionary = TargetRingModel.build(state, 0, abrams.id, far.id)["attack"]
	assert_true(detail["disabled"])
	assert_true((detail["forecast"] as Dictionary).is_empty())
	assert_true((detail["effects"] as Array).is_empty())
	assert_eq(detail["footer_label"], "UNAVAILABLE")
	assert_eq(detail["footer_value"], "TARGET OUT OF RANGE")


func test_summary_names_the_target() -> void:
	var model := TargetRingModel.build(state, 0, abrams.id, squad.id)
	var summary: Dictionary = model["summary"]
	assert_eq(summary["tab"], "TARGET")
	assert_eq(summary["title"], SQUAD.display_name)
	assert_eq(summary["description"], "Choose an action…")
	assert_eq(model["target_id"], squad.id)
	assert_eq(model["attacker_id"], abrams.id)


func test_an_own_unit_gets_info_only_and_its_summary() -> void:
	var model := TargetRingModel.build(state, 0, abrams.id, own.id)
	var slots: Array = model["slots"]
	assert_true(slots[TargetRingModel.SLOT_ATTACK]["empty"])
	assert_eq(slots[TargetRingModel.SLOT_INFO]["action"], &"info")
	assert_true(slots[TargetRingModel.SLOT_INFO]["enabled"])
	assert_true((model["attack"] as Dictionary).is_empty())
	assert_eq(model["summary"]["tab"], "UNIT")
	assert_eq(model["info"]["title"], "INFO")
	assert_eq(model["info"]["key"], 2)


func _csv_keys() -> Dictionary:
	var keys := {}
	var file := FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	while file != null and not file.eof_reached():
		keys[file.get_csv_line()[0]] = true
	return keys


func test_all_model_texts_are_translation_keys() -> void:
	var keys := _csv_keys()
	var texts: Array[String] = []
	var pairs := [[abrams.id, squad.id], [abrams.id, far.id], [-1, squad.id], [abrams.id, own.id]]
	for pair: Array in pairs:
		var model := TargetRingModel.build(state, 0, pair[0], pair[1])
		for slot: Dictionary in model["slots"]:
			texts.append_array(slot["label"])
			if slot["reason"] != "":
				texts.append(slot["reason"])
		for card: Dictionary in [model["attack"], model["info"], model["summary"]]:
			if card.is_empty():
				continue
			for key: String in ["tab", "description", "footer_label", "footer_value"]:
				if card[key] != "":
					texts.append(card[key])
			for line: Dictionary in card["effects"]:
				texts.append(line["label"])
	texts.append_array(TargetRingModel.REASON_TEXTS.values())
	for line: Dictionary in HudModel.attack_tag(state, abrams.id, squad.id):
		texts.append(line["label"])
	for text in texts:
		assert_true(keys.has(text), "'%s' is not in strings.csv" % text)
