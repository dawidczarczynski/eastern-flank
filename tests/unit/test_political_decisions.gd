# gdlint: disable=max-public-methods
extends TestCase
## Political decisions (TASK-117): Escalate, Stand down, Declare hostilities, Invoke alliance,
## Demand neutrality – rejections, effects, side symmetry, codec and replay.

const Borders := preload("res://tests/unit/test_borders_movement.gd")

var _events: Array[Dictionary] = []


## Quad grid, player 0's F on (0, 0), player 1's R on (7, 3) (belarus), level 1.
static func _setup() -> OperationalState:
	var s := Borders._quad()
	Borders._add(s, &"f", 0, Vector2i(0, 0))
	Borders._add(s, &"r", 1, Vector2i(7, 3))
	return s


func _sim(state: OperationalState) -> OperationalSimulation:
	_events.clear()
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	return sim


func _end(s: OperationalState) -> void:
	s.pending_battles.clear()
	var cmd := EndOperationalTurnCommand.new()
	assert_true(cmd.validate(s) == "")
	cmd.apply(s)


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


func _take(s: OperationalState, cmd: OperationalCommand) -> Array[Dictionary]:
	assert_eq(cmd.validate(s), "", "accepted")
	return cmd.apply(s)


# --- data ---


func test_ladder_data() -> void:
	var l := EscalationLadder.shipped()
	assert_eq(l.decisions_per_turn, 1)
	assert_eq(l.decision_escalation, 1)
	assert_eq(l.declaration_escalation, 1)
	assert_eq(l.alliance_escalation, 1)
	assert_eq(l.stand_down_cooldown_turns, 2)
	assert_eq(l.demand_neutrality_max_level, 2)
	assert_eq(l.problem(), "")
	var bad := l.duplicate() as EscalationLadder
	bad.decisions_per_turn = 0
	assert_true(bad.problem() != "")
	bad = l.duplicate() as EscalationLadder
	bad.stand_down_cooldown_turns = -1
	assert_true(bad.problem() != "")


func test_country_and_side_data() -> void:
	var op: OperationDefinition = load("res://data/operations/suwalki_gap.tres")
	var expected := {&"lithuania": false, &"poland": true, &"belarus": true, &"russia": true}
	for setup in op.countries:
		assert_eq(setup.accepts_ultimatum, expected[setup.country.id], String(setup.country.id))
	assert_eq(SideDefinition.find(&"nato").alliance_decision_name, "Invoke collective defence")
	assert_eq(SideDefinition.find(&"russia").alliance_decision_name, "Invoke the Union State")
	var s := Operation.build(&"suwalki_gap", 7)
	assert_eq(s.decisions_left, 1)
	assert_eq(s.stand_down_until, [0, 0] as Array[int])
	assert_false(s.get_country(&"lithuania").accepts_ultimatum)
	assert_eq(s.snapshot()["decisions_left"], 1)
	assert_eq(s.snapshot()["stand_down_until"], [0, 0])


# --- common ---


func test_common_rejections_and_budget() -> void:
	var s := _setup()
	s.pending_battles.append(BattleSetup.new())
	assert_eq(EscalateCommand.new().validate(s), "battle_pending")
	s.pending_battles.clear()
	var events := _take(s, EscalateCommand.new())
	assert_eq(_types(events), [&"political_decision_taken", &"escalation_changed"])
	assert_eq(events[0]["player"], 0)
	assert_eq(events[0]["decision"], &"escalate")
	assert_eq(events[0]["country"], &"")
	assert_eq(s.decisions_left, 0)
	assert_eq(EscalateCommand.new().validate(s), "no_decisions_left")
	assert_eq(StandDownCommand.new().validate(s), "no_decisions_left")
	assert_eq(DemandNeutralityCommand.new(&"belarus").validate(s), "no_decisions_left")
	_end(s)
	assert_eq(s.decisions_left, 1, "next player")
	_end(s)
	assert_eq(s.decisions_left, 1)


