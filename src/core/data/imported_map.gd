class_name ImportedMap
extends Resource
## A tactical map imported from real geography by tools/import_map.py (TASK-087, ADR 0018):
## data/maps/<id>.tres. Rectangular offset layout like MapGenerator (row 0 north, odd rows shifted
## east), one character per tile in `terrain_rows`, elevation per tile in game units. The importer
## writes these files; nothing in the game edits them.
##
## Geo-reference: tile centres lie `hex_spacing_m` apart in the projected CRS `crs` (UTM), so one
## world unit (TerrainField.HEX_SIZE, centre to corner) is hex_spacing_m / sqrt(3) metres; world x
## grows east, world z grows south, and world (0, 0) – the centre of tile (0, 0) – is at
## (`origin_easting`, `origin_northing`).

## Terrain characters of `terrain_rows`.
const TERRAIN_CHARS := {
	"P": Terrain.Type.PLAINS,
	"F": Terrain.Type.FOREST,
	"H": Terrain.Type.HILLS,
	"W": Terrain.Type.WATER,
	"A": Terrain.Type.FIELDS,
	"U": Terrain.Type.URBAN,
	"M": Terrain.Type.MARSH,
}
## Characters of `road_rows` / `river_rows`: LINK_CHARS[mask] for a 6-bit link mask (bit i = a
## link towards tile + Hex.DIRECTIONS[i], HexGrid.road_links); "." = no link.
const LINK_CHARS := ".123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ#@"
## Imported maps live here as <id>.tres.
const MAPS_DIR := "res://data/maps/"

@export var id: StringName
@export var display_name: String
## Columns and rows (offset layout; tile (col, row) = MapGenerator.offset_to_axial(col, row)).
@export var width: int
@export var height: int
## Distance between neighbouring tile centres in metres (the tactical scale, 250 m).
@export var hex_spacing_m: float = 250.0
## Projected CRS of the origin, e.g. "EPSG:32634" (UTM 34N).
@export var crs: String
@export var origin_easting: float
@export var origin_northing: float
## [min_lon, min_lat, max_lon, max_lat] of the map's hexes (WGS84 degrees), for reference.
@export var bbox_wgs84: PackedFloat64Array
## Game elevation of a land tile = land_min + (elevation_m - reference_m) * vertical_scale.
@export var reference_m: float
@export var vertical_scale: float
## One string per row, one character per tile: P plains, F forest, H hills, W water, A fields,
## U urban, M marsh.
@export var terrain_rows: PackedStringArray
## Dominant land cover per tile (the importer's input for the terrain type; no rule reads it):
## . unmapped, G grass/meadow, A fields, U urban, F forest, M marsh, W water.
@export var cover_rows: PackedStringArray
## Road links per tile (TASK-108), one LINK_CHARS character per tile like `terrain_rows`; empty =
## no roads. Storage rule: a link between two land tiles is stored on both; a link from a land tile
## towards water or off the map only on the land tile (drawn, no rule effect); water has none.
@export var road_rows: PackedStringArray
## River links per tile, same encoding and storage rule; a tile with a link is a river hex.
@export var river_rows: PackedStringArray
## Mean DEM height of each tile in metres (row-major), the real data behind `elevation`.
@export var elevation_m: PackedFloat32Array
## Game elevation of each tile (row-major; water below 0, land from land_min up).
@export var elevation: PackedFloat32Array
## Attribution of the source data (see data/maps/CREDITS).
@export var sources: String


## The map data/maps/<map_id>.tres; null when there is none (or the id is not a plain name).
static func find(map_id: StringName) -> ImportedMap:
	var file_name := String(map_id)
	if file_name == "" or not file_name.is_valid_filename() or file_name.contains("."):
		return null
	var path := MAPS_DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ImportedMap


## "" when the data is consistent, otherwise what is wrong.
func problem() -> String:
	if width <= 0 or height <= 0 or hex_spacing_m <= 0.0:
		return "empty map %dx%d, spacing %s m" % [width, height, hex_spacing_m]
	if terrain_rows.size() != height:
		return "%d terrain rows, expected %d" % [terrain_rows.size(), height]
	if elevation.size() != width * height:
		return "%d elevations, expected %d" % [elevation.size(), width * height]
	for row in height:
		var row_problem := _row_problem(row)
		if row_problem != "":
			return row_problem
	for kind: String in ["road", "river"]:
		var links_problem := _links_problem(kind, road_rows if kind == "road" else river_rows)
		if links_problem != "":
			return links_problem
	return ""


