extends TestCase
## Air defence and SEAD (TASK-098a): the three types, per-site coverage by weapon class, layered
## interception, suppression by a hit and its countdown, the shipped operation.

const Strikes := preload("res://tests/unit/test_strikes.gd")
const TARGET := Vector2i(6, 0)  # the airfield `a1` of Strikes._definition()
## Site hexes, all within 4 of TARGET: short, medium, long.
const SHORT_AT := Vector2i(7, 0)
const MEDIUM_AT := Vector2i(5, 0)
const LONG_AT := Vector2i(4, 1)

# --- data ---


func _type(id := &"x") -> AirDefenceDefinition:
	var type := AirDefenceDefinition.new()
	type.id = id
	type.radius_hexes = 3
	for weapon_class in StrikeMeansDefinition.WEAPON_CLASSES:
		type.intercept_pct[weapon_class] = 10
	return type


func test_shipped_types() -> void:
	var table := {
		&"mobile": [1, [20, 0, 0, 15, 35, 35]],
		&"short": [4, [50, 0, 0, 40, 60, 60]],
		&"medium": [10, [60, 20, 10, 50, 60, 50]],
		&"long": [30, [55, 50, 30, 50, 40, 30]],
	}
	assert_eq(AirDefenceDefinition.SHIPPED.size(), 4)
	assert_eq(AirDefenceDefinition.shipped().size(), 4, "unique ids")
	for id: StringName in table:
		var type := AirDefenceDefinition.find(id)
		assert_true(type != null, String(id))
		assert_eq(type.id, id)
		assert_eq(type.problem(), "", String(id))
		assert_true(type.display_name != "" and type.examples != "", String(id))
		assert_eq(type.radius_hexes, table[id][0], String(id))
		for index in StrikeMeansDefinition.WEAPON_CLASSES.size():
			var weapon_class := StrikeMeansDefinition.WEAPON_CLASSES[index]
			assert_eq(
				type.intercept_pct[weapon_class], table[id][1][index], "%s %s" % [id, weapon_class]
			)
	assert_true(AirDefenceDefinition.find(&"nope") == null)
	assert_true(AirDefenceDefinition.find(&"") == null)


func test_definition_problems() -> void:
	assert_eq(_type().problem(), "")
	var cases := {
		"empty id": func(t: AirDefenceDefinition) -> void: t.id = &"",
		"radius": func(t: AirDefenceDefinition) -> void: t.radius_hexes = 0,
		"missing class": func(t: AirDefenceDefinition) -> void: t.intercept_pct.erase(&"drone"),
		"unknown class": func(t: AirDefenceDefinition) -> void: t.intercept_pct[&"ufo"] = 10,
		"above 100": func(t: AirDefenceDefinition) -> void: t.intercept_pct[&"drone"] = 101,
		"below 0": func(t: AirDefenceDefinition) -> void: t.intercept_pct[&"drone"] = -1,
	}
	for label: String in cases:
		var type := _type()
		(cases[label] as Callable).call(type)
		assert_true(type.problem() != "", label)


func test_placement_and_installation_defaults() -> void:
	assert_eq(InstallationPlacement.new().ad_type, &"")
	assert_eq(OperationDefinition.new().suppression_rounds, 2)
	var installation := Installation.new()
	assert_eq(installation.suppressed_rounds, 0)
	assert_false(installation.suppressed())
	installation.suppressed_rounds = 1
	assert_true(installation.suppressed())


func test_definition_rejections() -> void:
	var cases := {
		"empty ad_type": func(op: OperationDefinition) -> void: op.installations[3].ad_type = &"",
		"unknown ad_type":
		func(op: OperationDefinition) -> void: op.installations[3].ad_type = &"huge",
		"ad_type on an airfield":
		func(op: OperationDefinition) -> void: op.installations[0].ad_type = &"short",
		"suppression rounds": func(op: OperationDefinition) -> void: op.suppression_rounds = 0,
	}
	for label: String in cases:
		var op := Strikes._definition()
		op.installations.append(Strikes._placement(&"ad", &"air_defence", 1, SHORT_AT, &"short"))
		(cases[label] as Callable).call(op)
		assert_true(Strikes._state(op) == null, label)
	var ok := Strikes._definition()
	ok.installations.append(Strikes._placement(&"ad", &"air_defence", 1, SHORT_AT, &"short"))
	assert_true(Strikes._state(ok) != null)


