extends TestCase
## The operational AI's political decisions (TASK-102b) and its route-incident rules.

const Fixtures := preload("res://tests/fixtures.gd")
const Strikes := preload("res://tests/unit/test_strikes.gd")
const Politics := preload("res://tests/unit/test_country_rules.gd")
const Ai := preload("res://tests/unit/test_operational_ai.gd")
const MECH := "res://data/formations/pl_mech_battalion.tres"
const MR := "res://data/formations/ru_motor_rifle_battalion.tres"

## The strip: Poland q0-1, Lithuania q2-3 (aligned 0), Belarus q4-5 (aligned 1), Russia q6-7.
const POLAND := Vector2i(0, 0)
const LITHUANIA := Vector2i(2, 0)
const BELARUS := Vector2i(4, 0)
const RUSSIA := Vector2i(6, 0)


## `own` / `enemy`: formation hexes of player 0 / 1; `goals` as AiGoals.
static func _state(
	own: Array[Vector2i], enemy: Array[Vector2i], goals: Array[AiGoal], level := 1
) -> OperationalState:
	var op := Politics._definition()
	var placements: Array[FormationPlacement] = []
	for i in own.size():
		placements.append(Strikes._formation(StringName("b%d" % i), MECH, 0, own[i]))
	for i in enemy.size():
		placements.append(Strikes._formation(StringName("r%d" % i), MR, 1, enemy[i]))
	op.formations = placements
	op.ai_goals = goals
	var state := Operation.from_definition(op, 1, Politics._grid(), Politics._country_map())
	state.escalation_level = level
	for country in state.countries:
		country.accepts_ultimatum = false  # tests of the ultimatum switch it on
	return state


static func _goals(coords: Array[Vector2i], player := 0) -> Array[AiGoal]:
	var goals: Array[AiGoal] = []
	for i in coords.size():
		goals.append(Ai._goal(StringName("g%d" % i), player, coords[i], AiGoal.TAKE))
	return goals


static func _decisions(commands: Array[OperationalCommand]) -> Array:
	return commands.filter(
		func(c: OperationalCommand) -> bool: return c is PoliticalDecisionCommand
	)


static func _type(state: OperationalState, player := 0) -> String:
	var found := _decisions(OperationalAi.plan(state, player))
	return "" if found.is_empty() else String(found[0].type_id())


func test_profile_fields() -> void:
	var profile := AiProfile.shipped()
	assert_eq(profile.problem(), "")
	assert_eq(profile.declare_min_strength_ratio, 1.5)
	assert_true(profile.ultimatum_enabled)
	assert_eq(profile.support_min_affordable_level_margin, 1)
	assert_true(profile.escalate_min_goal_gap > 0)
	var bad := AiProfile.new()
	bad.escalate_min_goal_gap = -1
	assert_true(bad.problem() != "")


func test_no_decision_without_a_reason() -> void:
	var state := _state([POLAND], [RUSSIA + Vector2i(1, 1)], _goals([Vector2i(1, 1)]))
	assert_eq(_type(state), "")


func test_decision_comes_first_and_only_one() -> void:
	var goals := _goals([Vector2i(1, 0), Vector2i(1, 1)])  # two untaken goals: escalate
	var state := _state([POLAND, Vector2i(0, 1)], [Vector2i(7, 1)], goals)
	var plan := OperationalAi.plan(state, 0)
	assert_true(plan[0] is EscalateCommand)
	assert_eq(_decisions(plan).size(), 1)
	assert_eq(state.escalation_level, 1, "planning changes nothing")


func test_escalate_conditions() -> void:
	var two := _goals([Vector2i(1, 0), Vector2i(1, 1)])
	var own: Array[Vector2i] = [POLAND]
	var enemy: Array[Vector2i] = [Vector2i(7, 1)]
	assert_eq(_type(_state(own, enemy, two)), "escalate")
	assert_eq(_type(_state(own, enemy, _goals([Vector2i(1, 0)]))), "", "gap too small")
	var profile := AiProfile.new()
	profile.escalate_min_goal_gap = 1
	assert_eq(
		(
			_decisions(OperationalAi.plan(_state(own, enemy, _goals([Vector2i(1, 0)])), 0, profile))
			. size()
		),
		1
	)
	assert_eq(_type(_state(own, enemy, two, 5)), "", "never at the cap")
	var standing := _state(own, enemy, two)
	standing.stand_down_until[0] = 3
	assert_eq(_type(standing), "", "standing down")