func _row_problem(row: int) -> String:
	var line := terrain_rows[row]
	if line.length() != width:
		return "terrain row %d has %d tiles, expected %d" % [row, line.length(), width]
	for ch in line:
		if not TERRAIN_CHARS.has(ch):
			return "unknown terrain '%s' in row %d" % [ch, row]
	return ""


## Checks one link layer: size, characters, no links on water, land–land links on both tiles.
func _links_problem(kind: String, rows: PackedStringArray) -> String:
	if rows.is_empty():
		return ""
	if rows.size() != height:
		return "%d %s rows, expected %d" % [rows.size(), kind, height]
	for row in height:
		if rows[row].length() != width:
			return "%s row %d has %d tiles, expected %d" % [kind, row, rows[row].length(), width]
		for ch in rows[row]:
			if not LINK_CHARS.contains(ch):
				return "unknown %s link '%s' in row %d" % [kind, ch, row]
	return _links_storage_problem(kind, _decode(rows))


## The storage rule on decoded masks: no links on water; a link between two land tiles is
## stored on both.
func _links_storage_problem(kind: String, masks: Dictionary) -> String:
	for c: Vector2i in masks:
		var mask: int = masks[c]
		if mask != 0 and _is_water(c):
			return "%s link on water tile %s" % [kind, c]
		for dir in 6:
			var n: Vector2i = c + Hex.DIRECTIONS[dir]
			if mask & (1 << dir) == 0 or not masks.has(n) or _is_water(n):
				continue
			if int(masks[n]) & (1 << ((dir + 3) % 6)) == 0:
				return "%s link %s -> %s is stored on one side only" % [kind, c, n]
	return ""


## Axial tile -> link mask of a valid link layer.
func _decode(rows: PackedStringArray) -> Dictionary:
	var masks := {}
	for row in height:
		var line := rows[row]
		for col in width:
			masks[MapGenerator.offset_to_axial(col, row)] = LINK_CHARS.find(line[col])
	return masks


func _is_water(c: Vector2i) -> bool:
	var offset := MapGenerator.axial_to_offset(c)
	return TERRAIN_CHARS[terrain_rows[offset.y][offset.x]] == Terrain.Type.WATER


## A HexGrid with every tile's terrain and elevation (authored elevation, no generated field);
## null with push_error when the data is malformed (`problem`).
func to_grid() -> HexGrid:
	var error := problem()
	if error != "":
		push_error("ImportedMap '%s': %s" % [id, error])
		return null
	var grid := HexGrid.new()
	grid.authored_elevation = true
	for row in height:
		var line := terrain_rows[row]
		for col in width:
			var c := MapGenerator.offset_to_axial(col, row)
			grid.set_terrain(c, TERRAIN_CHARS[line[col]])
			grid.set_elevation(c, elevation[row * width + col])
			if elevation_m.size() == width * height:
				grid.set_elevation_m(c, elevation_m[row * width + col])
	if not road_rows.is_empty():
		var roads := _decode(road_rows)
		for c: Vector2i in roads:
			grid.set_road_links(c, roads[c])
	if not river_rows.is_empty():
		var rivers := _decode(river_rows)
		for c: Vector2i in rivers:
			grid.set_river_links(c, rivers[c])
	return grid


## Metres of one world unit (TerrainField.HEX_SIZE).
func metres_per_world_unit() -> float:
	return hex_spacing_m / Hex.SQRT3


## Easting in `crs` (metres) of a world point (XZ plane). Floats, not Vector2: UTM northings
## of ~6e6 m would lose half a metre in a 32-bit vector.
func easting(p: Vector3) -> float:
	return origin_easting + p.x * metres_per_world_unit()


## Northing in `crs` (metres) of a world point; world +z is south.
func northing(p: Vector3) -> float:
	return origin_northing - p.z * metres_per_world_unit()


## Tile (axial) containing the projected point (it may be off the map).
func projected_to_tile(p_easting: float, p_northing: float) -> Vector2i:
	var m := metres_per_world_unit()
	var world := Vector3((p_easting - origin_easting) / m, 0.0, (origin_northing - p_northing) / m)
	return Hex.from_world(world, TerrainField.HEX_SIZE)
