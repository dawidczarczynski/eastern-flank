extends TestCase
## Graphic layers of the operational theatre map (TASK-126), split from
## test_operational_map_data.gd. Shares its projection helpers and places.

const MapData := preload("res://tests/unit/test_operational_map_data.gd")
const MAP_ID := &"suwalki_theatre"
## [name, lat, lon] of lake points smaller than their hex: water in the layer, not a WATER hex.
const SMALL_LAKES := [
	["Wigry (north)", 54.05, 23.10],
	["Wigry (south)", 54.02, 23.06],
	["Hancza", 54.265, 22.815],
]
const MAX_FILE_BYTES := 2_500_000

static var _map: ImportedMap


func before_all() -> void:
	_map = ImportedMap.find(MAP_ID)


func after_all() -> void:
	_map = null


## Offset tile (column, row) of a WGS84 point on the theatre map.
func _tile_of(lat: float, lon: float) -> Vector2i:
	var utm := MapData._to_utm34(lat, lon)
	return MapGenerator.axial_to_offset(_map.projected_to_tile(utm[0], utm[1]))


func _terrain_at(offset: Vector2i) -> String:
	return _map.terrain_rows[offset.y][offset.x]


func _place(place_name: String) -> Array:
	for place: Array in MapData.PLACES:
		if place[0] == place_name:
			return place
	return []


## Layer pixel (water / cover grid) of a WGS84 point.
func _layer_pixel(lat: float, lon: float) -> Vector2i:
	var utm := MapData._to_utm34(lat, lon)
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
