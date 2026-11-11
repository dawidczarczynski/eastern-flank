class_name OrderDefinition
extends Resource
## Numbers and class availability of one unit order (TASK-081a, GDD "Unit orders"), kept in
## data/orders/<id>.tres and read through OrderRules.

@export var id: StringName
## Unit classes (UnitDefinition.unit_class) that have this order.
@export var allowed_classes: Array[StringName] = []
## Defence added to a unit while the order lasts (Dig in).
@export var defence_bonus: int = 0
## Range in hexes for ordered fire (Blind fire, Smoke); 0 = not used.
@export var min_range: int = 0
@export var max_range: int = 0
## Attack modifier of the order (Blind fire -1).
@export var attack_modifier: int = 0