func test_declare_hostilities_needs_casus_belli_or_strength() -> void:
	var goals := _goals([BELARUS])
	var own: Array[Vector2i] = [POLAND, Vector2i(0, 1)]
	var enemy: Array[Vector2i] = [Vector2i(7, 1), Vector2i(7, 0)]
	var state := _state(own, enemy, goals)
	assert_eq(_type(state), "", "equal strength, no casus belli")
	state.get_country(&"belarus").casus_belli[0] = true
	var plan := OperationalAi.plan(state, 0)
	assert_eq((_decisions(plan)[0] as DeclareHostilitiesCommand).country_id, &"belarus")
	assert_eq(DeclareHostilitiesCommand.cost(state, 0, &"belarus"), 0)
	var strong := _state([POLAND, Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(7, 1)], goals)
	assert_eq(_type(strong), "declare_hostilities", "strength ratio")
	assert_eq(
		_type(_state([POLAND, Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(7, 1)], goals, 5)), ""
	)
	var pointless := _state([POLAND, Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(7, 1)], [])
	assert_eq(_type(pointless), "", "no goal on that soil")


func test_invoke_alliance_needs_a_goal_on_the_ally_soil() -> void:
	var state := _state([POLAND], [RUSSIA], _goals([LITHUANIA]))
	var found := _decisions(OperationalAi.plan(state, 0))
	assert_eq((found[0] as InvokeAllianceCommand).country_id, &"lithuania")
	assert_eq(_type(_state([POLAND], [RUSSIA], _goals([Vector2i(1, 1)]))), "")
	assert_eq(_type(_state([POLAND], [RUSSIA], _goals([LITHUANIA]), 5)), "", "level cap")


func test_demand_neutrality() -> void:
	var own: Array[Vector2i] = [POLAND]
	var enemy: Array[Vector2i] = [RUSSIA]
	var none: Array[AiGoal] = []
	var state := _state(own, enemy, none)
	state.get_country(&"belarus").accepts_ultimatum = true
	assert_eq(_type(state), "demand_neutrality")
	var found := _decisions(OperationalAi.plan(state, 0))
	assert_eq((found[0] as DemandNeutralityCommand).country_id, &"belarus")
	var off := AiProfile.new()
	off.ultimatum_enabled = false
	assert_eq(_decisions(OperationalAi.plan(state, 0, off)).size(), 0)
	var enemy_in: Array[Vector2i] = [BELARUS]
	var occupied := _state(own, enemy_in, none)
	occupied.get_country(&"belarus").accepts_ultimatum = true
	assert_eq(_type(occupied), "", "enemy troops in the country")
	var high := _state(own, enemy, none, 3)
	high.get_country(&"belarus").accepts_ultimatum = true
	assert_eq(_type(high), "", "level above 2")
	state.get_country(&"belarus").accepts_ultimatum = false
	assert_eq(_type(state), "", "refuses")


func test_stand_down() -> void:
	var none: Array[AiGoal] = []
	var own: Array[Vector2i] = [POLAND]
	var enemy: Array[Vector2i] = [RUSSIA]
	assert_eq(_type(_state(own, enemy, none, 4)), "stand_down", "level 4, nothing to gain")
	var state := _state(own, enemy, _goals([Vector2i(1, 1)]), 4)
	assert_eq(_type(state), "", "a goal within 2 hexes")
	state = _state(own, enemy, _goals([Vector2i(7, 1)]), 4)
	assert_true(_type(state) != "stand_down", "an untaken goal is something to gain")
	var routed := _state(own, enemy, _goals([Vector2i(7, 1)]), 2)
	routed.fielded_strength[0] = 1000
	assert_true(CollapseRules.in_collapse(routed, 0))
	assert_eq(_type(routed), "stand_down", "in collapse")
	routed.last_raise_turn[0] = routed.turn
	assert_true(_type(routed) != "stand_down", "the command's own conditions")
	routed = _state(own, enemy, _goals([Vector2i(1, 1)]), 2)
	routed.fielded_strength[0] = 1000
	assert_true(_type(routed) != "stand_down", "never while a goal is near")


