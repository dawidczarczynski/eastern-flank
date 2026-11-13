extends TestCase
## Escalation ladder (TASK-115): data, state, EscalationRules, calm decay, threshold.

const Politics := preload("res://tests/unit/test_country_rules.gd")


static func _strip() -> OperationalState:
	return Politics._strip()


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


static func _end_turns(sim: OperationalSimulation, count: int) -> void:
	for i in count:
		assert(sim.execute(EndOperationalTurnCommand.new()))


static func _ladder(levels := 5) -> EscalationLadder:
	var ladder := EscalationLadder.new()
	for i in levels:
		var level := EscalationLevel.new()
		level.id = StringName("l%d" % i)
		ladder.levels.append(level)
	ladder.sanctuary_open_level = 1
	ladder.allies_join_level = 2
	return ladder


# --- data ---


func test_shipped_ladder() -> void:
	var ladder := EscalationLadder.shipped()
	assert_eq(ladder.problem(), "")
	assert_eq(ladder.top(), 6)
	assert_eq(ladder.cap(), 5)
	var ids: Array = ladder.levels.map(func(l: EscalationLevel) -> Variant: return l.id)
	assert_eq(
		ids,
		[
			&"contained",
			&"limited_war",
			&"open_war",
			&"regional_war",
			&"general_war",
			&"strategic_alert",
			&"strategic_threshold",
		]
	)
	assert_eq(ladder.levels[0].strike_classes, [&"formation"])
	assert_eq(ladder.levels[1].strike_classes, [&"formation", &"air_defence", &"depot"])
	var open: Array[StringName] = [&"formation", &"air_defence", &"depot", &"airfield", &"c2"]
	for level in [2, 3, 4, 5]:
		assert_eq(ladder.levels[level].strike_classes, open, "level %d" % level)
	assert_eq(ladder.levels[6].strike_classes, [])
	assert_eq(ladder.sanctuary_open_level, 2)
	assert_eq(ladder.allies_join_level, 3)
	assert_eq(ladder.calm_rounds, 3)
	assert_eq(ladder.sanctuary_breach_escalation, 1)
	assert_eq(ladder.urban_strike_escalation, 1)
	assert_eq(ladder.collapse_strength_pct, 35)
	assert_eq(ladder.collapse_readiness_pct, 25)
	assert_eq(ladder.collapse_readiness_strength_pct, 55)


func test_ladder_problems() -> void:
	assert_eq(_ladder().problem(), "")
	assert_true(_ladder(2).problem() != "", "fewer than 3 levels")
	var duplicate := _ladder()
	duplicate.levels[3].id = duplicate.levels[1].id
	assert_true(duplicate.problem() != "", "duplicate ids")
	for field in ["sanctuary_open_level", "allies_join_level"]:
		for bad in [-1, 4]:
			var ladder := _ladder()
			ladder.set(field, bad)
			assert_true(ladder.problem() != "", "%s %d" % [field, bad])
	var calm := _ladder()
	calm.calm_rounds = 0
	assert_true(calm.problem() != "", "calm_rounds")
	for field in ["sanctuary_breach_escalation", "urban_strike_escalation"]:
		var ladder := _ladder()
		ladder.set(field, -1)
		assert_true(ladder.problem() != "", field)
	for field in [
		"collapse_strength_pct", "collapse_readiness_pct", "collapse_readiness_strength_pct"
	]:
		for bad in [0, 101]:
			var ladder := _ladder()
			ladder.set(field, bad)
			assert_true(ladder.problem() != "", "%s %d" % [field, bad])
		var edge := _ladder()
		edge.set(field, 100)
		assert_eq(edge.problem(), "", "%s 100" % field)


func test_initial_escalation() -> void:
	assert_eq(OperationDefinition.find(&"suwalki_gap").initial_escalation, 1)
	var s := _strip()
	assert_eq(s.escalation_level, 1)
	assert_eq(s.escalation_floor, 1)
	var op := Politics._definition()
	op.initial_escalation = 0
	assert_eq(Politics._strip(op).escalation_floor, 0)
	for bad in [-1, 6]:
		var bad_op := Politics._definition()
		bad_op.initial_escalation = bad
		assert_true(Politics._strip(bad_op) == null, "initial %d" % bad)


# --- state ---


