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
	else:
		name = _t(name)
	return PackedStringArray(
		[
			name,
			_t("HP %d/%d") % [unit.hp, definition.max_hp],
			_t("Moves %d/%d") % [unit.moves_left, definition.move_points],
			(
				_t("Attack %d · Defense %d · Range %d")
				% [definition.attack, definition.defense, definition.attack_range]
			),
			_t("Already attacked") if unit.has_attacked else _t("Ready to attack"),
		]
	)


## Static helper (no Object.tr()). test_localization.gd also scans string literals passed to `_t`.
static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
