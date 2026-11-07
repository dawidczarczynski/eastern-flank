extends TestCase
## ImportedMap graphic layers (TASK-126): water / cover / relief images of the operational
## import, finer than the hexes, for drawing only. tests/fixtures/maps/sample_op_map.tres is the
## importer's output on SYNTHETIC fixtures (10 x 8 hexes of 1 km, 43 x 29 pixels of 250 m; see
## tools/test_import_map.py); points are UTM 34N metres from the importer's `to_utm`.

const SAMPLE_OP_PATH := "res://tests/fixtures/maps/sample_op_map.tres"
const SAMPLE_PATH := "res://tests/fixtures/maps/sample_map.tres"
const SAVED_PATH := "user://test_imported_map_layers.tres"
## [easting, northing] of synthetic features.
const LAKE := [601247.6, 6037496.2]
const SEA := [592586.6, 6041040.8]
const FOREST := [597167.2, 6038854.4]
const TOWN := [600683.0, 6041045.6]
const HILL_NW_FLANK := [597031.3, 6042190.8]
const HILL_SE_FLANK := [597822.3, 6041539.8]


func _sample() -> ImportedMap:
	return load(SAMPLE_OP_PATH) as ImportedMap


## Layer pixel of a projected point.
static func _pixel(map: ImportedMap, point: Array) -> Vector2i:
	var m := map.metres_per_world_unit()
	var world := Vector2(
		(float(point[0]) - map.origin_easting) / m, (map.origin_northing - float(point[1])) / m
	)
	var pixel := map.world_to_layer_pixel(world)
	return Vector2i(roundi(pixel.x), roundi(pixel.y))


static func _value(map: ImportedMap, kind: StringName, point: Array) -> int:
	var pixel := _pixel(map, point)
	if kind == ImportedMap.LAYER_RELIEF:
		var step := float(map.layer_relief_step)
		pixel = Vector2i(roundi(pixel.x / step), roundi(pixel.y / step))
	return map.layer_bytes(kind)[pixel.y * map.layer_size(kind).x + pixel.x]


func test_the_operational_sample_has_valid_layers_of_250_m() -> void:
	var map := _sample()
	assert_true(map.has_graphic_layers())
	assert_eq(map.graphic_layers_problem(), "")
	assert_eq(map.layer_size(), Vector2i(43, 29))
	assert_eq(map.layer_size(ImportedMap.LAYER_COVER), Vector2i(43, 29))
	assert_eq(map.layer_size(ImportedMap.LAYER_RELIEF), Vector2i(22, 15), "500 m relief pixels")
	assert_eq(map.layer_pixel_m, 250.0)
	assert_eq(map.layer_relief_step, 2)
	for kind in ImportedMap.LAYERS:
		var image := map.layer_image(kind)
		var size := map.layer_size(kind)
		assert_true(image != null, "%s decodes" % kind)
		assert_eq(image.get_format(), Image.FORMAT_L8)
		assert_eq(Vector2i(image.get_width(), image.get_height()), size)
		assert_eq(map.layer_bytes(kind).size(), size.x * size.y)


func test_layer_values_at_the_synthetic_features() -> void:
	var map := _sample()
	assert_eq(_value(map, ImportedMap.LAYER_WATER, LAKE), ImportedMap.WATER_VALUE)
	assert_eq(_value(map, ImportedMap.LAYER_COVER, LAKE), ImportedMap.COVER_WATER)
	assert_eq(_value(map, ImportedMap.LAYER_WATER, SEA), ImportedMap.WATER_VALUE)
	assert_eq(_value(map, ImportedMap.LAYER_WATER, FOREST), 0)
	assert_eq(_value(map, ImportedMap.LAYER_COVER, FOREST), ImportedMap.COVER_FOREST)
	assert_eq(_value(map, ImportedMap.LAYER_COVER, TOWN), ImportedMap.COVER_URBAN)
	var lit := _value(map, ImportedMap.LAYER_RELIEF, HILL_NW_FLANK)
	var shaded := _value(map, ImportedMap.LAYER_RELIEF, HILL_SE_FLANK)
	assert_true(lit > ImportedMap.RELIEF_FLAT + 10, "north-west flank lit: %d" % lit)
	assert_true(shaded < ImportedMap.RELIEF_FLAT - 10, "south-east flank shaded: %d" % shaded)


