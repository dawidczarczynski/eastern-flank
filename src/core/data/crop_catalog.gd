class_name CropCatalog
extends Resource
## The crop kinds of the farmland look (TASK-200), kept as data/fields/crops.tres: wheat, green
## cereal, rape, stubble, ploughed and fallow / meadow, each a CropKind.

const DEFAULT_PATH := "res://data/fields/crops.tres"

@export var kinds: Array[CropKind] = []


## The shipped catalog.
static func load_default() -> CropCatalog:
	return load(DEFAULT_PATH) as CropCatalog


## The entry named `kind_name` (FieldParcels.CROPS), or null.
func get_kind(kind_name: StringName) -> CropKind:
	for k in kinds:
		if k.kind_name == kind_name:
			return k
	return null
