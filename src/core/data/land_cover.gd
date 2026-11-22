class_name LandCover
extends RefCounted
## The land cover under a battle map at sub-hex resolution (TASK-108g, ADR 0028 "Sub-hex land
## cover; hexes are mechanics only"): what the ground looks like, independent of the hex grid.
## Rules never read it – they read the hex Terrain.Type, which the importer derives from the same
## raster (the cells inside each hex).
##
## A raster cover holds one Kind per square cell of `cell_size` world units, row 0 north (world
## z grows south); cell (i, j) is centred at `origin` + (i, j) * cell_size. Points off the raster
## read the nearest edge cell. Built from an imported map (ImportedMap.land_cover) or a tactical
## layer cut (TacticalLayer.region_land_cover); `for_map` picks the source of a battle.
##
## Maps without a raster (the generated map, old data) get a fallback that expands the hex
## types: every point reads the kind of the hex it lies in (`kind_of_terrain`), with hard edges
## on the hex borders – the look such maps always had. `has_raster` tells the two apart.
##
## Pure and read-only; no randomness.

## Stored cell codes (import_map.py LAND_COVER): 0-6 are ImportedMap.COVER_*; ORCHARD, SCRUB and
## BARE are finer kinds of open ground whose rule class is PARENT (FIELD, GRASS, GRASS).
enum Kind { OPEN, GRASS, FIELD, URBAN, FOREST, MARSH, WATER, ORCHARD, SCRUB, BARE }

const KIND_COUNT := 10
## Rule class of every Kind (a sub-class -> its parent, the rest -> itself).
const PARENT: Array[int] = [
	Kind.OPEN,
	Kind.GRASS,
	Kind.FIELD,
	Kind.URBAN,
	Kind.FOREST,
	Kind.MARSH,
	Kind.WATER,
	Kind.FIELD,
	Kind.GRASS,
	Kind.GRASS,
]
## Sampling step (world units) of `share_in` on the fallback cover.
const FALLBACK_STEP := 0.125

## Raster size in cells (0 x 0 for the fallback).
var width := 0
var height := 0
## World (x, z) of the centre of cell (0, 0), the north-west one.
var origin := Vector2.ZERO
## World units of one cell side.
var cell_size := 1.0

var _cells := PackedByteArray()
var _grid: HexGrid


## A raster cover of `cells` (width * height Kind codes, row-major, row 0 north); null with
## push_error when the sizes do not match.
static func from_cells(
	cells: PackedByteArray, columns: int, rows: int, cell_origin: Vector2, size: float
) -> LandCover:
	if columns <= 0 or rows <= 0 or cells.size() != columns * rows or size <= 0.0:
		push_error("LandCover: %d cells for a %dx%d raster" % [cells.size(), columns, rows])
		return null
	var cover := LandCover.new()
	cover.width = columns
	cover.height = rows
	cover.origin = cell_origin
	cover.cell_size = size
	cover._cells = cells
	return cover


## The land-cover raster of an imported map in its world frame (tile (0, 0) centred at world
## (0, 0)); null when the map has none or it is malformed.
static func from_imported(map: ImportedMap) -> LandCover:
	var size := map.land_cover_width * map.land_cover_height
	if map.land_cover_cell_m <= 0.0 or size <= 0 or map.land_cover.is_empty():
		return null
	var cells := map.land_cover.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if cells.size() != size:
		return null
	var m := map.metres_per_world_unit()
	var cell_origin := Vector2(
		(map.land_cover_origin_easting - map.origin_easting) / m,
		(map.origin_northing - map.land_cover_origin_northing) / m
	)
	return from_cells(
		cells, map.land_cover_width, map.land_cover_height, cell_origin, map.land_cover_cell_m / m
	)


## The fallback cover of a map without a raster: the kind of the hex under every point.
static func from_grid(grid: HexGrid) -> LandCover:
	var cover := LandCover.new()
	cover._grid = grid if grid != null else HexGrid.new()
	return cover


## The cover of a battle's map (BattleSetup.map_id / map_region) whose rules grid is `grid`:
## the tactical layer's raster of the cut `region` plus `margin` world units around it, or the
## imported map's raster, else the fallback from `grid`. Never null.
static func for_map(
	map_id: StringName, region: Rect2i, grid: HexGrid, margin: float = 0.0
) -> LandCover:
	if map_id != BattleSetup.MAP_GENERATED_RIVER:
		var layer := TacticalLayer.find(map_id)
		if layer != null:
			var cut := layer.region_land_cover(region, margin)
			if cut != null:
				return cut
		else:
			var imported := ImportedMap.find(map_id)
			var whole := from_imported(imported) if imported != null else null
			if whole != null:
				return whole
	return from_grid(grid)


