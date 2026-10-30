class_name Scenario
extends RefCounted
## Battle setups built headless from a seed (shared by the game, replays and AI simulations).

const MAP_WIDTH := 12
const MAP_HEIGHT := 10
## Spawn slots per player, as offset [column, rows in fill order]: units with attack range 1 take
## the front slots, the others the back slots.
const FRONT_SLOTS := [[1, [3, 5, 7, 1, 9]], [MAP_WIDTH - 2, [2, 4, 6, 8, 0]]]
const BACK_SLOTS := [[0, [5, 3, 7]], [MAP_WIDTH - 1, [4, 2, 6]]]
## A river between the armies: its offset column for each row (north to south, consecutive
## tiles adjacent). Water is impassable, so the rows in RIVER_FORDS are plains crossings.
const RIVER_COLUMNS := [6, 5, 5, 5, 6, 6, 6, 5, 5, 5]
const RIVER_FORDS := [2, 7]
const OPERATION_NAME := "Iron Shore"
## Scenario names a MatchRecord can name (Scenario.build).
const NAMES: Array[String] = ["default_battle", "objective_battle"]
## Objectives of the objective test battle (TASK-088).
const OBJECTIVE_BATTLE_OBJECTIVES := preload("res://data/scenarios/objective_battle.tres")


## Starting state of the scenario `scenario_name` (NAMES); null for an unknown name.
static func build(scenario_name: String, seed_value: int, factions: Array[StringName]) -> GameState:
	match scenario_name:
		"default_battle":
			return default_battle(seed_value, factions)
		"objective_battle":
			return objective_battle(seed_value, factions)
	return null


## Default 2-player battle on a generated 12x10 map with a river (RIVER_COLUMNS) between the
## armies: `from_setup(default_battle_setup(seed_value, factions))`.
static func default_battle(
	seed_value: int, factions: Array[StringName] = FactionRegistry.DEFAULT_IDS
) -> GameState:
	return from_setup(default_battle_setup(seed_value, factions))


## Objective test battle: the default battle with the objectives of
## data/scenarios/objective_battle.tres (two east-bank hexes behind the fords held by player 1,
## player 0 must take both, player 1 holds them at the turn limit of 8, eliminate for both).
static func objective_battle(
	seed_value: int, factions: Array[StringName] = FactionRegistry.DEFAULT_IDS
) -> GameState:
	return from_setup(objective_battle_setup(seed_value, factions))


## objective_battle as a BattleSetup; its objectives are a fresh copy of the resource.
static func objective_battle_setup(
	seed_value: int, factions: Array[StringName] = FactionRegistry.DEFAULT_IDS
) -> BattleSetup:
	var setup := default_battle_setup(seed_value, factions)
	setup.objectives = BattleObjectives.from_dict(OBJECTIVE_BATTLE_OBJECTIVES.to_dict())
	return setup


## The default battle as a BattleSetup (ADR 0015); objectives = default_objectives().
## `factions` = faction id of player 0 and player 1 (FactionRegistry). Each player gets their
## faction's `default_force` in list order (unit ids follow it); factions don't change the map.
## Range-1 units take FRONT_SLOTS, the others BACK_SLOTS. A unit not in its owner's roster, or
## one beyond the free slots, is skipped with push_error (its slot stays used; since TASK-086 the
## tile of a roster-skipped unit is no longer forced to plains).
static func default_battle_setup(
	seed_value: int, factions: Array[StringName] = FactionRegistry.DEFAULT_IDS
) -> BattleSetup:
	var setup := BattleSetup.new()
	setup.seed = seed_value
	setup.map_id = BattleSetup.MAP_GENERATED_RIVER
	setup.operation_name = OPERATION_NAME
	setup.factions = factions.duplicate()
	for player in factions.size():
		setup.conditions.append(BattleSetup.Conditions.new())
		var faction := FactionRegistry.get_faction(factions[player])
		if faction == null:
			push_error("Scenario: player %d has an unknown faction" % player)
			continue
		var used := {true: 0, false: 0}  # front? -> slots taken
		for definition: UnitDefinition in faction.default_force:
			var front := definition.attack_range == 1
			var slots: Array = (FRONT_SLOTS if front else BACK_SLOTS)[player]
			var rows: Array = slots[1]
			if used[front] >= rows.size():
				push_error("Scenario: no free slot for '%s' of player %d" % [definition.id, player])
				continue
			var coord := MapGenerator.offset_to_axial(slots[0], rows[used[front]])
			used[front] += 1
			if not faction.has_unit(definition):
				push_error(
					(
						"Scenario: '%s' is not in player %d's roster – skipped"
						% [definition.id, player]
					)
				)
				continue
			var company := BattleSetup.Company.new()
			company.player = player
			company.unit_type = definition.id
			company.coord = coord
			company.strength = definition.max_hp
			setup.companies.append(company)
	return setup