func test_snapshot_carries_ad_type_and_suppression() -> void:
	var op := Strikes._definition()
	op.installations.append(Strikes._placement(&"ad", &"air_defence", 1, SHORT_AT, &"short"))
	var state := Strikes._state(op)
	state.get_installation(&"ad").suppressed_rounds = 2
	for entry: Dictionary in state.snapshot()["installations"]:
		if entry["id"] == "ad":
			assert_eq(entry["ad_type"], "short")
			assert_eq(entry["suppressed_rounds"], 2)
		else:
			assert_eq(entry["ad_type"], "")
			assert_eq(entry["suppressed_rounds"], 0)


# --- mobile air defence of formations ---


func test_a_formation_with_mobile_air_defence_intercepts_around_itself() -> void:
	var state := Strikes._state()
	# Formation `r` (Russia, motor rifle battalion with `mobile`) stands next to the airfield.
	var r := state.get_formation(&"r")
	r.definition.ad_type = &"mobile"
	assert_eq(load("res://data/formations/ru_motor_rifle_battalion.tres").ad_type, &"mobile")
	var near := Hex.neighbors(r.coord)[0]
	var sites := StrikeRules.interceptors(state, 0, &"strike_drone", near)
	assert_eq(sites.size(), 1)
	assert_eq(sites[0]["id"], &"r")
	assert_eq(sites[0]["p"], 35, "full strength, drone 35 %")
	assert_eq(StrikeRules.interceptors(state, 1, &"strike_drone", near).size(), 0, "own side")
	r.companies[0].strength = 1
	var weaker := StrikeRules.interceptors(state, 0, &"strike_drone", r.coord)
	assert_true(int(weaker[0]["p"]) < 35, "a battered formation intercepts less")
	var far := r.coord + Vector2i(3, 0)
	assert_eq(StrikeRules.interceptors(state, 0, &"strike_drone", far).size(), 0, "out of reach")
	assert_eq(StrikeRules.interceptors(state, 0, &"ballistic", r.coord).size(), 0, "0 % class")


# --- interception chance ---


## A state whose sites belong to `owner`: {id: [type, coord]} in this order; the striker is the
## other player.
func _sites(owner: int, sites: Array) -> OperationalState:
	var op := Strikes._definition()
	for site: Array in sites:
		op.installations.append(
			Strikes._placement(site[0], &"air_defence", owner, site[2], site[1])
		)
	return Strikes._state(op)


func _chance(state: OperationalState, owner: int, weapon: StringName, at := TARGET) -> int:
	return StrikeRules.interception_chance(state, 1 - owner, weapon, at)


func test_worked_examples_both_ways() -> void:
	for owner in 2:
		var short := _sites(owner, [[&"s", &"short", SHORT_AT]])
		assert_eq(_chance(short, owner, &"kalibr"), 50, "short vs kalibr")
		assert_eq(_chance(short, owner, &"kinzhal"), 0, "aeroballistic 0")
		var medium := _sites(owner, [[&"m", &"medium", MEDIUM_AT]])
		assert_eq(_chance(medium, owner, &"iskander_m"), 8, "20 x 40 / 100, x 40 / 100")
		var long := _sites(owner, [[&"l", &"long", LONG_AT]])
		long.get_installation(&"l").integrity = 100
		assert_eq(_chance(long, owner, &"geran_2"), 60, "40 x 150 / 100")
		var pair := _sites(owner, [[&"m", &"medium", MEDIUM_AT], [&"l", &"long", LONG_AT]])
		pair.get_installation(&"l").integrity = 50
		assert_eq(_chance(pair, owner, &"jassm_er"), 49, "60 + 27 -> 70, x 70 / 100")
		var trio := _sites(
			owner,
			[[&"s", &"short", SHORT_AT], [&"m", &"medium", MEDIUM_AT], [&"l", &"long", LONG_AT]]
		)
		assert_eq(_chance(trio, owner, &"kalibr"), 90, "91 capped at 90")
		assert_eq(_chance(trio, owner, &"jassm_er"), 63)
		trio.get_installation(&"m").suppressed_rounds = 2
		assert_eq(_chance(trio, owner, &"jassm_er"), 53, "77 x 70 / 100")


