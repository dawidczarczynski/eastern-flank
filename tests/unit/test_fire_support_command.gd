extends TestCase
## FireSupportCommand (TASK-099a): validation codes, the volley roll, state, codec and replay.

const Fixtures := preload("res://tests/fixtures.gd")
const EXPECTED_HITS := 2

var sim: GameSimulation
var own: Unit
var enemy: Unit
var rejection := ""


func before_each() -> void:
	var state := GameState.new(Fixtures.plains_grid(5), 2, 7)
	own = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	enemy = state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	state.fire_support_left[0] = 2
	state.fire_support_left[1] = 1
	sim = GameSimulation.new(state)
	rejection = ""
	sim.command_rejected.connect(func(_c: Command, reason: String) -> void: rejection = reason)


func _fire(player := 0, target := -1) -> bool:
	return sim.execute(FireSupportCommand.new(player, enemy.id if target < 0 else target))


func test_rejections() -> void:
	assert_false(_fire(1))
	assert_eq(rejection, "not_your_turn")
	assert_false(_fire(0, 99))
	assert_eq(rejection, "unknown_target")
	assert_false(_fire(0, own.id))
	assert_eq(rejection, "friendly_target")
	enemy.hp = 0
	assert_false(_fire())
	assert_eq(rejection, "target_dead")


func test_no_fire_support_left() -> void:
	sim.state.fire_support_left[0] = 0
	assert_false(_fire())
	assert_eq(rejection, "no_fire_support")


func test_one_per_turn() -> void:
	assert_true(_fire())
	assert_false(_fire())
	assert_eq(rejection, "fire_support_used_this_turn")
	assert_eq(sim.state.fire_support_left[0], 1)
	sim.execute(EndTurnCommand.new())
	sim.execute(EndTurnCommand.new())
	assert_true(_fire(), "the flag is reset for the new current player")
	assert_eq(sim.state.fire_support_left[0], 0)


func test_target_behind_cover_is_still_known() -> void:
	# No fog of war yet (TASK-100): terrain blocking the line of sight does not hide a target.
	var grid := sim.state.grid
	for q in range(1, 3):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.FOREST)
	assert_true(_fire())


func test_apply_events_and_no_side_effects() -> void:
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	var hp_before := enemy.hp
	assert_true(_fire())
	assert_eq(events[0]["type"], &"fire_support_used")
	assert_eq(events[0]["player"], 0)
	assert_eq(events[0]["target_id"], enemy.id)
	assert_eq(events[0]["remaining"], 1)
	assert_eq(events[0]["target_hp"], enemy.hp)
	assert_eq(enemy.hp, maxi(0, hp_before - (events[0]["hits"] as int)))
	assert_eq(own.hp, Fixtures.infantry().max_hp, "no counter-fire")
	assert_eq(sim.state.command_points, 0)
	assert_false(own.activated, "no command point spent")


func test_same_seed_same_hits_and_exact_count() -> void:
	var hits: Array[int] = []
	for i in 2:
		before_each()
		var events: Array[Dictionary] = []
		sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
		_fire()
		hits.append(events[0]["hits"])
	assert_eq(hits[0], hits[1])
	assert_eq(hits[0], EXPECTED_HITS)


func test_lethal_volley_kills_and_ends_battle() -> void:
	enemy.hp = 1
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	var rules := BattleConditionsRules.shipped()
	var needed := FireSupportCommand.hit_on(sim.state, enemy, rules)
	assert_true(needed >= 1 and needed <= rules.fire_support_die)
	assert_true(_fire())
	if not enemy.is_alive():
		assert_eq(events[1]["type"], &"unit_died")


func test_codec_round_trip() -> void:
	var command := FireSupportCommand.new(1, 4)
	var back := CommandCodec.from_dict(JSON.parse_string(JSON.stringify(command.to_dict())))
	assert_true(back is FireSupportCommand)
	assert_eq(back.to_dict(), command.to_dict())
	assert_eq(CommandCodec.from_dict({"type": "fire_support", "player": 0}), null)
	assert_eq(CommandCodec.from_dict({"type": "fire_support", "player": "a", "target_id": 1}), null)


func test_snapshot_holds_fire_support() -> void:
	_fire()
	var snap := sim.state.snapshot()
	assert_eq(snap["fire_support_left"], [1, 1])
	assert_eq(snap["fire_support_used_turn"], [true, false])


func test_replay_reproduces_state() -> void:
	var setup := Fixtures.auto_case("mirror", 3)
	setup.conditions[0].fire_support = 2
	setup.conditions[1].fire_support = 1
	var live := Scenario.from_setup(setup)
	var battle := GameSimulation.new(live)
	var target := live.units_of(1)[0]
	assert_true(battle.execute(FireSupportCommand.new(0, target.id)))
	battle.execute(EndTurnCommand.new())
	var replay := GameSimulation.new(Scenario.from_setup(setup))
	for command in battle.history:
		var again := CommandCodec.from_dict(command.to_dict())
		assert_true(replay.execute(again))
	assert_eq(replay.state.snapshot(), live.snapshot())
