class_name UnitStatus
extends RefCounted
## Pure helpers for unit marker/label state. No scene access.


## A unit is "done" when it cannot move and has nothing left to attack.
## With command points (TASK-091) a not yet activated unit of the player to move is done too
## once no point is left: it cannot act, while activated units keep their normal look.
static func is_done(state: GameState, unit: Unit) -> bool:
	if unit.owner_id == state.current_player and not state.can_activate(unit):
		return true
	if unit.moves_left != 0:
		return false
	return unit.has_attacked or AttackCommand.valid_targets(state, unit.id).is_empty()


## Pixel width of an HP bar fill for `hp` of `max_hp` on a bar `width` wide.
static func hp_fill_width(hp: int, max_hp: int, width: int) -> int:
	if max_hp <= 0:
		return 0
	return roundi(width * clampf(float(hp) / max_hp, 0.0, 1.0))