# --- escalate ---


func test_escalate() -> void:
	var s := _setup()
	_take(s, EscalateCommand.new())
	assert_eq(s.escalation_level, 2)
	assert_eq(s.escalation_caused, [1, 0] as Array[int])
	_end(s)
	_end(s)
	_take(s, EscalateCommand.new())
	assert_eq(s.escalation_level, 3)
	_end(s)
	_end(s)
	assert_eq(EscalateCommand.new().validate(s), "threshold")


func test_escalate_symmetry() -> void:
	var s := _setup()
	s.current_player = 1
	_take(s, EscalateCommand.new())
	assert_eq(s.escalation_caused, [0, 1] as Array[int])


# --- stand down ---


func test_stand_down() -> void:
	var s := _setup()
	_take(s, EscalateCommand.new())
	_end(s)
	_end(s)
	assert_eq(s.turn, 2)
	assert_eq(StandDownCommand.new().validate(s), "recent_escalation")
	_end(s)
	_end(s)
	assert_eq(s.turn, 3)
	var events := _take(s, StandDownCommand.new())
	assert_eq(events[0]["decision"], &"stand_down")
	assert_eq(s.escalation_level, 1)
	assert_eq(s.escalation_deescalated, [1, 0] as Array[int])
	assert_eq(s.stand_down_until[0], 5)
	for turn in [4, 5]:
		_end(s)
		_end(s)
		assert_eq(s.turn, turn)
		assert_eq(EscalateCommand.new().validate(s), "standing_down")
	_end(s)
	_end(s)
	assert_eq(EscalateCommand.new().validate(s), "")


func test_stand_down_floor_and_below_start() -> void:
	var s := _setup()
	s.escalation_level = 0
	assert_eq(StandDownCommand.new().validate(s), "at_floor")
	s.escalation_level = 1
	_take(s, StandDownCommand.new())
	assert_eq(s.escalation_level, 0)


func test_stand_down_occupying() -> void:
	var s := _setup()
	s.get_country(&"russia").breached_by[0] = true
	s.get_formation(&"f").coord = Vector2i(5, 0)
	assert_eq(StandDownCommand.new().validate(s), "occupying")
	s.get_formation(&"f").coord = Vector2i(0, 0)
	assert_eq(StandDownCommand.new().validate(s), "")
	s.get_country(&"russia").breached_by[0] = false
	s.get_country(&"belarus").declared_by[0] = true
	s.get_formation(&"f").coord = Vector2i(5, 3)
	assert_eq(StandDownCommand.new().validate(s), "occupying")


# --- declare hostilities ---


func test_declare_hostilities() -> void:
	var s := _setup()
	assert_eq(DeclareHostilitiesCommand.new(&"nowhere").validate(s), "unknown_country")
	assert_eq(DeclareHostilitiesCommand.new(&"russia").validate(s), "already_at_war")
	assert_eq(DeclareHostilitiesCommand.new(&"lithuania").validate(s), "own_country")
	assert_false(CountryRules.may_enter(s, 0, Vector2i(5, 3)))
	var events := _take(s, DeclareHostilitiesCommand.new(&"belarus"))
	assert_eq(events[0]["country"], &"belarus")
	var belarus := s.get_country(&"belarus")
	assert_eq(belarus.stance, CountryState.BELLIGERENT)
	assert_eq(belarus.side, 1)
	assert_true(belarus.declared_by[0])
	assert_eq(s.escalation_level, 2)
	assert_true(CountryRules.may_enter(s, 0, Vector2i(5, 3)))


func test_declare_with_casus_belli_is_free() -> void:
	var s := _setup()
	s.get_country(&"belarus").casus_belli[0] = true
	var events := _take(s, DeclareHostilitiesCommand.new(&"belarus"))
	assert_eq(s.escalation_level, 1)
	assert_false(_types(events).has(&"escalation_changed"))
	assert_true(s.get_country(&"belarus").declared_by[0])


