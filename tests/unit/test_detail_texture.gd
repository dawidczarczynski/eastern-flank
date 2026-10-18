extends TestCase

const SIZE := 64


func _max_step(h: PackedFloat32Array, size: int) -> float:
	var m := 0.0
	for y in size:
		for x in size - 1:
			m = maxf(m, absf(h[y * size + x + 1] - h[y * size + x]))
	for x in size:
		for y in size - 1:
			m = maxf(m, absf(h[(y + 1) * size + x] - h[y * size + x]))
	return m


func test_height_map_is_deterministic_and_seed_dependent() -> void:
	var a := DetailTexture.height_map(SIZE, [4, 8] as Array[int], 1)
	var b := DetailTexture.height_map(SIZE, [4, 8] as Array[int], 1)
	var c := DetailTexture.height_map(SIZE, [4, 8] as Array[int], 2)
	assert_eq(a.size(), SIZE * SIZE)
	assert_true(a == b, "same seed must give the same map")
	assert_true(a != c, "another seed must differ")


func test_height_map_values_in_unit_range() -> void:
	for v in DetailTexture.height_map(SIZE, [4, 8] as Array[int], 1):
		assert_true(v >= 0.0 and v <= 1.0, "value %f out of range" % v)


func test_height_map_is_seamless() -> void:
	var h := DetailTexture.height_map(SIZE, [4, 8] as Array[int], 1)
	var limit := _max_step(h, SIZE)
	for i in SIZE:
		assert_true(
			absf(h[i * SIZE] - h[i * SIZE + SIZE - 1]) <= limit + 1e-6, "row %d wrap too big" % i
		)
		assert_true(
			absf(h[i] - h[(SIZE - 1) * SIZE + i]) <= limit + 1e-6, "column %d wrap too big" % i
		)


func test_normal_of_flat_map_points_straight_up() -> void:
	var flat := PackedFloat32Array()
	flat.resize(16 * 16)
	flat.fill(0.4)
	var img := DetailTexture.normal_image(flat, 16, 7.0)
	for y in 16:
		for x in 16:
			var c := img.get_pixel(x, y)
			assert_true(absf(c.r - 0.5) <= 1.0 / 255.0 + 1e-4, "r %f" % c.r)
			assert_true(absf(c.g - 0.5) <= 1.0 / 255.0 + 1e-4, "g %f" % c.g)
			assert_true(absf(c.b - 1.0) <= 1.0 / 255.0 + 1e-4, "b %f" % c.b)


## Normal maps are OpenGL style (red = +x, green = up the image, i.e. towards row 0).
## A surface rising in +x tilts its normal towards -x (red < 0.5); one rising towards
## higher rows (down the image) tilts it up the image (green > 0.5).
func test_normal_sign_convention() -> void:
	var ramp_x := PackedFloat32Array()
	ramp_x.resize(16 * 16)
	var ramp_y := PackedFloat32Array()
	ramp_y.resize(16 * 16)
	for y in 16:
		for x in 16:
			ramp_x[y * 16 + x] = x * 0.01
			ramp_y[y * 16 + x] = y * 0.01
	var nx := DetailTexture.normal_image(ramp_x, 16, 7.0)
	var ny := DetailTexture.normal_image(ramp_y, 16, 7.0)
	for i in range(1, 15):
		assert_true(nx.get_pixel(i, 8).r < 0.5, "x ramp must give red < 0.5")
		assert_true(ny.get_pixel(8, i).g > 0.5, "y ramp must give green > 0.5")


func test_albedo_range() -> void:
	var h := DetailTexture.height_map(SIZE, [4, 8] as Array[int], 1)
	var img := DetailTexture.albedo_image(h, SIZE)
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			assert_true(c.r >= 0.73 - 1.0 / 255.0 and c.r <= 1.0, "albedo %f" % c.r)
			assert_true(c.b <= c.r + 1e-4 and c.b >= 0.7, "blue slightly below red")
