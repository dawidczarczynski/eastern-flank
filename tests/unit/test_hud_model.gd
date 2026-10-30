extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const URAGAN := preload("res://data/units/bm27_uragan.tres")

var state: GameState
var sim: GameSimulation
var attacker: Unit
var victim: Unit


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	attacker = state.add_unit(0, Fixtures.fighter(20, 2), Vector2i(0, 0))
	state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 0))
	state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 1))
	victim = state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	state.add_unit(1, Fixtures.infantry(), Vector2i(3, -1))
	sim = GameSimulation.new(state)


func test_start_of_game() -> void:
	var bar := HudModel.top_bar(state, 0)
	assert_eq(bar["turn_text"], "01")
	assert_eq(bar["turn_limit_text"], "")
	assert_eq(bar["active_player"], 0)
	var p0: Dictionary = bar["players"][0]
	var p1: Dictionary = bar["players"][1]
	assert_eq(p0["units"], 3)
	assert_eq(p0["ready"], 3)
	assert_eq(p0["status"], "YOUR TURN")
	assert_true(p0["active"])
	assert_eq(p1["status"], "WAITING")
	assert_false(p1["active"])


func test_unit_that_spent_everything_is_not_ready_and_dead_unit_is_not_counted() -> void:
	attacker.moves_left = 0
	assert_true(sim.execute(AttackCommand.new(attacker.id, victim.id)))
	assert_false(victim.is_alive())
	var bar := HudModel.top_bar(state, 0)
	assert_eq(bar["players"][0]["ready"], 2)
	assert_eq(bar["players"][1]["units"], 2)


func test_ai_turn_status() -> void:
	state.current_player = 1
	var bar := HudModel.top_bar(state, 0)
	assert_eq(bar["players"][1]["status"], "AI TURN")
	assert_eq(bar["players"][0]["status"], "WAITING")
	assert_eq(bar["active_player"], 1)


func test_turn_text_is_zero_padded() -> void:
	state.turn = 12
	assert_eq(HudModel.top_bar(state, 0)["turn_text"], "12")
	state.turn = 7
	assert_eq(HudModel.top_bar(state, 0)["turn_text"], "07")


func test_banner_for() -> void:
	assert_true(HudModel.banner_for(1, 0, 1, 1))
	assert_true(HudModel.banner_for(1, 1, 2, 0))
	assert_false(HudModel.banner_for(1, 0, 1, 0))


func test_result_banner() -> void:
	assert_eq(HudModel.result_banner(state, 0), "")
	state.finish(0, &"eliminated")
	assert_eq(HudModel.result_banner(state, 0), "VICTORY")
	state.finish(1, &"eliminated")
	assert_eq(HudModel.result_banner(state, 0), "DEFEAT")


func test_result_banner_for_a_draw() -> void:
	state.finish(-1, &"turn_limit")
	assert_eq(HudModel.result_banner(state, 0), "DRAW")


func test_top_bar_at_uses_playback_turn_and_player() -> void:
	var bar := HudModel.top_bar_at(state, 0, 5, 1)
	assert_eq(bar["turn_text"], "05")
	assert_eq(bar["active_player"], 1)
	assert_eq(bar["players"][1]["status"], "AI TURN")
	assert_eq(bar["players"][0]["status"], "WAITING")
	assert_eq(bar["players"][0]["units"], 3)


func test_sides_use_faction_data() -> void:
	var bar := HudModel.top_bar(state, 0)
	var p0: Dictionary = bar["players"][0]
	var p1: Dictionary = bar["players"][1]
	assert_eq(p0["name"], "Poland")
	assert_eq(p0["short"], "PL")
	assert_eq(p0["color"], state.faction_of(0).color)
	assert_eq(p0["ink"], state.faction_of(0).ink_color)
	assert_eq(p1["name"], "Russia")
	assert_eq(p1["short"], "RU")
	assert_eq(p1["color"], state.faction_of(1).color)


func test_turn_text_shows_the_turn_limit() -> void:
	assert_eq(HudModel.turn_text(3, 0), "03")
	assert_eq(HudModel.turn_text(3, 8), "03 / 08")
	assert_eq(HudModel.turn_text(12, 15), "12 / 15")


func test_top_bar_shows_the_battle_turn_limit() -> void:
	var no_conditions: Array[VictoryCondition] = []
	state.set_objectives(Fixtures.objectives(8, [], [], no_conditions))
	state.turn = 3
	assert_eq(HudModel.top_bar(state, 0)["turn_text"], "03")
	assert_eq(HudModel.top_bar(state, 0)["turn_limit_text"], "/08")
	assert_eq(HudModel.top_bar_at(state, 0, 5, 1)["turn_text"], "05")


