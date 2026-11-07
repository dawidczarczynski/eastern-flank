extends TestCase
## The operational theatre map data/maps/suwalki_theatre.tres (TASK-092a): REAL data imported by
## `tools/import_map.py --profile=operational` (5 km hexes, 68 x 64, UTM 34N; see
## data/maps/CREDITS).
## Places are given in WGS84 degrees and projected with the map's UTM zone (Krüger series, the
## same as the importer's `to_utm`).

const MAP_ID := &"suwalki_theatre"
const WIDTH := 68
const HEIGHT := 64
## [name, lat, lon] – each must lie on a tile ≥ 2 hexes from every map edge.
const PLACES := [
	["Kaliningrad", 54.7104, 20.4522],
	["Chernyakhovsk", 54.6346, 21.8128],
	["Sovetsk", 55.0817, 21.8869],
	["Olsztyn", 53.7784, 20.4801],
	["Bialystok", 53.1325, 23.1688],
	["Elk", 53.8281, 22.3647],
	["Suwalki", 54.1115, 22.9308],
	["Augustow", 53.8436, 22.9799],
	["Grodno", 53.6694, 23.8131],
	["Lida", 53.8885, 25.2846],
	["Marijampole", 54.5599, 23.3541],
	["Kaunas", 54.8985, 23.9036],
	["Vilnius", 54.6872, 25.2797],
]
## The cities whose hexes should be URBAN (≥ 5 of 7 must be; the tuning target is all 7).
const CITIES := ["Kaliningrad", "Vilnius", "Kaunas", "Bialystok", "Grodno", "Olsztyn", "Suwalki"]
## Water points: the importer's default sea seeds (open Baltic, Curonian Lagoon) and Lake Śniardwy.
const WATER_POINTS := [
	["Baltic seed", 55.30, 20.60],
	["Curonian Lagoon seed", 55.10, 21.05],
	["Sniardwy", 53.75, 21.73]
]

## Country of each place (TASK-113).
const PLACE_COUNTRIES := {
	"Kaliningrad": "RU",
	"Chernyakhovsk": "RU",
	"Sovetsk": "RU",
	"Olsztyn": "PL",
	"Bialystok": "PL",
	"Elk": "PL",
	"Suwalki": "PL",
	"Augustow": "PL",
	"Grodno": "BY",
	"Lida": "BY",
	"Marijampole": "LT",
	"Kaunas": "LT",
	"Vilnius": "LT",
}
const COUNTRY_CODES := ["PL", "LT", "BY", "RU"]

# WGS84 / UTM (the importer's constants).
const _A := 6378137.0
const _F := 1.0 / 298.257223563
const _K0 := 0.9996
const _ZONE_34_MERIDIAN := 21.0

static var _map: ImportedMap
static var _grid: HexGrid


func before_all() -> void:
	_map = ImportedMap.find(MAP_ID)
	_grid = _map.to_grid() if _map != null else null


func after_all() -> void:
	_map = null
	_grid = null


static func _atanh(x: float) -> float:
	return 0.5 * log((1.0 + x) / (1.0 - x))


## [easting, northing] in UTM zone 34N of a WGS84 point (Krüger series to n³, like the importer).
static func _to_utm34(lat_deg: float, lon_deg: float) -> Array[float]:
	var n := _F / (2.0 - _F)
	var rect := _A / (1.0 + n) * (1.0 + n * n / 4.0 + pow(n, 4.0) / 64.0)
	var alpha: Array[float] = [
		n / 2.0 - 2.0 * n * n / 3.0 + 5.0 * pow(n, 3.0) / 16.0,
		13.0 * n * n / 48.0 - 3.0 * pow(n, 3.0) / 5.0,
		61.0 * pow(n, 3.0) / 240.0,
	]
	var c := 2.0 * sqrt(n) / (1.0 + n)
	var phi := deg_to_rad(lat_deg)
	var dlam := deg_to_rad(lon_deg - _ZONE_34_MERIDIAN)
	var t := sinh(_atanh(sin(phi)) - c * _atanh(c * sin(phi)))
	var xi_p := atan2(t, cos(dlam))
	var eta_p := _atanh(sin(dlam) / sqrt(1.0 + t * t))
	var xi := xi_p
	var eta := eta_p
	for j in range(1, 4):
		xi += alpha[j - 1] * sin(2.0 * j * xi_p) * cosh(2.0 * j * eta_p)
		eta += alpha[j - 1] * cos(2.0 * j * xi_p) * sinh(2.0 * j * eta_p)
	return [500000.0 + _K0 * rect * eta, _K0 * rect * xi]


