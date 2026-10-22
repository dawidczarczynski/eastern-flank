extends TestCase

const SIZE := 64


func _check(image: Image, label: String) -> void:
	assert_eq(image.get_format(), Image.FORMAT_RGBA8, label)
	assert_true(image.has_mipmaps(), "%s mipmaps" % label)
	for y in SIZE:
		for x in SIZE:
			var c := image.get_pixel(x, y)
			if c.a != 0.0 and c.a != 1.0:
				_fail("%s alpha %f" % [label, c.a])
				return
			if c.a == 1.0 and (absf(c.r - c.g) > 0.01 or absf(c.g - c.b) > 0.01):
				_fail("%s not neutral grey" % label)
				return
	var coverage := LeafTexture.coverage(image)
	assert_true(coverage >= 0.35 and coverage <= 0.75, "%s coverage %.3f" % [label, coverage])


func test_cluster() -> void:
	for seed_value in [1, 2, 3]:
		_check(LeafTexture.cluster(SIZE, seed_value), "cluster %d" % seed_value)


func test_needles() -> void:
	for seed_value in [1, 2, 3]:
		_check(LeafTexture.needles(SIZE, seed_value), "needles %d" % seed_value)


func test_deterministic_per_seed() -> void:
	var cluster := LeafTexture.cluster(SIZE, 4).get_data()
	assert_true(cluster == LeafTexture.cluster(SIZE, 4).get_data())
	var needles := LeafTexture.needles(SIZE, 4).get_data()
	assert_true(needles == LeafTexture.needles(SIZE, 4).get_data())
	assert_true(cluster != LeafTexture.cluster(SIZE, 5).get_data())
