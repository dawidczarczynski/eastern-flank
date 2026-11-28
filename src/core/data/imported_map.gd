# gdlint: disable=max-public-methods
class_name ImportedMap
extends Resource
## A map imported from real geography by tools/import_map.py (TASK-087, ADR 0018):
## data/maps/<id>.tres – a tactical battle map (250 m hexes) or the operational theatre map
## (5 km hexes, `--profile=operational`, TASK-092a). Rectangular offset layout like MapGenerator
## (row 0 north, odd rows shifted east), one character per tile in `terrain_rows`, elevation per
## tile in game units. The importer writes these files; nothing in the game edits them.
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
## Graphic layers (TASK-126) – names for `layer_image` / `layer_bytes`.
const LAYER_WATER := &"water"
const LAYER_COVER := &"cover"
const LAYER_RELIEF := &"relief"
## Ranks of `place_ranks` (TASK-112).
const PLACE_CITY := 0
const PLACE_TOWN := 1
const PLACE_VILLAGE := 2
const LAYERS: Array[StringName] = [LAYER_WATER, LAYER_COVER, LAYER_RELIEF]
## Values of the `cover` layer (the importer's COVER_CLASSES index). The operational import does
## not download fields or grass, so there OPEN is all open land (mostly fields).
const COVER_OPEN := 0
const COVER_GRASS := 1
const COVER_FIELDS := 2
const COVER_URBAN := 3
const COVER_FOREST := 4
const COVER_MARSH := 5
const COVER_WATER := 6
## Value of the `water` layer on water (land is 0).
const WATER_VALUE := 255
## `relief` value of flat ground (255 * sin 45°: the sun stands 45° high in the north-west).
const RELIEF_FLAT := 180
## Edge kinds of a parcel edge (`parcel_edge_kinds`, TASK-215a): what runs along it.
const PARCEL_EDGE_PLAIN := 0
const PARCEL_EDGE_TRACK := 1
const PARCEL_EDGE_HEDGE := 2
## Land use of a parcel by its `parcel_landuse_codes` value.
const PARCEL_LANDUSES: Array[StringName] = [&"farmland", &"meadow", &"orchard"]

