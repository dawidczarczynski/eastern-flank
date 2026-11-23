class_name CoverLook
extends RefCounted
## The look of a land-cover raster (TASK-108g, ADR 0028 "Sub-hex land cover; hexes are mechanics
## only"): what the ground, trees and grass of a point show, read from LandCover instead of the
## hex Terrain.Type. Only built for a real raster (`make` returns null for the fallback cover), so
## a caller holding a null CoverLook keeps the hex-type code path it always had.
##
## Forest edges are soft and noisy, never hex-shaped: the forest weight is bilinear between the
## raster's cell centres, shifted by a two-octave value noise (integer hashes of the noise lattice,
## no RandomNumberGenerator, no GameState.rng) and cut at 0.5. A point whose four nearest cells
## are all forest (or none is) never changes – only the edges wander, by up to about half a cell.
## Pure and read-only after construction: safe on the planning threads.

## Noise lattice spacings in raster cells (coarse and fine octave) and their amplitudes.
const NOISE_CELLS := 2.5
const NOISE_FINE_CELLS := 0.9
const NOISE_AMPLITUDE := 0.6
const NOISE_FINE_AMPLITUDE := 0.3
## Half width of the soft forest edge (in forest weight) of `forest_k`.
const SOFT_EDGE := 0.2
const NOISE_SALT := 0x108A
const FINE_SALT := 0x108B
## The cover Kinds a real field parcel (TASK-215b) shows on, as bits (1 << Kind): open land,
## grass, field, orchard, scrub and bare ground, not forest, water, villages or marsh.
const PARCEL_KINDS_MASK := (
	(1 << LandCover.Kind.OPEN)
	| (1 << LandCover.Kind.GRASS)
	| (1 << LandCover.Kind.FIELD)
	| (1 << LandCover.Kind.ORCHARD)
	| (1 << LandCover.Kind.SCRUB)
	| (1 << LandCover.Kind.BARE)
)

var cover: LandCover
var _cells := PackedByteArray()
var _width := 0
var _height := 0
var _origin := Vector2.ZERO
var _inverse_cell := 1.0
var _cell := 1.0
var _rect := Rect2()


## The look of `land_cover`, or null when it is null or the fallback (no raster).
static func make(land_cover: LandCover) -> CoverLook:
	if land_cover == null or not land_cover.has_raster():
		return null
	return CoverLook.new(land_cover)


func _init(land_cover: LandCover) -> void:
	cover = land_cover
	_cells = land_cover.cells()
	_width = land_cover.width
	_height = land_cover.height
	_origin = land_cover.origin
	_cell = land_cover.cell_size
	_inverse_cell = 1.0 / land_cover.cell_size
	_rect = land_cover.world_rect()


## The Terrain.Type whose ground look a cover Kind shows (TerrainSplat, GrassPlanner): the rule
## class for forest, fields, villages, marsh and water; PLAINS for the open kinds (an orchard is
## grass under fruit trees, scrub and bare ground are open land).
static func look_terrain(kind: int) -> int:
	match kind:
		LandCover.Kind.FOREST:
			return Terrain.Type.FOREST
		LandCover.Kind.FIELD:
			return Terrain.Type.FIELDS
		LandCover.Kind.URBAN:
			return Terrain.Type.URBAN
		LandCover.Kind.MARSH:
			return Terrain.Type.MARSH
		LandCover.Kind.WATER:
			return Terrain.Type.WATER
	return Terrain.Type.PLAINS


## World rectangle the raster covers. Beyond it the look is open land (OPEN, no forest) – what
## the off-map margin showed before the raster – instead of the raster's stretched edge cells.
func world_rect() -> Rect2:
	return _rect


## Bilinear forest weight (0..1) at world (x, z), before the edge noise.
func forest_weight(x: float, z: float) -> float:
	return kind_weight(LandCover.Kind.FOREST, x, z)


## Bilinear weight (0..1) of the cover Kind `kind` at world (x, z) (between the four nearest cell
## centres), before the edge noise; beyond the raster all OPEN.
func kind_weight(kind: int, x: float, z: float) -> float:
	if not _rect.has_point(Vector2(x, z)):
		return 1.0 if kind == LandCover.Kind.OPEN else 0.0
	var u := clampf((x - _origin.x) * _inverse_cell, 0.0, _width - 1)
	var v := clampf((z - _origin.y) * _inverse_cell, 0.0, _height - 1)
	var i := mini(floori(u), _width - 1)
	var j := mini(floori(v), _height - 1)
	var fu := u - i
	var fv := v - j
	var i2 := mini(i + 1, _width - 1)
	var j2 := mini(j + 1, _height - 1)
	var w := 0.0
	if _cells[j * _width + i] == kind:
		w += (1.0 - fu) * (1.0 - fv)
	if _cells[j * _width + i2] == kind:
		w += fu * (1.0 - fv)
	if _cells[j2 * _width + i] == kind:
		w += (1.0 - fu) * fv
	if _cells[j2 * _width + i2] == kind:
		w += fu * fv
	return w


