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
	var country_problem := _countries_problem()
	if country_problem != "":
		return country_problem
	return _places_problem()


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
	for index in border_lines.size():
		var line := border_lines[index]
		if line.size() < 2:
			return "border line %d has %d points, expected at least 2" % [index, line.size()]
		for point in line:
			if not (is_finite(point.x) and is_finite(point.y)):
				return "border line %d has a non-finite point" % index
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