@export var id: StringName
@export var display_name: String
## Columns and rows (offset layout; tile (col, row) = MapGenerator.offset_to_axial(col, row)).
@export var width: int
@export var height: int
## Distance between neighbouring tile centres in metres (tactical 250 m, operational 5000 m).
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
## Water width in whole metres (1..63) of the river through each tile (TASK-216), one LINK_CHARS
## character per tile like `river_rows` ("." = none); empty = no data, every river is
## HexGrid.RIVER_WIDTH_DEFAULT_M wide (older maps).
@export var river_width_rows: PackedStringArray
## ISO 3166 alpha-2 codes of the countries of an operational map (TASK-113), in the importer's
## `--countries` order; empty = no countries (tactical maps, old maps).
@export var countries: PackedStringArray
## Country per tile, one character like `terrain_rows`: "0".."9" = index into `countries`,
## "." = none (water, or a hex without land). Empty = no countries. No country on a water tile.
@export var country_rows: PackedStringArray
## The real country borders for drawing (TASK-113): smooth polylines clipped to the map, in world
## units (Vector2.x = world x east, Vector2.y = world z south, hex size 1, i.e. `Hex.to_world`
## space), simplified to 0.1 hex. They are never snapped to hexes; the per-hex `country_rows`
## are for the rules only. Empty = none (tactical maps, old maps).
@export var border_lines: Array[PackedVector2Array]
## The real roads and rivers for drawing (operational maps): smooth polylines from the OSM ways,
## clipped to the map, in the same world units as `border_lines`, simplified to ~0.04 hex. The
## parallel `*_line_classes` give each line's class: roads 1 = motorway / trunk,
## 2 = primary, 3 = secondary (a class carries on through a junction-free joint); rivers 2 = major,
## 1 = medium, 0 = the rest by the length of their course from the source (>= 80 / >= 30 km).
## `road_rows` / `river_rows` stay the rules' data; these lines are view data only. Empty = none
## (tactical maps, older maps: the view then draws the hex links).
@export var road_lines: Array[PackedVector2Array]
@export var road_line_classes: PackedInt32Array
@export var river_lines: Array[PackedVector2Array]
@export var river_line_classes: PackedInt32Array
## Place names for the staff map's labels (TASK-112), three parallel arrays (index = one place), in
## the importer's order (rank, then population, name, OSM id; a view may rely on it). Names are the
## local OSM `name` (diacritics kept); positions are world units like `border_lines`; ranks are
## PLACE_CITY / PLACE_TOWN / PLACE_VILLAGE. Labels are view data only; no rule reads them. Empty =
## none (tactical maps, older maps). Read them with `place_count()` / `place_at(index)`.
@export var place_names: PackedStringArray
@export var place_positions: PackedVector2Array
@export var place_ranks: PackedInt32Array
## Mean DEM height of each tile in metres (row-major), the real data behind `elevation`.
@export var elevation_m: PackedFloat32Array
## Game elevation of each tile (row-major; water below 0, land from land_min up).
@export var elevation: PackedFloat32Array
## Attribution of the source data (see data/maps/CREDITS).
@export var sources: String
## Land-cover raster of a tactical map (TASK-108g, ADR 0028 "Sub-hex land cover"): zlib of
## `land_cover_width` x `land_cover_height` LandCover.Kind bytes, square cells of
## `land_cover_cell_m` metres, row 0 north; the centre of cell (0, 0) (north-west) is at
## (`land_cover_origin_easting`, `land_cover_origin_northing`). The hex terrain is derived from it
## by the importer; only the view reads it (LandCover.from_imported). Empty = none (operational
## and older maps).
@export var land_cover_cell_m: float = 0.0
@export var land_cover_width: int
@export var land_cover_height: int
@export var land_cover_origin_easting: float
@export var land_cover_origin_northing: float
@export var land_cover: PackedByteArray
## Satellite colour layer (TASK-192a, ADR 0031 "Satellite colour layer"): a baseline JPEG of
## `colour_width` x `colour_height` sRGB pixels of `colour_cell_m` metres (Sentinel-2 L2A, corrected
## by the importer), row 0 north; the centre of pixel (0, 0) (north-west) is at
## (`colour_origin_easting`, `colour_origin_northing`). Only the view reads it (`sample`).
## Empty = none (operational and older maps).
@export var colour_cell_m: float = 0.0
@export var colour_width: int
@export var colour_height: int
@export var colour_origin_easting: float
@export var colour_origin_northing: float
## Attribution and the Sentinel-2 scenes the layer was made from (see data/maps/CREDITS).
@export var colour_sources: String
@export var colour_jpg: PackedByteArray

## Graphic layers for drawing the operational map (TASK-126; GDD "Operational map", map
## principle): images of the importer's sample lattice, finer than the hexes and never read by a
## rule. Grayscale PNGs, row 0 north, pixel (0, 0) the north-west one: water and cover have
## `layer_width` x `layer_height` pixels `layer_pixel_m` metres apart, the relief one pixel per
## `layer_relief_step` of them (its pixel (i, j) lies on layer pixel (i * step, j * step)).
## Empty = no layers (tactical maps, older maps). Decode them with `layer_image` /
## `layer_bytes`; place them in world space with `layer_world_rect(kind)` /
## `layer_pixel_to_world`.
@export var layer_width: int
@export var layer_height: int
@export var layer_pixel_m: float
## Projected position (`crs`, metres) of the centre of pixel (0, 0).
@export var layer_origin_easting: float
@export var layer_origin_northing: float
## Layer pixels per relief pixel (2: the relief has 500 m pixels).
@export var layer_relief_step: int = 1
## 1-bit PNG: water (lakes, reservoirs, wide rivers, the sea) decodes to WATER_VALUE, land to 0.
@export var layer_water_png: PackedByteArray
## 8-bit PNG: COVER_* per pixel.
@export var layer_cover_png: PackedByteArray
## 8-bit PNG: hillshade of the DEM (RELIEF_FLAT on flat ground, brighter facing the north-west).
@export var layer_relief_png: PackedByteArray

