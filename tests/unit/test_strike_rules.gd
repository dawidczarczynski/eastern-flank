extends TestCase
## Deep strikes (TASK-097a): targets, range, ROE, capability, resolution, round boundary.

const Strikes := preload("res://tests/unit/test_strikes.gd")
const A1 := Vector2i(6, 0)

# --- targets, range, ROE ---


func test_targets() -> void:
	var state := Strikes._state()
	var ids: Array = StrikeRules.targets(state, 0).map(
		func(t: Dictionary) -> Variant: return t["id"]
	)
	assert_eq(ids, [&"a1", &"d1", &"r"])
	var first := StrikeRules.targets(state, 0)[0]
	assert_eq(first["kind"], &"installation")
	assert_eq(first["coord"], A1)
	assert_eq(first["class_id"], &"airfield")
	assert_eq(StrikeRules.targets(state, 0)[2]["kind"], &"formation")
	assert_eq(StrikeRules.targets(state, 0)[2]["class_id"], &"formation")
	var mirrored: Array = StrikeRules.targets(state, 1).map(
		func(t: Dictionary) -> Variant: return t["id"]
	)
	assert_eq(mirrored, [&"pl_air", &"b"])
	state.get_installation(&"d1").integrity = 0
	assert_eq(StrikeRules.targets(state, 0).size(), 2, "destroyed ones are not targets")


func test_in_range() -> void:
	var state := Strikes._state()
	assert_true(StrikeRules.in_range(state, 0, &"short", Vector2i(5, 0)), "2 from Lithuania")
	assert_false(StrikeRules.in_range(state, 0, &"short", Vector2i(6, 0)))
	assert_true(StrikeRules.in_range(state, 0, &"sure", Vector2i(7, 0)))
	assert_true(StrikeRules.in_range(state, 0, &"short", Vector2i(0, 0)), "own soil is distance 0")
	assert_false(StrikeRules.in_range(state, 0, &"nuke", Vector2i(0, 0)))
	# Mirrored: player 1 measures from Belarus and Russia.
	assert_true(StrikeRules.in_range(state, 1, &"short", Vector2i(2, 0)), "2 from Belarus")
	assert_false(StrikeRules.in_range(state, 1, &"short", Vector2i(1, 0)))
	# A country aligned with the enemy is no origin; once it is aligned with the player it is.
	var far := Strikes._state()
	far.get_country(&"lithuania").side = 1
	assert_false(StrikeRules.in_range(far, 0, &"short", Vector2i(5, 0)))
	far.get_country(&"lithuania").side = 0
	assert_true(StrikeRules.in_range(far, 0, &"short", Vector2i(5, 0)))


func test_target_problem_order() -> void:
	var state := Strikes._state()
	assert_eq(StrikeRules.target_problem(state, 0, &"nope"), "unknown_target")
	assert_eq(StrikeRules.target_problem(state, 0, &"pl_air"), "unknown_target", "own installation")
	assert_eq(StrikeRules.target_problem(state, 0, &"b"), "unknown_target", "own formation")
	assert_eq(StrikeRules.target_problem(state, 0, &"a1"), "closed_country", "level 1")
	assert_eq(StrikeRules.target_problem(state, 0, &"d1"), "closed_country")
	state.escalation_level = 2
	assert_eq(StrikeRules.target_problem(state, 0, &"a1"), "")
	assert_eq(StrikeRules.target_problem(state, 0, &"a1", &"short"), "out_of_range")
	assert_eq(StrikeRules.target_problem(state, 0, &"a1", &"sure"), "")
	state.get_installation(&"a1").integrity = 0
	assert_eq(StrikeRules.target_problem(state, 0, &"a1"), "target_destroyed")


func test_target_problem_roe_and_mirror() -> void:
	var state := Strikes._state()
	assert_eq(StrikeRules.target_problem(state, 1, &"b"), "")
	assert_eq(StrikeRules.target_problem(state, 1, &"pl_air"), "roe_class", "airfield at level 1")
	state.escalation_level = 2
	assert_eq(StrikeRules.target_problem(state, 1, &"pl_air"), "")
	var op := Strikes._definition()
	op.installations.append(Strikes._placement(&"by_depot", &"depot", 1, Vector2i(4, 0)))
	var with_belarus := Strikes._state(op)
	assert_eq(StrikeRules.target_problem(with_belarus, 0, &"by_depot"), "closed_country")


