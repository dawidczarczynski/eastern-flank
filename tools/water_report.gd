extends SceneTree
## Water error report (TASK-223a, ADR 0034): builds the grid of a map, the river channels over it
## and prints WaterValidator's violations: a count per rule and the first 20 positions.
## Run via tools/water_report.sh. Manually:
##   godot --headless --path . --script res://tools/water_report.gd -- --map=suwalki
##   ... -- --map=suwalki_theatre --region=47:45
## --map: an imported map id (ImportedMap, whole map) – with --region the theatre whose
## operational hex col:row is cut like the terrain viewer does (TerrainViewSetup).
## Exit codes: 0 report printed, 2 invalid arguments or unknown map.

const SHOWN := 20


func _initialize() -> void:
	var map_id := &"suwalki"
	var region := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_id = StringName(arg.trim_prefix("--map="))
		elif arg.begins_with("--region="):
			region = arg.trim_prefix("--region=")
		else:
			printerr("Unknown argument '%s' (--map=<id> --region=<col>:<row>)" % arg)
			quit(2)
			return
	var setup := _setup(map_id, region)
	var state := Scenario.from_setup(setup) if setup != null else null
	var grid := state.grid if state != null else null
	if grid == null:
		printerr("No map '%s'%s" % [map_id, " / region " + region if region != "" else ""])
		quit(2)
		return
	MapScale.apply_map_id(setup.map_id)
	# As the battle does before it builds the view: river widths from the land-cover raster.
	RiverWidths.apply(grid, BattleCover.for_battle(setup, "", setup.seed, grid))
	var surface := TerrainSurface.new(grid)
	surface.prime()
	surface.channel = RiverShape.channel(grid, surface)
	var sample := WaterSampleAdapter.build(grid, surface)
	var found := WaterValidator.check(sample)
	print(
		(
			"%s%s: %d reaches, %d bridges"
			% [
				map_id,
				" " + region if region != "" else "",
				sample.reaches.size(),
				sample.bridges.size()
			]
		)
	)
	for rule in WaterValidator.RULES:
		var n := 0
		for v in found:
			if v["rule"] == rule:
				n += 1
		print("  %-14s %d" % [rule, n])
	print("first %d positions (rule  world x,z  value / limit):" % SHOWN)
	for i in mini(SHOWN, found.size()):
		var v := found[i]
		var p: Vector2 = v["position"]
		print("  %-14s %8.2f, %8.2f  %.3f / %.3f" % [v["rule"], p.x, p.y, v["value"], v["limit"]])
	quit(0)


## The battle setup whose map is reported: the cut around an operational hex, or the whole map.
func _setup(map_id: StringName, region: String) -> BattleSetup:
	if region == "":
		var setup := BattleSetup.new()
		setup.map_id = map_id
		setup.factions = FactionRegistry.DEFAULT_IDS.duplicate()
		setup.conditions = [BattleSetup.Conditions.new(), BattleSetup.Conditions.new()]
		setup.objectives = BattleObjectives.new()
		return setup
	var parts := region.split(":")
	if parts.size() != 2:
		return null
	return TerrainViewSetup.build(
		map_id, MapGenerator.offset_to_axial(parts[0].to_int(), parts[1].to_int())
	)