## Real field parcels of a tactical map (TASK-215a, ADR 0032 "Real field parcel boundaries"): the
## OSM farmland / meadow / orchard polygons split by roads, tracks, hedges, tree rows and fences.
## Vertices in whole metres east (x) and south (z) of tile (0, 0)'s centre, the frame of `sample`.
## Parcel i has `parcel_rings[i]` rings (the first the outer one, counter-clockwise seen from above
## with north up; then its holes, the other way round); ring r has `parcel_ring_sizes[r]` vertices,
## stored in `parcel_points` as x, z pairs, in parcel and ring order; `parcel_edge_codes` has one
## PARCEL_EDGE_* per vertex (the edge from it to the next vertex of its ring). Only the view reads
## them. Empty = none (operational and older maps). Read them with `parcel_count`,
## `parcel_polygon`, `parcel_edge_kinds` and `parcel_landuse`.
@export var parcel_landuse_codes: PackedByteArray
@export var parcel_rings: PackedInt32Array
@export var parcel_ring_sizes: PackedInt32Array
@export var parcel_points: PackedInt32Array
@export var parcel_edge_codes: PackedByteArray

## Real tree features of a tactical map (TASK-199a, `--trees`): OSM single trees, tree rows,
## orchards and farmyards, in whole metres east (x) and south (z) of tile (0, 0)'s centre like the
## parcels. `tree_points` holds x, z pairs; tree row i has `tree_row_sizes[i]` vertices in
## `tree_row_points`; orchards and farmyards are polygons stored like the parcels (`*_rings` rings
## per polygon, the outer one first and counter-clockwise north up, `*_ring_sizes` vertices per
## ring, `*_points` x, z pairs). Only the view reads them. Empty = none (operational and older
## maps). Read them with `tree_point`, `tree_row_polyline`, `orchard_polygon`, `farmyard_polygon`.
@export var tree_points: PackedInt32Array
@export var tree_row_sizes: PackedInt32Array
@export var tree_row_points: PackedInt32Array
@export var orchard_rings: PackedInt32Array
@export var orchard_ring_sizes: PackedInt32Array
@export var orchard_points: PackedInt32Array
@export var farmyard_rings: PackedInt32Array
@export var farmyard_ring_sizes: PackedInt32Array
@export var farmyard_points: PackedInt32Array

## The decoded colour layer (first use decodes it, then it is kept).
var _colour: ColourRaster
var _colour_tried := false
## First ring of each parcel and first vertex of each ring (plus one past the end), built on the
## first parcel read.
var _parcel_first_ring := PackedInt32Array()
var _ring_first_point := PackedInt32Array()
## First vertex of each tree row (plus one past the end), and per area kind (&"orchard",
## &"farmyard") [first ring per polygon, first vertex per ring], built on the first read.
var _row_first_point := PackedInt32Array()
var _area_index := {}


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
	var size_problem := _size_problem()
	if size_problem != "":
		return size_problem
	for row in height:
		var row_problem := _row_problem(row)
		if row_problem != "":
			return row_problem
	for kind: String in ["road", "river"]:
		var links_problem := _links_problem(kind, road_rows if kind == "road" else river_rows)
		if links_problem != "":
			return links_problem
	var extra_problem := _river_widths_problem()
	if extra_problem == "":
		extra_problem = _countries_problem()
	if extra_problem != "":
		return extra_problem
	var places_problem := _places_problem()
	if places_problem != "":
		return places_problem
	var parcels_problem := _parcels_problem()
	return parcels_problem if parcels_problem != "" else _trees_problem()


func _size_problem() -> String:
	if width <= 0 or height <= 0 or hex_spacing_m <= 0.0:
		return "empty map %dx%d, spacing %s m" % [width, height, hex_spacing_m]
	if terrain_rows.size() != height:
		return "%d terrain rows, expected %d" % [terrain_rows.size(), height]
	if elevation.size() != width * height:
		return "%d elevations, expected %d" % [elevation.size(), width * height]
	return ""


