class_name WreckLife
extends RefCounted
## Lifecycle bookkeeping of one wreck (TASK-065), no nodes: the smoke thins after the first
## turn and stops after SMOKE_TURNS `turn_started` events; a living unit ending a move on the
## wreck's tile hides it for good. Wrecks are pure scenery – they never touch game state.

const SMOKE_TURNS := 3
## Share of the smoke rate left once the first turn is over.
const THIN_FACTOR := 0.5

var coord: Vector2i
var hidden := false
var _turns := 0


func _init(wreck_coord := Vector2i.ZERO) -> void:
	coord = wreck_coord


## A turn started somewhere in the battle (any player).
func on_turn_started() -> void:
	_turns += 1


## A living unit finished a move on `to`. Returns true when this hides the wreck now.
func on_unit_moved(to: Vector2i) -> bool:
	if hidden or to != coord:
		return false
	hidden = true
	return true


func turns() -> int:
	return _turns


func smoke_active() -> bool:
	return not hidden and _turns < SMOKE_TURNS


## Smoke rate factor: full during the first turn, thin afterwards, 0 when it has stopped.
func smoke_factor() -> float:
	if not smoke_active():
		return 0.0
	return 1.0 if _turns == 0 else THIN_FACTOR


## The flickering fire light burns during the first turn only.
func fire_active() -> bool:
	return not hidden and _turns == 0
