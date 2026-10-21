extends TestCase


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_neutral_greys_stay_neutral() -> void:
	for v in [0.1, 0.5, 0.9]:
		var c := ColorGrade.grade(Color(v, v, v), ColorGrade.DEFAULT)
		var spread := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
		assert_true(spread <= 0.03, "grey %s -> %s spread %s" % [v, c, spread])


func test_luminance_is_monotonic_over_grey_ramp() -> void:
	var previous := -1.0
	for i in 11:
		var v := i / 10.0
		var lum := _lum(ColorGrade.grade(Color(v, v, v), ColorGrade.DEFAULT))
		assert_true(lum > previous, "step %d not increasing (%s <= %s)" % [i, lum, previous])
		previous = lum


func test_saturation_drops() -> void:
	var grass := Color.html("#5a8a2e")
	var graded := ColorGrade.grade(grass, ColorGrade.DEFAULT)
	assert_true(graded.s < grass.s, "%s !< %s" % [graded.s, grass.s])


func test_green_shifts_toward_olive() -> void:
	var grass := Color.html("#5a8a2e")
	var no_shift := ColorGrade.DEFAULT.duplicate()
	no_shift["green_shift"] = 0.0
	var graded := ColorGrade.grade(grass, ColorGrade.DEFAULT)
	var control := ColorGrade.grade(grass, no_shift)
	assert_true(graded.h < control.h, "hue %s !< %s" % [graded.h, control.h])


func test_output_is_clamped() -> void:
	for c in [Color.WHITE, Color.BLACK, Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]:
		var g := ColorGrade.grade(c, ColorGrade.DEFAULT)
		for v in [g.r, g.g, g.b]:
			assert_true(v >= 0.0 and v <= 1.0, "%s out of range" % g)


func test_lut_dimensions() -> void:
	var slices := ColorGrade.lut(17, ColorGrade.DEFAULT)
	assert_eq(slices.size(), 17)
	for img in slices:
		assert_eq(img.get_width(), 17)
		assert_eq(img.get_height(), 17)


func test_lut_texels_match_grade() -> void:
	var slices := ColorGrade.lut(17, ColorGrade.DEFAULT)
	for b in [0, 5, 16]:
		for g in [0, 8, 16]:
			for r in [0, 3, 16]:
				var expected := ColorGrade.grade(
					Color(r / 16.0, g / 16.0, b / 16.0), ColorGrade.DEFAULT
				)
				var actual := slices[b].get_pixel(r, g)
				var ok := (
					absf(actual.r - expected.r) <= 1.5 / 255.0
					and absf(actual.g - expected.g) <= 1.5 / 255.0
					and absf(actual.b - expected.b) <= 1.5 / 255.0
				)
				assert_true(ok, "texel (%d,%d,%d) %s != %s" % [r, g, b, actual, expected])


func test_deterministic() -> void:
	var c := Color(0.3, 0.6, 0.2)
	assert_eq(ColorGrade.grade(c, ColorGrade.DEFAULT), ColorGrade.grade(c, ColorGrade.DEFAULT))
	var a := ColorGrade.lut(5, ColorGrade.DEFAULT)
	var b := ColorGrade.lut(5, ColorGrade.DEFAULT)
	assert_eq(a[2].get_data(), b[2].get_data())


func test_cached_texture_is_3d_and_shared() -> void:
	var t1 := ColorGrade.cached_texture()
	assert_true(t1 is ImageTexture3D)
	assert_true(t1 == ColorGrade.cached_texture())


func test_apply_to_environment() -> void:
	var env := Environment.new()
	ColorGrade.apply_to(env)
	assert_true(env.adjustment_enabled)
	assert_true(env.adjustment_color_correction is Texture3D)
