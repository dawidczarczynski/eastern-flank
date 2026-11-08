class_name BattleSetup
extends RefCounted
## Everything a tactical battle starts from – the only channel from the operational layer into a
## battle (ADR 0015). A scenario battle is a BattleSetup too (`Scenario.default_battle_setup`);
## `Scenario.from_setup` builds the battle's GameState from it.
## JSON form (`to_dict`): {"seed", "map_id", "map_region": [x, y, w, h], "operation_name",
## "factions": [ids], "companies": [Company], "conditions": [Conditions per player],
## "objectives": BattleObjectives, "attacker", "terrain", "missions": [Mission]}.
## `from_dict` returns null on anything malformed (incl. a negative region size,
## not one `conditions` entry per faction or inconsistent objectives);
## "objectives": {} reads as BattleObjectives.default_objectives().

## Map built by MapGenerator from `seed` with the default battle's river (Scenario).
const MAP_GENERATED_RIVER := &"generated_river"


## One company entering the battle. Company i becomes unit id i + 1 (spawn order).
class Company:
	extends RefCounted
	## Player (side index) the company fights for.
	var player: int
	## UnitDefinition id; it must be in the player's faction roster.
	var unit_type: StringName
	var coord: Vector2i
	## Starting HP (company strength), 1 … the unit's max_hp.
	var strength: int
	## Operational id of the company (e.g. "pl_15bde/2"), "" in scenario battles; BattleResult
	## reports losses under it.
	var ref: String = ""

	func to_dict() -> Dictionary:
		return {
			"player": player,
			"unit_type": String(unit_type),
			"coord": [coord.x, coord.y],
			"strength": strength,
			"ref": ref,
		}

	static func from_dict(d: Variant) -> Company:
		if not d is Dictionary:
			return null
		var player_value: Variant = CommandCodec.to_int_or_null(d.get("player"))
		var coord_value: Variant = BattleSetup.vector_or_null(d.get("coord"))
		var strength_value: Variant = CommandCodec.to_int_or_null(d.get("strength"))
		var type_value: Variant = d.get("unit_type")
		var ref_value: Variant = d.get("ref")
		if player_value == null or coord_value == null or strength_value == null:
			return null
		if not type_value is String or not ref_value is String:
			return null
		var company := Company.new()
		company.player = player_value
		company.unit_type = StringName(type_value)
		company.coord = coord_value
		company.strength = strength_value
		company.ref = ref_value
		return company


## Battle conditions of one side, shaped by the operation (VISION 2.2). `command_points` is read
## by Scenario.from_setup (TASK-091); the rest by no rule yet (TASK-099).
class Conditions:
	extends RefCounted
	## Activations per turn; 0 = unlimited.
	var command_points: int = 0
	## Ammunition supply in percent of full.
	var ammunition: int = 100
	## Morale in percent of normal.
	var morale: int = 100
	## Fire support missions available (artillery / air), 0 = none.
	var fire_support: int = 0
	## Operational posture of the side's formation (TASK-094a), &"" in scenario battles.
	var posture: StringName = &""
	## Defence bonus of that posture (OperationalPosture.position_bonus), resolved by the
	## operation; the tactical layer never reads operational data.
	var position_bonus: int = 0

	func to_dict() -> Dictionary:
		return {
			"command_points": command_points,
			"ammunition": ammunition,
			"morale": morale,
			"fire_support": fire_support,
			"posture": String(posture),
			"position_bonus": position_bonus,
		}

	static func from_dict(d: Variant) -> Conditions:
		if not d is Dictionary:
			return null
		var values := {}
		for key: String in [
			"command_points", "ammunition", "morale", "fire_support", "position_bonus"
		]:
			values[key] = CommandCodec.to_int_or_null(d.get(key))
			if values[key] == null:
				return null
		if not d.get("posture") is String:
			return null
		var conditions := Conditions.new()
		conditions.command_points = values["command_points"]
		conditions.ammunition = values["ammunition"]
		conditions.morale = values["morale"]
		conditions.fire_support = values["fire_support"]
		conditions.position_bonus = values["position_bonus"]
		conditions.posture = StringName(d["posture"] as String)
		return conditions


## What one side is told to do in a contact battle (TASK-094a, GDD "Player roles"): the
## briefing of the commander.
class Mission:
	extends RefCounted
	## &"attack", &"defend" or &"hold_out" (a formation caught on the march).
	var task: StringName = &""
	## Translation key of the intent text (the order's destination) and its format arguments.
	var intent_key := ""
	var intent_args: Array = []
	## Display name (translation key) of the side's formation.
	var formation_name := ""

	func to_dict() -> Dictionary:
		return {
			"task": String(task),
			"intent_key": intent_key,
			"intent_args": intent_args.duplicate(),
			"formation_name": formation_name,
		}

	static func from_dict(d: Variant) -> Mission:
		if not d is Dictionary:
			return null
		var task_value: Variant = d.get("task")
		var key_value: Variant = d.get("intent_key")
		var args_value: Variant = d.get("intent_args")
		var name_value: Variant = d.get("formation_name")
		if not (task_value is String and key_value is String and name_value is String):
			return null
		if not args_value is Array:
			return null
		var mission := Mission.new()
		mission.task = StringName(task_value)
		mission.intent_key = key_value
		mission.formation_name = name_value
		for arg: Variant in args_value:
			if arg is String:
				mission.intent_args.append(arg)
				continue
			var number: Variant = CommandCodec.to_int_or_null(arg)
			if number == null:
				return null
			mission.intent_args.append(number)
		return mission


