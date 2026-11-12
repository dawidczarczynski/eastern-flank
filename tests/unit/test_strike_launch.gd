extends TestCase
## Launch point and launcher kind of a deep strike (TASK-147, GDD "Deep strikes"): the
## `launcher_kind` of every shipped weapon, `StrikeRules.launch_origin` (own site of the matching
## kind nearest the target, else the standoff point) and the `strike_launched` fields.

const Strikes := preload("res://tests/unit/test_strikes.gd")
const A1 := Vector2i(6, 0)
const PL_AIR := Vector2i(0, 1)
## Shipped weapon -> [launcher_kind, platform text (unchanged by TASK-147)].
const KINDS := {
	&"iskander_m": [&"launcher", "truck launcher"],
	&"kinzhal": [&"fighter", "fighter-launched (MiG-31K)"],
	&"kalibr": [&"ship", "ship / coastal launcher"],
	&"kh101": [&"bomber", "bomber-launched (Tu-95MS / Tu-160)"],
	&"geran_2": [&"drone_site", "truck launcher"],
	&"jassm_er": [&"fighter", "fighter-launched (F-16 Block 52+)"],
	&"storm_shadow": [&"fighter", "fighter-launched (allied)"],
	&"atacms": [&"launcher", "truck launcher (HIMARS)"],
	&"prsm": [&"launcher", "truck launcher (HIMARS)"],
	&"homar_k": [&"launcher", "truck launcher (K239 Chunmoo)"],
	&"warmate": [&"drone_site", "tube launcher"],
	&"tomahawk": [&"ship", "ship / submarine-launched (US Navy)"],
}


static func _means(id: StringName, kind: StringName, range_hexes := 50) -> StrikeMeansDefinition:
	var means := Strikes._means(id, 100, 100, 35, range_hexes)
	means.launcher_kind = kind
	return means


## The strip of test_strikes (Poland and Lithuania own to player 0) at open war, with the
## made-up weapons `air`, `sea`, `tel`, `uav` of each launcher kind.
static func _state(op: OperationDefinition = null) -> OperationalState:
	var state := Strikes._state(op)
	state.escalation_level = 2
	for pair: Array in [
		[&"air", &"fighter"], [&"sea", &"ship"], [&"tel", &"launcher"], [&"uav", &"drone_site"]
	]:
		state.strike_means[pair[0]] = _means(pair[0], pair[1])
		state.strike_stock[0][pair[0]] = 10
	return state


## A sea hex north of the strip: water that belongs to no country, next to (1, 0) and (2, 0).
static func _add_sea(state: OperationalState) -> void:
	state.grid.set_terrain(Vector2i(2, -1), Terrain.Type.WATER)


func test_every_shipped_weapon_has_its_launcher_kind_and_keeps_its_platform() -> void:
	assert_eq(KINDS.size(), StrikeMeansDefinition.SHIPPED.size())
	for id: StringName in StrikeMeansDefinition.SHIPPED:
		var means := StrikeMeansDefinition.find(id)
		assert_true(StrikeMeansDefinition.LAUNCHER_KINDS.has(means.launcher_kind), String(id))
		assert_eq(means.launcher_kind, KINDS[id][0], String(id))
		assert_eq(means.platform, KINDS[id][1], String(id))
		assert_eq(means.problem(), "", String(id))
		var text := FileAccess.get_file_as_string(StrikeMeansDefinition.DIR + String(id) + ".tres")
		assert_true(text.contains('launcher_kind = &"'), "set in the file: %s" % id)


func test_launcher_kinds_and_problem() -> void:
	assert_eq(
		StrikeMeansDefinition.LAUNCHER_KINDS,
		(
			[&"fighter", &"bomber", &"ship", &"submarine", &"launcher", &"drone_site"]
			as Array[StringName]
		)
	)
	var means := _means(&"x", &"submarine")
	assert_eq(means.problem(), "")
	means.launcher_kind = &""
	assert_true(means.problem().contains("launcher_kind"))
	means.launcher_kind = &"catapult"
	assert_true(means.problem().contains("launcher_kind"))