func test_radius_destroyed_own_and_unknown() -> void:
	var state := _sites(1, [[&"s", &"short", SHORT_AT]])
	assert_eq(_chance(state, 1, &"kalibr", Vector2i(11, 0)), 50, "exactly the radius")
	assert_eq(_chance(state, 1, &"kalibr", Vector2i(12, 0)), 0, "radius + 1")
	assert_eq(_chance(state, 1, &"nope"), 0, "unknown weapon")
	assert_eq(StrikeRules.interception_chance(state, 1, &"kalibr", TARGET), 0, "own site")
	state.get_installation(&"s").integrity = 0
	assert_eq(_chance(state, 1, &"kalibr"), 0, "destroyed")


func test_interceptors_list() -> void:
	var state := _sites(1, [[&"s", &"short", SHORT_AT], [&"l", &"long", LONG_AT]])
	var ids: Array = StrikeRules.interceptors(state, 0, &"kalibr", TARGET).map(
		func(site: Dictionary) -> Variant: return site["id"]
	)
	assert_eq(ids, [&"s", &"l"])
	state.get_installation(&"s").suppressed_rounds = 1
	assert_eq(StrikeRules.interceptors(state, 0, &"kalibr", TARGET).size(), 1)
	ids = StrikeRules.interceptors(state, 0, &"kinzhal", TARGET).map(
		func(site: Dictionary) -> Variant: return site["id"]
	)
	assert_eq(ids, [&"l"], "a site with 0 against the class is not counted")


# --- coverage ---


func test_coverage() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var nato := StrikeRules.coverage(state, 0)
	assert_eq(nato.size(), 3)
	var radii: Array = nato.map(func(c: Dictionary) -> Variant: return c["radius_hexes"])
	radii.sort()
	assert_eq(radii, [4, 10, 30])
	assert_eq(nato[0]["id"], &"nato_ad_bialystok")
	assert_eq(nato[0]["ad_type"], &"long")
	assert_eq(nato[0]["integrity"], 100)
	assert_false(nato[0]["suppressed"])
	assert_eq(nato[0]["suppressed_rounds"], 0)
	state.get_installation(&"nato_ad_suwalki").suppressed_rounds = 2
	state.get_installation(&"nato_ad_olsztyn").integrity = 0
	var after := StrikeRules.coverage(state, 0)
	assert_eq(after.size(), 2, "destroyed sites leave the list")
	assert_true(after[1]["suppressed"])
	assert_eq(after[1]["suppressed_rounds"], 2)
	assert_eq(StrikeRules.coverage(state, 1).size(), 3)


# --- suppression ---


## A state for the sequence: player 0 at level 3, an enemy medium site next to the airfield `a1`
## and a test weapon with JASSM-ER's numbers but accuracy 100, damage 40.
func _sead_state(seed_value: int) -> OperationalState:
	var op := Strikes._definition()
	op.installations.append(Strikes._placement(&"ad", &"air_defence", 1, SHORT_AT, &"medium"))
	var state := Strikes._state(op, seed_value)
	state.escalation_level = 3
	var means := Strikes._means(&"jassm", 100, 70, 40, 200)
	state.strike_means[&"jassm"] = means
	return state


## A seed whose first interception draw does not exceed `p` percent (so the missile gets through).
func _seed_without_interception(p: int) -> int:
	for seed_value in range(1, 200):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		if rng.randi_range(1, 100) > p:
			return seed_value
	return 1


func _strike(state: OperationalState, target_id: StringName) -> Array[Dictionary]:
	return StrikeRules.resolve(state, 0, &"jassm", StrikeRules.find_target(state, 0, target_id), 1)