## Bilinear weight (0..1) of the cover Kinds whose bits are set in `mask` (1 << Kind) at world
## (x, z), as kind_weight; beyond the raster the OPEN bit decides.
func kinds_weight(mask: int, x: float, z: float) -> float:
	if not _rect.has_point(Vector2(x, z)):
		return 1.0 if (mask & (1 << LandCover.Kind.OPEN)) != 0 else 0.0
	var u := clampf((x - _origin.x) * _inverse_cell, 0.0, _width - 1)
	var v := clampf((z - _origin.y) * _inverse_cell, 0.0, _height - 1)
	var i := mini(floori(u), _width - 1)
	var j := mini(floori(v), _height - 1)
	var fu := u - i
	var fv := v - j
	var i2 := mini(i + 1, _width - 1)
	var j2 := mini(j + 1, _height - 1)
	var w := 0.0
	if (mask & (1 << _cells[j * _width + i])) != 0:
		w += (1.0 - fu) * (1.0 - fv)
	if (mask & (1 << _cells[j * _width + i2])) != 0:
		w += fu * (1.0 - fv)
	if (mask & (1 << _cells[j2 * _width + i])) != 0:
		w += (1.0 - fu) * fv
	if (mask & (1 << _cells[j2 * _width + i2])) != 0:
		w += fu * fv
	return w


## Whether a real field parcel shows at world (x, z) (TASK-215b): inside the noisy outline of
## the PARCEL_KINDS_MASK kinds, i.e. not under the forest, water, village or marsh a separate
## OSM area maps over the farmland. The shader's twin is in_cover(xz, COVER_PARCEL_MASK).
func allows_parcel(x: float, z: float) -> bool:
	var w := kinds_weight(PARCEL_KINDS_MASK, x, z)
	if w <= 0.0 or w >= 1.0:
		return w > 0.5
	return w + edge_noise(x, z) > 0.5


## Whether world (x, z) lies inside the noisy outline of the cover Kind `kind` (as is_forest).
func has_kind(kind: int, x: float, z: float) -> bool:
	var w := kind_weight(kind, x, z)
	if w <= 0.0 or w >= 1.0:
		return w > 0.5
	return w + edge_noise(x, z) > 0.5


## The forest weight with the edge noise (may leave 0..1 only on edges); forest where > 0.5.
func forest_value(x: float, z: float) -> float:
	var w := kind_weight(LandCover.Kind.FOREST, x, z)
	if w <= 0.0 or w >= 1.0:
		return w
	return w + edge_noise(x, z)


## Whether world (x, z) shows forest (trees, forest floor).
func is_forest(x: float, z: float) -> bool:
	return forest_value(x, z) > 0.5


## Soft forest share (0..1) at world (x, z): 1 inside, 0 outside, a smooth step SOFT_EDGE wide
## around the noisy edge (density of edge plants and the far canopy).
func forest_k(x: float, z: float) -> float:
	var t := clampf((forest_value(x, z) - 0.5 + SOFT_EDGE) / (2.0 * SOFT_EDGE), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The cover Kind at world (x, z) without forest: the raster cell's kind, or, on a forest cell,
## the kind of the nearest-weighted non-forest cell around it (OPEN when all four are forest).
func open_kind_at(x: float, z: float) -> int:
	if not _rect.has_point(Vector2(x, z)):
		return LandCover.Kind.OPEN
	var u := clampf((x - _origin.x) * _inverse_cell, 0.0, _width - 1)
	var v := clampf((z - _origin.y) * _inverse_cell, 0.0, _height - 1)
	var i := clampi(roundi(u), 0, _width - 1)
	var j := clampi(roundi(v), 0, _height - 1)
	var own := int(_cells[j * _width + i])
	if own != LandCover.Kind.FOREST:
		return own
	var i0 := mini(floori(u), _width - 1)
	var j0 := mini(floori(v), _height - 1)
	var best := int(LandCover.Kind.OPEN)
	var best_w := -1.0
	for dj in 2:
		for di in 2:
			var ci := mini(i0 + di, _width - 1)
			var cj := mini(j0 + dj, _height - 1)
			var code := int(_cells[cj * _width + ci])
			if code == LandCover.Kind.FOREST:
				continue
			var w := (1.0 - absf(u - ci)) * (1.0 - absf(v - cj))
			if w > best_w:
				best_w = w
				best = code
	return best


## The Terrain.Type whose look world (x, z) shows: FOREST on forest (noisy edge), else
## look_terrain of the open kind there.
func terrain_at(x: float, z: float) -> int:
	if is_forest(x, z):
		return Terrain.Type.FOREST
	return look_terrain(open_kind_at(x, z))


## Edge noise in [-(A + a) / 2, (A + a) / 2] at world (x, z) (A, a: the two amplitudes).
func edge_noise(x: float, z: float) -> float:
	var coarse := _value_noise(x, z, _cell * NOISE_CELLS, NOISE_SALT)
	var fine := _value_noise(x, z, _cell * NOISE_FINE_CELLS, FINE_SALT)
	return (coarse - 0.5) * NOISE_AMPLITUDE + (fine - 0.5) * NOISE_FINE_AMPLITUDE


## Value noise in [0, 1): integer-hashed lattice values of spacing `spacing`, smoothly
## interpolated.
static func _value_noise(x: float, z: float, spacing: float, salt: int) -> float:
	var u := x / spacing
	var v := z / spacing
	var i := floori(u)
	var j := floori(v)
	var fu := u - i
	var fv := v - j
	fu = fu * fu * (3.0 - 2.0 * fu)
	fv = fv * fv * (3.0 - 2.0 * fv)
	var a := lerpf(_lattice(i, j, salt), _lattice(i + 1, j, salt), fu)
	var b := lerpf(_lattice(i, j + 1, salt), _lattice(i + 1, j + 1, salt), fu)
	return lerpf(a, b, fv)


## Unit hash [0, 1) of a lattice point (ScatterPlanner's 32-bit finaliser).
static func _lattice(i: int, j: int, salt: int) -> float:
	var h := ScatterPlanner.tile_seed(salt, Vector2i(i, j), NOISE_SALT)
	return float(h & 0xFFFFFF) / 16777216.0
