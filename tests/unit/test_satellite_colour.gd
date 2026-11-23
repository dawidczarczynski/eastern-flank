extends TestCase
## Satellite colour blend (TASK-192b, ADR 0031): the weight / tint functions SatelliteColour shares
## with assets/shaders/satellite_colour.gdshaderinc, the flag that keeps `balanced` and maps
## without a layer unchanged, and the layer textures cut from the fixture map / layer.

const COLOUR_MAP := "res://tests/fixtures/maps/sample_colour_map.tres"
const PLAIN_MAP := "res://tests/fixtures/maps/sample_map.tres"
const LAYER_FOLDER := "res://tests/fixtures/maps/sample_layer/"
const INCLUDE := "res://assets/shaders/satellite_colour.gdshaderinc"
const TERRAIN := "res://assets/shaders/terrain.gdshader"
const CANOPY := "res://assets/shaders/canopy.gdshader"
## Splat-like and canopy colours (linear) against layer colours of other hues.
const BASES: Array[Color] = [
	Color(0.114, 0.172, 0.020), Color(0.335, 0.268, 0.057), Color(0.083, 0.053, 0.022)
]
const LAYERS: Array[Color] = [
	Color(0.12, 0.15, 0.10), Color(0.30, 0.22, 0.08), Color(0.03, 0.06, 0.04), Color(0.4, 0.4, 0.4)
]


func after_each() -> void:
	VisualScale.reset()
	LookPreset.reset()


func _close(actual: float, expected: float, tolerance: float, message := "") -> void:
	assert_true(
		absf(actual - expected) <= tolerance, "%s: %f, expected %f" % [message, actual, expected]
	)


func _shader_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	return material


func _colour() -> SatelliteColour:
	return SatelliteColour.from_imported(load(COLOUR_MAP) as ImportedMap)


func test_look_preset_holds_the_blend_values_in_metres() -> void:
	var values := LookPreset.satellite()
	assert_eq(values["near_tint"], 0.25)
	assert_eq(values["blend_start_m"], 300.0)
	assert_eq(values["blend_end_m"], 1500.0)


func test_weight_is_the_near_tint_close_up_and_one_far_away() -> void:
	var values := LookPreset.satellite()
	_close(SatelliteColour.weight(0.0, values), 0.25, 1e-6)
	_close(SatelliteColour.weight(300.0, values), 0.25, 1e-6)
	var mid := SatelliteColour.weight(900.0, values)
	assert_true(mid > 0.25 and mid < 1.0, "900 m lies between: %f" % mid)
	_close(SatelliteColour.weight(1500.0, values), 1.0, 1e-6)
	_close(SatelliteColour.weight(5000.0, values), 1.0, 1e-6)
	var previous := 0.0
	for d in range(0, 2000, 50):
		var w := SatelliteColour.weight(float(d), values)
		assert_true(w >= previous, "the weight never falls with distance")
		previous = w


func test_near_tint_preserves_the_luminance_and_takes_the_layer_hue() -> void:
	var values := LookPreset.satellite()
	for base in BASES:
		for layer in LAYERS:
			var near := SatelliteColour.ground(base, layer, 100.0, values)
			var lb := SatelliteColour.luma(base)
			var diff := absf(SatelliteColour.luma(near) - lb) / lb
			assert_true(diff <= 0.02, "near luma within 2 %% (%f)" % diff)
			# Towards the layer's chroma: the hue shifts by a quarter of the way.
			var hue := SatelliteColour.hue(base, layer)
			_close(near.r, lerpf(base.r, hue.r, 0.25), 1e-5)
			_close(near.g, lerpf(base.g, hue.g, 0.25), 1e-5)


func test_far_ground_is_the_layer_colour() -> void:
	var values := LookPreset.satellite()
	for base in BASES:
		for layer in LAYERS:
			var far := SatelliteColour.ground(base, layer, 1500.0, values)
			_close(far.r, layer.r, 1e-5)
			_close(far.g, layer.g, 1e-5)
			_close(far.b, layer.b, 1e-5)
			# No coverage (beyond the raster): the textured colour.
			var outside := SatelliteColour.ground(base, layer, 1500.0, values, 0.0)
			_close(outside.g, base.g, 1e-6)


func test_the_blend_has_no_jump() -> void:
	var values := LookPreset.satellite()
	var base := BASES[1]
	var layer := LAYERS[0]
	var previous := SatelliteColour.ground(base, layer, 0.0, values)
	for d in range(10, 2000, 10):
		var c := SatelliteColour.ground(base, layer, float(d), values)
		var step := absf(c.r - previous.r) + absf(c.g - previous.g) + absf(c.b - previous.b)
		assert_true(step < 0.01, "step at %d m: %f" % [d, step])
		previous = c


