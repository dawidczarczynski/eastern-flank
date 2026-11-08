class_name TacticalLayer
extends Resource
## The tactical (250 m hex) terrain of a whole theatre, imported once and cut on demand for a
## contact battle (TASK-094b, ADR 0018 "Tactical layer"): data/maps/<id>/layer.tres plus one
## TacticalChunk per `chunk_size` square (chunk_<cx>_<cy>.tres), written by
## tools/import_map.py --profile=layer. Rectangular offset layout like ImportedMap (row 0 north,
## odd rows shifted east); geo-reference as ImportedMap: tile (0, 0) at (`origin_easting`,
## `origin_northing`) of `crs`, world x east, world z south, one world unit =
## hex_spacing_m / sqrt 3.
## Chunks load lazily and stay decoded in this instance (`region_grid` reads only the chunks a
## region touches).

const MAPS_DIR := "res://data/maps/"
const INDEX_FILE := "layer.tres"

@export var id: StringName
@export var display_name: String
## Columns and rows of the whole layer (offset layout).
@export var width: int
@export var height: int
## Hexes per chunk side (even, so every chunk starts on an even row).
@export var chunk_size: int = 128
@export var hex_spacing_m: float = 250.0
@export var crs: String
@export var origin_easting: float
@export var origin_northing: float
## [min_lon, min_lat, max_lon, max_lat] of the layer (WGS84 degrees), for reference.
@export var bbox_wgs84: PackedFloat64Array
## Stored height h (uint16) means metres = h * elevation_step_m - elevation_offset_m.
@export var elevation_offset_m: float = 100.0
@export var elevation_step_m: float = 0.1
## Game elevation of a cut, as the tactical import (ADR 0018): land = land_min + (metres - lowest
## land tile of the cut) * scale, scale = exaggeration x true scale, reduced so the highest land
## tile stays at top_elevation; water = water_elevation.
@export var land_min: float = 0.12
@export var top_elevation: float = 2.2
@export var water_elevation: float = -0.4
@export var exaggeration: float = 1.5
## Attribution of the source data (see data/maps/CREDITS).
@export var sources: String

## Folder of the chunk files ("" for a layer built in memory).
var _folder := ""
## Chunk index (Vector2i) -> decoded planes (PackedByteArray, TacticalChunk.PLANES planes).
var _planes: Dictionary = {}
var _chunk_sizes: Dictionary = {}  # chunk index -> Vector2i (width, height)


## The layer data/maps/<layer_id>/layer.tres; null when there is none or the id is not a plain name.
static func find(layer_id: StringName) -> TacticalLayer:
	var name := String(layer_id)
	if name == "" or not name.is_valid_filename() or name.contains("."):
		return null
	var folder := MAPS_DIR + name + "/"
	if not ResourceLoader.exists(folder + INDEX_FILE):
		return null
	var layer := load(folder + INDEX_FILE) as TacticalLayer
	if layer != null:
		layer._folder = folder
	return layer


## A layer held in memory (tests, hand-made grids): the tiles (col, row) of `grid` in offset
## layout, `columns` x `rows`; missing tiles read as water. Elevation metres from
## `grid.elevation_m` when set, else 0. `chunk` is the chunk side (even).
static func from_grid(
	grid: HexGrid,
	columns: int,
	rows: int,
	spacing: float = 250.0,
	easting: float = 0.0,
	northing: float = 0.0,
	chunk: int = 128
) -> TacticalLayer:
	var layer := TacticalLayer.new()
	layer.id = &"in_memory"
	layer.width = columns
	layer.height = rows
	layer.chunk_size = chunk
	layer.hex_spacing_m = spacing
	layer.origin_easting = easting
	layer.origin_northing = northing
	for cy in range(0, rows, chunk):
		for cx in range(0, columns, chunk):
			var w := mini(chunk, columns - cx)
			var h := mini(chunk, rows - cy)
			var n := w * h
			var planes := PackedByteArray()
			planes.resize(TacticalChunk.PLANES * n)
			for r in h:
				for c in w:
					var axial := MapGenerator.offset_to_axial(cx + c, cy + r)
					var i := r * w + c
					var t := Terrain.Type.WATER
					var metres := 0.0
					if grid.has_tile(axial):
						t = grid.get_terrain(axial)
						if grid.has_elevation_m(axial):
							metres = grid.elevation_m(axial)
					planes[i] = t
					planes[n + i] = grid.road_links(axial)
					planes[2 * n + i] = grid.river_links(axial)
					var stored := clampi(
						roundi((metres + layer.elevation_offset_m) / layer.elevation_step_m),
						0,
						65535
					)
					planes[3 * n + i] = stored & 0xFF
					planes[4 * n + i] = stored >> 8
			@warning_ignore("integer_division")
			var key := Vector2i(cx / chunk, cy / chunk)
			layer._planes[key] = planes
			layer._chunk_sizes[key] = Vector2i(w, h)
	return layer


## Metres of one world unit (TerrainField.HEX_SIZE).
func metres_per_world_unit() -> float:
	return hex_spacing_m / Hex.SQRT3


## Offset tile (column, row) containing the projected point; it may lie off the layer.
func projected_to_offset(p_easting: float, p_northing: float) -> Vector2i:
	var m := metres_per_world_unit()
	var world := Vector3((p_easting - origin_easting) / m, 0.0, (origin_northing - p_northing) / m)
	return MapGenerator.axial_to_offset(Hex.from_world(world, TerrainField.HEX_SIZE))