func _row_problem(row: int) -> String:
	var line := terrain_rows[row]
	if line.length() != width:
		return "terrain row %d has %d tiles, expected %d" % [row, line.length(), width]
	for ch in line:
		if not TERRAIN_CHARS.has(ch):
			return "unknown terrain '%s' in row %d" % [ch, row]
	return ""


## Checks the country layer: codes, then one row per map row with the map's width, only digits
## below `countries.size()` and ".", no country on a water tile.
func _countries_problem() -> String:
	var lines_problem := _border_lines_problem()
	if lines_problem != "":
		return lines_problem
	if country_rows.is_empty() and countries.is_empty():
		return ""
	var codes_problem := _country_codes_problem()
	if codes_problem != "":
		return codes_problem
	if country_rows.size() != height:
		return "%d country rows, expected %d" % [country_rows.size(), height]
	for row in height:
		var row_problem := _country_row_problem(row)
		if row_problem != "":
			return row_problem
	return ""


func _country_codes_problem() -> String:
	var seen := {}
	for code in countries:
		if code.length() != 2 or code != code.to_upper() or code.to_lower() == code.to_upper():
			return "country code '%s' is not two upper-case letters" % code
		if seen.has(code):
			return "duplicate country '%s'" % code
		seen[code] = true
	return ""


func _country_row_problem(row: int) -> String:
	var line := country_rows[row]
	if line.length() != width:
		return "country row %d has %d tiles, expected %d" % [row, line.length(), width]
	for col in width:
		var ch := line[col]
		if ch == ".":
			continue
		if not ch.is_valid_int() or ch.to_int() >= countries.size():
			return "unknown country '%s' in row %d" % [ch, row]
		if TERRAIN_CHARS[terrain_rows[row][col]] == Terrain.Type.WATER:
			return "country on water tile (%d, %d)" % [col, row]
	return ""


## Every border line needs at least two finite points.
func _border_lines_problem() -> String:
	var problem := _lines_problem(border_lines, "border line")
	if problem == "":
		problem = _lines_problem(road_lines, "road line")
	if problem == "":
		problem = _lines_problem(river_lines, "river line")
	if problem == "" and road_line_classes.size() != road_lines.size():
		problem = (
			"%d road line classes for %d road lines" % [road_line_classes.size(), road_lines.size()]
		)
	if problem == "" and river_line_classes.size() != river_lines.size():
		problem = (
			"%d river line classes for %d river lines"
			% [river_line_classes.size(), river_lines.size()]
		)
	return problem


func _lines_problem(lines: Array[PackedVector2Array], label: String) -> String:
	for index in lines.size():
		var line := lines[index]
		if line.size() < 2:
			return "%s %d has %d points, expected at least 2" % [label, index, line.size()]
		for point in line:
			if not (is_finite(point.x) and is_finite(point.y)):
				return "%s %d has a non-finite point" % [label, index]
	return ""


## Number of place names (TASK-112).
func place_count() -> int:
	return place_names.size()


## Place `index` as {"name": String, "position": Vector2 (world units), "rank": int (PLACE_*)}.
func place_at(index: int) -> Dictionary:
	return {
		"name": place_names[index], "position": place_positions[index], "rank": place_ranks[index]
	}


## World rectangle (XZ plane, hex size 1, Vector2.x = world x, Vector2.y = world z) that covers all
## hexes of the map: tile (0, 0) is centred on the origin; the first two rows give the x extremes.
func hex_world_rect() -> Rect2:
	var half_width := Hex.SQRT3 / 2.0
	var max_x := Hex.SQRT3 * (width - 1) + (Hex.SQRT3 / 2.0 if height > 1 else 0.0) + half_width
	var max_z := 1.5 * (height - 1) + 1.0
	return Rect2(Vector2(-half_width, -1.0), Vector2(max_x + half_width, max_z + 1.0))