func test_canopy_takes_the_layer_hue_and_keeps_its_lit_shadow_ratio() -> void:
	var values := LookPreset.satellite()
	# canopy.gdshader: crown top 0.85, gap 0.4 (dome shade) times the crown colour.
	for base in BASES:
		for layer in LAYERS:
			var crown := SatelliteColour.canopy(base, layer, 2000.0, values)
			var before := SatelliteColour.luma(base * 0.85) / SatelliteColour.luma(base * 0.4)
			var after := SatelliteColour.luma(crown * 0.85) / SatelliteColour.luma(crown * 0.4)
			assert_true(absf(after / before - 1.0) <= 0.02, "lit / shadow ratio within 2 %")
			var lum_diff := absf(SatelliteColour.luma(crown) / SatelliteColour.luma(base) - 1.0)
			assert_true(lum_diff <= 0.02, "the crown keeps its brightness")
			if layer.s > 0.05:
				var dh := absf(crown.h - layer.h)
				assert_true(minf(dh, 1.0 - dh) < 0.01, "the layer's hue far away")


func test_balanced_or_no_layer_leaves_the_flag_off() -> void:
	var default_on: Variant = RenderingServer.shader_get_parameter_default(
		TerrainGround.SHADER.get_rid(), &"satellite_on"
	)
	assert_true(default_on == null or default_on == false, "the shader default is off")
	var colour := _colour()
	assert_true(colour != null)
	var balanced := _shader_material()
	SatelliteColour.apply(balanced, colour)
	assert_false(balanced.get_shader_parameter(&"satellite_on"), "balanced: off")
	assert_true(balanced.get_shader_parameter(&"satellite_map") == null, "no texture bound")
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var no_layer := _shader_material()
	SatelliteColour.apply(no_layer, null)
	assert_false(no_layer.get_shader_parameter(&"satellite_on"), "true without a layer: off")
	assert_true(SatelliteColour.from_imported(load(PLAIN_MAP) as ImportedMap) == null)


func test_for_map_only_under_the_true_preset() -> void:
	assert_true(SatelliteColour.for_map(&"suwalki", Rect2i(), 0.0) == null, "balanced: none")
	VisualScale.apply(VisualScale.TRUE_PRESET)
	assert_true(SatelliteColour.for_map(BattleSetup.MAP_GENERATED_RIVER, Rect2i(), 0.0) == null)


func test_true_preset_sets_the_parameters_in_world_units() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var colour := _colour()
	var material := _shader_material()
	SatelliteColour.apply(material, colour)
	assert_true(material.get_shader_parameter(&"satellite_on"))
	var blend: Vector2 = material.get_shader_parameter(&"satellite_blend")
	_close(blend.x, MapScale.to_units(300.0), 1e-5)
	_close(blend.y, MapScale.to_units(1500.0), 1e-5)
	_close(material.get_shader_parameter(&"satellite_near_tint"), 0.25, 1e-6)
	var rect: Vector4 = material.get_shader_parameter(&"satellite_rect")
	_close(rect.x, colour.rect.position.x, 1e-5)
	_close(rect.z, 1.0 / colour.rect.size.x, 1e-6)
	assert_true(material.get_shader_parameter(&"satellite_map") is ImageTexture)


func test_imported_layer_texture_matches_the_raster() -> void:
	var map := load(COLOUR_MAP) as ImportedMap
	var colour := SatelliteColour.from_imported(map)
	var m := map.metres_per_world_unit()
	assert_eq(colour.image.get_size(), Vector2i(map.colour_width, map.colour_height))
	_close(colour.rect.size.x, map.colour_width * map.colour_cell_m / m, 1e-4)
	# A world point and the same point in the raster's metres give the same colour.
	var p := colour.rect.get_center()
	var expected := map.sample(p.x * m, p.y * m)
	var actual := colour.sample_world(p.x, p.y)
	_close(actual.r, expected.r, 1e-4)
	_close(actual.g, expected.g, 1e-4)
	assert_true(colour.gpu_bytes() > colour.image.get_width() * colour.image.get_height() * 4)


func test_layer_cut_matches_the_layer_samples() -> void:
	var layer := TacticalLayer.from_folder(LAYER_FOLDER)
	var region := Rect2i(0, 0, layer.width, layer.height)
	var colour := SatelliteColour.from_layer(layer, region, 1.0)
	assert_true(colour != null)
	var m := layer.metres_per_world_unit()
	var c := layer.colour_cell_m
	_close(colour.rect.size.x / colour.image.get_width(), c / m, 1e-5)
	for p: Vector2 in [colour.rect.get_center(), colour.rect.position + colour.rect.size * 0.3]:
		var expected := layer.sample(p.x * m, p.y * m)
		var actual := colour.sample_world(p.x, p.y)
		assert_true(
			(
				absf(actual.r - expected.r) <= 2.0 / 255.0
				and absf(actual.g - expected.g) <= 2.0 / 255.0
			),
			"cut %s vs layer %s at %s" % [actual, expected, p]
		)
	assert_true(SatelliteColour.from_layer(layer, Rect2i(0, 1, 1, 1), 0.0) == null, "odd row")


func test_the_shaders_include_the_layer_and_guard_it_by_the_flag() -> void:
	for path in [TERRAIN, CANOPY]:
		var code := FileAccess.get_file_as_string(path)
		assert_true(code.contains('#include "%s"' % INCLUDE), path)
		assert_true(code.contains("if (satellite_on)"), path)
	var include := FileAccess.get_file_as_string(INCLUDE)
	assert_true(include.contains("uniform bool satellite_on = false;"))
