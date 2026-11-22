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
## Land-cover raster of the whole layer (TASK-108g, ADR 0028): `land_cover_width` x
## `land_cover_height` square cells of `land_cover_cell_m` metres, row 0 north; the centre of cell
## (0, 0) (north-west) is at (`land_cover_origin_easting`, `land_cover_origin_northing`). Stored in
## windows per chunk (TacticalChunk.cover). Cell size 0 = a layer without a raster.
@export var land_cover_cell_m: float = 0.0
@export var land_cover_width: int
@export var land_cover_height: int
@export var land_cover_origin_easting: float
@export var land_cover_origin_northing: float
## Satellite colour raster of the whole layer (TASK-192a, ADR 0031): `colour_width` x
## `colour_height` sRGB pixels of `colour_cell_m` metres, row 0 north; the centre of pixel (0, 0)
## (north-west) is at (`colour_origin_easting`, `colour_origin_northing`). Stored as one JPEG
## window per chunk (TacticalChunk.colour_*), decoded on first use. 0 / empty = none.
@export var colour_cell_m: float = 0.0
@export var colour_width: int
@export var colour_height: int
@export var colour_origin_easting: float
@export var colour_origin_northing: float
@export var colour_sources: String

## Folder of the chunk files ("" for a layer built in memory).
var _folder := ""
## Chunk index (Vector2i) -> decoded planes (PackedByteArray, TacticalChunk.PLANES planes).
var _planes: Dictionary = {}
var _chunk_sizes: Dictionary = {}  # chunk index -> Vector2i (width, height)
## Chunk index (Vector2i) -> its TacticalChunk (kept for the compressed cover window) / the
## decoded cover window (PackedByteArray, loaded on first use by region_land_cover).
var _chunks: Dictionary = {}
var _covers: Dictionary = {}
## Chunk index (Vector2i) -> its decoded colour window (ColourRaster in global raster pixels, or
## null when it has none or does not decode).
var _colours: Dictionary = {}


## The layer data/maps/<layer_id>/layer.tres; null when there is none or the id is not a plain name.
static func find(layer_id: StringName) -> TacticalLayer:
	var name := String(layer_id)
	if name == "" or not name.is_valid_filename() or name.contains("."):
		return null
	return from_folder(MAPS_DIR + name + "/")


## The layer in `folder` (ending in "/": layer.tres and its chunk files); null when there is none.
static func from_folder(folder: String) -> TacticalLayer:
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
			_chunks[key] = chunk
	_planes[key] = planes
	return planes


## Adds the chunk `key` of a layer built in memory (tests, hand-made layers) with its cover
## window; its hex planes stay those of `from_grid`.
func add_cover_chunk(key: Vector2i, chunk: TacticalChunk) -> void:
	_chunks[key] = chunk
	_covers.erase(key)
	_colours.erase(key)


## True when the layer has a land-cover raster (layers imported before TASK-108g have none).
func has_land_cover() -> bool:
	return land_cover_cell_m > 0.0 and land_cover_width > 0 and land_cover_height > 0


## The land cover of the cut `region` (see `region_grid`) plus `margin` world units around it,
## clamped to the raster, in the cut's world frame (local tile (0, 0) centred at world (0, 0)).
## Null when the layer has no raster or the region is bad; cells of a missing chunk read OPEN.
func region_land_cover(region: Rect2i, margin: float = 0.0) -> LandCover:
	if not has_land_cover() or region_problem(region) != "":
		return null
	var m := metres_per_world_unit()
	var c := land_cover_cell_m
	var corner := Hex.to_world(
		MapGenerator.offset_to_axial(region.position.x, region.position.y), TerrainField.HEX_SIZE
	)
	var corner_e := origin_easting + corner.x * m
	var corner_n := origin_northing - corner.z * m
	var half := Hex.SQRT3 * 0.5
	var world := Rect2(
		-half - margin,
		-1.0 - margin,
		Hex.SQRT3 * region.size.x + half + 2.0 * margin,
		1.5 * (region.size.y - 1) + 2.0 + 2.0 * margin
	)
	var i0 := clampi(
		floori((corner_e + world.position.x * m - land_cover_origin_easting) / c),
		0,
		land_cover_width - 1
	)
	var i1 := clampi(
		ceili((corner_e + world.end.x * m - land_cover_origin_easting) / c),
		i0,
		land_cover_width - 1
	)
	var j0 := clampi(
		floori((land_cover_origin_northing - corner_n + world.position.y * m) / c),
		0,
		land_cover_height - 1
	)
	var j1 := clampi(
		ceili((land_cover_origin_northing - corner_n + world.end.y * m) / c),
		j0,
		land_cover_height - 1
	)
	var rect := Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1)
	var cell_origin := Vector2(
		(land_cover_origin_easting + i0 * c - corner_e) / m,
		(corner_n - land_cover_origin_northing + j0 * c) / m
	)
	return LandCover.from_cells(_cover_cells(rect), rect.size.x, rect.size.y, cell_origin, c / m)


