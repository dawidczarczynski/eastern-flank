extends TestCase
## TerrainGround (TASK-134): ground textures repeat in real metres through MapScale, and a detail
## texture fades in close to the camera.


func after_each() -> void:
	MapScale.reset()


func test_layer_repeats_are_the_real_texture_sizes_through_map_scale() -> void:
	var repeats := TerrainGround.layer_repeats()
	assert_eq(repeats.size(), TerrainTextures.SOURCE_METRES.size())
	for i in repeats.size():
		var metres := TerrainTextures.SOURCE_METRES[i]
		assert_true(is_equal_approx(repeats[i], metres / MapScale.metres_per_unit), "layer %d" % i)
		# Grass: 1.4 m, i.e. ~100 repeats per world unit at the 250 m hex (was 1.4 per unit).
		assert_true(repeats[i] < 0.03, "layer %d is a few metres, not ~100 m" % i)
	MapScale.metres_per_unit = 50.0
	var coarse := TerrainGround.layer_repeats()
	for i in repeats.size():
		assert_true(
			is_equal_approx(coarse[i], TerrainTextures.SOURCE_METRES[i] / 50.0), "follows MapScale"
		)


func test_the_material_carries_the_real_metre_repeats_and_the_detail() -> void:
	var material := TerrainGround.material({"terrain_texture_size": 16})
	var repeats: PackedFloat32Array = material.get_shader_parameter(&"layer_repeat")
	assert_eq(repeats, TerrainGround.layer_repeats())
	# Beyond the cross-fade band the far pattern (also metres through MapScale) keeps the ground
	# readable from the default zoom; the band ends before the default camera distance.
	var far: PackedFloat32Array = material.get_shader_parameter(&"layer_repeat_far")
	assert_eq(far, TerrainGround.layer_repeats(TerrainGround.FAR_PATTERN_FACTOR))
	var band: Vector2 = material.get_shader_parameter(&"scale_fade")
	assert_true(band.x < band.y and band.y < CameraRig.DEFAULT_DISTANCE, "%s" % band)
	assert_true(material.get_shader_parameter(&"detail_on"))
	assert_true(material.get_shader_parameter(&"detail_map") is Texture2D)
	assert_true(
		is_equal_approx(
			material.get_shader_parameter(&"detail_repeat"),
			MapScale.to_units(TerrainGround.DETAIL_METRES)
		)
	)
	var fade: Vector2 = material.get_shader_parameter(&"detail_fade")
	assert_true(fade.x < fade.y and absf(fade.y - 6.0) < 0.5, "fades in below ~6 units: %s" % fade)


func test_the_shader_fades_the_detail_by_view_distance() -> void:
	var code := TerrainGround.SHADER.code
	for name: String in [
		"detail_on", "detail_map", "detail_repeat", "detail_fade", "layer_repeat_far", "scale_fade"
	]:
		assert_true(code.contains("uniform") and code.contains(name), name)
	assert_true(code.contains("CAMERA_POSITION_WORLD"), "faded by the distance to the camera")


func test_the_detail_texture_tiles_and_carries_height_in_alpha() -> void:
	var texture := TerrainGround.detail_texture()
	var image := texture.get_image()
	assert_eq(image.get_size(), Vector2i.ONE * TerrainGround.DETAIL_SIZE)
	assert_true(image.has_mipmaps())
	var low := 1.0
	var high := 0.0
	for k in 64:
		var a := image.get_pixel(k * 2, k).a
		low = minf(low, a)
		high = maxf(high, a)
	assert_true(high - low > 0.1, "height varies: %f..%f" % [low, high])
	assert_eq(TerrainGround.detail_texture(), texture, "made once")
