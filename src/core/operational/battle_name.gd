class_name BattleName
extends RefCounted
## The two-line name of a battle (TASK-168): a situation phrase ("Contact with the enemy") from
## the setup and the viewer's role, and the nearest named place of the map. Pure and computed on
## demand – nothing is stored in a setup or a save. Translation happens in the view layer.

const ASSAULT := &"ASSAULT"
const ASSAULT_TOWN := &"ASSAULT_TOWN"
const ASSAULT_FOREST := &"ASSAULT_FOREST"
const ASSAULT_RIVER := &"ASSAULT_RIVER"
const DEFENCE := &"DEFENCE"
const DEFENCE_TOWN := &"DEFENCE_TOWN"
const CONTACT_ENEMY := &"CONTACT_ENEMY"

const KEYS: Array[StringName] = [
	ASSAULT,
	ASSAULT_TOWN,
	ASSAULT_FOREST,
	ASSAULT_RIVER,
	DEFENCE,
	DEFENCE_TOWN,
	CONTACT_ENEMY,
]

const COMPASS: Array[String] = [
	"DIR_E", "DIR_SE", "DIR_S", "DIR_SW", "DIR_W", "DIR_NW", "DIR_N", "DIR_NE"
]
## Closer than this (km) the bare place name is enough.
const NEAR_KM := 1.5


## Situation key of `setup` seen by `viewer`; &"" for a scenario battle (no operational name).
## `crossing`: the objective hex lies on a river / bridge (caller's cheap lookup).
static func situation(setup: BattleSetup, viewer: int, crossing := false) -> StringName:
	if setup == null or setup.attacker < 0 or setup.missions.is_empty():
		return &""
	for mission in setup.missions:
		if mission != null and mission.task == &"hold_out":
			return CONTACT_ENEMY
	if setup.attacker == viewer:
		if setup.terrain == &"water" or crossing:
			return ASSAULT_RIVER
		if setup.terrain == &"urban":
			return ASSAULT_TOWN
		if setup.terrain == &"forest":
			return ASSAULT_FOREST
		return ASSAULT
	return DEFENCE_TOWN if setup.terrain == &"urban" else DEFENCE


## Situation keys by player, [for player 0, for player 1] – what the battle events carry so the
## journal and the result screen can name a battle after the setup is gone.
static func situations(setup: BattleSetup) -> Array[StringName]:
	return [situation(setup, 0), situation(setup, 1)]


## Nearest place to `coord`: {name, km, dir}; `km` is 0 and `dir` "" closer than NEAR_KM; {} when
## the map is null or has no places.
static func place(map: ImportedMap, coord: Vector2i) -> Dictionary:
	if map == null or map.place_count() == 0:
		return {}
	var at := Hex.to_world(coord, 1.0)
	var here := Vector2(at.x, at.z)
	var best := -1
	var best_distance := INF
	for i in map.place_count():
		var distance := here.distance_to(map.place_at(i)["position"])
		if distance < best_distance:
			best_distance = distance
			best = i
	var found: Dictionary = map.place_at(best)
	var km := best_distance * map.hex_spacing_m / Hex.SQRT3 / 1000.0
	if km < NEAR_KM:
		return {"name": found["name"], "km": 0, "dir": ""}
	var offset: Vector2 = here - found["position"]  # from the place to the hex; +y is south
	var sector := posmod(roundi(atan2(offset.y, offset.x) / (TAU / 8.0)), 8)
	return {"name": found["name"], "km": roundi(km), "dir": COMPASS[sector]}