## Cells of the global raster rectangle `rect`, row-major, row 0 north, gathered from the cover
## windows of the chunks around it (OPEN where a chunk or its window is missing).
func _cover_cells(rect: Rect2i) -> PackedByteArray:
	var c := land_cover_cell_m
	var keys: Array[Vector2i] = []
	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	# A window edge lies within a hex of its chunk's edge: two hexes of slack find every window.
	var slack := Vector2i(2, 2)
	var last_tile := Vector2i(width - 1, height - 1)
	for corner: Vector2i in [rect.position, rect.end]:
		var tile := projected_to_offset(
			land_cover_origin_easting + corner.x * c, land_cover_origin_northing - corner.y * c
		)
		for t: Vector2i in [tile - slack, tile + slack]:
			var key := _chunk_key(t.clamp(Vector2i.ZERO, last_tile))
			low = low.min(key)
			high = high.max(key)
	for cy in range(low.y, high.y + 1):
		for cx in range(low.x, high.x + 1):
			keys.append(Vector2i(cx, cy))
	# Windows overlapping the rectangle, sorted west to east, so each row is appended in order.
	var windows: Array[Rect2i] = []
	var cells: Array[PackedByteArray] = []
	for key in keys:
		_planes_at(key * chunk_size)
		var chunk: TacticalChunk = _chunks.get(key)
		if chunk == null or not chunk.cover_rect().intersects(rect):
			continue
		if not _covers.has(key):
			_covers[key] = chunk.decode_cover()
		var decoded: PackedByteArray = _covers[key]
		if decoded.is_empty():
			continue
		windows.append(chunk.cover_rect())
		cells.append(decoded)
	var order: Array[int] = []
	for k in windows.size():
		order.append(k)
	order.sort_custom(
		func(a: int, b: int) -> bool: return windows[a].position.x < windows[b].position.x
	)
	var out := PackedByteArray()
	var gap := PackedByteArray()
	for y in range(rect.position.y, rect.end.y):
		var x := rect.position.x
		for k in order:
			var w := windows[k]
			if y < w.position.y or y >= w.end.y or w.end.x <= x or w.position.x >= rect.end.x:
				continue
			if w.position.x > x:
				gap.resize(w.position.x - x)
				gap.fill(LandCover.Kind.OPEN)
				out.append_array(gap)
				x = w.position.x
			var end := mini(w.end.x, rect.end.x)
			var base := (y - w.position.y) * w.size.x - w.position.x
			out.append_array(cells[k].slice(base + x, base + end))
			x = end
		if x < rect.end.x:
			gap.resize(rect.end.x - x)
			gap.fill(LandCover.Kind.OPEN)
			out.append_array(gap)
	return out


## True when the layer has a satellite colour raster (TASK-192a; older layers have none).
func has_colour_layer() -> bool:
	return colour_cell_m > 0.0 and colour_width > 0 and colour_height > 0


## sRGB colour of the ground at `x_m` metres east and `z_m` metres south of tile (0, 0)'s centre,
## bilinear between pixel centres and clamped to the raster's edge, read from the colour window of
## the chunk around the point; transparent black when the layer has no colour or the window is
## missing.
func sample(x_m: float, z_m: float) -> Color:
	if not has_colour_layer():
		return Color(0.0, 0.0, 0.0, 0.0)
	var c := colour_cell_m
	var fx := clampf(
		(origin_easting + x_m - colour_origin_easting) / c, 0.0, float(colour_width - 1)
	)
	var fy := clampf(
		(colour_origin_northing - origin_northing + z_m) / c, 0.0, float(colour_height - 1)
	)
	var pixel := Vector2i(
		mini(floori(fx), maxi(colour_width - 2, 0)), mini(floori(fy), maxi(colour_height - 2, 0))
	)
	var need := Rect2i(pixel, Vector2i(mini(2, colour_width), mini(2, colour_height)))
	var tile := projected_to_offset(
		colour_origin_easting + pixel.x * c, colour_origin_northing - pixel.y * c
	)
	var centre := _chunk_key(tile.clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1)))
	for dy in [0, -1, 1]:
		for dx in [0, -1, 1]:
			var key: Vector2i = centre + Vector2i(dx, dy)
			var raster := _colour_window(key)
			if raster == null:
				continue
			var window := Rect2i(Vector2i(raster.origin / c), raster.size())
			if window.encloses(need):
				return raster.sample(fx * c, fy * c)
	return Color(0.0, 0.0, 0.0, 0.0)


## The decoded colour window of chunk `key` with its origin at the window's first pixel (frame:
## metres from the centre of raster pixel (0, 0)); null when there is none.
func _colour_window(key: Vector2i) -> ColourRaster:
	if _colours.has(key):
		return _colours[key]
	var raster: ColourRaster = null
	if key.x >= 0 and key.y >= 0 and key.x * chunk_size < width and key.y * chunk_size < height:
		_planes_at(key * chunk_size)
		var chunk: TacticalChunk = _chunks.get(key)
		if chunk != null and not chunk.colour_jpg.is_empty():
			raster = ColourRaster.from_jpg(
				chunk.colour_jpg,
				chunk.colour_width,
				chunk.colour_height,
				colour_cell_m,
				Vector2(chunk.colour_column, chunk.colour_row) * colour_cell_m
			)
	_colours[key] = raster
	return raster


## Colour windows decoded so far (tests).
func loaded_colour_windows() -> int:
	var count := 0
	for key: Vector2i in _colours:
		if _colours[key] != null:
			count += 1
	return count


## Chunks decoded so far (tests, the debug preview's load statistics).
func loaded_chunks() -> int:
	var count := 0
	for key: Vector2i in _planes:
		if not (_planes[key] as PackedByteArray).is_empty():
			count += 1
	return count