func test_sequence_sead_then_airfield() -> void:
	var state := _sead_state(_seed_without_interception(42))
	var ad := state.get_installation(&"ad")
	assert_eq(StrikeRules.interception_chance(state, 0, &"jassm", TARGET), 42)
	var events := _strike(state, &"ad")
	assert_eq(events[0]["hits"], 1)
	assert_eq(events[0]["interceptor_ids"], [&"ad"])
	assert_eq(ad.integrity, 60)
	assert_eq(ad.suppressed_rounds, 2)
	var types := Strikes._types(events)
	assert_eq(types, [&"strike_resolved", &"installation_changed", &"installation_suppressed"])
	assert_eq(events[2]["id"], &"ad")
	assert_eq([events[2]["before"], events[2]["after"], events[2]["cause"]], [0, 2, &"strike"])
	var next := _strike(state, &"a1")
	assert_eq(next[0]["p_intercept"], 0)
	assert_eq(next[0]["interceptor_ids"], [])
	StrikeRules.end_round(state)
	StrikeRules.end_round(state)
	assert_eq(ad.suppressed_rounds, 0)
	assert_eq(ad.integrity, 70)
	assert_eq(StrikeRules.interception_chance(state, 0, &"jassm", TARGET), 29)


func test_refresh_never_stacks_and_event_on_every_hit() -> void:
	var state := _sead_state(_seed_without_interception(42))
	var ad := state.get_installation(&"ad")
	ad.integrity = 100
	state.strike_means[&"jassm"].damage = 10
	var events := _strike(state, &"ad")
	assert_eq(events[0]["hits"], 1)
	assert_eq(ad.suppressed_rounds, 2)
	# Hit again at once: the site is silent now, so the missile cannot be intercepted.
	events = _strike(state, &"ad")
	assert_eq(ad.suppressed_rounds, 2, "refresh, not 4")
	assert_eq(Strikes._types(events).count(&"installation_suppressed"), 1)
	assert_eq([events[2]["before"], events[2]["after"]], [2, 2])


func test_countdown_trace_and_refresh_at_one() -> void:
	var state := _sead_state(1)
	var ad := state.get_installation(&"ad")
	ad.suppressed_rounds = 2
	var events := StrikeRules.end_round(state)
	assert_eq(ad.suppressed_rounds, 1)
	var lapses := events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"installation_suppressed"
	)
	assert_eq(lapses.size(), 1)
	assert_eq([lapses[0]["before"], lapses[0]["after"], lapses[0]["cause"]], [2, 1, &"lapse"])
	StrikeRules.resolve(state, 0, &"sure", StrikeRules.find_target(state, 0, &"ad"), 1)
	assert_eq(ad.suppressed_rounds, 2, "a hit at 1 refreshes to 2")
	StrikeRules.end_round(state)
	StrikeRules.end_round(state)
	assert_eq(ad.suppressed_rounds, 0)
	var quiet := StrikeRules.end_round(state)
	assert_eq(
		quiet.filter(func(e: Dictionary) -> bool: return e["type"] == &"installation_suppressed"),
		[],
		"nothing to count down at 0"
	)


func test_no_suppression_without_a_hit_or_on_destruction_or_other_classes() -> void:
	var state := _sead_state(1)
	state.strike_means[&"never"] = Strikes._means(&"never", 0)
	state.strike_stock[0][&"never"] = 5
	var ad := state.get_installation(&"ad")
	var events := StrikeRules.resolve(
		state, 0, &"never", StrikeRules.find_target(state, 0, &"ad"), 2
	)
	assert_eq(Strikes._types(events), [&"strike_resolved"])
	assert_eq(ad.suppressed_rounds, 0)
	ad.integrity = 30
	state.strike_means[&"sure"].damage = 40
	events = StrikeRules.resolve(state, 0, &"sure", StrikeRules.find_target(state, 0, &"ad"), 1)
	assert_true(ad.destroyed())
	assert_eq(ad.suppressed_rounds, 0)
	assert_false(Strikes._types(events).has(&"installation_suppressed"))
	events = StrikeRules.resolve(state, 0, &"sure", StrikeRules.find_target(state, 0, &"a1"), 1)
	assert_false(Strikes._types(events).has(&"installation_suppressed"))
	# A destroyed site is silent forever and repair does not revive it.
	for i in 5:
		StrikeRules.end_round(state)
	assert_true(ad.destroyed())
	assert_eq(StrikeRules.interception_chance(state, 0, &"jassm", TARGET), 0)


