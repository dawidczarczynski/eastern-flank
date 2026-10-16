class_name Unit
extends RefCounted
## State of a single unit on the map.

var id: int
var owner_id: int
var definition: UnitDefinition
var coord: Vector2i
var hp: int
var moves_left: int
var has_attacked: bool = false


func _init(p_id: int, p_owner_id: int, p_definition: UnitDefinition, p_coord: Vector2i) -> void:
	id = p_id
	owner_id = p_owner_id
	definition = p_definition
	coord = p_coord
	hp = p_definition.max_hp
	moves_left = p_definition.move_points


func is_alive() -> bool:
	return hp > 0