func test_escalation_preview() -> void:
	var state := Strikes._state()
	assert_eq(StrikeRules.escalation_preview(state, 0, &"a1"), 1, "sanctuary breach")
	assert_eq(StrikeRules.escalation_preview(state, 0, &"nope"), 0)
	state.grid.set_terrain(A1, Terrain.Type.URBAN)
	assert_eq(StrikeRules.escalation_preview(state, 0, &"a1"), 2)


# --- capability ---


func test_capability() -> void:
	var state := Strikes._state()
	assert_eq(StrikeRules.capability(state, 0, &"airfield"), 100)
	assert_eq(StrikeRules.capability(state, 0, &"c2"), 100, "none = 100")
	state.get_installation(&"a1").integrity = 40
	assert_eq(StrikeRules.capability(state, 1, &"airfield"), 40)
	state.installations.append(
		Installation.from_placement(Strikes._placement(&"a2", &"airfield", 1, Vector2i(5, 0)))
	)
	state.get_installation(&"a2").integrity = 0
	assert_eq(StrikeRules.capability(state, 1, &"airfield"), 20)


# --- resolution ---


func test_resolve_hits_and_misses() -> void:
	var state := Strikes._state()
	var target := StrikeRules.find_target(state, 0, &"a1")
	var events := StrikeRules.resolve(state, 0, &"sure", target, 2)
	assert_eq(Strikes._types(events), [&"strike_resolved", &"installation_changed"])
	assert_eq(events[0]["hits"], 2)
	assert_eq(events[0]["misses"], 0)
	assert_eq(events[0]["intercepted"], 0)
	assert_eq(events[0]["damage_dealt"], 70)
	assert_eq(state.get_installation(&"a1").integrity, 30)
	assert_eq(events[1]["cause"], &"strike")
	assert_eq(events[1]["before"], 100)
	assert_eq(events[1]["after"], 30)
	assert_false(events[1]["destroyed"])
	var none := StrikeRules.resolve(state, 0, &"never", target, 3)
	assert_eq(Strikes._types(none), [&"strike_resolved"])
	assert_eq(none[0]["misses"], 3)
	assert_eq(state.get_installation(&"a1").integrity, 30)


func test_resolve_draws_two_per_missile() -> void:
	var state := Strikes._state()
	var reference := RandomNumberGenerator.new()
	reference.seed = 1
	for i in 6:
		reference.randi_range(1, 100)
	var target := StrikeRules.find_target(state, 0, &"a1")
	StrikeRules.resolve(state, 0, &"never", target, 3)
	assert_eq(state.rng.state, reference.state)


func test_resolve_destroys_and_caps() -> void:
	var state := Strikes._state()
	state.get_installation(&"a1").integrity = 20
	var target := StrikeRules.find_target(state, 0, &"a1")
	var events := StrikeRules.resolve(state, 0, &"sure", target, 2)
	assert_eq(events[0]["damage_dealt"], 20)
	assert_true(events[0]["target_destroyed"])
	assert_eq(state.get_installation(&"a1").integrity, 0)
	assert_true(events[1]["destroyed"])


func test_resolve_formation() -> void:
	var state := Strikes._state()
	var formation := state.get_formation(&"r")
	var before := formation.strength()
	var first_company_before := formation.companies[0].strength
	var target := StrikeRules.find_target(state, 0, &"r")
	var events := StrikeRules.resolve(state, 0, &"sure", target, 1)
	assert_eq(Strikes._types(events), [&"strike_resolved", &"formation_damaged"])
	assert_eq(formation.strength(), before - 2)
	assert_eq(formation.companies[0].strength, first_company_before - 2, "ties: lowest index")
	assert_eq(events[0]["damage_dealt"], 2)
	for company in formation.companies:
		company.strength = 1
	events = StrikeRules.resolve(state, 0, &"sure", target, 4)
	assert_eq(Strikes._types(events), [&"strike_resolved", &"formation_destroyed"])
	assert_true(events[0]["target_destroyed"])
	assert_true(state.get_formation(&"r") == null)