func test_aircraft_fly_from_the_own_airfield_nearest_the_target() -> void:
	var state := _state()
	assert_eq(StrikeRules.launch_origin(state, 0, &"air", A1), PL_AIR)
	var rng_before := state.rng.state
	var snapshot := state.snapshot()
	assert_eq(StrikeRules.launch_origin(state, 0, &"air", A1), PL_AIR, "deterministic")
	assert_eq(state.rng.state, rng_before, "no rng draw")
	assert_eq(state.snapshot(), snapshot, "pure")


func test_a_destroyed_or_out_of_range_airfield_falls_back_to_the_standoff_point() -> void:
	var state := _state()
	var standoff := StrikeLaunch.standoff_origin(state, 0, A1, 50)
	state.get_installation(&"pl_air").integrity = 0
	assert_eq(StrikeRules.launch_origin(state, 0, &"air", A1), standoff)
	state.get_installation(&"pl_air").integrity = 50
	state.strike_means[&"air"].range_hexes = 5
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"air", A1),
		StrikeLaunch.standoff_origin(state, 0, A1, 5),
		"the airfield is 6 hexes away"
	)


func test_the_enemy_airfield_is_never_a_launch_site() -> void:
	var state := _state()
	state.get_installation(&"pl_air").owner = 1
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"air", A1),
		StrikeLaunch.standoff_origin(state, 0, A1, 50)
	)


func test_ground_launchers_fire_from_the_own_artillery_formation_nearest_the_target() -> void:
	var op := Strikes._definition()
	op.formations.append(
		Strikes._formation(&"far", "res://data/formations/pl_mlrs_squadron.tres", 0, Vector2i(0, 0))
	)
	op.formations.append(
		Strikes._formation(
			&"near", "res://data/formations/pl_mlrs_squadron.tres", 0, Vector2i(3, 1)
		)
	)
	var state := _state(op)
	assert_eq(StrikeRules.launch_origin(state, 0, &"tel", A1), Vector2i(3, 1))
	assert_eq(
		StrikeRules.launch_origin(state, 1, &"tel", PL_AIR),
		StrikeLaunch.standoff_origin(state, 1, PL_AIR, 50),
		"the enemy's artillery is not player 1's; its own formation is not artillery"
	)


func test_ground_launchers_without_an_artillery_formation_use_the_standoff_point() -> void:
	var state := _state()
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"tel", A1),
		StrikeLaunch.standoff_origin(state, 0, A1, 50),
		"the mechanised battalion is no launcher"
	)


func test_drones_have_no_launch_site_yet_and_use_the_standoff_point() -> void:
	var state := _state()
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"uav", A1),
		StrikeLaunch.standoff_origin(state, 0, A1, 50)
	)


func _is_sea(state: OperationalState, hex: Vector2i) -> bool:
	return (
		state.grid.has_tile(hex)
		and state.grid.get_terrain(hex) == Terrain.Type.WATER
		and not state.country_map.has(hex)
	)


func test_ships_fire_from_the_sea_off_the_own_coast() -> void:
	var state := _state()
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"sea", A1),
		StrikeLaunch.standoff_origin(state, 0, A1, 50),
		"no sea"
	)
	_add_sea(state)
	var origin := StrikeRules.launch_origin(state, 0, &"sea", A1)
	assert_eq(origin, Vector2i(2, -1))
	assert_true(_is_sea(state, origin), "a ship's origin is a water hex of no country")
	assert_eq(StrikeRules.launch_origin(state, 0, &"sea", A1), origin, "deterministic")
	state.country_map[Vector2i(2, -1)] = &"poland"
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"sea", A1),
		StrikeLaunch.standoff_origin(state, 0, A1, 50),
		"water inside a country is a lake, not the sea"
	)


