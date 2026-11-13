class_name MeansGrant
extends Resource
## One strike-means grant of a support package (TASK-122): `count` of the named weapon are added
## to the recipient's strike stock when the package is delivered.

## Id of a StrikeMeansDefinition, e.g. &"kh101"; its `side` must allow the package's side.
@export var means: StringName
@export var count: int = 0
