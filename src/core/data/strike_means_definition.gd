class_name StrikeMeansDefinition
extends Resource
## A means of deep strike (TASK-097a, GDD "Deep strikes"): cruise missile, ballistic missile,
## strike drone. Kept as data/strike/<id>.tres; every number is an [ASSUMPTION] balanced later.

const DIR := "res://data/strike/"
## Means shipped in data/strike/.
const SHIPPED: Array[StringName] = [&"cruise", &"ballistic", &"strike_drone"]

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## Chance (%) that a missile that was not intercepted hits, 0-100.
@export_range(0, 100) var accuracy_pct: int = 80
## How much the target's air defence bites (% of its interception chance), 0-200.
@export_range(0, 200) var interceptability_pct: int = 100
## Integrity an installation loses per hit.
@export var damage: int = 35
## Strength points a formation's strongest company loses per hit.
@export var formation_damage: int = 2
## Largest salvo of one strike.
@export var max_salvo: int = 4
## Range in hexes, measured from the nearest hex of the side's own or aligned countries.
@export var range_hexes: int = 50


## The means data/strike/<means_id>.tres; null when there is none.
static func find(means_id: StringName) -> StrikeMeansDefinition:
	var file_name := String(means_id)
	if file_name == "" or not file_name.is_valid_filename() or file_name.contains("."):
		return null
	var path := DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StrikeMeansDefinition


## Every shipped means by id.
static func shipped() -> Dictionary:
	var result := {}
	for means_id in SHIPPED:
		result[means_id] = find(means_id)
	return result


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	if id == &"":
		return "empty id"
	if accuracy_pct < 0 or accuracy_pct > 100:
		return "accuracy_pct %d outside 0 .. 100" % accuracy_pct
	if interceptability_pct < 0 or interceptability_pct > 200:
		return "interceptability_pct %d outside 0 .. 200" % interceptability_pct
	if damage <= 0 or formation_damage <= 0:
		return "damage and formation_damage must be positive"
	if max_salvo < 1 or range_hexes < 1:
		return "max_salvo and range_hexes must be at least 1"
	return ""
