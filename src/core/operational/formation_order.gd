class_name FormationOrder
extends RefCounted
## A standing order of a formation (TASK-092d): move to `destination`. The posture lives on the
## Formation. Executed at the end of the turn (TASK-092e).

var destination: Vector2i


func _init(p_destination: Vector2i = Vector2i.ZERO) -> void:
	destination = p_destination
