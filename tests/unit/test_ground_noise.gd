extends TestCase
## GroundNoise: the macro and jitter noises of the terrain look.


func test_macro_k_is_deterministic_and_in_unit_range() -> void:
	for i in 20:
		var m := GroundNoise.macro_k(i * 1.7, i * 0.9)
		assert_eq(m, GroundNoise.macro_k(i * 1.7, i * 0.9))
		assert_true(m >= 0.0 and m <= 1.0)


func test_jitter_is_deterministic_and_bounded() -> void:
	var j := GroundNoise.jitter(1.3, -2.7)
	assert_eq(j, GroundNoise.jitter(1.3, -2.7))
	assert_true(absf(j.x - 1.3) <= 0.275 and absf(j.y + 2.7) <= 0.275, str(j))
