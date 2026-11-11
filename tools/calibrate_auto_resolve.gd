extends SceneTree
## Compares AutoResolve with played AI-vs-AI battles of the same setups (TASK-128). Run via
## tools/calibrate_auto_resolve.sh. Prints per case: wins P0 / P1 / draws and mean strength lost
## by each side, for auto-resolve and for the played battle, and the largest win-share gap.

const Fixtures := preload("res://tests/fixtures.gd")
const CASES := ["crush", "mirror", "fortress", "siege", "caught"]
const POLAND_ROWS := [&"pl_mech_infantry", &"pl_mech_infantry", &"pl_mech_infantry", &"m1a2_sepv3"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var count := 50
	var max_turns := 60
	var only := ""
	var variants: Array[AutoResolveRules] = [AutoResolveRules.shipped()]
	for arg in args:
		if arg.begins_with("--seeds="):
			count = int(arg.get_slice("=", 1))
		elif arg.begins_with("--max-turns="):
			max_turns = int(arg.get_slice("=", 1))
		elif arg.begins_with("--rules="):
			variants = []
			for pair in arg.get_slice("=", 1).split(","):
				var rules := AutoResolveRules.new()
				rules.default_rounds = int(pair.get_slice(":", 0))
				rules.break_share = int(pair.get_slice(":", 1))
				variants.append(rules)
		elif arg.begins_with("--case="):
			only = arg.get_slice("=", 1)
	var worst := 0.0
	for kind: String in CASES:
		if only != "" and only != kind:
			continue
		var played := _tally()
		var autos: Array[Dictionary] = []
		for rules in variants:
			autos.append(_tally())
		for s in count:
			var setup := _case(kind, s + 1)
			for i in variants.size():
				_add(autos[i], AutoResolve.resolve(setup, variants[i]))
			_add_played(played, setup, max_turns)
		print("%-9s played %s" % [kind, _line(played)])
		for i in variants.size():
			var gap := _gap(autos[i], played, count)
			worst = maxf(worst, gap)
			print(
				(
					"%-9s auto %2d:%3d %s   gap %.0f points"
					% [
						"",
						variants[i].default_rounds,
						variants[i].break_share,
						_line(autos[i]),
						gap
					]
				)
			)
	print("Largest win-share gap (over every variant): %.0f points" % worst)
	quit()


## kind: "crush", "mirror", "fortress" (TASK-120), "siege" (8 v 4 attackers vs hills defence) and
## "caught" (defender caught on the march on plains).
func _case(kind: String, seed_value: int) -> BattleSetup:
	var pl: Array[StringName] = [&"poland", &"poland"]
	var advance := [&"advance", 0]
	var rows: Array = []
	match kind:
		"crush":
			pl = [&"poland", &"russia"]
			for t in [&"m1a2_sepv3", &"m1a2_sepv3", &"m1a2_sepv3", &"pl_mech_infantry"]:
				rows.append([0, t, 10])
			rows.append([1, &"ru_motor_rifle", 10])
			return _build(pl, rows, [advance, [&"defend", 1]], &"plains", seed_value)
		"siege":
			for i in 2:
				for t in POLAND_ROWS:
					rows.append([0, t, 10])
			for t in POLAND_ROWS:
				rows.append([1, t, 10])
			return _build(pl, rows, [advance, [&"defend", 1]], &"hills", seed_value)
		"caught":
			for player in 2:
				for t in POLAND_ROWS:
					rows.append([player, t, 10])
			return _build(pl, rows, [advance, [&"march", -1]], &"plains", seed_value)
	for player in 2:
		for t in POLAND_ROWS:
			rows.append([player, t, 10])
	if kind == "fortress":
		return _build(pl, rows, [advance, [&"defend", 1]], &"hills", seed_value)
	return _build(pl, rows, [advance, advance], &"plains", seed_value)


func _build(
	factions: Array[StringName], rows: Array, postures: Array, terrain: StringName, seed_value: int
) -> BattleSetup:
	var setup := Fixtures.auto_setup(factions, rows, postures, terrain, seed_value)
	var used := [0, 0]
	for company in setup.companies:
		var slots: Array = Scenario.FRONT_SLOTS[company.player]
		var column: int = slots[0]
		var row_list: Array = slots[1]
		var n: int = used[company.player]
		used[company.player] += 1
		# More than five companies: the next column behind the front.
		var step := 1 if company.player == 0 else -1
		company.coord = MapGenerator.offset_to_axial(
			column - step * (n / row_list.size()), row_list[n % row_list.size()]
		)
	return setup


func _tally() -> Dictionary:
	return {"wins": [0, 0], "draws": 0, "lost": [0, 0]}


func _add(tally: Dictionary, result: BattleResult) -> void:
	if result.winner < 0:
		tally["draws"] += 1
	else:
		tally["wins"][result.winner] += 1
	for company in result.companies:
		tally["lost"][company.player] += company.strength_start - company.strength_end


func _add_played(tally: Dictionary, setup: BattleSetup, max_turns: int) -> void:
	var state := Scenario.from_setup(setup)
	if state == null:
		return
	if setup.terrain == &"hills":
		for unit in state.units.values():
			if unit.owner_id != setup.attacker:
				MapGenerator.force_terrain(state.grid, unit.coord, Terrain.Type.HILLS)
	var sim := GameSimulation.new(state)
	MatchRunner.run(sim, max_turns)
	if state.winner < 0:
		tally["draws"] += 1
	else:
		tally["wins"][state.winner] += 1
	for unit in state.units.values():
		pass
	for i in setup.companies.size():
		var unit := state.units.get(i + 1) as Unit
		var left := 0 if unit == null else unit.hp
		tally["lost"][setup.companies[i].player] += setup.companies[i].strength - left


func _line(t: Dictionary) -> String:
	return (
		"%d / %d / %d  losses %.1f / %.1f"
		% [t["wins"][0], t["wins"][1], t["draws"], t["lost"][0] / _n(t), t["lost"][1] / _n(t)]
	)


func _n(t: Dictionary) -> float:
	return float(t["wins"][0] + t["wins"][1] + t["draws"])


func _gap(a: Dictionary, b: Dictionary, count: int) -> float:
	var worst := 0.0
	for p in 2:
		worst = maxf(worst, absf(a["wins"][p] - b["wins"][p]) * 100.0 / count)
	return worst
