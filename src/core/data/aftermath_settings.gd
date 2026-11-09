class_name AftermathSettings
extends Resource
## Numbers of a battle's consequences for the operation (TASK-095, GDD "Battle hand-off and
## auto-resolve"), kept in data/operational/aftermath.tres; read by BattleConsequences and
## OperationalOrders.budget. **[ASSUMPTION]** until calibrated.

const PATH := "res://data/operational/aftermath.tres"

static var _default: AftermathSettings

## Readiness (0 … 100) a battle costs the attacking / defending formation.
@export var readiness_loss_attacker: int = 15
@export var readiness_loss_defender: int = 10
## Readiness regained at the start of the owner's turn by a formation that did not fight in its
## last turn.
@export var readiness_recovery: int = 10
## Readiness below this counts as this much when the order budget is computed (percent).
@export var readiness_floor: int = 40


## The shipped data/operational/aftermath.tres, loaded once.
static func shipped() -> AftermathSettings:
	if _default == null:
		_default = load(PATH) as AftermathSettings
	return _default


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	if readiness_loss_attacker < 0 or readiness_loss_attacker > 100:
		return "readiness_loss_attacker must be within 0 … 100"
	if readiness_loss_defender < 0 or readiness_loss_defender > 100:
		return "readiness_loss_defender must be within 0 … 100"
	if readiness_recovery < 0 or readiness_recovery > 100:
		return "readiness_recovery must be within 0 … 100"
	if readiness_floor < 1 or readiness_floor > 100:
		return "readiness_floor must be within 1 … 100"
	return ""