## Offset tile (column, row) of a WGS84 point on the theatre map.
func _tile_of(lat: float, lon: float) -> Vector2i:
	var utm := _to_utm34(lat, lon)
	return MapGenerator.axial_to_offset(_map.projected_to_tile(utm[0], utm[1]))


func _terrain_at(offset: Vector2i) -> String:
	return _map.terrain_rows[offset.y][offset.x]


func _place(place_name: String) -> Array:
	for place: Array in PLACES:
		if place[0] == place_name:
			return place
	return []


func test_projection_matches_the_importer() -> void:
	# tools/import_map.py to_utm(54.1115, 22.9308, 34) = (626217.4, 5997651.5) (rounded).
	var utm := _to_utm34(54.1115, 22.9308)
	assert_true(absf(utm[0] - 626217.4) < 1.0, "easting %f" % utm[0])
	assert_true(absf(utm[1] - 5997651.5) < 1.0, "northing %f" % utm[1])


func test_theatre_map_is_valid_and_has_the_decided_size() -> void:
	assert_true(_map != null, "data/maps/suwalki_theatre.tres loads")
	assert_eq(_map.problem(), "")
	assert_eq([_map.width, _map.height, _map.hex_spacing_m], [WIDTH, HEIGHT, 5000.0])
	assert_eq(_map.crs, "EPSG:32634", "UTM 34N for the whole map")
	assert_eq(_grid.coords().size(), 4352)
	assert_true(_map.sources.contains("GLO-90"), "the operational import reads GLO-90")


func test_places_lie_at_least_two_hexes_inside_the_edges() -> void:
	for place: Array in PLACES:
		var tile := _tile_of(place[1], place[2])
		var edge := mini(mini(tile.x, tile.y), mini(WIDTH - 1 - tile.x, HEIGHT - 1 - tile.y))
		assert_true(edge >= 2, "%s on tile %s, %d hexes from the edge" % [place[0], tile, edge])


func test_the_tactical_sample_lies_on_land_inside_the_theatre() -> void:
	var tactical := ImportedMap.find(&"suwalki")
	var middle := MapGenerator.offset_to_axial(tactical.width / 2, tactical.height / 2)
	var world := Hex.to_world(middle, TerrainField.HEX_SIZE)
	var axial := _map.projected_to_tile(tactical.easting(world), tactical.northing(world))
	var tile := MapGenerator.axial_to_offset(axial)
	assert_true(tile.x >= 0 and tile.x < WIDTH and tile.y >= 0 and tile.y < HEIGHT, str(tile))
	assert_true(_terrain_at(tile) != "W", "tile %s is %s" % [tile, _terrain_at(tile)])


func test_water_is_at_most_fifteen_percent_and_where_it_belongs() -> void:
	var water := 0
	for row in _map.terrain_rows:
		water += row.count("W")
	assert_true(water <= 0.15 * WIDTH * HEIGHT, "%d water hexes" % water)
	for point: Array in WATER_POINTS:
		var tile := _tile_of(point[1], point[2])
		assert_eq(_terrain_at(tile), "W", "%s on tile %s" % [point[0], tile])


func test_most_cities_are_urban() -> void:
	var urban: Array[String] = []
	for city: String in CITIES:
		var place := _place(city)
		if _terrain_at(_tile_of(place[1], place[2])) == "U":
			urban.append(city)
	assert_true(urban.size() >= 5, "urban city hexes: %s" % [urban])


func test_roads_and_rivers() -> void:
	var roads := 0
	var rivers := 0
	for c: Vector2i in _grid.coords():
		if _grid.road_links(c) != 0:
			roads += 1
		if _grid.is_river(c):
			rivers += 1
	assert_true(roads >= 300, "%d hexes with a road link" % roads)
	assert_true(rivers >= 50, "%d river hexes" % rivers)


func test_the_land_is_one_connected_region() -> void:
	var land := {}
	for c: Vector2i in _grid.coords():
		if _grid.get_terrain(c) != Terrain.Type.WATER:
			land[c] = true
	var largest := 0
	var seen := {}
	for start: Vector2i in land:
		if seen.has(start):
			continue
		var size := 0
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			size += 1
			for n in Hex.neighbors(c):
				if land.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		largest = maxi(largest, size)
	assert_true(largest >= 0.9 * land.size(), "largest region %d of %d" % [largest, land.size()])


# --- TASK-113: countries ---