func test_nuclear_last_resort() -> void:
	var own: Array[Vector2i] = [Vector2i(7, 1)]
	var none: Array[AiGoal] = []
	var state := _state([POLAND], own, none, 5)
	state.fielded_strength[1] = 1000
	state.may_use_nuclear[1] = true
	state.current_player = 1
	state.last_raise_turn[1] = state.turn  # stand down is not an option
	assert_eq(_type(state, 1), "nuclear_strike")
	var nato := _state([POLAND], [], none, 5)
	nato.fielded_strength[0] = 1000
	nato.last_raise_turn[0] = nato.turn
	assert_true(CollapseRules.in_collapse(nato, 0))
	assert_eq(_type(nato), "", "NATO never")
	# Another valid decision: a free declaration on a country with a casus belli.
	var goals := _goals([BELARUS], 1)
	state = _state([POLAND], own, goals, 5)
	state.fielded_strength[1] = 1000
	state.may_use_nuclear[1] = true
	state.current_player = 1
	state.last_raise_turn[1] = state.turn
	state.get_country(&"lithuania").casus_belli[1] = true
	goals = [Ai._goal(&"g", 1, LITHUANIA, AiGoal.TAKE)]
	state.ai_goals = goals
	assert_eq(_type(state, 1), "declare_hostilities", "another decision is available")
	state = _state([POLAND], own, none, 4)
	state.fielded_strength[1] = 1000
	state.may_use_nuclear[1] = true
	state.current_player = 1
	assert_true(_type(state, 1) != "nuclear_strike", "below the cap")


func test_decisions_execute_for_both_sides() -> void:
	for player in 2:
		var goals := _goals([Vector2i(1, 0), Vector2i(1, 1)], player)
		var state := _state([POLAND], [RUSSIA], goals)
		state.current_player = player
		var plan := OperationalAi.plan(state, player)
		assert_eq(_decisions(plan).size(), 1, "side %d" % player)
		assert_eq(Ai._run(state, plan), [] as Array[String], "side %d" % player)


func test_determinism() -> void:
	var goals := _goals([Vector2i(1, 0), Vector2i(1, 1)])
	var a := OperationalAi.plan(_state([POLAND], [RUSSIA], goals), 0)
	var b := OperationalAi.plan(_state([POLAND], [RUSSIA], goals), 0)
	assert_eq(
		a.map(func(c: OperationalCommand) -> Dictionary: return c.to_dict()),
		b.map(func(c: OperationalCommand) -> Dictionary: return c.to_dict())
	)


func test_orders_respect_closed_countries() -> void:
	var state := _state([Vector2i(3, 1)], [RUSSIA], _goals([BELARUS]), 1)
	var plan := OperationalAi.plan(state, 0)
	for order in Ai._orders(plan):
		assert_true(state.country_at(order.destination) != &"belarus")
	assert_eq(Ai._run(state, plan), [] as Array[String])


func test_orders_avoid_cap_incidents() -> void:
	# Level 4: entering Russia (a sanctuary) would raise the level to the cap.
	var state := _state([Vector2i(3, 1)], [], _goals([RUSSIA]), 4)
	var belarus := state.get_country(&"belarus")
	belarus.stance = CountryState.BELLIGERENT
	var timid := AiProfile.new()
	var into_russia := func(c: IssueOrderCommand) -> bool:
		return state.country_at(c.destination) == &"russia"
	assert_false(Ai._orders(OperationalAi.plan(state, 0, timid)).any(into_russia))
	var bold := AiProfile.new()
	bold.aggression = 0.8
	var orders := Ai._orders(OperationalAi.plan(state, 0, bold))
	assert_true(orders.any(into_russia))
	state.escalation_level = 1  # Russia is closed below Open war: no order into it
	state.get_country(&"russia").breached_by[0] = false
	assert_false(Ai._orders(OperationalAi.plan(state, 0, bold)).any(into_russia))
