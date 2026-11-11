class_name UnitDefinition
extends Resource
## Static data for a unit type. Instances are kept as .tres files in data/units/.

## Size of a tactical hex in metres: the scale of the weapon ranges (TASK-131a).
const HEX_METRES := 250
const FIRE_DIRECT := &"direct"
const FIRE_INDIRECT := &"indirect"

@export var id: StringName
@export var display_name: String
## Label above the unit (translation key, at most 6 characters): a short real designation
## (M1A2, T-72B3); units without one (squads) use their class abbreviation (INF).
@export var short_name: String
## Unit class id from docs/design/units/classes.json: infantry, tank or mlrs.
@export var unit_class: StringName
## How the unit moves (catalog `mobility`): foot, wheeled or tracked.
@export var mobility: StringName = &"foot"
@export var max_hp: int = 10
@export var move_points: int = 3
@export var attack: int = 4
@export var defense: int = 2
## Weapon reach in real metres (TASK-131a, GDD "Stat derivation rules" → "Attack range"),
## converted to hexes of HEX_METRES by effective_hexes() / max_hexes() / min_hexes(). Up to the
## effective range a shot has its full hit chance, falling linearly to 50 % at the maximum
## range (the last hex where the unit may fire); targets closer than the minimum cannot be hit
## (0 = none). The defaults reach exactly the adjacent hex.
@export var effective_range_m: int = 250
@export var max_range_m: int = 250
@export var min_range_m: int = 0
## FIRE_DIRECT (needs line of sight, LineOfSight) or FIRE_INDIRECT (ignores it).
@export var fire_mode: StringName = FIRE_DIRECT
## Sound ids (TASK-123) looked up in data/audio/sound_bank.tres by the view: the shot, the engine
## loop while the unit moves (`none` = silent) and the running-gear loop (`tracks`, `wheels`;
## `none` for infantry).
@export var fire_sound: StringName = &"rifle"
@export var engine_sound: StringName = &"none"
@export var move_sound: StringName = &"none"

## Hexes of full effect: floor(effective_range_m / HEX_METRES).
@warning_ignore("integer_division")
func effective_hexes() -> int:
	return effective_range_m / HEX_METRES


## The last hex distance the unit may fire at: floor(max_range_m / HEX_METRES).
@warning_ignore("integer_division")
func max_hexes() -> int:
	return max_range_m / HEX_METRES


## Hex distances below this cannot be hit: ceil(min_range_m / HEX_METRES); 0 = no minimum.
@warning_ignore("integer_division")
func min_hexes() -> int:
	return (min_range_m + HEX_METRES - 1) / HEX_METRES


## True for indirect fire (artillery): it ignores line of sight.
func is_indirect() -> bool:
	return fire_mode == FIRE_INDIRECT