func _axial_of(place_name: String) -> Vector2i:
	var place := _place(place_name)
	var tile := _tile_of(place[1], place[2])
	return MapGenerator.offset_to_axial(tile.x, tile.y)


func _hexes_of(code: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c: Vector2i in _grid.coords():
		if _map.country_at(c) == code:
			result.append(c)
	return result


func test_the_four_countries_are_in_the_data_in_the_decided_order() -> void:
	assert_eq(Array(_map.countries), COUNTRY_CODES)
	assert_eq(_map.country_rows.size(), HEIGHT)


func test_every_land_hex_has_a_country_and_water_has_none() -> void:
	var missing: Array[Vector2i] = []
	for c: Vector2i in _grid.coords():
		var water := _grid.get_terrain(c) == Terrain.Type.WATER
		if water:
			assert_eq(_map.country_at(c), "", "water %s" % c)
		elif _map.country_at(c) == "":
			missing.append(c)
	assert_true(
		missing.is_empty(),
		"%d land hexes without a country, first %s" % [missing.size(), missing.slice(0, 5)]
	)


func test_each_country_owns_at_least_thirty_hexes() -> void:
	for code: String in COUNTRY_CODES:
		assert_true(_hexes_of(code).size() >= 30, "%s: %d hexes" % [code, _hexes_of(code).size()])


func test_the_places_fall_into_the_right_country() -> void:
	for place_name: String in PLACE_COUNTRIES:
		assert_eq(_map.country_at(_axial_of(place_name)), PLACE_COUNTRIES[place_name], place_name)


func test_the_kaliningrad_oblast_is_one_region_and_never_touches_belarus() -> void:
	var russia := _hexes_of("RU")
	var seen := {}
	var start := _axial_of("Kaliningrad")
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for n in Hex.neighbors(c):
			if not seen.has(n) and _map.country_at(n) == "RU":
				seen[n] = true
				stack.append(n)
	assert_eq(seen.size(), russia.size(), "RU hexes reachable from Kaliningrad through RU hexes")
	for c in russia:
		for n in Hex.neighbors(c):
			assert_true(_map.country_at(n) != "BY", "RU hex %s touches BY hex %s" % [c, n])


## The Suwalki Gap: the fewest PL / LT land hexes in a chain from a RU hex to a BY hex.
func test_the_suwalki_gap_is_about_thirteen_hexes_wide() -> void:
	var dist := {}
	var queue: Array[Vector2i] = []
	for c in _hexes_of("RU"):
		for n in Hex.neighbors(c):
			var code := _map.country_at(n)
			if (code == "PL" or code == "LT") and not dist.has(n):
				dist[n] = 1
				queue.append(n)
	var best := 1000000
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for n in Hex.neighbors(c):
			var code := _map.country_at(n)
			if code == "BY":
				best = mini(best, dist[c])
			elif (code == "PL" or code == "LT") and not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	print("Suwalki Gap: shortest RU-to-BY chain of PL/LT hexes = %d" % best)
	assert_true(best >= 10 and best <= 18, "Gap chain of %d hexes" % best)


## The drawn borders are the real ways (TASK-113): valid, simplified, and every pair of
## neighbouring hexes of different countries has a border line close to its shared edge.
func test_the_drawn_borders_run_where_the_countries_meet() -> void:
	assert_eq(_map.problem(), "")
	assert_true(_map.border_lines.size() >= 3, "%d border lines" % _map.border_lines.size())
	var far: Array[String] = []
	var checked := 0
	for c in _hexes_of("RU") + _hexes_of("LT") + _hexes_of("BY"):
		for n in Hex.neighbors(c):
			var other := _map.country_at(n)
			if other == "" or other == _map.country_at(c):
				continue
			checked += 1
			var a := Hex.to_world(c, 1.0)
			var b := Hex.to_world(n, 1.0)
			var mid := Vector2(a.x + b.x, a.z + b.z) / 2.0
			if _distance_to_borders(mid) > 1.2:
				far.append("%s-%s" % [c, n])
	assert_true(checked > 50, "%d country edges checked" % checked)
	assert_eq(far.size(), 0, "edges far from every border line: %s" % [far.slice(0, 5)])


func _distance_to_borders(point: Vector2) -> float:
	var best := INF
	for line in _map.border_lines:
		for i in line.size() - 1:
			var closest := Geometry2D.get_closest_point_to_segment(point, line[i], line[i + 1])
			best = minf(best, closest.distance_to(point))
	return best


func test_to_grid_takes_at_most_a_second() -> void:
	var times: Array[float] = []
	for i in 3:
		var start := Time.get_ticks_usec()
		var grid := _map.to_grid()
		times.append((Time.get_ticks_usec() - start) / 1e6)
		assert_true(grid != null)
	times.sort()
	assert_true(times[1] <= 1.0, "to_grid median %.3f s" % times[1])


func test_the_theatre_is_not_a_battle_scenario() -> void:
	assert_false("suwalki_theatre" in Scenario.NAMES)
	for scenario_name in Scenario.NAMES:
		assert_false(scenario_name.contains("theatre"), scenario_name)


# Graphic layers (TASK-126) --------------------------------------------------------------------

## [name, lat, lon] of lake points smaller than their hex: water in the layer, not a WATER hex.
const SMALL_LAKES := [
	["Wigry (north)", 54.05, 23.10],
	["Wigry (south)", 54.02, 23.06],
	["Hancza", 54.265, 22.815],
]
const MAX_FILE_BYTES := 2_500_000


## Layer pixel (water / cover grid) of a WGS84 point.
func _layer_pixel(lat: float, lon: float) -> Vector2i:
	var utm := _to_utm34(lat, lon)
	var m := _map.metres_per_world_unit()
	var world := Vector2((utm[0] - _map.origin_easting) / m, (_map.origin_northing - utm[1]) / m)
	var pixel := _map.world_to_layer_pixel(world)
	return Vector2i(roundi(pixel.x), roundi(pixel.y))


func test_the_theatre_has_valid_layers_of_250_m() -> void:
	assert_true(_map.has_graphic_layers())
	assert_eq(_map.graphic_layers_problem(), "")
	assert_eq(_map.layer_pixel_m, 250.0)
	assert_eq(_map.layer_size(), Vector2i(1371, 1115))
	assert_eq(_map.layer_size(ImportedMap.LAYER_RELIEF), Vector2i(686, 558))


func test_lakes_smaller_than_a_hex_are_water_in_the_layer() -> void:
	var water := _map.layer_bytes(ImportedMap.LAYER_WATER)
	for lake: Array in SMALL_LAKES:
		var pixel := _layer_pixel(lake[1], lake[2])
		assert_eq(water[pixel.y * _map.layer_width + pixel.x], ImportedMap.WATER_VALUE, lake[0])
		assert_true(_terrain_at(_tile_of(lake[1], lake[2])) != "W", "%s: land hex" % lake[0])


func test_the_curonian_spit_is_land_between_sea_and_lagoon() -> void:
	var water := _map.layer_bytes(ImportedMap.LAYER_WATER)
	for lat: float in [55.1, 55.2, 55.3]:
		var west := _layer_pixel(lat, 20.5)
		var east := _layer_pixel(lat, 21.3)
		var runs := ""
		for x in range(west.x, east.x + 1):
			var ch := "W" if water[west.y * _map.layer_width + x] != 0 else "L"
			if not runs.ends_with(ch):
				runs += ch
		assert_true(runs.begins_with("WLW"), "lat %.1f: sea, spit, lagoon (%s)" % [lat, runs])


func test_towns_are_urban_in_the_cover_layer() -> void:
	var cover := _map.layer_bytes(ImportedMap.LAYER_COVER)
	for city: String in ["Suwalki", "Kaunas"]:
		var place := _place(city)
		var pixel := _layer_pixel(place[1], place[2])
		assert_eq(cover[pixel.y * _map.layer_width + pixel.x], ImportedMap.COVER_URBAN, city)


func test_the_map_file_stays_within_its_size_budget() -> void:
	var path := ImportedMap.MAPS_DIR + String(MAP_ID) + ".tres"
	var size := FileAccess.open(path, FileAccess.READ).get_length()
	assert_true(size <= MAX_FILE_BYTES, "%d bytes" % size)


func test_loading_and_decoding_the_layers_stays_fast() -> void:
	# Measured 2026-11-07: load 74 ms (9 ms without layers) + decode 13 ms; the budget is
	# +150 ms (TASK-126). The guard is looser for slower machines.
	var path := ImportedMap.MAPS_DIR + String(MAP_ID) + ".tres"
	var times: Array[float] = []
	for i in 3:
		var start := Time.get_ticks_usec()
		var map := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ImportedMap
		for kind in ImportedMap.LAYERS:
			assert_true(map.layer_image(kind) != null)
		times.append((Time.get_ticks_usec() - start) / 1e6)
	times.sort()
	assert_true(times[1] <= 0.3, "load + decode median %.3f s" % times[1])