# --- round boundary ---


func test_resupply_and_repair_at_round_boundary() -> void:
	var op := Strikes._definition()
	op.installations.append(Strikes._placement(&"hurt", &"depot", 1, Vector2i(5, 0)))
	op.installations.append(Strikes._placement(&"dead", &"depot", 1, Vector2i(5, 1)))
	op.installations.append(Strikes._placement(&"almost", &"depot", 1, Vector2i(4, 0)))
	var state := Strikes._state(op)
	state.get_installation(&"hurt").integrity = 60
	state.get_installation(&"dead").integrity = 0
	state.get_installation(&"almost").integrity = 98
	var sim := OperationalSimulation.new(state)
	var seen: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: seen.append(e))
	var rng_before := state.rng.state
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(StrikeRules.stock(state, 1, &"geran_2"), 16, "half a round: nothing yet")
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(StrikeRules.stock(state, 0, &"jassm_er"), 9)
	assert_eq(StrikeRules.stock(state, 1, &"kalibr"), 9)
	assert_eq(StrikeRules.stock(state, 1, &"geran_2"), 18)
	assert_eq(state.get_installation(&"hurt").integrity, 65)
	assert_eq(state.get_installation(&"dead").integrity, 0)
	assert_eq(state.get_installation(&"almost").integrity, 100)
	assert_eq(state.get_installation(&"a1").integrity, 100)
	assert_eq(state.rng.state, rng_before, "no draws")
	var causes: Array = (
		seen
		. filter(func(e: Dictionary) -> bool: return e["type"] == &"installation_changed")
		. map(func(e: Dictionary) -> Variant: return e["cause"])
	)
	assert_eq(causes, [&"repair", &"repair"])
	var sources: Array = (
		seen
		. filter(func(e: Dictionary) -> bool: return e["type"] == &"strike_stock_changed")
		. map(func(e: Dictionary) -> Variant: return "%d%s" % [e["player"], e["means"]])
	)
	assert_eq(sources, ["0jassm_er", "1kalibr", "1geran_2"])


func test_strikes_left_reset_for_next_player() -> void:
	var state := Strikes._state()
	state.strikes_left = 0
	assert_true(OperationalSimulation.new(state).execute(EndOperationalTurnCommand.new()))
	assert_eq(state.strikes_left, 2)


# --- mirror (TASK-141a: no rule names a side) ---


## The same weapon-neutral strike for player 0 and player 1 on mirrored targets gives the same
## result and draws the same numbers.
func test_mirrored_strike_gives_the_same_result() -> void:
	var results: Array = []
	for player in 2:
		var state := Strikes._state()
		var target_id := &"a1" if player == 0 else &"pl_air"
		var target := StrikeRules.find_target(state, player, target_id)
		var rng_before := state.rng.state
		var events := StrikeRules.resolve(state, player, &"cruise", target, 3)
		var resolved := events[0].duplicate()
		resolved.erase("player")
		resolved.erase("target")
		results.append([resolved, state.get_installation(target_id).integrity])
		var reference := RandomNumberGenerator.new()
		reference.state = rng_before
		for i in 6:
			reference.randi_range(1, 100)
		assert_eq(state.rng.state, reference.state, "2 draws per missile, player %d" % player)
	assert_eq(results[0], results[1])


## A strike with a named shipped weapon draws exactly 2 numbers per missile.
func test_named_weapon_draws_two_per_missile() -> void:
	var state := Strikes._state()
	var target := StrikeRules.find_target(state, 1, &"pl_air")
	var reference := RandomNumberGenerator.new()
	reference.state = state.rng.state
	for i in 4:
		reference.randi_range(1, 100)
	StrikeRules.resolve(state, 1, &"iskander_m", target, 2)
	assert_eq(state.rng.state, reference.state)