func test_the_sea_next_to_the_own_coast_beats_sea_nearer_the_target() -> void:
	var state := _state()
	_add_sea(state)
	state.grid.set_terrain(Vector2i(5, -1), Terrain.Type.WATER)
	var origin := StrikeRules.launch_origin(state, 0, &"sea", A1)
	assert_eq(origin, Vector2i(2, -1), "(5, -1) is nearer the target but off the enemy coast")
	state.strike_means[&"sea"].range_hexes = 4
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"sea", A1),
		Vector2i(5, -1),
		"(2, -1) is out of range: the in-range sea hex nearest the own coast"
	)
	state.strike_means[&"sea"].range_hexes = 1
	assert_eq(
		StrikeRules.launch_origin(state, 0, &"sea", A1),
		StrikeLaunch.standoff_origin(state, 0, A1, 1),
		"no sea in range"
	)


func test_sea_away_from_the_own_coast_is_reached_over_the_map() -> void:
	var state := _state()
	state.grid.set_terrain(Vector2i(5, -1), Terrain.Type.PLAINS)
	state.grid.set_terrain(Vector2i(6, -2), Terrain.Type.WATER)
	var origin := StrikeRules.launch_origin(state, 0, &"sea", A1)
	assert_eq(origin, Vector2i(6, -2))
	assert_true(_is_sea(state, origin))


func test_unknown_means_uses_the_border_hex() -> void:
	var state := _state()
	assert_eq(StrikeRules.launch_origin(state, 0, &"nope", A1), StrikeLaunch.origin(state, 0, A1))


func test_standoff_and_border_match_the_strike_trail() -> void:
	var state := _state()
	for range_hexes in [1, 5, 6, 50, 500]:
		assert_eq(
			StaffMapStrikeTrail.launch_origin(state, 0, A1, range_hexes),
			StrikeLaunch.standoff_origin(state, 0, A1, range_hexes)
		)
	assert_eq(StaffMapStrikeTrail.origin(state, 0, A1), StrikeLaunch.origin(state, 0, A1))


func test_strike_launched_carries_launcher_kind_and_origin() -> void:
	var state := _state()
	var sim := OperationalSimulation.new(state)
	var seen: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: seen.append(e))
	assert_true(sim.execute(StrikeCommand.new(&"jassm_er", &"a1", 1)))
	var is_launch := func(e: Dictionary) -> bool: return e["type"] == &"strike_launched"
	var launched: Dictionary = seen.filter(is_launch)[0]
	assert_eq(launched["launcher_kind"], "fighter")
	assert_true(launched["launcher_kind"] is String)
	assert_eq(launched["origin"], PL_AIR)


func test_each_launcher_kind_in_the_event() -> void:
	var expected := {
		&"air": ["fighter", PL_AIR],
		&"sea": ["ship", Vector2i(2, -1)],
		&"uav": ["drone_site", null],
		&"tel": ["launcher", null],
	}
	for means_id: StringName in expected:
		var state := _state()
		_add_sea(state)
		var events := StrikeCommand.new(means_id, &"a1", 1).apply(state)
		var launched: Dictionary = events[1]
		assert_eq(launched["type"], &"strike_launched")
		assert_eq(launched["launcher_kind"], expected[means_id][0], String(means_id))
		var origin: Variant = expected[means_id][1]
		if origin == null:
			origin = StrikeLaunch.standoff_origin(_state(), 0, A1, 50)
		assert_eq(launched["origin"], origin, String(means_id))


func test_same_state_and_command_give_the_same_origin_and_rng() -> void:
	var results: Array = []
	for i in 2:
		var state := _state()
		var events := StrikeCommand.new(&"air", &"a1", 2).apply(state)
		results.append([events[1]["origin"], state.rng.state, events])
	assert_eq(results[0], results[1])


func test_launch_origin_draws_nothing_so_the_rng_after_a_strike_is_unchanged() -> void:
	var state := _state()
	var rng_before := state.rng.state
	var probe := RandomNumberGenerator.new()
	probe.state = rng_before
	for i in 4:
		probe.randi_range(1, 100)
	StrikeCommand.new(&"air", &"a1", 2).apply(state)
	assert_eq(state.rng.state, probe.state, "still exactly 2 draws per missile")
