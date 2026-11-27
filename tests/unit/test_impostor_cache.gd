extends TestCase
## The impostor atlas disk cache (TASK-222): a round trip returns the same pixels, another key, size
## or a damaged file is a miss (the caller then bakes), and the key follows the look.

const PATH := "user://test_impostor_cache.cache"


func after_each() -> void:
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute("%s.%d.tmp" % [PATH, OS.get_process_id()])


func _image(seed_value: int) -> Image:
	var image := Image.create(24, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 24:
			image.set_pixel(
				x, y, Color8((x * 9 + seed_value) % 256, y * 15, (x * y) % 256, 255 - x)
			)
	return image


func test_round_trip_returns_identical_images() -> void:
	var atlas := _image(3)
	var normals := _image(77)
	TreeImpostors._write_cache(PATH, "key", atlas, normals)
	var read := TreeImpostors._read_cache(PATH, "key", Vector2i(24, 16))
	assert_eq(read.size(), 2)
	assert_eq(read[0].get_data(), atlas.get_data())
	assert_eq(read[1].get_data(), normals.get_data())
	assert_false(
		FileAccess.file_exists("%s.%d.tmp" % [PATH, OS.get_process_id()]), "no temp file is left"
	)


func test_another_key_or_size_is_a_miss() -> void:
	TreeImpostors._write_cache(PATH, "key", _image(1), _image(2))
	assert_eq(TreeImpostors._read_cache(PATH, "other", Vector2i(24, 16)).size(), 0)
	assert_eq(TreeImpostors._read_cache(PATH, "key", Vector2i(24, 17)).size(), 0)


func test_missing_or_truncated_file_is_a_miss() -> void:
	assert_eq(TreeImpostors._read_cache(PATH, "key", Vector2i(24, 16)).size(), 0)
	TreeImpostors._write_cache(PATH, "key", _image(1), _image(2))
	var bytes := FileAccess.get_file_as_bytes(PATH)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_buffer(bytes.slice(0, bytes.size() / 2))
	file.close()
	assert_eq(TreeImpostors._read_cache(PATH, "key", Vector2i(24, 16)).size(), 0)


func test_key_follows_the_look_and_is_stable() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var key := TreeImpostors._cache_key("look a")
	assert_eq(TreeImpostors._cache_key("look a"), key)
	assert_true(TreeImpostors._cache_key("look b") != key)
	VisualScale.reset()
	MapScale.reset()


func test_fresh_bake_equals_cached_bake_where_rendering_works() -> void:
	if not TreeImpostors._can_render():
		return
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var size := Vector2i(
		TreeImpostors.CELL.x * TreeImpostors.VIEWS,
		TreeImpostors.CELL.y * TreeImpostors.SPECIES.size() * TreeMeshes.VARIANTS
	)
	var fresh := TreeImpostors._bake_atlas(TreeImpostors.SPECIES.size() * TreeMeshes.VARIANTS, size)
	TreeImpostors._write_cache(PATH, "k", fresh[0], fresh[1])
	var read := TreeImpostors._read_cache(PATH, "k", size)
	assert_eq(read[0].get_data(), (fresh[0] as Image).get_data())
	assert_eq(read[1].get_data(), (fresh[1] as Image).get_data())
	VisualScale.reset()
	MapScale.reset()
