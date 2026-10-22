extends TestCase
## TerrainTextures: fallback for maps that cannot be loaded (TASK-055).


func test_fallback_maps_are_neutral_and_sized() -> void:
	var normal := TerrainTextures._fallback_map("normal_gl", 8, Image.FORMAT_RGBA8)
	assert_eq(normal.get_size(), Vector2i(8, 8))
	var n := normal.get_pixel(3, 3)
	assert_true(absf(n.r - 0.5) < 0.01 and absf(n.g - 0.5) < 0.01 and n.b > 0.99, str(n))
	var ao := TerrainTextures._fallback_map("ao", 8, Image.FORMAT_L8)
	assert_eq(ao.get_format(), Image.FORMAT_L8)
	assert_true(ao.get_pixel(0, 0).r > 0.99, "no occlusion")
	var albedo := TerrainTextures._fallback_map("albedo", 8, Image.FORMAT_RGBA8)
	assert_true(absf(albedo.get_pixel(0, 0).r - 0.5) < 0.01, "mid grey")


func test_every_layer_map_loads_at_the_requested_size() -> void:
	for layer in TerrainTextures.LAYERS.size():
		for map_name: String in ["albedo", "normal_gl", "roughness", "ao", "height"]:
			var image := TerrainTextures._load_map(layer, map_name, 64, Image.FORMAT_RGBA8)
			assert_eq(image.get_size(), Vector2i(64, 64), "%d %s" % [layer, map_name])