## Three arrays of one length; every place has a non-blank name, a rank in 0..2 and a finite
## position inside the map's rectangle.
func _places_problem() -> String:
	var count := place_names.size()
	if place_positions.size() != count or place_ranks.size() != count:
		return (
			"%d place names, %d positions and %d ranks"
			% [count, place_positions.size(), place_ranks.size()]
		)
	var rect := hex_world_rect()
	for index in count:
		if place_names[index].strip_edges() == "":
			return "place %d has an empty name" % index
		if place_ranks[index] < PLACE_CITY or place_ranks[index] > PLACE_VILLAGE:
			return "place %d has rank %d, expected 0..2" % [index, place_ranks[index]]
		var point := place_positions[index]
		if not (is_finite(point.x) and is_finite(point.y)):
			return "place %d has a non-finite position" % index
		if not rect.has_point(point):
			return "place %d lies outside the map at %s" % [index, point]
	return ""


## ISO code of the country of the axial tile `coord`; "" for water, a hex without a country, a
## tile off the map or a map without country rows.
func country_at(coord: Vector2i) -> String:
	if country_rows.is_empty():
		return ""
	var offset := MapGenerator.axial_to_offset(coord)
	if offset.x < 0 or offset.x >= width or offset.y < 0 or offset.y >= height:
		return ""
	if offset.y >= country_rows.size() or offset.x >= country_rows[offset.y].length():
		return ""
	var ch := country_rows[offset.y][offset.x]
	if ch == "." or not ch.is_valid_int() or ch.to_int() >= countries.size():
		return ""
	return countries[ch.to_int()]


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


## Shape of `river_width_rows` (empty is fine): one row per tile row, only LINK_CHARS characters.
func _river_widths_problem() -> String:
	if river_width_rows.is_empty():
		return ""
	if river_width_rows.size() != height:
		return "%d river width rows, expected %d" % [river_width_rows.size(), height]
	for row in height:
		if river_width_rows[row].length() != width:
			return (
				"river width row %d has %d tiles, expected %d"
				% [row, river_width_rows[row].length(), width]
			)
		for ch in river_width_rows[row]:
			if not LINK_CHARS.contains(ch):
				return "unknown river width '%s' in row %d" % [ch, row]
	return ""


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
	if not river_width_rows.is_empty():
		var widths := _decode(river_width_rows)
		for c: Vector2i in widths:
			if widths[c] > 0 and grid.river_links(c) != 0:
				grid.set_river_width_m(c, float(widths[c]))
	return grid


## True when the map carries the three graphic layers (TASK-126). A cheap check of the fields;
## `graphic_layers_problem` decodes and validates them.
func has_graphic_layers() -> bool:
	return (
		layer_width > 0
		and layer_height > 0
		and layer_pixel_m > 0.0
		and not layer_water_png.is_empty()
		and not layer_cover_png.is_empty()
		and not layer_relief_png.is_empty()
	)


## Pixels of one graphic layer (columns east, rows south); (0, 0) without layers.
func layer_size(kind: StringName = LAYER_WATER) -> Vector2i:
	if not has_graphic_layers() or not LAYERS.has(kind):
		return Vector2i.ZERO
	if kind == LAYER_RELIEF:
		var step := maxi(layer_relief_step, 1)
		return Vector2i((layer_width - 1) / step + 1, (layer_height - 1) / step + 1)
	return Vector2i(layer_width, layer_height)


## The stored PNG of one layer (LAYER_WATER, LAYER_COVER, LAYER_RELIEF); empty for other names.
func layer_png(kind: StringName) -> PackedByteArray:
	match kind:
		LAYER_WATER:
			return layer_water_png
		LAYER_COVER:
			return layer_cover_png
		LAYER_RELIEF:
			return layer_relief_png
	return PackedByteArray()


## One layer decoded: a FORMAT_L8 image of `layer_size(kind)`, row 0 north (ready for an
## ImageTexture; one byte per pixel, see WATER_VALUE, COVER_*, RELIEF_FLAT). Decodes on every
## call – build the textures once. Null without layers or when the PNG is malformed.
func layer_image(kind: StringName) -> Image:
	if not has_graphic_layers() or not LAYERS.has(kind):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(layer_png(kind)) != OK:
		return null
	if Vector2i(image.get_width(), image.get_height()) != layer_size(kind):
		return null
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
	return image


