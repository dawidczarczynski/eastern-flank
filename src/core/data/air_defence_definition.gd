class_name AirDefenceDefinition
extends Resource
## An air-defence type (TASK-098a, GDD "Deep strikes"): the reach of a site and its chance to
## intercept each weapon class. Kept as data/air_defence/<id>.tres; every number is an
## [ASSUMPTION] balanced later (TASK-103). Radius in hexes, 1 hex = 5 km.

const DIR := "res://data/air_defence/"
## Types shipped in data/air_defence/, shortest reach first.
const SHIPPED: Array[StringName] = [&"mobile", &"short", &"medium", &"long"]

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## Real systems this type stands for (flavour only).
@export var examples: String = ""
## Hexes around the site in which it covers (the exact radius counts).
@export var radius_hexes: int = 4
## Interception chance (%) of an intact, active site per weapon class: {class: 0-100}; one key
## for each of StrikeMeansDefinition.WEAPON_CLASSES.
@export var intercept_pct: Dictionary = {}


## The type data/air_defence/<type_id>.tres; null when there is none.
static func find(type_id: StringName) -> AirDefenceDefinition:
	var file_name := String(type_id)
	if file_name == "" or not file_name.is_valid_filename() or file_name.contains("."):
		return null
	var path := DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AirDefenceDefinition


## Every shipped type by id.
static func shipped() -> Dictionary:
	var result := {}
	for type_id in SHIPPED:
		result[type_id] = find(type_id)
	return result


## Chance (%) against a weapon class; 0 for an unknown class.
func chance_against(weapon_class: StringName) -> int:
	return int(intercept_pct.get(weapon_class, 0))


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	if id == &"":
		return "empty id"
	if radius_hexes < 1:
		return "radius_hexes %d must be at least 1" % radius_hexes
	for weapon_class in StrikeMeansDefinition.WEAPON_CLASSES:
		if not intercept_pct.has(weapon_class):
			return "intercept_pct lacks '%s'" % weapon_class
	for key: Variant in intercept_pct:
		if not StrikeMeansDefinition.WEAPON_CLASSES.has(key):
			return "intercept_pct has unknown weapon class '%s'" % key
		if (
			not intercept_pct[key] is int
			or int(intercept_pct[key]) < 0
			or int(intercept_pct[key]) > 100
		):
			return "intercept_pct of '%s' is not an int in 0 .. 100" % key
	return ""