## Projected (easting, northing) of the centre of offset tile (column, row).
func offset_to_projected(tile: Vector2i) -> Vector2:
	var world := Hex.to_world(MapGenerator.offset_to_axial(tile.x, tile.y), TerrainField.HEX_SIZE)
	var m := metres_per_world_unit()
	return Vector2(origin_easting + world.x * m, origin_northing - world.z * m)


func has_offset(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height


## "" when `region` (offset columns / rows of this layer) can be cut, otherwise why not: it must be
## non-empty, inside the layer and start on an even row (so the cut keeps the odd-row shift).
func region_problem(region: Rect2i) -> String:
	if region.size.x <= 0 or region.size.y <= 0:
		return "empty region %s" % region
	if (
		region.position.x < 0
		or region.position.y < 0
		or region.end.x > width
		or region.end.y > height
	):
		return "region %s outside the %dx%d layer" % [region, width, height]
	if region.position.y % 2 != 0:
		return "region %s starts on an odd row" % region
	return ""


## Terrain of one offset tile of the layer (WATER off the layer or when its chunk is missing).
func terrain_at(tile: Vector2i) -> Terrain.Type:
	var planes := _planes_at(tile)
	if planes.is_empty():
		return Terrain.Type.WATER
	return planes[_index_in_chunk(tile)] as Terrain.Type


## Road link mask of one offset tile of the layer (0 off the layer).
func road_links_at(tile: Vector2i) -> int:
	var planes := _planes_at(tile)
	if planes.is_empty():
		return 0
	return planes[_chunk_area(tile) + _index_in_chunk(tile)]


## The cut `region` as a HexGrid in local coordinates: offset tile (c, r) of the cut = layer tile
## (region.position.x + c, region.position.y + r), so the battle map starts at (0, 0) like every
## other map. Terrain, road and river links (also those pointing out of the cut), real metres and
## game elevation scaled over the cut's own land tiles; authored elevation. Null with push_error
## for a bad region (`region_problem`) or a missing / malformed chunk.
func region_grid(region: Rect2i) -> HexGrid:
	var error := region_problem(region)
	if error != "":
		push_error("TacticalLayer '%s': %s" % [id, error])
		return null
	var grid := HexGrid.new()
	grid.authored_elevation = true
	var land_metres: Array[float] = []
	for r in region.size.y:
		for c in region.size.x:
			var tile := region.position + Vector2i(c, r)
			var planes := _planes_at(tile)
			if planes.is_empty():
				push_error("TacticalLayer '%s': chunk of tile %s missing" % [id, tile])
				return null
			var n := _chunk_area(tile)
			var i := _index_in_chunk(tile)
			var local := MapGenerator.offset_to_axial(c, r)
			var t := planes[i] as Terrain.Type
			grid.set_terrain(local, t)
			if planes[n + i] != 0:
				grid.set_road_links(local, planes[n + i])
			if planes[2 * n + i] != 0:
				grid.set_river_links(local, planes[2 * n + i])
			var stored := planes[3 * n + i] | (planes[4 * n + i] << 8)
			var metres := stored * elevation_step_m - elevation_offset_m
			grid.set_elevation_m(local, metres)
			if t != Terrain.Type.WATER:
				land_metres.append(metres)
	_set_game_elevation(grid, land_metres)
	return grid


## Game elevation of every tile of a cut (see `land_min`).
func _set_game_elevation(grid: HexGrid, land_metres: Array[float]) -> void:
	var low := 0.0
	var high := 0.0
	if not land_metres.is_empty():
		low = land_metres.min()
		high = land_metres.max()
	var scale := exaggeration / metres_per_world_unit()
	if high > low:
		scale = minf(scale, (top_elevation - land_min) / (high - low))
	for c in grid.coords():
		if grid.get_terrain(c) == Terrain.Type.WATER:
			grid.set_elevation(c, water_elevation)
		else:
			grid.set_elevation(c, land_min + (grid.elevation_m(c) - low) * scale)


func _chunk_key(tile: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(tile.x / chunk_size, tile.y / chunk_size)


func _chunk_area(tile: Vector2i) -> int:
	var size: Vector2i = _chunk_sizes.get(_chunk_key(tile), Vector2i.ZERO)
	return size.x * size.y


func _index_in_chunk(tile: Vector2i) -> int:
	var size: Vector2i = _chunk_sizes.get(_chunk_key(tile), Vector2i.ZERO)
	return (tile.y % chunk_size) * size.x + tile.x % chunk_size


## Decoded planes of the chunk holding `tile` (loaded on first use); empty off the layer or when
## the chunk file is missing or malformed.
func _planes_at(tile: Vector2i) -> PackedByteArray:
	if not has_offset(tile) or chunk_size <= 0:
		return PackedByteArray()
	var key := _chunk_key(tile)
	if _planes.has(key):
		return _planes[key]
	var planes := PackedByteArray()
	var path := "%schunk_%d_%d.tres" % [_folder, key.x, key.y]
	if _folder != "" and ResourceLoader.exists(path):
		var chunk := load(path) as TacticalChunk
		var expected := Vector2i(
			mini(chunk_size, width - key.x * chunk_size),
			mini(chunk_size, height - key.y * chunk_size)
		)
		if (
			chunk != null
			and chunk.column == key.x * chunk_size
			and chunk.row == key.y * chunk_size
			and Vector2i(chunk.width, chunk.height) == expected
		):
			planes = chunk.decode()
			_chunk_sizes[key] = expected
	_planes[key] = planes
	return planes


## Chunks decoded so far (tests, the debug preview's load statistics).
func loaded_chunks() -> int:
	var count := 0
	for key: Vector2i in _planes:
		if not (_planes[key] as PackedByteArray).is_empty():
			count += 1
	return count