## Starting GameState of `setup`: its map from `map_id` and `seed`, spawn tiles forced to plains,
## company i as unit id i + 1 with HP = its strength, `GameState.rng` seeded with `seed`.
## null (with push_error) for an unknown map id or a company that cannot be placed: unknown
## player or faction, unit type not in the roster, strength outside 1 … max_hp, a taken or
## missing tile, objectives that are inconsistent (BattleObjectives.problem) or have a hex off
## the map. Objective hexes that are water become plains; owners start at the data's initial
## owners (a unit spawning on one does not capture it); `starting_hp` is recorded after spawning.
## `map_region` and conditions are not read yet (TASK-087 / TASK-094, TASK-091, TASK-099).
static func from_setup(setup: BattleSetup) -> GameState:
	var grid := _build_map(setup.map_id, setup.seed)
	if grid == null:
		push_error("Scenario: unknown map '%s'" % setup.map_id)
		return null
	var state := GameState.new(grid, setup.factions.size(), setup.seed)
	state.player_factions = setup.factions.duplicate()
	state.operation_name = setup.operation_name
	for company in setup.companies:
		var faction := state.faction_of(company.player)
		var definition := faction.find_unit(company.unit_type) if faction != null else null
		if definition == null:
			push_error(
				"Scenario: player %d cannot field '%s'" % [company.player, company.unit_type]
			)
			return null
		if company.strength < 1 or company.strength > definition.max_hp:
			push_error(
				"Scenario: strength %d of '%s' out of range" % [company.strength, company.unit_type]
			)
			return null
		if not grid.has_tile(company.coord) or state.unit_at(company.coord) != null:
			push_error("Scenario: tile %s is missing or taken" % company.coord)
			return null
		MapGenerator.force_terrain(grid, company.coord, Terrain.Type.PLAINS)
		state.add_unit(company.player, definition, company.coord).hp = company.strength
	var problem := setup.objectives.problem(state.player_count)
	if problem != "":
		push_error("Scenario: objectives – %s" % problem)
		return null
	for c in setup.objectives.hexes:
		if not grid.has_tile(c):
			push_error("Scenario: objective hex %s is off the map" % c)
			return null
		if grid.get_terrain(c) == Terrain.Type.WATER:
			MapGenerator.force_terrain(grid, c, Terrain.Type.PLAINS)
	state.set_objectives(setup.objectives)
	state.record_starting_hp()
	return state


## Map of a BattleSetup; null for an unknown id.
static func _build_map(map_id: StringName, seed_value: int) -> HexGrid:
	match map_id:
		BattleSetup.MAP_GENERATED_RIVER:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var grid := MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, rng)
			_add_river(grid)
			return grid
	return null


static func _add_river(grid: HexGrid) -> void:
	for row in RIVER_COLUMNS.size():
		var coord := MapGenerator.offset_to_axial(RIVER_COLUMNS[row], row)
		var t := Terrain.Type.PLAINS if row in RIVER_FORDS else Terrain.Type.WATER
		MapGenerator.force_terrain(grid, coord, t)
