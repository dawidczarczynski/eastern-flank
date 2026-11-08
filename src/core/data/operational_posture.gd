class_name OperationalPosture
extends Resource
## A posture of a formation on the operational map (TASK-092d, GDD "Orders and postures"): how
## much of its move points a formation spends per turn and whether its route avoids enemy zones
## of control. One data/operational/postures/<id>.tres per posture.

const POSTURES_DIR := "res://data/operational/postures/"
const NAMES: Array[StringName] = [&"march", &"advance", &"defend"]

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## Share (percent) of the formation's move_points spent per turn, 1 … 100.
@export var move_percent: int = 100
## Plan around the zones of control of enemy formations (OperationalRoutes.plan).
@export var avoids_contact: bool = false
## Defence bonus the posture gives in a battle (TASK-094a, BattleSetup.Conditions.position_bonus),
## -3 … 3: defend +1, advance 0, march -1.
@export var position_bonus: int = 0


## The posture data/operational/postures/<posture_id>.tres; null when there is none.
static func find(posture_id: StringName) -> OperationalPosture:
	if not NAMES.has(posture_id):
		return null
	var path := POSTURES_DIR + String(posture_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as OperationalPosture


## "" when the posture is valid, otherwise what is wrong.
func problem() -> String:
	if move_percent < 1 or move_percent > 100:
		return "move_percent %d outside 1 … 100" % move_percent
	if position_bonus < -3 or position_bonus > 3:
		return "position_bonus %d outside -3 … 3" % position_bonus
	return ""


## Move points spent per turn by a formation with `move_points`: rounded down, at least 1.
func budget(move_points: int) -> int:
	return maxi(1, move_points * move_percent / 100)