## The Kind a hex of terrain `t` shows on the fallback cover.
static func kind_of_terrain(t: Terrain.Type) -> Kind:
	match t:
		Terrain.Type.FOREST:
			return Kind.FOREST
		Terrain.Type.WATER:
			return Kind.WATER
		Terrain.Type.FIELDS:
			return Kind.FIELD
		Terrain.Type.URBAN:
			return Kind.URBAN
		Terrain.Type.MARSH:
			return Kind.MARSH
	return Kind.OPEN


## True for a real raster, false for the fallback that expands the hex types.
func has_raster() -> bool:
	return _grid == null


## The raw cells (width * height Kind codes, row 0 north), e.g. for an R8 texture; empty for
## the fallback.
func cells() -> PackedByteArray:
	return _cells


## World rectangle the raster cells cover (cell edges); empty for the fallback.
func world_rect() -> Rect2:
	if not has_raster():
		return Rect2()
	var half := Vector2.ONE * cell_size * 0.5
	return Rect2(origin - half, Vector2(width, height) * cell_size)


## Kind at world (x, z): the cell containing the point (the nearest edge cell off the raster), or
## the kind of the hex under it on the fallback (OPEN off the grid).
func class_at(x: float, z: float) -> Kind:
	if not has_raster():
		var c := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
		return kind_of_terrain(_grid.get_terrain(c)) if _grid.has_tile(c) else Kind.OPEN
	var i := clampi(floori((x - origin.x) / cell_size + 0.5), 0, width - 1)
	var j := clampi(floori((z - origin.y) / cell_size + 0.5), 0, height - 1)
	return _cells[j * width + i] as Kind


## Share (0..1) of `kind` in the world rectangle `rect`: of the raster cells whose centre lies in
## it (the cell under its centre when none does), or of a FALLBACK_STEP lattice of points on the
## fallback.
func share_in(rect: Rect2, kind: Kind) -> float:
	return shares_in(rect)[kind]


## Shares (0..1, KIND_COUNT entries summing to 1) of every Kind in `rect` (see `share_in`).
func shares_in(rect: Rect2) -> PackedFloat32Array:
	var shares := PackedFloat32Array()
	shares.resize(KIND_COUNT)
	var total := 0
	if has_raster():
		var i0 := maxi(0, ceili((rect.position.x - origin.x) / cell_size))
		var i1 := mini(width - 1, ceili((rect.end.x - origin.x) / cell_size) - 1)
		var j0 := maxi(0, ceili((rect.position.y - origin.y) / cell_size))
		var j1 := mini(height - 1, ceili((rect.end.y - origin.y) / cell_size) - 1)
		for j in range(j0, j1 + 1):
			var base := j * width
			for i in range(i0, i1 + 1):
				shares[_cells[base + i]] += 1.0
				total += 1
	else:
		var columns := maxi(1, floori(rect.size.x / FALLBACK_STEP))
		var rows := maxi(1, floori(rect.size.y / FALLBACK_STEP))
		var step := Vector2(rect.size.x / columns, rect.size.y / rows)
		for r in rows:
			for c in columns:
				var p := rect.position + step * Vector2(c + 0.5, r + 0.5)
				shares[class_at(p.x, p.y)] += 1.0
				total += 1
	if total == 0:
		var centre := rect.get_center()
		shares[class_at(centre.x, centre.y)] = 1.0
		return shares
	for k in KIND_COUNT:
		shares[k] /= total
	return shares


## Soft weight (0..1) of `kind` at world (x, z): bilinear between the four nearest cell centres,
## so it changes continuously everywhere – also across hex borders. The fallback is hard: 1 in
## the hexes that show `kind`, else 0.
func weight(kind: Kind, x: float, z: float) -> float:
	return weights_at(x, z)[kind]


## Soft weights (KIND_COUNT entries summing to 1) of every Kind at world (x, z) (see `weight`).
func weights_at(x: float, z: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(KIND_COUNT)
	if not has_raster():
		weights[class_at(x, z)] = 1.0
		return weights
	var u := clampf((x - origin.x) / cell_size, 0.0, width - 1)
	var v := clampf((z - origin.y) / cell_size, 0.0, height - 1)
	var i := mini(floori(u), width - 1)
	var j := mini(floori(v), height - 1)
	var fu := u - i
	var fv := v - j
	var i2 := mini(i + 1, width - 1)
	var j2 := mini(j + 1, height - 1)
	weights[_cells[j * width + i]] += (1.0 - fu) * (1.0 - fv)
	weights[_cells[j * width + i2]] += fu * (1.0 - fv)
	weights[_cells[j2 * width + i]] += (1.0 - fu) * fv
	weights[_cells[j2 * width + i2]] += fu * fv
	return weights