func test_pixel_and_world_mapping_round_trip() -> void:
	var map := _sample()
	var pixel := Vector2(12.25, 7.5)
	var back := map.world_to_layer_pixel(map.layer_pixel_to_world(pixel))
	assert_true(back.distance_to(pixel) < 1e-4, "%s" % back)
	var step := map.layer_pixel_to_world(Vector2(1, 0)) - map.layer_pixel_to_world(Vector2.ZERO)
	assert_true(absf(step.x - map.layer_pixel_world_size()) < 1e-4 and absf(step.y) < 1e-4)
	var down := map.layer_pixel_to_world(Vector2(0, 1)) - map.layer_pixel_to_world(Vector2.ZERO)
	assert_true(down.y > 0.0, "row 1 lies south of row 0 (world +z)")
	# 1 km hexes: one world unit is 1000 / sqrt(3) m, a 250 m pixel 0.433 units
	assert_true(absf(map.layer_pixel_world_size() - 250.0 * Hex.SQRT3 / 1000.0) < 1e-9)
	var relief := map.layer_pixel_world_size(ImportedMap.LAYER_RELIEF)
	assert_true(absf(relief - 2.0 * map.layer_pixel_world_size()) < 1e-9)


func test_the_layers_cover_every_hex_centre() -> void:
	var map := _sample()
	var rect := map.layer_world_rect()
	assert_true(rect.has_area())
	assert_true(rect.position.is_equal_approx(map.layer_pixel_to_world(Vector2(-0.5, -0.5))))
	var relief := map.layer_world_rect(ImportedMap.LAYER_RELIEF)
	assert_true(relief.position.is_equal_approx(map.layer_pixel_to_world(Vector2(-1.0, -1.0))))
	assert_true(relief.encloses(rect), "the relief texels end half a coarse pixel outside")
	for row in map.height:
		for col in map.width:
			var axial := MapGenerator.offset_to_axial(col, row)
			var centre := Hex.to_world(axial, TerrainField.HEX_SIZE)
			assert_true(rect.has_point(Vector2(centre.x, centre.z)), "hex %d,%d" % [col, row])


func test_save_and_load_keep_the_layers_byte_for_byte() -> void:
	var map := _sample()
	assert_eq(ResourceSaver.save(map, SAVED_PATH), OK)
	var loaded := (
		ResourceLoader.load(SAVED_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ImportedMap
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED_PATH))
	assert_true(loaded != null)
	for kind in ImportedMap.LAYERS:
		assert_eq(loaded.layer_png(kind), map.layer_png(kind), "%s png" % kind)
		assert_eq(loaded.layer_bytes(kind), map.layer_bytes(kind), "%s pixels" % kind)
	assert_eq(loaded.layer_world_rect(), map.layer_world_rect())
	assert_eq(loaded.terrain_rows, map.terrain_rows)


func test_maps_without_layers_load_and_report_none() -> void:
	var tactical := load(SAMPLE_PATH) as ImportedMap
	for map: ImportedMap in [tactical, ImportedMap.new()]:
		assert_false(map.has_graphic_layers())
		assert_eq(map.layer_size(), Vector2i.ZERO)
		assert_eq(map.graphic_layers_problem(), "no graphic layers")
		assert_eq(map.layer_world_rect(), Rect2())
		for kind in ImportedMap.LAYERS:
			assert_true(map.layer_image(kind) == null)
			assert_true(map.layer_bytes(kind).is_empty())
	assert_true(tactical.to_grid() != null, "the rules grid does not need layers")


func test_problem_reports_malformed_layers() -> void:
	var map := _sample().duplicate() as ImportedMap
	map.layer_width += 1
	assert_true(map.graphic_layers_problem().contains("does not decode"))
	assert_true(map.layer_image(ImportedMap.LAYER_WATER) == null)
	map = _sample().duplicate() as ImportedMap
	map.layer_cover_png = PackedByteArray([1, 2, 3])
	assert_true(map.graphic_layers_problem().contains("cover"))
	assert_true(map.to_grid() != null, "malformed layers never break the rules grid")
	map = _sample().duplicate() as ImportedMap
	map.layer_water_png = map.layer_cover_png
	assert_true(map.graphic_layers_problem().contains("water layer value"))
	assert_true(ImportedMap.new().layer_image(&"unknown") == null)
