extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

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
	state.winner = 0
	assert_eq(HudModel.result_banner(state, 0), "VICTORY")
	state.winner = 1
	assert_eq(HudModel.result_banner(state, 0), "DEFEAT")


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
