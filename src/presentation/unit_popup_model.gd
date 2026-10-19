class_name UnitPopupModel
extends RefCounted
## Pure model of the unit hover card (TASK-021). Returns untranslated English strings;
## the view translates them. No nodes, no tr().

const DONE_COLOR := Color("#a19f95")
const MOVES_SCALE := 6.0
const RANGE_SCALE := 6.0
const STAT_SCALE := 10.0
const _OFFSET_X := 24.0
const _FLIP_OFFSET_X := 344.0
const _FLIP_MARGIN := 330.0
const _EDGE := 8.0
const _OFFSET_Y := 80.0
const _TOP := 96.0
const _BOTTOM := 16.0


## Keys: type (class label key, e.g. CLASS_TANK), faction, color, name (display_name), hp,
## max_hp, segments (Array[Color]), stats (Array of {label, value: String, fill: float}),
## status, status_color.
static func build(state: GameState, unit: Unit, viewer_player: int) -> Dictionary:
	var definition := unit.definition
	var max_hp := definition.max_hp
	var fill_color := UiPalette.hp_color(unit.hp, max_hp)
	var segments: Array[Color] = []
	for i in max_hp:
		segments.append(fill_color if i < unit.hp else UiPalette.HP_EMPTY)
	# Same sum as AttackCommand, so the card shows the defense the unit fights with.
	var terrain_defense := state.grid.defense_bonus(unit.coord)
	var defense := definition.defense + terrain_defense
	var stats: Array[Dictionary] = [
		_stat("Attack", str(definition.attack), definition.attack / STAT_SCALE),
		_stat("Defense", _defense_text(definition.defense, terrain_defense), defense / STAT_SCALE),
		_stat(
			"Moves",
			"%d/%d" % [unit.moves_left, definition.move_points],
			unit.moves_left / MOVES_SCALE
		),
		_stat("Range", str(definition.attack_range), definition.attack_range / RANGE_SCALE),
	]
	var status := _status(state, unit, viewer_player)
	var faction_color := UiPalette.faction_color(state, unit.owner_id)
	return {
		"type": "CLASS_%s" % String(definition.unit_class).to_upper(),
		"faction": UiPalette.faction_name(state, unit.owner_id),
		"color": faction_color,
		"name": definition.display_name,
		"hp": unit.hp,
		"max_hp": max_hp,
		"segments": segments,
		"stats": stats,
		"status": status[0],
		"status_color": status[1],
	}


## Top-left of the card for the cursor `mouse`, a `viewport` of the given size and a `card`
## of the real size: right of the cursor, flipped left near the right edge, kept below the
## top bar and inside the bottom edge.
static func placement(mouse: Vector2, viewport: Vector2, card: Vector2) -> Vector2:
	var x := mouse.x + _OFFSET_X
	if x + _FLIP_MARGIN > viewport.x:
		x = mouse.x - _FLIP_OFFSET_X
	x = maxf(_EDGE, x)
	var max_y := viewport.y - card.y - _BOTTOM
	var y := _TOP
	if max_y > _TOP:
		y = clampf(mouse.y - _OFFSET_Y, _TOP, max_y)
	return Vector2(x, y)


## Effective defense, with the base + terrain breakdown when the terrain adds anything.
static func _defense_text(base: int, terrain_bonus: int) -> String:
	if terrain_bonus == 0:
		return str(base)
	return "%d (%d%+d)" % [base + terrain_bonus, base, terrain_bonus]


static func _stat(label: String, value: String, fill: float) -> Dictionary:
	return {"label": label, "value": value, "fill": clampf(fill, 0.0, 1.0)}


## [status key, colour].
static func _status(state: GameState, unit: Unit, viewer_player: int) -> Array:
	if unit.owner_id != viewer_player:
		return ["Enemy unit", UiPalette.faction_color(state, unit.owner_id)]
	if UnitStatus.is_done(state, unit):
		return ["Done this turn", DONE_COLOR]
	if unit.has_attacked:
		return ["Ready · already attacked", UiPalette.HP_HIGH]
	return ["Ready", UiPalette.HP_HIGH]