func test_suppressed_site_still_repairs_is_a_target_and_keeps_its_zone() -> void:
	var state := _sead_state(1)
	var ad := state.get_installation(&"ad")
	ad.integrity = 50
	ad.suppressed_rounds = 2
	assert_eq(StrikeRules.target_problem(state, 0, &"ad"), "")
	StrikeRules.end_round(state)
	assert_eq(ad.integrity, 55)
	var entry := StrikeRules.coverage(state, 1)[0]
	assert_true(entry["suppressed"])
	assert_eq(entry["radius_hexes"], 10)


func test_capability_ignores_suppression() -> void:
	var state := _sead_state(1)
	var before := StrikeRules.capability(state, 1, &"airfield")
	state.get_installation(&"ad").suppressed_rounds = 2
	assert_eq(StrikeRules.capability(state, 1, &"airfield"), before)


# --- draws ---


func test_draw_order_is_unchanged() -> void:
	var state := _sites(1, [[&"s", &"short", SHORT_AT], [&"l", &"long", LONG_AT]])
	state.escalation_level = 3
	var reference := RandomNumberGenerator.new()
	reference.seed = 1
	for i in 6:
		reference.randi_range(1, 100)
	StrikeRules.resolve(state, 0, &"kalibr", StrikeRules.find_target(state, 0, &"a1"), 3)
	assert_eq(state.rng.state, reference.state, "2 x count draws whatever the sites")


func test_chances_are_fixed_before_the_salvo() -> void:
	var state := _sead_state(1)
	state.strike_means[&"jassm"].interceptability_pct = 100
	var events := _strike(state, &"ad")
	assert_eq(events[0]["p_intercept"], 60, "the target site counted at full strength")


# --- shipped operation ---


func test_shipped_sites() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var expected := {
		&"nato_ad_bialystok": [0, &"long"],
		&"nato_ad_suwalki": [0, &"short"],
		&"nato_ad_olsztyn": [0, &"medium"],
		&"ru_ad_kaliningrad": [1, &"long"],
		&"ru_ad_grodno": [1, &"medium"],
		&"ru_ad_chernyakhovsk": [1, &"short"],
	}
	for id: StringName in expected:
		var installation := state.get_installation(id)
		assert_true(installation != null, String(id))
		assert_eq(installation.class_id, &"air_defence")
		assert_eq(installation.owner, expected[id][0], String(id))
		assert_eq(installation.ad_type, expected[id][1], String(id))
		assert_true(state.country_at(installation.coord) != &"", String(id))
	var occupied := {}
	for installation in state.installations:
		assert_false(occupied.has(installation.coord), "one installation per hex")
		occupied[installation.coord] = true
	for player in 2:
		var types: Array = StrikeRules.coverage(state, player).map(
			func(c: Dictionary) -> Variant: return c["ad_type"]
		)
		assert_eq(types.size(), 3)
		assert_true(types.has(&"long") and types.has(&"medium") and types.has(&"short"))


func test_shipped_effect() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	for player in 2:
		var weapons: Array = state.strike_stock[player].keys()
		var inside := &"ru_c2_kaliningrad" if player == 0 else &"nato_c2_bialystok"
		var outside := &"ru_airfield_lida" if player == 0 else &"nato_depot_kaunas"
		for weapon: StringName in weapons:
			if not (state.strike_means[weapon] as StrikeMeansDefinition).usable_by(player):
				continue
			var in_coord := state.get_installation(inside).coord
			var out_coord := state.get_installation(outside).coord
			assert_true(
				StrikeRules.interception_chance(state, player, weapon, in_coord) > 0,
				"%s on %s" % [weapon, inside]
			)
			assert_eq(
				StrikeRules.interception_chance(state, player, weapon, out_coord),
				0,
				"%s on %s" % [weapon, outside]
			)


func test_destroying_a_suppressed_site_clears_its_suppression() -> void:
	var state := _sead_state(1)
	var ad := state.get_installation(&"ad")
	ad.suppressed_rounds = 2
	ad.integrity = 30
	state.strike_means[&"sure"].damage = 40
	var events := StrikeRules.resolve(
		state, 0, &"sure", StrikeRules.find_target(state, 0, &"ad"), 1
	)
	assert_true(ad.destroyed())
	assert_eq(ad.suppressed_rounds, 0)
	assert_true(Strikes._types(events).has(&"installation_suppressed"))
	var quiet := StrikeRules.end_round(state)
	assert_false(Strikes._types(quiet).has(&"installation_suppressed"))