func test_state_defaults_and_snapshot() -> void:
	var s := _strip()
	assert_eq(s.escalation_caused, [0, 0])
	assert_eq(s.escalation_deescalated, [0, 0])
	assert_eq(s.last_raise_turn, [-1, -1])
	assert_eq(s.calm_rounds, 0)
	assert_false(s.raised_this_round)
	assert_eq(s.result, {})
	var snap := s.snapshot()
	assert_eq(
		snap["escalation"],
		{
			"level": 1,
			"caused": [0, 0],
			"deescalated": [0, 0],
			"last_raise_turn": [-1, -1],
			"calm_rounds": 0,
			"raised_this_round": false,
			"urban_escalated": [false, false],
		}
	)
	assert_eq(snap["result"], {})
	assert_eq(snap["fielded_strength"], [0, 0])


# --- raise / lower ---


func test_raise() -> void:
	var s := _strip()
	var rng_before := s.rng.state
	var events := EscalationRules.raise(s, 1, &"test")
	assert_eq(s.escalation_level, 2)
	assert_eq(s.escalation_caused, [0, 1])
	assert_eq(s.last_raise_turn, [-1, 1])
	assert_true(s.raised_this_round)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"escalation_changed")
	assert_eq(events[0]["level"], 2)
	assert_eq(events[0]["previous"], 1)
	assert_eq(events[0]["by"], 1)
	assert_eq(events[0]["cause"], &"test")
	assert_eq(s.rng.state, rng_before, "no rng draws")


func test_raise_rejects_bad_input() -> void:
	var s := _strip()
	assert_eq(EscalationRules.raise(s, 2, &"test"), [])
	assert_eq(EscalationRules.raise(s, 0, &"test", 0), [])
	assert_eq(EscalationRules.raise(s, 0, &"test", -1), [])
	assert_eq(s.escalation_level, 1)
	assert_false(s.raised_this_round)


func test_allies_join() -> void:
	var s := _strip()
	EscalationRules.raise(s, 0, &"test")
	var events := EscalationRules.raise(s, 0, &"test")
	assert_eq(
		_types(events),
		[&"escalation_changed", &"country_stance_changed", &"country_stance_changed"]
	)
	assert_eq(events[1]["country"], &"lithuania")
	assert_eq(events[1]["stance"], CountryState.BELLIGERENT)
	assert_eq(events[1]["side"], 0)
	assert_eq(events[1]["cause"], &"ladder")
	assert_eq(events[1]["by"], -1)
	assert_eq(events[2]["country"], &"belarus")
	assert_eq(events[2]["side"], 1)
	assert_eq(s.get_country(&"lithuania").stance, CountryState.BELLIGERENT)


func test_neutral_joins_as_aligned() -> void:
	var s := _strip()
	CountryRules.set_stance(s, &"belarus", CountryState.NEUTRAL, -1, &"test", 0)
	EscalationRules.raise(s, 0, &"test", 2)
	var belarus := s.get_country(&"belarus")
	assert_eq(belarus.stance, CountryState.ALIGNED)
	assert_eq(belarus.side, 1)


func test_no_join_when_already_above() -> void:
	var s := _strip()
	EscalationRules.raise(s, 0, &"test", 2)
	var events := EscalationRules.lower(s, -1, &"x")
	assert_eq(events.size(), 1)
	assert_eq(s.get_country(&"lithuania").stance, CountryState.BELLIGERENT, "never revert")
	assert_eq(_types(EscalationRules.raise(s, 0, &"test")), [&"escalation_changed"])
	s.escalation_level = 4
	assert_eq(_types(EscalationRules.raise(s, 0, &"test")), [&"escalation_changed"], "to the cap")


func test_raise_is_capped_below_the_top() -> void:
	var s := _strip()
	s.escalation_level = 4
	s.raised_this_round = false
	var events := EscalationRules.raise(s, 0, &"test", 3)
	assert_eq(s.escalation_level, 5)
	assert_eq(s.escalation_caused, [1, 0], "only the real steps")
	assert_eq(_types(events), [&"escalation_changed"])
	assert_eq(events[0]["level"], 5)
	assert_eq(s.result, {}, "a raise never ends the operation")
	s.raised_this_round = false
	assert_eq(EscalationRules.raise(s, 1, &"test"), [], "no-op at the cap")
	assert_eq(s.escalation_level, 5)
	assert_eq(s.escalation_caused, [1, 0])
	assert_false(s.raised_this_round)
	assert_eq(s.last_raise_turn, [1, -1])


