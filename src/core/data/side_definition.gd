class_name SideDefinition
extends Resource
## A side of an operation (TASK-092b, GDD "Sides"): a player and a bloc. Instances are kept as
## data/sides/<id>.tres. Side differences are data only – no rule asks which side this is.

const SIDES_DIR := "res://data/sides/"

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## Faction that gives the side its colours and HUD; one of `factions`.
@export var lead_faction: StringName
## Factions whose formation types the side may field.
@export var factions: Array[StringName] = []


## The side data/sides/<side_id>.tres; null when there is none (or the id is not a plain name).
static func find(side_id: StringName) -> SideDefinition:
	var file_name := String(side_id)
	if file_name == "" or not file_name.is_valid_filename() or file_name.contains("."):
		return null
	var path := SIDES_DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as SideDefinition
