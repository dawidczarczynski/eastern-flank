class_name OperationDefinition
extends Resource
## An operation (TASK-092b): map, the two sides and the start order of battle. Instances are kept
## as data/operations/<id>.tres; Operation builds an OperationalState from one.

const OPERATIONS_DIR := "res://data/operations/"

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## Imported map id (ImportedMap.find).
@export var map_id: StringName
## Side of each player (index = player); exactly two.
@export var sides: Array[SideDefinition] = []
## Player who moves first (0 or 1).
@export var first_player: int = 0
## Calendar date (YYYY-MM-DD) on which turn 1 starts (OperationalClock).
@export var start_date: String = ""
## Posture (OperationalPosture id) every formation starts in.
@export var initial_posture: StringName = &"defend"
## Hexes around a formation that belong to its side in the front line (FrontLine).
@export var front_range: int = 3
## Escalation level the operation starts at (0 .. ladder top - 1, TASK-115); also the calm floor.
@export var initial_escalation: int = 1
## Start stance of each country on the map (TASK-114).
@export var countries: Array[CountrySetup] = []
## Start formations; their order is the order in which orders execute.
@export var formations: Array[FormationPlacement] = []


## The operation data/operations/<operation_id>.tres; null when there is none.
static func find(operation_id: StringName) -> OperationDefinition:
	var file_name := String(operation_id)
	if file_name == "" or not file_name.is_valid_filename() or file_name.contains("."):
		return null
	var path := OPERATIONS_DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as OperationDefinition
