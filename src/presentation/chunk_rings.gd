class_name ChunkRings
extends Resource
## Distance rings of the chunked world (TASK-072b, ChunkManager): per chunk layer the draw reach in
## metres around the camera target. A layer's chunks are built within `build_factor` x its reach
## and freed beyond `free_factor` x the build radius (hysteresis: a camera wobbling around the
## build border builds and frees nothing). LOW quality multiplies every reach by
## `low_quality_factor`. Presentation data kept as data/visuals/chunk_rings.tres; metres become
## world units through MapScale, so the rings stay right at any map scale.

const PATH := "res://data/visuals/chunk_rings.tres"

## Layer id (StringName) -> draw reach in metres, measured from the camera target (XZ).
@export var reach_m: Dictionary = {}
## Build ring = reach x build_factor.
@export var build_factor := 1.5
## Free ring = build ring x free_factor.
@export var free_factor := 1.2
## LOW quality: every reach x this.
@export var low_quality_factor := 0.66


## The rings of data/visuals/chunk_rings.tres.
static func load_default() -> ChunkRings:
	return load(PATH) as ChunkRings


## Draw reach of `layer` in world units (0 for an unknown layer: it builds nothing).
func reach(layer: StringName, low_quality := false) -> float:
	var metres: float = reach_m.get(layer, 0.0)
	return MapScale.to_units(metres) * (low_quality_factor if low_quality else 1.0)


## Chunks of `layer` whose nearest point lies within this distance (world units) of the camera
## target are built.
func build_radius(layer: StringName, low_quality := false) -> float:
	return reach(layer, low_quality) * build_factor


## Built chunks of `layer` farther than this from the camera target are freed.
func free_radius(layer: StringName, low_quality := false) -> float:
	return build_radius(layer, low_quality) * free_factor
