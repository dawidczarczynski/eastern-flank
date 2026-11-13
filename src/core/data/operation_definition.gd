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
## Start installations of both sides (TASK-097a); their order is the setup order.
@export var installations: Array[InstallationPlacement] = []
## Starting strike stock per player (index = player): {means id: count}; empty = none.
@export var strike_stock: Array[Dictionary] = []
## Stock each player gains per round, per player: {means id: count}.
@export var strike_resupply: Array[Dictionary] = []
## Strikes each player may launch per own turn.
@export var strikes_per_turn: int = 2
## Rounds a hit silences an air-defence site (SEAD, TASK-098a).
@export var suppression_rounds: int = 2
## Integrity a damaged, not destroyed, installation regains each round.
@export var repair_per_round: int = 5
## Objectives of the operational AI, both sides (AiGoal.player; TASK-102a).
@export var ai_goals: Array[AiGoal] = []
## Victory objectives (hex or installation, side, points; TASK-107a); the AI goals reuse them.
@export var objectives: Array[OperationObjective] = []
## The Gap road link: ordered road hexes from Suwałki to Marijampolė (OperationVictory).
@export var gap_chain: Array[Vector2i] = []
## Rounds of the operation; at the end of the last one the higher score wins.
@export var round_limit: int = 30
## Side 1 wins at once when it holds the whole chain at the end of this many consecutive rounds.
@export var closed_rounds_to_win: int = 2
## A score difference below this is a draw.
@export var draw_margin: int = 5
## Points for side 0 while the Gap is open / for side 1 while it is closed, at the end.
@export var gap_open_points: int = 10
@export var gap_closed_points: int = 10
## Points lost per net escalation step caused (max(0, caused - deescalated)).
@export var escalation_penalty: int = 3
## Packages of outside support, in setup order (TASK-121).
@export var support_packages: Array[SupportPackage] = []
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
