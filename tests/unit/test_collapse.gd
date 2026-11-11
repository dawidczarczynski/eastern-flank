extends TestCase
## Fielded strength and collapse (TASK-140, GDD "Escalation ladder"): OperationalState.
## fielded_strength and the pure CollapseRules.

const Data := preload("res://tests/unit/test_contribution_data.gd")
const Politics := preload("res://tests/unit/test_country_rules.gd")


## Poland / Lithuania strip with a start formation per player (on (0, 0) and (1, 0)).
static func _definition() -> OperationDefinition:
	var op := Data.definition()
	op.formations = (
		[Data.placement(&"blue_1", 0, Vector2i(0, 0)), Data.placement(&"red_1", 1, Vector2i(1, 0))]
		as Array[FormationPlacement]
	)
	return op


static func _company_formation(
	id: StringName, owner: int, max_strength: int, strength: int, readiness: int
) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = Vector2i(owner, 0)
	var company := Formation.Company.new(&"test", max_strength, "%s/1" % id)
	company.strength = strength
	f.companies.append(company)
	f.readiness = readiness
	return f


## A strip state where `player` has fielded 400 and one formation of `present` strength left.
static func _collapse_state(player: int, present: int, readiness: int) -> OperationalState:
	var s := Politics._strip()
	s.fielded_strength[player] = 400
	if present > 0:
		s.formations.append(_company_formation(&"f", player, 400, present, readiness))
	return s


# --- fielded strength ---


func test_fielded_strength_at_build() -> void:
	var s := Data.build(_definition())
	assert_eq(s.fielded_strength[0], s.get_formation(&"blue_1").max_strength())
	assert_eq(s.fielded_strength[1], s.get_formation(&"red_1").max_strength())
	assert_true(s.fielded_strength[0] > 0)
	assert_eq(s.snapshot()["fielded_strength"], s.fielded_strength)


func test_joined_formations_add_to_fielded() -> void:
	var s := Data.build(_definition())
	var before := s.fielded_strength.duplicate()
	CountryRules.set_stance(s, &"lithuania", &"belligerent", 0, &"test", -1)
	var added := s.get_formation(&"a").max_strength() + s.get_formation(&"b").max_strength()
	assert_eq(s.fielded_strength, [before[0] + added, before[1]])


func test_destroyed_formations_stay_in_fielded() -> void:
	var s := Data.build(_definition())
	var fielded := s.fielded_strength.duplicate()
	s.formations.erase(s.get_formation(&"red_1"))
	assert_eq(s.fielded_strength, fielded)
	assert_eq(CollapseRules.strength_pct(s, 1), 0)
	assert_true(CollapseRules.in_collapse(s, 1), "no formation left")


# --- CollapseRules ---


func test_strength_pct_and_readiness() -> void:
	var s := _collapse_state(0, 300, 80)
	s.formations.append(_company_formation(&"g", 0, 100, 0, 40))
	s.fielded_strength[0] = 400
	assert_eq(CollapseRules.present_strength(s, 0), 300)
	assert_eq(CollapseRules.strength_pct(s, 0), 75)
	assert_eq(CollapseRules.avg_readiness(s, 0), 60)
	var empty := Politics._strip()
	assert_eq(CollapseRules.strength_pct(empty, 0), 100, "nothing fielded")
	assert_eq(CollapseRules.avg_readiness(empty, 0), 100, "no formations")
	var odd := _collapse_state(1, 133, 0)
	odd.fielded_strength[1] = 400
	assert_eq(CollapseRules.strength_pct(odd, 1), 33, "integer division")


func test_in_collapse_table() -> void:
	# [present, readiness, expected]
	var table := [
		[200, 100, true],
		[204, 100, false],
		[280, 35, true],
		[284, 0, false],
		[280, 36, false],
		[0, 100, true],
	]
	for player in 2:
		for row: Array in table:
			var s := _collapse_state(player, row[0], row[1])
			var rng_before := s.rng.state
			assert_eq(
				CollapseRules.in_collapse(s, player),
				row[2],
				"player %d present %d readiness %d" % [player, row[0], row[1]]
			)
			assert_eq(s.rng.state, rng_before, "no rng draws")


func test_collapse_uses_ladder_numbers() -> void:
	var s := _collapse_state(0, 240, 100)  # 60 %
	assert_false(CollapseRules.in_collapse(s, 0))
	var ladder: EscalationLadder = s.ladder.duplicate()
	ladder.collapse_strength_pct = 60
	s.ladder = ladder
	assert_true(CollapseRules.in_collapse(s, 0))


# --- replay ---


func test_fielded_strength_survives_replay() -> void:
	var s := Data.build(_definition())
	var sim := OperationalSimulation.new(s)
	s.current_player = 0
	assert_true(sim.execute(InvokeAllianceCommand.new(&"lithuania")))
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	var encoded: Array = []
	for command in sim.history:
		encoded.append(JSON.parse_string(JSON.stringify(command.to_dict())))
	var replay_state := Data.build(_definition())
	replay_state.current_player = 0
	var replay := OperationalSimulation.new(replay_state)
	for entry: Dictionary in encoded:
		assert_true(replay.execute(OperationalCommandCodec.from_dict(entry)))
	assert_eq(replay_state.snapshot(), s.snapshot())
	assert_true(s.fielded_strength[0] > s.get_formation(&"blue_1").max_strength())