func test_declare_threshold_and_standing_down() -> void:
	var s := _setup()
	s.escalation_level = 3
	assert_eq(DeclareHostilitiesCommand.new(&"belarus").validate(s), "threshold")
	s.get_country(&"belarus").casus_belli[0] = true
	assert_eq(DeclareHostilitiesCommand.new(&"belarus").validate(s), "")
	s.stand_down_until[0] = 2
	assert_eq(DeclareHostilitiesCommand.new(&"belarus").validate(s), "standing_down")


func test_declare_symmetry() -> void:
	var s := _setup()
	s.current_player = 1
	_take(s, DeclareHostilitiesCommand.new(&"lithuania"))
	var lithuania := s.get_country(&"lithuania")
	assert_eq(lithuania.stance, CountryState.BELLIGERENT)
	assert_eq(lithuania.side, 0)
	assert_eq(s.escalation_level, 2)
	assert_true(lithuania.declared_by[1])


func test_declare_on_neutral_joins_other_side() -> void:
	var s := _setup()
	s.get_country(&"belarus").stance = CountryState.NEUTRAL
	s.get_country(&"belarus").side = -1
	_take(s, DeclareHostilitiesCommand.new(&"belarus"))
	assert_eq(s.get_country(&"belarus").side, 1)


# --- invoke alliance ---


func test_invoke_alliance() -> void:
	var s := _setup()
	assert_eq(InvokeAllianceCommand.new(&"nowhere").validate(s), "unknown_country")
	assert_eq(InvokeAllianceCommand.new(&"belarus").validate(s), "not_your_ally")
	assert_eq(InvokeAllianceCommand.new(&"poland").validate(s), "already_at_war")
	s.stand_down_until[0] = 1
	assert_eq(InvokeAllianceCommand.new(&"lithuania").validate(s), "standing_down")
	s.stand_down_until[0] = 0
	s.escalation_level = 3
	assert_eq(InvokeAllianceCommand.new(&"lithuania").validate(s), "threshold")
	s.escalation_level = 1
	var events := _take(s, InvokeAllianceCommand.new(&"lithuania"))
	assert_eq(events[0]["decision"], &"invoke_alliance")
	assert_eq(s.get_country(&"lithuania").stance, CountryState.BELLIGERENT)
	assert_eq(s.get_country(&"lithuania").side, 0)
	assert_eq(s.escalation_level, 2)


func test_invoke_alliance_symmetry() -> void:
	var s := _setup()
	s.current_player = 1
	_take(s, InvokeAllianceCommand.new(&"belarus"))
	assert_eq(s.get_country(&"belarus").stance, CountryState.BELLIGERENT)
	assert_eq(s.get_country(&"belarus").side, 1)
	assert_eq(s.escalation_caused, [0, 1] as Array[int])


# --- demand neutrality ---


func test_demand_neutrality() -> void:
	var s := _setup()
	assert_eq(DemandNeutralityCommand.new(&"nowhere").validate(s), "unknown_country")
	assert_eq(DemandNeutralityCommand.new(&"poland").validate(s), "not_hostile")
	assert_eq(DemandNeutralityCommand.new(&"russia").validate(s), "not_hostile")
	assert_eq(DemandNeutralityCommand.new(&"belarus").validate(s), "troops_present")
	s.get_formation(&"r").coord = Vector2i(5, 0)
	s.escalation_level = 3
	assert_eq(DemandNeutralityCommand.new(&"belarus").validate(s), "level_too_high")
	s.escalation_level = 1
	s.stand_down_until[0] = 9
	var events := _take(s, DemandNeutralityCommand.new(&"belarus"))
	assert_eq(_types(events), [&"political_decision_taken", &"country_stance_changed"])
	assert_eq(s.get_country(&"belarus").stance, CountryState.NEUTRAL)
	assert_eq(s.escalation_level, 1)
	assert_false(CountryRules.may_enter(s, 1, Vector2i(5, 3)))


