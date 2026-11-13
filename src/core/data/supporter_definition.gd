class_name SupporterDefinition
extends Resource
## An off-map supporter (TASK-121, GDD "Outside support"): a third party that can send help to a
## fixed side. Not a country: no hexes, no stance. Instances are kept as data/supporters/<id>.tres.

const SUPPORTERS_DIR := "res://data/supporters/"
## Explicit table (exported builds list `.remap` files, not the .tres).
const IDS: Array[StringName] = [&"nato_allies", &"north_korea", &"china", &"iran"]

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## The side (player index) the supporter helps.
@export var side: int = 0


## The supporter data/supporters/<supporter_id>.tres; null when there is none.
static func find(supporter_id: StringName) -> SupporterDefinition:
	if not IDS.has(supporter_id):
		return null
	return load(SUPPORTERS_DIR + String(supporter_id) + ".tres") as SupporterDefinition
