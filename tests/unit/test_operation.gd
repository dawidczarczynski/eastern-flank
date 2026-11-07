extends TestCase
## Operational state, simulation and building (TASK-092b, ADR 0015).


class ProbeCommand:
	extends OperationalCommand
	var reason := ""

	func validate(_state: OperationalState) -> String:
		return reason

	func apply(state: OperationalState) -> Array[Dictionary]:
		state.turn += 1
		return [{"type": &"probe", "turn": state.turn}]


static func _unit(unit_id: StringName) -> UnitDefinition:
	return load("res://data/units/%s.tres" % unit_id) as UnitDefinition


static func _grid() -> HexGrid:
	var grid := HexGrid.new()
	for q in range(0, 8):
		for r in range(0, 4):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	grid.set_terrain(Vector2i(3, 3), Terrain.Type.WATER)
	return grid


static func _side(side_id: StringName, factions: Array[StringName]) -> SideDefinition:
	var side := SideDefinition.new()
	side.id = side_id
	side.display_name = String(side_id)
	side.lead_faction = factions[0]
	side.factions = factions
	return side


static func _formation_type(faction: StringName, units: Array[StringName]) -> FormationDefinition:
	var def := FormationDefinition.new()
	def.id = StringName("%s_test" % faction)
	def.display_name = "Test"
	def.faction = faction
	def.formation_class = &"mechanised"
	for unit_id in units:
		def.companies.append(_unit(unit_id))
	return def


static func _placement(
	id: StringName, player: int, def: FormationDefinition, coord: Vector2i
) -> FormationPlacement:
	var p := FormationPlacement.new()
	p.id = id
	p.display_name = String(id)
	p.parent = "Brigade"
	p.player = player
	p.definition = def
	p.coord = coord
	return p


static func _definition() -> OperationDefinition:
	var op := OperationDefinition.new()
	op.id = &"test_op"
	op.display_name = "Test"
	op.map_id = &"none"
	op.sides = [_side(&"blue", [&"poland"]), _side(&"red", [&"russia"])] as Array[SideDefinition]
	op.first_player = 1
	var blue := _formation_type(&"poland", [&"pl_mech_infantry", &"m1a2_sepv3"])
	var red := _formation_type(&"russia", [&"t72b3"])
	op.formations.append(_placement(&"b1", 0, blue, Vector2i(0, 0)))
	op.formations.append(_placement(&"r1", 1, red, Vector2i(7, 3)))
	op.formations.append(_placement(&"a0", 0, blue, Vector2i(1, 0)))
	return op


func test_build_from_definition() -> void:
	var state := Operation.from_definition(_definition(), 5, _grid())
	assert_true(state != null)
	assert_eq(state.operation_id, &"test_op")
	assert_eq(state.player_sides, [&"blue", &"red"] as Array[StringName])
	assert_eq(state.player_factions, [&"poland", &"russia"] as Array[StringName])
	assert_eq(state.first_player, 1)
	assert_eq(state.current_player, 1)
	assert_eq(state.turn, 1)
	assert_true(state.pending_battles.is_empty())
	assert_eq(state.formations.size(), 3)
	var ids: Array[StringName] = []
	for f in state.formations:
		ids.append(f.id)
	assert_eq(ids, [&"b1", &"r1", &"a0"] as Array[StringName], "placement order")
	var b1 := state.get_formation(&"b1")
	assert_eq(b1.owner_id, 0)
	assert_eq(b1.coord, Vector2i(0, 0))
	assert_eq(b1.companies.size(), 2)
	assert_eq(b1.companies[0].unit_type, &"pl_mech_infantry")
	assert_eq(b1.companies[0].strength, 10)
	assert_eq(b1.companies[0].ref, "b1/1")
	assert_eq(b1.companies[1].ref, "b1/2")
	assert_eq(b1.strength(), 20)
	assert_eq(b1.max_strength(), 20)
	assert_eq(state.formation_at(Vector2i(7, 3)).id, &"r1")
	assert_true(state.formation_at(Vector2i(5, 1)) == null)
	assert_true(state.get_formation(&"zz") == null)


func test_snapshot() -> void:
	var state := Operation.from_definition(_definition(), 5, _grid())
	var snap := state.snapshot()
	assert_eq(snap["turn"], 1)
	assert_eq(snap["current_player"], 1)
	assert_true(snap["rng_state"] is String)
	var entries: Array = snap["formations"]
	assert_eq(entries.size(), 3)
	var expected := {
		"id": "a0",
		"player": 0,
		"coord": [1, 0],
		"companies": [["pl_mech_infantry", 10], ["m1a2_sepv3", 10]],
	}
	assert_eq(entries[0], expected)
	assert_eq(entries[1]["id"], "b1")
	assert_eq(entries[2]["id"], "r1")
	assert_eq(JSON.parse_string(JSON.stringify(snap)).size(), snap.size())


func _rejected(op: OperationDefinition, message: String, grid: HexGrid = _grid()) -> void:
	assert_true(Operation.from_definition(op, 1, grid) == null, message)