func test_demand_neutrality_refusal_is_data() -> void:
	var s := _setup()
	s.current_player = 1
	s.get_country(&"lithuania").accepts_ultimatum = false
	assert_eq(DemandNeutralityCommand.new(&"lithuania").validate(s), "refuses_ultimatum")
	s.get_country(&"lithuania").accepts_ultimatum = true
	_take(s, DemandNeutralityCommand.new(&"lithuania"))
	assert_eq(s.get_country(&"lithuania").stance, CountryState.NEUTRAL)


func test_decisions_change_only_political_state() -> void:
	var s := _setup()
	var before := s.snapshot()
	_take(s, EscalateCommand.new())
	var after := s.snapshot()
	assert_eq(after["formations"], before["formations"])
	assert_eq(after["installations"], before["installations"])
	assert_eq(after["rng_state"], before["rng_state"])


# --- codec and replay ---


func test_codec_round_trip() -> void:
	var commands: Array[OperationalCommand] = [
		EscalateCommand.new(),
		StandDownCommand.new(),
		DeclareHostilitiesCommand.new(&"belarus"),
		InvokeAllianceCommand.new(&"lithuania"),
		DemandNeutralityCommand.new(&"nowhere"),
	]
	for cmd in commands:
		var d := JSON.parse_string(JSON.stringify(cmd.to_dict())) as Dictionary
		var back := OperationalCommandCodec.from_dict(d)
		assert_true(back != null)
		assert_eq(back.to_dict(), cmd.to_dict())
	var unknown := OperationalCommandCodec.from_dict({"type": "invoke_alliance", "country": "x"})
	assert_eq(unknown.validate(_setup()), "unknown_country")
	for type in ["declare_hostilities", "invoke_alliance", "demand_neutrality"]:
		assert_true(OperationalCommandCodec.from_dict({"type": type}) == null)
		assert_true(OperationalCommandCodec.from_dict({"type": type, "country": 5}) == null)


func _scripted(state: OperationalState, dicts: Array[Dictionary]) -> Array[Dictionary]:
	var sim := _sim(state)
	var all: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: all.append(e))
	for d in dicts:
		var cmd := OperationalCommandCodec.from_dict(
			JSON.parse_string(JSON.stringify(d)) as Dictionary
		)
		var reason := cmd.validate(state)
		if reason == "":
			assert_true(sim.execute(cmd))
		else:
			assert_false(sim.execute(cmd))
			all.append({"type": &"rejected", "reason": reason})
	return all


func test_replay_on_real_operation() -> void:
	var end := EndOperationalTurnCommand.new().to_dict()
	# Russia (player 1) moves first in this operation.
	var dicts: Array[Dictionary] = [
		EscalateCommand.new().to_dict(),
		end,
		DemandNeutralityCommand.new(&"belarus").to_dict(),
		InvokeAllianceCommand.new(&"lithuania").to_dict(),
		end,
		StandDownCommand.new().to_dict(),
		end,
		end,
	]
	var first := Operation.build(&"suwalki_gap", 7)
	var rng_before := first.rng.state
	var events_a := _scripted(first, dicts)
	var kinds := _types(events_a)
	assert_true(kinds.has(&"political_decision_taken"))
	var reasons := events_a.filter(func(e: Dictionary) -> bool: return e["type"] == &"rejected")
	assert_eq(
		reasons.map(func(e: Dictionary) -> Variant: return e["reason"]),
		["troops_present", "recent_escalation"]
	)
	assert_eq(first.get_country(&"lithuania").stance, CountryState.BELLIGERENT)
	assert_eq(first.rng.state, rng_before)
	var second := Operation.build(&"suwalki_gap", 7)
	var events_b := _scripted(second, dicts)
	assert_eq(first.snapshot(), second.snapshot())
	assert_eq(str(events_a), str(events_b))
