class_name UnitInfo
extends RefCounted
## Pure text formatter for the selected unit info panel (HUD). It only formats fields of
## Unit / UnitDefinition – no game rules here.


## Returns exactly 5 lines: name, HP, moves, combat stats, attack readiness.
static func lines(unit: Unit) -> PackedStringArray:
	var definition := unit.definition
	var name := definition.display_name
	if name.is_empty():
		name = String(definition.id)
	return PackedStringArray(
		[
			name,
			"HP %d/%d" % [unit.hp, definition.max_hp],
			"Moves %d/%d" % [unit.moves_left, definition.move_points],
			(
				"Attack %d · Defense %d · Range %d"
				% [definition.attack, definition.defense, definition.attack_range]
			),
			"Already attacked" if unit.has_attacked else "Ready to attack",
		]
	)