func test_rejects_bad_placements() -> void:
	var op := _definition()
	op.formations[0].coord = Vector2i(20, 20)
	_rejected(op, "off the map")
	op = _definition()
	op.formations[0].coord = Vector2i(3, 3)
	_rejected(op, "impassable")
	op = _definition()
	op.formations[0].coord = Vector2i(1, 0)
	_rejected(op, "two on one tile")
	op = _definition()
	op.formations[2].id = &"b1"
	_rejected(op, "duplicate id")
	op = _definition()
	op.formations[1].player = 0
	_rejected(op, "faction not in the player's side")
	op = _definition()
	op.formations[0].definition = _formation_type(&"poland", [&"t72b3"])
	_rejected(op, "company outside the roster")
	op = _definition()
	op.formations[0].player = 2
	_rejected(op, "player out of range")
	op = _definition()
	op.formations[0].definition = null
	_rejected(op, "no definition")


func test_rejects_bad_sides() -> void:
	var op := _definition()
	op.first_player = 2
	_rejected(op, "first player 2")
	op = _definition()
	op.first_player = -1
	_rejected(op, "first player -1")
	op = _definition()
	op.sides.pop_back()
	_rejected(op, "one side")
	op = _definition()
	op.sides.append(_side(&"green", [&"russia"]))
	_rejected(op, "three sides")
	op = _definition()
	op.sides[0].lead_faction = &"russia"
	_rejected(op, "lead faction not in factions")
	op = _definition()
	op.sides[0].factions = [&"poland", &"russia"] as Array[StringName]
	_rejected(op, "faction in both sides")
	op = _definition()
	op.sides[1] = null
	_rejected(op, "null side")


func test_rejects_unknown_operation_and_map() -> void:
	assert_true(Operation.build(&"no_such_operation", 1) == null)
	assert_true(Operation.from_definition(_definition(), 1) == null, "unknown map")


func test_shipped_operation_builds() -> void:
	assert_eq(Operation.NAMES, [&"suwalki_gap"] as Array[StringName])
	var state := Operation.build(&"suwalki_gap", 7)
	assert_true(state != null)
	assert_eq(state.formations.size(), 18)
	assert_eq(state.player_sides, [&"nato", &"russia"] as Array[StringName])
	assert_eq(state.player_factions, [&"poland", &"russia"] as Array[StringName])
	assert_eq(state.current_player, 1)
	var mech := state.get_formation(&"pl_mech_1")
	assert_true(mech != null)
	assert_eq(mech.companies[3].ref, "pl_mech_1/4")
	assert_eq(mech.companies[3].unit_type, &"m1a2_sepv3")
	var totals := [0, 0]
	for f in state.formations:
		totals[f.owner_id] += f.strength()
	assert_eq(totals, [276, 332])


func test_build_is_deterministic() -> void:
	var a := Operation.build(&"suwalki_gap", 7).snapshot()
	var b := Operation.build(&"suwalki_gap", 7).snapshot()
	var c := Operation.build(&"suwalki_gap", 8).snapshot()
	assert_eq(a, b)
	assert_true(a["rng_state"] != c["rng_state"])
	c["rng_state"] = a["rng_state"]
	assert_eq(a, c, "seeds differ only in rng_state")


func test_simulation_executes_and_rejects() -> void:
	var sim := OperationalSimulation.new(Operation.from_definition(_definition(), 5, _grid()))
	var events: Array[Dictionary] = []
	var rejections: Array[String] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: OperationalCommand, reason: String) -> void: rejections.append(reason)
	)
	var bad := ProbeCommand.new()
	bad.reason = "nope"
	assert_false(sim.execute(bad))
	assert_eq(rejections, ["nope"] as Array[String])
	assert_true(sim.history.is_empty())
	assert_eq(sim.state.turn, 1)
	var good := ProbeCommand.new()
	assert_true(sim.execute(good))
	assert_eq(sim.history.size(), 1)
	assert_eq(events, [{"type": &"probe", "turn": 2}] as Array[Dictionary])


func test_codec_rejects_unknown_and_malformed() -> void:
	var cases: Array[Dictionary] = [{}, {"type": 3}, {"type": null}, {"type": ["order"]}]
	cases.append_array([{"type": "move"}, {"type": "end_turn"}, {"type": "no_such"}])
	for d in cases:
		assert_true(OperationalCommandCodec.from_dict(d) == null, str(d))
	assert_eq(OperationalCommandCodec.to_int_or_null(3.0), 3)
	assert_true(OperationalCommandCodec.to_int_or_null(1.5) == null)
	assert_true(OperationalCommandCodec.to_int_or_null(true) == null)
	assert_true(OperationalCommandCodec.to_int_or_null(INF) == null)
	assert_true(OperationalCommandCodec.to_int_or_null("3") == null)
	assert_eq(OperationalCommand.new().to_dict(), {})


## The operational layer never references the tactical simulation (ADR 0015 §1) and never
## compares side or faction ids with literals (GDD "Sides").
func test_operational_code_stays_independent() -> void:
	var forbidden := RegEx.create_from_string(
		"\\b(GameState|GameSimulation|Command|CommandCodec|MoveUnitCommand|AttackCommand"
		+ "|EndTurnCommand)\\b"
	)
	var literal := RegEx.create_from_string("[\"'](nato|russia|poland)[\"']")
	var dir := DirAccess.open("res://src/core/operational")
	assert_true(dir != null)
	var checked := 0
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		checked += 1
		var text := FileAccess.get_file_as_string("res://src/core/operational/" + file_name)
		var hit := forbidden.search(text)
		var hit_text := hit.get_string() if hit else ""
		assert_true(hit == null, "%s references %s" % [file_name, hit_text])
		var lit := literal.search(text)
		var lit_text := lit.get_string() if lit else ""
		assert_true(lit == null, "%s compares with %s" % [file_name, lit_text])
	assert_true(checked >= 6)
