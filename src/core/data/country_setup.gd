class_name CountrySetup
extends Resource
## Start stance of one country in an operation (TASK-114; a sub-resource of OperationDefinition).

@export var country: CountryDefinition
## &"neutral", &"aligned" or &"belligerent".
@export var stance: StringName = &"neutral"
## Side (player index) of an aligned / belligerent country; -1 for a neutral one.
@export var side: int = -1
## Side the country goes to when the war widens (-1 = none, 0, 1).
@export var leaning: int = -1
## Formations that appear on the map when the country becomes belligerent on its leaning side
## (TASK-118). Every placement's `player` is the `leaning`; `coord` lies in this country.
@export var contribution: Array[FormationPlacement] = []