## One layer as row-major bytes (`layer_size(kind).x` per row, row 0 north); empty when
## unavailable.
func layer_bytes(kind: StringName) -> PackedByteArray:
	var image := layer_image(kind)
	return image.get_data() if image != null else PackedByteArray()


## "" when the graphic layers decode to images of the stated size with valid values, otherwise
## what is wrong (also when there are none – the view then falls back to the hex look).
func graphic_layers_problem() -> String:
	if not has_graphic_layers():
		return "no graphic layers"
	for kind in LAYERS:
		var data := layer_bytes(kind)
		var size := layer_size(kind)
		if data.is_empty() or data.size() != size.x * size.y:
			return "%s layer does not decode to %dx%d pixels" % [kind, size.x, size.y]
		if kind == LAYER_WATER and data.count(0) + data.count(WATER_VALUE) != data.size():
			return "water layer value other than 0 / %d" % WATER_VALUE
		if kind == LAYER_COVER:
			var known := 0
			for value in COVER_WATER + 1:
				known += data.count(value)
			if known != data.size():
				return "cover layer value above %d" % COVER_WATER
	return ""


## World units (x east, z south) between neighbouring pixels of a layer.
func layer_pixel_world_size(kind: StringName = LAYER_WATER) -> float:
	var step := maxi(layer_relief_step, 1) if kind == LAYER_RELIEF else 1
	return layer_pixel_m * step / metres_per_world_unit()


## World position (Vector2.x = world x east, Vector2.y = world z south, `Hex.to_world` space) of
## a point in water / cover pixel coordinates; Vector2(i, j) is the centre of pixel (i, j) (relief
## pixel (i, j) is at Vector2(i, j) * layer_relief_step).
func layer_pixel_to_world(pixel: Vector2) -> Vector2:
	var m := metres_per_world_unit()
	var e := layer_origin_easting + pixel.x * layer_pixel_m
	var n := layer_origin_northing - pixel.y * layer_pixel_m
	return Vector2((e - origin_easting) / m, (origin_northing - n) / m)


## Inverse of `layer_pixel_to_world`.
func world_to_layer_pixel(world: Vector2) -> Vector2:
	var m := metres_per_world_unit()
	var e := origin_easting + world.x * m
	var n := origin_northing - world.y * m
	return Vector2(
		(e - layer_origin_easting) / layer_pixel_m, (layer_origin_northing - n) / layer_pixel_m
	)


## The world rectangle (x east, y = world z south) a layer's pixels cover, from the outer edge
## of pixel (0, 0) to the outer edge of the last pixel: a texture over it puts each texel centre
## on its pixel centre (uv = (world - position) / size). The relief's rectangle is slightly
## larger than the water / cover one (half a coarse pixel). Empty without layers.
func layer_world_rect(kind: StringName = LAYER_WATER) -> Rect2:
	if not has_graphic_layers() or not LAYERS.has(kind):
		return Rect2()
	var step := float(maxi(layer_relief_step, 1)) if kind == LAYER_RELIEF else 1.0
	var corner := layer_pixel_to_world(Vector2(-0.5, -0.5) * step)
	return Rect2(corner, Vector2(layer_size(kind)) * layer_pixel_world_size(kind))


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


## True when the map has a satellite colour layer (TASK-192a).
func has_colour_layer() -> bool:
	return (
		colour_cell_m > 0.0 and colour_width > 0 and colour_height > 0 and not colour_jpg.is_empty()
	)


## The decoded colour layer in the frame of `sample` (metres east / south of tile (0, 0)'s centre);
## null when there is none or it does not decode.
func colour_raster() -> ColourRaster:
	if not _colour_tried:
		_colour_tried = true
		if has_colour_layer():
			var pixel_origin := Vector2(
				colour_origin_easting - origin_easting, origin_northing - colour_origin_northing
			)
			_colour = ColourRaster.from_jpg(
				colour_jpg, colour_width, colour_height, colour_cell_m, pixel_origin
			)
	return _colour


