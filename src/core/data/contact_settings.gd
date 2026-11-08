class_name ContactSettings
extends Resource
## How a contact battle's map is cut and set up (TASK-094b, GDD "Battle hand-off and
## auto-resolve"), kept in data/operational/contact.tres; read by ContactMap.

const PATH := "res://data/operational/contact.tres"

static var _default: ContactSettings

## Size of the cut in tactical hexes (offset columns x rows; 40 x 30 = 10 x 6.5 km at 250 m).
@export var width: int = 40
@export var height: int = 30
## Turn limit of a contact battle (the defender holds the field when it is reached).
@export var turn_limit: int = 12
## Smallest hex distance between two deployed companies (2 = at least one free hex between them);
## relaxed to 1 only when a side's third has no such tile left.
@export var deploy_spacing: int = 2
## Operational map id -> id of its tactical layer (data/maps/<id>/layer.tres).
@export var tactical_layers: Dictionary = {}


## The shipped data/operational/contact.tres, loaded once.
static func shipped() -> ContactSettings:
	if _default == null:
		_default = load(PATH) as ContactSettings
	return _default


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	if width < 3 or height < 3:
		return "the cut must be at least 3 x 3 hexes, is %d x %d" % [width, height]
	if turn_limit < 1:
		return "turn_limit must be at least 1"
	if deploy_spacing < 1:
		return "deploy_spacing must be at least 1"
	for key: Variant in tactical_layers:
		if (
			not (key is StringName or key is String)
			or not (tactical_layers[key] is StringName or tactical_layers[key] is String)
		):
			return "tactical_layers maps map ids to layer ids"
	return ""


## Tactical layer id of the operational map `map_id`; &"" when it has none.
func layer_for(map_id: StringName) -> StringName:
	for key: Variant in tactical_layers:
		if StringName(key) == map_id:
			return StringName(tactical_layers[key])
	return &""
