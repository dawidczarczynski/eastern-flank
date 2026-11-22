extends TestCase
## Satellite colour layer (TASK-192a, ADR 0031): ColourRaster and how ImportedMap / TacticalLayer
## load it. The fixtures are made by tools/test_import_map.py --make-fixtures from SYNTHETIC
## Sentinel-2 scenes: scene A is three flat colours west / middle / east with a cloud over the
## north-west corner and no data in a southern strip of the middle, both filled from scene B.

const COLOUR_MAP := "res://tests/fixtures/maps/sample_colour_map.tres"
const PLAIN_MAP := "res://tests/fixtures/maps/sample_map.tres"
const LAYER_FOLDER := "res://tests/fixtures/maps/sample_layer/"
## sRGB of the fixture colours after the importer's L2A -> sRGB (tools/test_import_map.py).
const MIDDLE := Color8(126, 133, 101)
const FILL := Color8(56, 91, 45)
const EAST := Color8(163, 152, 133)
## JPEG (quality 85) keeps a flat area within a few levels.
const TOLERANCE := 4.0 / 255.0


func _near(actual: Color, expected: Color, message: String) -> void:
	var ok := (
		absf(actual.r - expected.r) <= TOLERANCE
		and absf(actual.g - expected.g) <= TOLERANCE
		and absf(actual.b - expected.b) <= TOLERANCE
	)
	assert_true(
		ok, "%s: %s, expected %s" % [message, actual.to_html(false), expected.to_html(false)]
	)


func test_raster_samples_bilinear_between_pixel_centres_and_clamps() -> void:
	var image := Image.create(2, 1, false, Image.FORMAT_RGB8)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0))
	image.set_pixel(1, 0, Color(1.0, 0.5, 0.0))
	var raster := ColourRaster.from_image(image, 10.0, Vector2(5.0, 5.0))
	assert_true(raster != null)
	_near(raster.sample(5.0, 5.0), Color(0.0, 0.0, 0.0), "pixel (0, 0) centre")
	_near(raster.sample(10.0, 5.0), Color(0.5, 0.25, 0.0), "halfway")
	_near(raster.sample(500.0, -50.0), Color(1.0, 0.5, 0.0), "outside: the edge pixel")
	assert_eq(raster.size(), Vector2i(2, 1))


func test_from_jpg_rejects_bad_bytes_and_wrong_sizes() -> void:
	assert_true(ColourRaster.from_jpg(PackedByteArray([1, 2, 3]), 2, 2, 10.0, Vector2.ZERO) == null)
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var jpg := image.save_jpg_to_buffer()
	assert_true(ColourRaster.from_jpg(jpg, 4, 4, 10.0, Vector2.ZERO) != null)
	assert_true(ColourRaster.from_jpg(jpg, 5, 4, 10.0, Vector2.ZERO) == null)


func test_imported_map_samples_its_layer_at_the_fixture_points() -> void:
	var map := load(COLOUR_MAP) as ImportedMap
	assert_true(map.has_colour_layer())
	assert_eq(map.problem(), "")
	var c := map.colour_cell_m
	# The frame: metres east / south of tile (0, 0)'s centre (world units x metres_per_world_unit).
	var west := map.colour_origin_easting - c * 0.5 - map.origin_easting
	var north := map.origin_northing - (map.colour_origin_northing + c * 0.5)
	var w := map.colour_width * c
	var h := map.colour_height * c
	_near(map.sample(west + w * 0.5, north + h * 0.5), MIDDLE, "centre (scene A)")
	_near(map.sample(west + c * 0.5, north + c * 0.5), FILL, "north-west corner (cloud in A: B)")
	_near(map.sample(west + w + 500.0, north + h + 500.0), EAST, "outside: the south-east edge")
	_near(map.sample(west + w * 0.5, north + h - c), FILL, "the strip without data in A: B")
	assert_true(map.colour_sources.contains("Copernicus Sentinel data 2024"))


func test_a_map_without_the_layer_loads_as_before() -> void:
	var map := load(PLAIN_MAP) as ImportedMap
	assert_eq(map.problem(), "")
	assert_false(map.has_colour_layer())
	assert_true(map.colour_raster() == null)
	assert_true(map.land_cover_cell_m > 0.0, "the older data is still there")
	var op := load("res://tests/fixtures/maps/sample_op_map.tres") as ImportedMap
	assert_false(op.has_colour_layer())


func test_tactical_layer_samples_across_its_chunk_windows() -> void:
	var layer := TacticalLayer.from_folder(LAYER_FOLDER)
	assert_true(layer != null)
	assert_true(layer.has_colour_layer())
	assert_eq(layer.colour_cell_m, 40.0)
	var c := layer.colour_cell_m
	var west := layer.colour_origin_easting - c * 0.5 - layer.origin_easting
	var north := layer.origin_northing - (layer.colour_origin_northing + c * 0.5)
	var w := layer.colour_width * c
	var h := layer.colour_height * c
	# The synthetic scene: red rises 1 DN per 8 m east, green 1 DN per 8 m south, so neighbouring
	# samples differ a little and the colour never jumps at a chunk border.
	var previous := layer.sample(west + c * 0.5, north + h * 0.5)
	var x := west + c * 0.5
	var largest := 0.0
	while x < west + w:
		var colour := layer.sample(x, north + h * 0.5)
		largest = maxf(largest, absf(colour.r - previous.r) + absf(colour.g - previous.g))
		previous = colour
		x += c * 0.5
	assert_true(largest < 8.0 / 255.0, "no jump between chunk windows (largest step %f)" % largest)
	var east := layer.sample(west + w - c * 0.5, north + c * 0.5)
	var west_colour := layer.sample(west + c * 0.5, north + c * 0.5)
	assert_true(east.r > west_colour.r + 0.05, "redder to the east")
	_near(layer.sample(west - 1000.0, north - 1000.0), west_colour, "outside: the north-west edge")
	assert_true(layer.loaded_colour_windows() >= 3, "the windows of a row of chunks")


func test_a_layer_without_colour_loads_as_before() -> void:
	var grid := HexGrid.new()
	var layer := TacticalLayer.from_grid(grid, 2, 2)
	assert_false(layer.has_colour_layer())
	assert_eq(layer.sample(0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0))
