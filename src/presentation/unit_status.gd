class_name UnitStatus
extends RefCounted
## Pure helpers for unit marker/label state. No scene access.


## A unit is "done" when it cannot move and has nothing left to attack.
static func is_done(state: GameState, unit: Unit) -> bool:
	if unit.moves_left != 0:
		return false
	return unit.has_attacked or AttackCommand.valid_targets(state, unit.id).is_empty()


## Pixel width of an HP bar fill for `hp` of `max_hp` on a bar `width` wide.
static func hp_fill_width(hp: int, max_hp: int, width: int) -> int:
	if max_hp <= 0:
		return 0
	return roundi(width * clampf(float(hp) / max_hp, 0.0, 1.0))