## sRGB colour of the ground at `x_m` metres east and `z_m` metres south of tile (0, 0)'s centre
## (world x and z times metres_per_world_unit), clamped to the layer's edge; transparent black
## when the map has no colour layer.
func sample(x_m: float, z_m: float) -> Color:
	var raster := colour_raster()
	return raster.sample(x_m, z_m) if raster != null else Color(0.0, 0.0, 0.0, 0.0)


## True when the map carries field parcels (TASK-215a).
func has_parcels() -> bool:
	return not parcel_rings.is_empty()


func parcel_count() -> int:
	return parcel_rings.size()


## Parcel `index` as rings of metres (Vector2(x east, z south) of tile (0, 0)'s centre): the outer
## ring first, then its holes; a ring is not closed (its last vertex joins the first).
func parcel_polygon(index: int) -> Array[PackedVector2Array]:
	_index_parcels()
	var rings: Array[PackedVector2Array] = []
	for ring in range(_parcel_first_ring[index], _parcel_first_ring[index + 1]):
		var points := PackedVector2Array()
		for k in range(_ring_first_point[ring], _ring_first_point[ring + 1]):
			points.append(Vector2(parcel_points[2 * k], parcel_points[2 * k + 1]))
		rings.append(points)
	return rings


## PARCEL_EDGE_* of every edge of parcel `index`, per ring like `parcel_polygon` (edge k runs from
## vertex k to the next one).
func parcel_edge_kinds(index: int) -> Array[PackedByteArray]:
	_index_parcels()
	var kinds: Array[PackedByteArray] = []
	for ring in range(_parcel_first_ring[index], _parcel_first_ring[index + 1]):
		kinds.append(parcel_edge_codes.slice(_ring_first_point[ring], _ring_first_point[ring + 1]))
	return kinds


## &"farmland", &"meadow" or &"orchard".
func parcel_landuse(index: int) -> StringName:
	return PARCEL_LANDUSES[parcel_landuse_codes[index]]


func _index_parcels() -> void:
	if _parcel_first_ring.size() == parcel_rings.size() + 1:
		return
	_parcel_first_ring = PackedInt32Array([0])
	for count in parcel_rings:
		_parcel_first_ring.append(_parcel_first_ring[-1] + count)
	_ring_first_point = PackedInt32Array([0])
	for size in parcel_ring_sizes:
		_ring_first_point.append(_ring_first_point[-1] + size)


## The parcel arrays agree in length; every parcel has a ring, every ring three vertices; codes
## known.
func _parcels_problem() -> String:
	var count := parcel_rings.size()
	if parcel_landuse_codes.size() != count:
		return "%d parcel landuse codes for %d parcels" % [parcel_landuse_codes.size(), count]
	var rings := 0
	for n in parcel_rings:
		if n < 1:
			return "a parcel without rings"
		rings += n
	if parcel_ring_sizes.size() != rings:
		return "%d parcel ring sizes for %d rings" % [parcel_ring_sizes.size(), rings]
	return _parcel_points_problem()


func _parcel_points_problem() -> String:
	var points := 0
	for n in parcel_ring_sizes:
		if n < 3:
			return "a parcel ring with %d vertices" % n
		points += n
	if parcel_points.size() != 2 * points or parcel_edge_codes.size() != points:
		return (
			"%d parcel coordinates and %d edge kinds for %d vertices"
			% [parcel_points.size(), parcel_edge_codes.size(), points]
		)
	for code in parcel_edge_codes:
		if code > PARCEL_EDGE_HEDGE:
			return "unknown parcel edge kind %d" % code
	for code in parcel_landuse_codes:
		if code >= PARCEL_LANDUSES.size():
			return "unknown parcel landuse %d" % code
	return ""


## True when the map carries tree features (TASK-199a).
func has_tree_features() -> bool:
	return not (
		tree_points.is_empty()
		and tree_row_sizes.is_empty()
		and orchard_rings.is_empty()
		and farmyard_rings.is_empty()
	)


func tree_point_count() -> int:
	return tree_points.size() / 2


