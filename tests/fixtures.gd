extends RefCounted
## Shared test data. Usage: const Fixtures := preload("res://tests/fixtures.gd")


## Hexagonal all-plains map with radius `radius` around (0, 0).
static func plains_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var c := Vector2i(q, r)
			if Hex.distance(Vector2i.ZERO, c) <= radius:
				grid.set_terrain(c, Terrain.Type.PLAINS)
	return grid


## A MapView built on `grid` with `quality`, outside a scene tree (its _ready() is run here).
## The caller frees it.
static func map_view(grid: HexGrid, quality: Dictionary = {}) -> MapView:
	var view := MapView.new()
	view._ready()
	view.quality = quality
	view.build(grid)
	return view


## Undoes what tests change on a MapView shared between them (TestCase.before_all): highlights,
## hover, path dots, grid mode and camera distance. The built terrain stays.
static func reset_map_view(view: MapView) -> void:
	view.clear_highlights()
	view.set_hover(null)
	view.clear_path()
	if not view._grid_auto:
		view.cycle_grid_mode()
	view.set_camera_distance(CameraRig.DEFAULT_DISTANCE)


static func infantry() -> UnitDefinition:
	var definition := UnitDefinition.new()
	definition.id = &"test_infantry"
	definition.max_hp = 10
	definition.move_points = 3
	definition.attack = 4
	definition.defense = 2
	return definition


## Unit definition with custom combat stats (3 move points).
static func fighter(
	attack: int, defense: int, max_hp: int = 10, attack_range: int = 1
) -> UnitDefinition:
	var definition := infantry()
	definition.id = &"test_fighter"
	definition.attack = attack
	definition.defense = defense
	definition.max_hp = max_hp
	definition.attack_range = attack_range
	return definition


## A unit whose every shot hits (per-element rolls, TASK-089a): its attack is so high that
## hit_on is capped at max_hp, the size of its die. A strike therefore deals exactly the
## striker's current HP in damage – the tool for tests that need a certain result.
static func sure_fighter(max_hp: int, defense: int = 2, attack_range: int = 1) -> UnitDefinition:
	var definition := fighter(100, defense, max_hp, attack_range)
	definition.id = &"test_sure_fighter"
	return definition


## The generic cavalry calibration unit of the GDD (8 HP, move 5, A5 D2, range 1), class tank.
static func generic_tank() -> UnitDefinition:
	var definition := UnitDefinition.new()
	definition.id = &"test_generic_tank"
	definition.display_name = "Test Tank"
	definition.short_name = "TNK"
	definition.unit_class = &"tank"
	definition.mobility = &"tracked"
	definition.max_hp = 8
	definition.move_points = 5
	definition.attack = 5
	definition.defense = 2
	definition.attack_range = 1
	return definition


## Victory condition of `kind` (VictoryCondition.Kind) for `player` (-1 = both).
static func condition(
	kind: VictoryCondition.Kind, player: int, hexes: Array[Vector2i] = [], share_percent: int = 0
) -> VictoryCondition:
	return VictoryCondition.make(kind, player, hexes, share_percent)


## BattleObjectives with `turn_limit`, objective `hexes` (initial owners parallel to them,
## -1 = neutral) and `conditions`.
static func objectives(
	turn_limit: int, hexes: Array[Vector2i], owners: Array[int], conditions: Array[VictoryCondition]
) -> BattleObjectives:
	var result := BattleObjectives.new()
	result.turn_limit = turn_limit
	result.hexes = hexes
	result.initial_owners = owners
	result.conditions = conditions
	return result


## A contact on the real theatre (TASK-094c): a player-1 formation whose companies its faction
## fields is put on a free land hex next to such a player-0 formation and ContactRules starts the
## battle as the end of a turn would. Returns the events (formation_halted + battle_pending);
## empty when no pair fits. `skip` pairs are passed over (a second contact uses other formations).
static func theatre_contact(state: OperationalState, skip := 0) -> Array[Dictionary]:
	var own: Array[Formation] = []
	var enemy: Array[Formation] = []
	for formation in state.formations:
		if _fieldable(state, formation):
			(own if formation.owner_id == 0 else enemy).append(formation)
	if skip >= mini(own.size(), enemy.size()):
		return []
	var attacker := enemy[skip]
	var defender := own[skip]
	var placed := false
	for neighbor in Hex.neighbors(defender.coord):
		if (
			state.grid.has_tile(neighbor)
			and state.grid.get_terrain(neighbor) != Terrain.Type.WATER
			and state.formation_at(neighbor) == null
		):
			attacker.coord = neighbor
			placed = true
			break
	if not placed:
		return []
	var events: Array[Dictionary] = [
		{
			"type": &"formation_halted",
			"formation_id": attacker.id,
			"at": attacker.coord,
			"reason": &"contact",
		}
	]
	ContactRules.start_battles(state, events)
	return events


static func _fieldable(state: OperationalState, formation: Formation) -> bool:
	var faction := FactionRegistry.get_faction(state.player_factions[formation.owner_id])
	for company in formation.companies:
		if faction == null or faction.find_unit(company.unit_type) == null:
			return false
	return true


## A battle setup for the auto-resolve tests (TASK-120). `rows` = [player, unit type, strength];
## `postures` = [[posture, position bonus], ...] per player; attacker 0, plains, no turn limit,
## command points 0 unless the caller changes them. Company i has ref "t/<i>".
static func auto_setup(
	factions: Array[StringName],
	rows: Array,
	postures: Array,
	terrain: StringName = &"plains",
	seed_value := 1
) -> BattleSetup:
	var setup := BattleSetup.new()
	setup.seed = seed_value
	setup.factions = factions
	setup.attacker = 0
	setup.terrain = terrain
	for i in rows.size():
		var company := BattleSetup.Company.new()
		company.player = rows[i][0]
		company.unit_type = rows[i][1]
		company.strength = rows[i][2]
		company.ref = "t/%d" % i
		company.coord = Vector2i(i, 0)
		setup.companies.append(company)
	for posture: Array in postures:
		var side := BattleSetup.Conditions.new()
		side.posture = posture[0]
		side.position_bonus = posture[1]
		setup.conditions.append(side)
	return setup


## The named auto-resolve setups of TASK-120: "salvo", "crush", "mirror", "fortress".
static func auto_case(kind: String, seed_value := 1) -> BattleSetup:
	var pl_ru: Array[StringName] = [&"poland", &"russia"]
	var pl_pl: Array[StringName] = [&"poland", &"poland"]
	var advance := [&"advance", 0]
	match kind:
		"salvo":
			return auto_setup(
				pl_ru,
				[[0, &"homar_k", 3], [0, &"homar_k", 6], [1, &"bm27_uragan", 6]],
				[advance, [&"march", -1]],
				&"plains",
				seed_value
			)
		"crush":
			return auto_setup(
				pl_ru,
				[
					[0, &"m1a2_sepv3", 10],
					[0, &"m1a2_sepv3", 10],
					[0, &"m1a2_sepv3", 10],
					[0, &"pl_mech_infantry", 10],
					[1, &"ru_motor_rifle", 10],
				],
				[advance, [&"defend", 1]],
				&"plains",
				seed_value
			)
	var rows: Array = []
	for player in 2:
		for i in 3:
			rows.append([player, &"pl_mech_infantry", 10])
		rows.append([player, &"m1a2_sepv3", 10])
	if kind == "fortress":
		return auto_setup(pl_pl, rows, [advance, [&"defend", 1]], &"hills", seed_value)
	return auto_setup(pl_pl, rows, [advance, advance], &"plains", seed_value)
