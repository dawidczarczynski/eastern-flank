class_name CropKind
extends Resource
## One crop kind of the farmland look (TASK-200): its colours, row spacing, harvest-state tone and
## share of the parcels. Instances live in the CropCatalog (data/fields/crops.tres). Look data only:
## the simulation never reads it.

## FieldParcels.CROPS name this entry describes (wheat, green, rape, stubble, ploughed, meadow).
@export var kind_name: StringName
@export var display_name: String
## Plant colour (sRGB) of the standing crop and the furrow colour between the rows.
@export var colour: Color = Color.WHITE
@export var furrow: Color = Color.WHITE
## Distance between two rows in real metres (0.3-0.75 m); the plant width is a fraction of it.
@export var row_spacing_m: float = 0.5
@export_range(0.05, 1.0) var plant_frac: float = 0.6
## The colour of a parcel in its harvest state (ripe / drying / cut), shown on some parcels.
@export var harvest_tone: Color = Color.WHITE
## Weight of the kind in the region mix (the weights are normalised).
@export var weight: float = 1.0
## The parcel keeps the grass ground look instead of a crop colour (meadow / fallow).
@export var ground_look: bool = false
## Grass clump keep factor on the parcel (GrassPlanner): 0 on every crop, 1 on meadow.
@export var grass_keep: float = 0.0