func test_cap_mirrors_and_follows_the_ladder() -> void:
	var m := _strip()
	m.escalation_level = 3
	EscalationRules.raise(m, 1, &"test", 9)
	assert_eq(m.escalation_level, 5)
	assert_eq(m.escalation_caused, [0, 2])
	assert_eq(m.result, {})
	var small := _strip()
	small.ladder = _ladder(5)
	small.escalation_level = 2
	EscalationRules.raise(small, 0, &"test", 5)
	assert_eq(small.escalation_level, 3, "a 5-level ladder caps at top() - 1")
	assert_eq(small.result, {})


func test_lower() -> void:
	var s := _strip()
	var events := EscalationRules.lower(s, 1, &"stand_down")
	assert_eq(s.escalation_level, 0)
	assert_eq(s.escalation_deescalated, [0, 1])
	assert_eq(events[0]["level"], 0)
	assert_eq(events[0]["previous"], 1)
	assert_eq(events[0]["by"], 1)
	assert_eq(EscalationRules.lower(s, 1, &"stand_down"), [])
	assert_eq(s.escalation_deescalated, [0, 1])
	s.escalation_level = 2
	EscalationRules.lower(s, -1, &"calm")
	assert_eq(s.escalation_deescalated, [0, 1], "nobody credited")


# --- operation over ---


func test_every_command_rejected_when_over() -> void:
	var s := _strip()
	s.result = {"winner": -1, "reason": &"nuclear_use", "by": 1}
	var sim := OperationalSimulation.new(s)
	var rejected: Array[String] = []
	sim.command_rejected.connect(
		func(_c: OperationalCommand, r: String) -> void: rejected.append(r)
	)
	sim.execute(EndOperationalTurnCommand.new())
	sim.execute(IssueOrderCommand.new(&"x", Vector2i.ZERO, &"march"))
	sim.execute(ResolveBattleCommand.new())
	assert_eq(rejected, ["operation_over", "operation_over", "operation_over"])
	assert_eq(sim.history.size(), 0)


# --- calm decay ---


func test_calm_decay() -> void:
	var s := _strip()
	s.first_player = 0
	s.current_player = 0
	var sim := OperationalSimulation.new(s)
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	EscalationRules.raise(s, 1, &"test")
	_end_turns(sim, 2)  # round 1 ends: raised
	assert_eq(s.calm_rounds, 0)
	_end_turns(sim, 4)  # rounds 2, 3
	assert_eq(s.escalation_level, 2)
	assert_eq(s.calm_rounds, 2)
	events.clear()
	_end_turns(sim, 2)  # round 4
	assert_eq(s.escalation_level, 1)
	assert_eq(s.escalation_caused, [0, 1])
	assert_eq(s.calm_rounds, 0)
	assert_eq(
		_types(events),
		[
			&"operational_turn_ended",
			&"operational_turn_started",
			&"operational_turn_ended",
			&"escalation_changed",
			&"operational_turn_started",
		]
	)
	assert_eq(events[3]["cause"], &"calm")
	assert_eq(events[3]["by"], -1)
	_end_turns(sim, 20)
	assert_eq(s.escalation_level, 1, "floor")


func test_raise_resets_calm_count() -> void:
	var s := _strip()
	s.first_player = 0
	s.current_player = 0
	var sim := OperationalSimulation.new(s)
	EscalationRules.raise(s, 1, &"test")
	_end_turns(sim, 2)  # round 1
	_end_turns(sim, 2)  # round 2
	EscalationRules.raise(s, 1, &"test")  # round 3: level 3
	_end_turns(sim, 2)  # round 3
	_end_turns(sim, 2 * 2)  # rounds 4, 5
	assert_eq(s.escalation_level, 3)
	_end_turns(sim, 2)  # round 6
	assert_eq(s.escalation_level, 2)


func test_calm_works_from_the_cap() -> void:
	var s := _strip()
	s.first_player = 0
	s.current_player = 0
	s.escalation_level = 4
	EscalationRules.raise(s, 1, &"test")
	s.definition.round_limit = 100  # the 30-round limit (TASK-107a) is not under test
	var sim := OperationalSimulation.new(s)
	_end_turns(sim, 2)  # round 1: raised
	assert_eq(s.escalation_level, 5)
	_end_turns(sim, 2 * 3)  # three quiet rounds
	assert_eq(s.escalation_level, 4)
	_end_turns(sim, 2 * 30)
	assert_eq(s.escalation_level, 1, "not below the start level")


func test_stand_down_from_the_cap() -> void:
	var s := _strip()
	s.escalation_level = 5
	s.current_player = 0
	var sim := OperationalSimulation.new(s)
	assert_true(sim.execute(StandDownCommand.new()))
	assert_eq(s.escalation_level, 4)
