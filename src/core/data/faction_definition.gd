class_name FactionDefinition
extends Resource
## Static data for a faction (a country). Instances are kept as .tres files in data/factions/
## and looked up by id through FactionRegistry.
## Rule (ADR-0002/0007): core and AI never read the Presentation group.

@export var id: StringName
## Translation key, translated in the UI.
@export var display_name: String
## 2–3 letters for the HUD badge.
@export var short_name: String
## Unit types this faction may field.
@export var roster: Array[UnitDefinition] = []

@export_group("Presentation")
## Main UI colour (HUD strip, markers, labels).
@export var color: Color = Color.WHITE
## Dark text colour drawn on top of `color` (HUD badge).
@export var ink_color: Color = Color.BLACK
## Three camouflage colours of the faction's units.
@export var camo: PackedColorArray = PackedColorArray()
## Colour of infantry vests.
@export var vest_color: Color = Color.BLACK


## True when a unit type with the same id as `definition` is in the roster.
func has_unit(definition: UnitDefinition) -> bool:
	return definition != null and find_unit(definition.id) != null


## Roster entry with the given unit id; null if the faction does not field it.
func find_unit(unit_id: StringName) -> UnitDefinition:
	for entry: UnitDefinition in roster:
		if entry != null and entry.id == unit_id:
			return entry
	return null
