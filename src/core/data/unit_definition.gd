class_name UnitDefinition
extends Resource
## Static data for a unit type. Instances are kept as .tres files in data/units/.

@export var id: StringName
@export var display_name: String
## Label above the unit (translation key): a short real designation (M1A2); generic units
## without one use their class abbreviation (INF, TNK, ART).
@export var short_name: String
## Unit class id from docs/design/units/classes.json: infantry, tank or mlrs.
@export var unit_class: StringName
@export var max_hp: int = 10
@export var move_points: int = 3
@export var attack: int = 4
@export var defense: int = 2
@export var attack_range: int = 1
