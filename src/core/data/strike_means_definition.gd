class_name StrikeMeansDefinition
extends Resource
## A means of deep strike (TASK-097a, TASK-141a, GDD "Deep strikes"): one real named weapon
## (Iskander-M, JASSM-ER ...). Kept as data/strike/<id>.tres; range is the real one / 5 km,
## the other numbers are [ASSUMPTION]s balanced later (TASK-103).

const DIR := "res://data/strike/"
## Means shipped in data/strike/ (Russia, then NATO).
const SHIPPED: Array[StringName] = [
	&"iskander_m",
	&"kinzhal",
	&"kalibr",
	&"kh101",
	&"geran_2",
	&"jassm_er",
	&"storm_shadow",
	&"atacms",
	&"prsm",
	&"homar_k",
	&"warmate",
	&"tomahawk",
]
## The weapon classes: a label for the view and the manual only, no rule reads it.
const WEAPON_CLASSES: Array[StringName] = [
	&"cruise", &"ballistic", &"aeroballistic", &"rocket", &"drone", &"loitering"
]
## `side` of a weapon usable by either side (test data only in v1).
const ANY_SIDE := -1

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
## One of WEAPON_CLASSES (view and manual only).
@export var weapon_class: StringName = &"cruise"
## The player that may hold the weapon (0 NATO, 1 Russia) or ANY_SIDE. Checked where stock enters
## (Operation.from_definition, StrikeRules.add_stock) through `usable_by`.
@export_range(-1, 1) var side: int = ANY_SIDE
## Launch platform as short text, e.g. "truck launcher" (view only; launchers come with TASK-098).
@export var platform: String = ""
## NATO / manufacturer designation, e.g. "9M723" (view only).
@export var designation: String = ""


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


## Whether `player` may hold this weapon in its stock.
func usable_by(player: int) -> bool:
	return side == ANY_SIDE or side == player


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
	return _label_problem()


## The weapon class and side (TASK-141a); "" when valid.
func _label_problem() -> String:
	if not WEAPON_CLASSES.has(weapon_class):
		return "unknown weapon_class '%s'" % weapon_class
	if side < ANY_SIDE or side > 1:
		return "side %d outside -1 .. 1" % side
	return ""