func test_result_reason_follows_the_end_reason_and_the_side() -> void:
	assert_eq(HudModel.result_reason(state, 0), "")
	state.finish(0, &"objective_taken")
	assert_eq(HudModel.result_reason(state, 0), "OBJECTIVES TAKEN")
	assert_eq(HudModel.result_reason(state, 1), "OBJECTIVES LOST")
	state.finish(1, &"eliminated")
	assert_eq(HudModel.result_reason(state, 0), "OUR FORCES ELIMINATED")
	assert_eq(HudModel.result_reason(state, 1), "ENEMY ELIMINATED")
	state.finish(0, &"enemy_destroyed")
	assert_eq(HudModel.result_reason(state, 0), "ENEMY DESTROYED")
	state.finish(-1, &"turn_limit")
	assert_eq(HudModel.result_reason(state, 0), "TURN LIMIT REACHED")
	state.finish(-1, &"no_such_reason")
	assert_eq(HudModel.result_reason(state, 0), "")


func _forecast_texts(
	attacker_def: UnitDefinition, defender_def: UnitDefinition, distance: int = 1
) -> Array[String]:
	var forecast_state := GameState.new(Fixtures.plains_grid(7), 2, 1)
	var a := forecast_state.add_unit(0, attacker_def, Vector2i(0, 0))
	var d := forecast_state.add_unit(1, defender_def, Vector2i(distance, 0))
	var texts: Array[String] = []
	for line: Dictionary in HudModel.attack_forecast(forecast_state, a.id, d.id):
		texts.append(("%s %s" % [line["label"], line["value"]]).strip_edges())
	return texts


func test_forecast_abrams_on_a_squad() -> void:
	assert_eq(
		_forecast_texts(ABRAMS, SQUAD), ["DAMAGE 4.0 (2–6)", "DESTROY <1 %", "COUNTER 0.6 (0–2)"]
	)


func test_forecast_abrams_on_an_uragan() -> void:
	assert_eq(
		_forecast_texts(ABRAMS, URAGAN), ["DAMAGE 5.4 (4–6)", "DESTROY 63 %", "COUNTER 0.2 (0–1)"]
	)


func test_forecast_homar_on_an_uragan_at_six_hexes() -> void:
	assert_eq(_forecast_texts(HOMAR, URAGAN, 6), ["DAMAGE 5.0 (4–6)", "DESTROY 33 %", "NO COUNTER"])


func test_forecast_hides_a_zero_destroy_chance() -> void:
	var texts := _forecast_texts(Fixtures.fighter(5, 2, 5), Fixtures.fighter(5, 2))  # 5 shots, 10 HP
	assert_eq(texts.size(), 2)
	assert_true(texts[0].begins_with("DAMAGE "))
	assert_true(texts[1].begins_with("COUNTER "))


func test_destroy_chance_text_at_the_edges() -> void:
	assert_eq(HudModel.destroy_chance_text(0.0), "")
	assert_eq(HudModel.destroy_chance_text(0.0001), "<1 %")
	assert_eq(HudModel.destroy_chance_text(0.6331), "63 %")
	assert_eq(HudModel.destroy_chance_text(0.996), ">99 %")
	assert_eq(HudModel.destroy_chance_text(1.0), "100 %")


func test_forecast_only_for_a_valid_target() -> void:
	assert_eq(HudModel.attack_forecast(state, attacker.id, victim.id).size(), 3)
	var far := state.unit_at(Vector2i(3, 0))
	assert_true(HudModel.attack_forecast(state, attacker.id, far.id).is_empty())  # out of range
	assert_eq(HudModel.attack_tag(state, attacker.id, victim.id).size(), 3)
	assert_true(HudModel.attack_tag(state, attacker.id, far.id).is_empty())
	assert_true(HudModel.attack_tag(state, -1, victim.id).is_empty())
	var own := state.unit_at(Vector2i(-3, 0))
	assert_true(HudModel.attack_forecast(state, attacker.id, own.id).is_empty())
	assert_true(HudModel.attack_forecast(state, -1, victim.id).is_empty())  # nothing selected
	attacker.has_attacked = true
	assert_true(HudModel.attack_forecast(state, attacker.id, victim.id).is_empty())


func _tag_texts(
	attacker_def: UnitDefinition, defender_def: UnitDefinition, distance: int = 1
) -> Array[String]:
	var tag_state := GameState.new(Fixtures.plains_grid(7), 2, 1)
	var a := tag_state.add_unit(0, attacker_def, Vector2i(0, 0))
	var d := tag_state.add_unit(1, defender_def, Vector2i(distance, 0))
	var texts: Array[String] = []
	for line: Dictionary in HudModel.attack_tag(tag_state, a.id, d.id):
		texts.append(("%s %s" % [line["label"], line["value"]]).strip_edges())
	return texts


func test_tag_abrams_on_a_squad_and_homar_on_an_uragan_at_six_hexes() -> void:
	assert_eq(_tag_texts(ABRAMS, SQUAD), ["ATTACK ~4.0 (2–6)", "DESTROY <1 %", "COUNTER ~0.6"])
	assert_eq(_tag_texts(HOMAR, URAGAN, 6), ["ATTACK ~5.0 (4–6)", "DESTROY 33 %", "NO COUNTER"])
