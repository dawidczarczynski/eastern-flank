class_name OperationalPace
extends Resource
## One pace of the route preview (TASK-092c): how many move points a formation spends per turn
## and whether its route avoids enemy zones of control. TASK-092d replaces the paces with
## postures read from the same numbers.

@export var id: StringName
## Move points spent per turn.
@export var budget: int = 8
## Plan around the zones of control of enemy formations.
@export var avoid_contact: bool = false
