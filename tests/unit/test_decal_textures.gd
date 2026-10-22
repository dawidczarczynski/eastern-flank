extends TestCase

const SIZE := 64


func _images() -> Dictionary:
	return {
		"tread": DecalTextures.tread(SIZE),
		"tyre": DecalTextures.tyre(SIZE),
		"crater": DecalTextures.crater(SIZE),
		"scorch": DecalTextures.scorch(SIZE),
	}


func test_size_and_transparent_border() -> void:
	var images := _images()
	for key: String in images:
		var image: Image = images[key]
		assert_eq(image.get_width(), SIZE, key)
		assert_eq(image.get_height(), SIZE, key)
		for i in SIZE:
			for p in [Vector2i(i, 0), Vector2i(i, SIZE - 1), Vector2i(0, i), Vector2i(SIZE - 1, i)]:
				assert_eq(image.get_pixelv(p).a, 0.0, "%s border %s" % [key, p])


func test_textures_have_visible_content() -> void:
	var images := _images()
	for key: String in images:
		var opaque := 0
		var image: Image = images[key]
		for y in SIZE:
			for x in SIZE:
				if image.get_pixel(x, y).a > 0.3:
					opaque += 1
		assert_true(opaque > SIZE, "%s has content" % key)


func test_cached_and_deterministic() -> void:
	var first := DecalTextures.tread(SIZE)
	assert_true(first == DecalTextures.tread(SIZE), "same cached image")
	# A fresh paint gives the same pixels as the cached one.
	var fresh := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fresh.fill(Color(0, 0, 0, 0))
	DecalTextures._paint_crater(fresh, SIZE)
	var cached := DecalTextures.crater(SIZE)
	for p in [Vector2i(32, 32), Vector2i(10, 20), Vector2i(45, 50), Vector2i(5, 5)]:
		assert_true(fresh.get_pixelv(p).is_equal_approx(cached.get_pixelv(p)), "pixel %s" % p)


func test_revealed_cuts_the_alpha_beyond_the_cut_only() -> void:
	var base := DecalTextures.tread(64)
	var cut := DecalTextures.revealed(base, 0.5)
	assert_eq(cut.get_width(), 64)
	for y in 64:
		assert_eq(cut.get_pixel(40, y).a, 0.0, "beyond the cut")
		assert_eq(cut.get_pixel(10, y), base.get_pixel(10, y), "before the cut: same pattern")
	assert_eq(DecalTextures.revealed(base, 1.0).get_pixel(60, 16), base.get_pixel(60, 16))