## Single tree `index` in metres (Vector2(x east, z south) of tile (0, 0)'s centre).
func tree_point(index: int) -> Vector2:
	return Vector2(tree_points[2 * index], tree_points[2 * index + 1])


func tree_row_count() -> int:
	return tree_row_sizes.size()


## Tree row `index` as an open polyline of metres (frame of `tree_point`).
func tree_row_polyline(index: int) -> PackedVector2Array:
	if _row_first_point.size() != tree_row_sizes.size() + 1:
		_row_first_point = _first_offsets(tree_row_sizes)
	var points := PackedVector2Array()
	for k in range(_row_first_point[index], _row_first_point[index + 1]):
		points.append(Vector2(tree_row_points[2 * k], tree_row_points[2 * k + 1]))
	return points


func orchard_count() -> int:
	return orchard_rings.size()


## Orchard `index` as rings of metres like `parcel_polygon`: the outer ring, then its holes.
func orchard_polygon(index: int) -> Array[PackedVector2Array]:
	return _area_polygon(&"orchard", orchard_rings, orchard_ring_sizes, orchard_points, index)


func farmyard_count() -> int:
	return farmyard_rings.size()


## Farmyard `index` as rings of metres like `parcel_polygon`: the outer ring, then its holes.
func farmyard_polygon(index: int) -> Array[PackedVector2Array]:
	return _area_polygon(&"farmyard", farmyard_rings, farmyard_ring_sizes, farmyard_points, index)


func _area_polygon(
	kind: StringName,
	rings: PackedInt32Array,
	sizes: PackedInt32Array,
	points: PackedInt32Array,
	index: int
) -> Array[PackedVector2Array]:
	var offsets: Array = _area_index.get(kind, [])
	if offsets.is_empty() or (offsets[0] as PackedInt32Array).size() != rings.size() + 1:
		offsets = [_first_offsets(rings), _first_offsets(sizes)]
		_area_index[kind] = offsets
	var first_ring: PackedInt32Array = offsets[0]
	var first_point: PackedInt32Array = offsets[1]
	var polygon: Array[PackedVector2Array] = []
	for ring in range(first_ring[index], first_ring[index + 1]):
		var ring_points := PackedVector2Array()
		for k in range(first_point[ring], first_point[ring + 1]):
			ring_points.append(Vector2(points[2 * k], points[2 * k + 1]))
		polygon.append(ring_points)
	return polygon


## 0 and the running sums of `counts` (the first item of each group, plus one past the end).
static func _first_offsets(counts: PackedInt32Array) -> PackedInt32Array:
	var offsets := PackedInt32Array([0])
	for count in counts:
		offsets.append(offsets[-1] + count)
	return offsets


## The tree arrays agree in length: x, z pairs; every row two vertices; polygons like the parcels.
func _trees_problem() -> String:
	if tree_points.size() % 2 != 0:
		return "%d tree point coordinates (not pairs)" % tree_points.size()
	var row_points := 0
	for n in tree_row_sizes:
		if n < 2:
			return "a tree row with %d vertices" % n
		row_points += n
	if tree_row_points.size() != 2 * row_points:
		return "%d tree row coordinates for %d vertices" % [tree_row_points.size(), row_points]
	var orchard_problem := _area_problem(
		"orchard", orchard_rings, orchard_ring_sizes, orchard_points
	)
	if orchard_problem != "":
		return orchard_problem
	return _area_problem("farmyard", farmyard_rings, farmyard_ring_sizes, farmyard_points)


static func _area_problem(
	kind: String, rings: PackedInt32Array, sizes: PackedInt32Array, points: PackedInt32Array
) -> String:
	var ring_count := 0
	for n in rings:
		if n < 1:
			return "a %s without rings" % kind
		ring_count += n
	if sizes.size() != ring_count:
		return "%d %s ring sizes for %d rings" % [sizes.size(), kind, ring_count]
	var point_count := 0
	for n in sizes:
		if n < 3:
			return "a %s ring with %d vertices" % [kind, n]
		point_count += n
	if points.size() != 2 * point_count:
		return "%d %s coordinates for %d vertices" % [points.size(), kind, point_count]
	return ""
