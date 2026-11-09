class_name EscalationLevel
extends Resource
## One rung of the escalation ladder (TASK-115, GDD "Escalation ladder").

@export var id: StringName
## Translation key (English), translated in the UI.
@export var display_name: String
## Strike target classes allowed at this level (ROE, TASK-097).
@export var strike_classes: Array[StringName] = []
