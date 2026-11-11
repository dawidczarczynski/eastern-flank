class_name RangeOverlayModel
extends RefCounted
## Pure model of the range overlay of a selected unit (TASK-131b): which hexes it can fire at.
## build() returns three sets of grid coordinates (the unit's own hex and off-map hexes never
## appear; hexes closer than the minimum range are not marked):
## - effective: min_hexes <= distance <= effective_hexes;
## - extended: effective_hexes < distance <= max_hexes (reduced hit chance);
## - blocked: the hexes of the two sets above that direct fire cannot see (LineOfSight); always
##   empty for artillery.
## The outline of the view is drawn around effective and effective + extended; blocked hexes are
## dimmed. Whole-map artillery simply gets every hex outside the minimum range.


static func build(state: GameState, unit: Unit) -> Dictionary:
	var definition := unit.definition
	var effective: Array[Vector2i] = []
	var extended: Array[Vector2i] = []
	var blocked: Array[Vector2i] = []
	var min_hexes := definition.min_hexes()
	var effective_hexes := definition.effective_hexes()
	var max_hexes := definition.max_hexes()
	var direct := not definition.is_indirect()
	for c in state.grid.coords():
		var d := Hex.distance(unit.coord, c)
		if d == 0 or d < min_hexes or d > max_hexes:
			continue
		if d <= effective_hexes:
			effective.append(c)
		else:
			extended.append(c)
		if direct and not LineOfSight.visible(state.grid, unit.coord, c):
			blocked.append(c)
	return {"effective": effective, "extended": extended, "blocked": blocked}
