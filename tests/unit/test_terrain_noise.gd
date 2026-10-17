extends TestCase


func test_hash_at_origin_is_zero() -> void:
	assert_eq(TerrainNoise.hash(0.0, 0.0, 0.0), 0.0)


func test_hash_of_integer_triples_is_in_unit_interval() -> void:
	for x in range(-5, 5):
		for y in range(-5, 5):
			for s in range(0, 10):
				var h := TerrainNoise.hash(x, y, s)
				assert_true(h >= 0.0 and h < 1.0, "hash(%d, %d, %d) = %f" % [x, y, s, h])


func test_value_noise_at_lattice_point_equals_hash() -> void:
	assert_eq(TerrainNoise.value_noise(3.0, 5.0, 1.0), TerrainNoise.hash(3.0, 5.0, 1.0))


func test_fbm_samples_are_in_unit_interval() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 500:
		var x := rng.randf_range(-1000.0, 1000.0)
		var y := rng.randf_range(-1000.0, 1000.0)
		var n := TerrainNoise.fbm(x, y, float(i % 20))
		assert_true(n >= 0.0 and n <= 1.0, "fbm(%f, %f) = %f" % [x, y, n])


func test_ridged_samples_are_in_unit_interval() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for i in 200:
		var n := TerrainNoise.ridged(
			rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0), 21.0
		)
		assert_true(n >= 0.0 and n <= 1.0, "ridged = %f" % n)


func test_smooth() -> void:
	assert_eq(TerrainNoise.smooth(0.0, 1.0, 0.5), 0.5)
	assert_eq(TerrainNoise.smooth(0.0, 1.0, -1.0), 0.0)
	assert_eq(TerrainNoise.smooth(0.0, 1.0, 2.0), 1.0)
	assert_eq(TerrainNoise.smooth(1.0, 0.0, 0.25), 0.84375)
