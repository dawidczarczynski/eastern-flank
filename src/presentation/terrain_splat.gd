class_name TerrainSplat
extends RefCounted
## Pure per-vertex ground layer weights for the terrain shader (TASK-055): which of the six
## CC0 ground materials (TerrainTextures.LAYERS) show at a vertex, from its tile's terrain
## type, slope, height and two noises. The mesh stores layers 0-3 in ARRAY_COLOR and 4-5 in
## ARRAY_CUSTOM0; assets/shaders/terrain.gdshader blends them.
## Usage: TerrainSplat.weights(Terrain.Type.HILLS, 1.0 - normal.y, y, 0.0, moisture, macro)

const LAYER_COUNT := 6
## Layer indices (same order as the texture arrays).
const GRASS := 0
const DRY_GRASS := 1
const DIRT := 2
const MUD := 3
const GRAVEL := 4
const ROCK := 5

## Plains: dry grass over the macro noise range (the former vertex-colour dry patches)...
const DRY_FROM := 0.55
const DRY_TO := 0.75
const DRY_MAX := 0.75
## ...and bare dirt patches where the fine moisture noise exceeds DIRT_PATCH_FROM.
const DIRT_PATCH_FROM := 0.8
const DIRT_PATCH_TO := 0.95
const DIRT_PATCH_MAX := 0.4
## Forest floor: dirt (needles, leaf litter) with some grass; trees come from the scatter.
const FOREST_DIRT := 0.6
## Rock by slope (1 - normal.y) on all land, and on high ground (as the old rock colouring).
const ROCK_SLOPE_FROM := 0.22
const ROCK_SLOPE_TO := 0.45
const ROCK_HEIGHT_FROM := 1.3
const ROCK_HEIGHT_TO := 1.8
const ROCK_HEIGHT_MAX := 0.85
## Gravel peaks at the rock/grass transition (rock weight 0.5).
const GRAVEL_MAX := 0.45
## Shore: land up to SHORE_BAND above the water level gets mud (at most SHORE_MUD_MAX) and dirt.
const SHORE_BAND := 0.12
const SHORE_MUD_MAX := 0.7
const SHORE_DIRT_MAX := 0.25


## Six weights summing to 1. `terrain` is a Terrain.Type, or -1 off the map (plains rules).
## `slope` = 1 - normal.y, `height` the vertex height, `moisture` a fine noise in [0, 1]
## (> DIRT_PATCH_FROM: dirt patches on plains), `macro` the large-scale dry/moist noise in
## [0, 1] (> DRY_FROM: dry grass).
static func weights(
	terrain: int, slope: float, height: float, water_level: float, moisture: float, macro: float
) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(LAYER_COUNT)
	if terrain == Terrain.Type.WATER and height < water_level:
		w[MUD] = 1.0  # lake / river bed under the transparent water
		return w
	# Base cover.
	var dry := TerrainNoise.smooth(DRY_FROM, DRY_TO, macro) * DRY_MAX
	if terrain == Terrain.Type.FOREST:
		w[DIRT] = FOREST_DIRT
		w[GRASS] = 1.0 - FOREST_DIRT
	else:
		var patch := TerrainNoise.smooth(DIRT_PATCH_FROM, DIRT_PATCH_TO, moisture) * DIRT_PATCH_MAX
		w[DIRT] = patch
		w[DRY_GRASS] = (1.0 - patch) * dry
		w[GRASS] = (1.0 - patch) * (1.0 - dry)
	# Rock on steep or high ground, gravel at its edge; the base cover keeps the rest.
	var rock := TerrainNoise.smooth(ROCK_SLOPE_FROM, ROCK_SLOPE_TO, slope)
	rock = maxf(
		rock, TerrainNoise.smooth(ROCK_HEIGHT_FROM, ROCK_HEIGHT_TO, height) * ROCK_HEIGHT_MAX
	)
	var gravel := minf(1.0 - rock, GRAVEL_MAX * 4.0 * rock * (1.0 - rock))
	_scale(w, 1.0 - rock - gravel)
	w[ROCK] += rock
	w[GRAVEL] += gravel
	# Shore band above the water.
	var shore := clampf(1.0 - (height - water_level) / SHORE_BAND, 0.0, 1.0)
	var mud := minf(shore, SHORE_MUD_MAX)
	var dirt := minf(shore, 1.0 - mud) * SHORE_DIRT_MAX
	_scale(w, 1.0 - mud - dirt)
	w[MUD] += mud
	w[DIRT] += dirt
	return w


## One pass of neighbour averaging over a row-major vertex grid (`columns` x `rows`, LAYER_COUNT
## weights per vertex): each vertex becomes the mean of itself and its neighbours within one
## step (3 x 3, clipped at the border). Sums stay 1.
static func smooth(w: PackedFloat32Array, columns: int, rows: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(w.size())
	for j in rows:
		for i in columns:
			var o := (j * columns + i) * LAYER_COUNT
			var count := 0
			for nj in range(maxi(j - 1, 0), mini(j + 2, rows)):
				for ni in range(maxi(i - 1, 0), mini(i + 2, columns)):
					var n := (nj * columns + ni) * LAYER_COUNT
					for layer in LAYER_COUNT:
						result[o + layer] += w[n + layer]
					count += 1
			for layer in LAYER_COUNT:
				result[o + layer] /= count
	return result


static func _scale(w: PackedFloat32Array, factor: float) -> void:
	for layer in LAYER_COUNT:
		w[layer] *= factor