## Seed of the battle: map generation (generated maps) and GameState.rng. In a campaign it is
## drawn from the operational RNG at contact (ADR 0015). Within +-2^53 to survive JSON.
var seed: int
## MAP_GENERATED_RIVER, or the id of a map imported from real terrain (data/maps/<id>.tres).
var map_id: StringName = MAP_GENERATED_RIVER
## Cut of an imported map (TASK-094, not read yet); an empty rect = the whole map.
var map_region := Rect2i()
## Display name of the operation (GameState.operation_name).
var operation_name := ""
## Faction id of each player (index = player id).
var factions: Array[StringName] = []
var companies: Array[Company] = []
## One entry per player.
var conditions: Array[Conditions] = []
## Victory conditions, objective hexes and turn limit (TASK-088).
var objectives: BattleObjectives = BattleObjectives.default_objectives()
## Player who attacks (the formation that halted on contact), -1 in scenario battles (TASK-094a).
var attacker: int = -1
## Terrain id of the defender's operational hex; &"" (= plains) in scenario battles.
var terrain: StringName = &""
## One Mission per player (index = player id); empty in scenario battles.
var missions: Array[Mission] = []


func to_dict() -> Dictionary:
	var faction_ids: Array[String] = []
	for faction_id in factions:
		faction_ids.append(String(faction_id))
	var company_list: Array[Dictionary] = []
	for company in companies:
		company_list.append(company.to_dict())
	var condition_list: Array[Dictionary] = []
	for side in conditions:
		condition_list.append(side.to_dict())
	var mission_list: Array[Dictionary] = []
	for mission in missions:
		mission_list.append(mission.to_dict())
	return {
		"attacker": attacker,
		"terrain": String(terrain),
		"missions": mission_list,
		"seed": seed,
		"map_id": String(map_id),
		"map_region":
		[map_region.position.x, map_region.position.y, map_region.size.x, map_region.size.y],
		"operation_name": operation_name,
		"factions": faction_ids,
		"companies": company_list,
		"conditions": condition_list,
		"objectives": objectives.to_dict(),
	}


## null when a field is missing or has the wrong type (JSON floats are accepted when integral).
static func from_dict(d: Dictionary) -> BattleSetup:
	var seed_value: Variant = CommandCodec.to_int_or_null(d.get("seed"))
	var map_value: Variant = d.get("map_id")
	var region_value: Variant = d.get("map_region")
	var name_value: Variant = d.get("operation_name")
	var faction_list: Variant = d.get("factions")
	var company_list: Variant = d.get("companies")
	var condition_list: Variant = d.get("conditions")
	var objective_value: Variant = d.get("objectives")
	var attacker_value: Variant = CommandCodec.to_int_or_null(d.get("attacker"))
	var terrain_value: Variant = d.get("terrain")
	var mission_list: Variant = d.get("missions")
	if attacker_value == null or not terrain_value is String or not mission_list is Array:
		return null
	if seed_value == null or not map_value is String or not name_value is String:
		return null
	if not faction_list is Array or not company_list is Array or not condition_list is Array:
		return null
	if not objective_value is Dictionary or not region_value is Array or region_value.size() != 4:
		return null
	var setup := BattleSetup.new()
	setup.seed = seed_value
	setup.map_id = StringName(map_value)
	setup.operation_name = name_value
	var objectives := BattleObjectives.from_dict(objective_value)
	if objectives == null:
		return null
	setup.objectives = objectives
	setup.attacker = attacker_value
	setup.terrain = StringName(terrain_value as String)
	for entry: Variant in mission_list:
		var mission := Mission.from_dict(entry)
		if mission == null:
			return null
		setup.missions.append(mission)
	var position: Variant = vector_or_null(region_value.slice(0, 2))
	var size: Variant = vector_or_null(region_value.slice(2, 4))
	if position == null or size == null:
		return null
	if size.x < 0 or size.y < 0:
		return null
	setup.map_region = Rect2i(position, size)
	for entry: Variant in faction_list:
		if not entry is String:
			return null
		setup.factions.append(StringName(entry))
	for entry: Variant in company_list:
		var company := Company.from_dict(entry)
		if company == null:
			return null
		setup.companies.append(company)
	for entry: Variant in condition_list:
		var side := Conditions.from_dict(entry)
		if side == null:
			return null
		setup.conditions.append(side)
	if setup.conditions.size() != setup.factions.size():
		return null
	if not setup.missions.is_empty() and setup.missions.size() != setup.factions.size():
		return null
	return setup


## Vector2i from a JSON pair [x, y] of integral numbers; null otherwise.
static func vector_or_null(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	var x: Variant = CommandCodec.to_int_or_null(value[0])
	var y: Variant = CommandCodec.to_int_or_null(value[1])
	if x == null or y == null:
		return null
	return Vector2i(x, y)
