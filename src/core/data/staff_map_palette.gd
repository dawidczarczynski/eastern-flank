class_name StaffMapPalette
extends Resource
## Colours and line widths of the paper staff map (TASK-093a). One resource,
## data/operational/staff_map_palette.tres; the scene has no colour literals. Widths and spacings
## are in hex units (centre to corner = 1).

const PATH := "res://data/operational/staff_map_palette.tres"

## Behind the map sheet (outside the theatre).
@export var desk := Color("#3b3a34")
@export var paper := Color("#ece4cc")
## Fills per terrain; a transparent colour is not drawn (plains = bare paper).
@export var plains := Color(0, 0, 0, 0)
@export var fields := Color("#f1e9b9")
@export var forest := Color("#a7c487")
@export var hills := Color("#d9c9a1")
@export var water := Color("#9cc6e2")
@export var urban := Color("#8e8e8a")
@export var marsh := Color("#cadbc4")
@export var marsh_hatch := Color("#5b8fc2")
@export var marsh_hatch_spacing := 0.16
@export var road := Color("#d8532a")
@export var road_width := 0.11
@export var river := Color("#3f86c6")
@export var river_width := 0.09
## Hillshade: lit and shaded tint, strength 0..1 (opacity at full shade).
@export var shade_light := Color("#fffdf0")
@export var shade_dark := Color("#33334a")
@export var shade_strength := 0.5
@export var grid := Color(0.25, 0.2, 0.1, 0.22)
@export var hover_outline := Color("#e8b04a")
@export var smoothing := 2


## The fill colour of a terrain type.
func fill(terrain: Terrain.Type) -> Color:
	var colours := {
		Terrain.Type.FIELDS: fields,
		Terrain.Type.FOREST: forest,
		Terrain.Type.HILLS: hills,
		Terrain.Type.WATER: water,
		Terrain.Type.URBAN: urban,
		Terrain.Type.MARSH: marsh,
	}
	return colours.get(terrain, plains)
