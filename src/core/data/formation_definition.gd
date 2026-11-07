class_name FormationDefinition
extends Resource
## A formation type of the operational layer (TASK-092b, GDD "Formations"): a battalion-sized
## group of companies. Instances are kept as .tres files in data/formations/<id>.tres; an
## operation (OperationDefinition) places named formations of these types on its map.

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## Faction id (FactionRegistry) whose roster the companies come from.
@export var faction: StringName
## Echelon of the counter: &"battalion" for now.
@export var echelon: StringName = &"battalion"
## &"mechanised", &"armoured" or &"artillery" (read by the staff map symbols).
@export var formation_class: StringName
## Operational move points per turn.
@export var move_points: int = 8
## Companies in order; company n (from 1) gets the ref "<formation id>/<n>".
@export var companies: Array[UnitDefinition] = []


## Full strength: the sum of the companies' max_hp.
func strength() -> int:
	var total := 0
	for unit in companies:
		if unit != null:
			total += unit.max_hp
	return total
