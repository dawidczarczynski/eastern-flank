extends TestCase
## TerrainTextures: fallback for maps that cannot be loaded (TASK-055), the disk cache of the
## packed images.

const CACHE_TEST_DIR := "user://test_terrain_texture_cache"
const CACHE_TEST_SIZE := 32


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


func _with_test_cache() -> void:
	TerrainTextures.cache_dir = CACHE_TEST_DIR
	TerrainTextures._cache.erase(CACHE_TEST_SIZE)
	DirAccess.remove_absolute(TerrainTextures.cache_path(CACHE_TEST_SIZE))


func _drop_test_cache() -> void:
	DirAccess.remove_absolute(TerrainTextures.cache_path(CACHE_TEST_SIZE))
	DirAccess.remove_absolute(CACHE_TEST_DIR)
	TerrainTextures._cache.erase(CACHE_TEST_SIZE)
	TerrainTextures.cache_dir = ""


## Packed image bytes of a job, layer by layer (the dummy renderer of the headless tests keeps
## no texture data, so the images are compared before they become Texture2DArrays).
func _job_bytes(job: TerrainTextures._Job) -> Array:
	var result: Array = []
	for maps: Dictionary in job.images:
		for key: String in TerrainTextures.PACKED_MAPS:
			var image: Image = maps[key]
			assert_true(image.has_mipmaps(), key)
			result.append(image.get_data())
	return result


func test_cache_file_round_trips_the_packed_images() -> void:
	_with_test_cache()
	var path := TerrainTextures.cache_path(CACHE_TEST_SIZE)
	var packed := TerrainTextures._Job.new(CACHE_TEST_SIZE)
	packed.key = "key"
	for layer in TerrainTextures.LAYERS.size():
		packed.pack_layer(layer)
	packed.write_cache(path)
	var read := TerrainTextures._Job.new(CACHE_TEST_SIZE)
	read.key = "key"
	read.read_cache(path)
	assert_false(read.failed)
	assert_eq(read.averages, packed.averages)
	assert_eq(_job_bytes(read), _job_bytes(packed))
	var other := TerrainTextures._Job.new(CACHE_TEST_SIZE)
	other.key = "another key"
	other.read_cache(path)
	assert_true(other.failed, "packed from other sources")
	_drop_test_cache()


## The second run reads the packed images from the cache file: same pixels, same averages.
func test_packed_images_come_back_from_the_disk_cache() -> void:
	_with_test_cache()
	var packed := TerrainTextures.arrays(CACHE_TEST_SIZE)
	assert_eq(TerrainTextures.last_source, "packed")
	assert_true(FileAccess.file_exists(TerrainTextures.cache_path(CACHE_TEST_SIZE)), "written")
	TerrainTextures._cache.erase(CACHE_TEST_SIZE)
	var cached := TerrainTextures.arrays(CACHE_TEST_SIZE)
	assert_eq(TerrainTextures.last_source, "cache")
	assert_eq(cached["average_colors"], packed["average_colors"])
	assert_eq(
		(cached["normal_rough_ao"] as Texture2DArray).get_layers(), TerrainTextures.LAYERS.size()
	)
	_drop_test_cache()


func test_a_cache_file_of_another_key_or_a_damaged_one_is_packed_again() -> void:
	_with_test_cache()
	var packed := TerrainTextures.arrays(CACHE_TEST_SIZE)
	var path := TerrainTextures.cache_path(CACHE_TEST_SIZE)
	# Another key (a source texture changed).
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_pascal_string("stale")
	file.close()
	TerrainTextures._cache.erase(CACHE_TEST_SIZE)
	TerrainTextures.arrays(CACHE_TEST_SIZE)
	assert_eq(TerrainTextures.last_source, "packed")
	# The right key but a cut-off body.
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_pascal_string(TerrainTextures.cache_key(CACHE_TEST_SIZE))
	file.store_float(0.5)
	file.close()
	TerrainTextures._cache.erase(CACHE_TEST_SIZE)
	var again := TerrainTextures.arrays(CACHE_TEST_SIZE)
	assert_eq(TerrainTextures.last_source, "packed")
	assert_eq(again["average_colors"], packed["average_colors"])
	_drop_test_cache()


func test_no_cache_key_when_the_cache_is_off() -> void:
	TerrainTextures.cache_dir = ""
	assert_eq(TerrainTextures.cache_key(CACHE_TEST_SIZE), "")


## One array carries the normal's x, y and roughness / AO: a ground sample is two fetches.
func test_normal_array_carries_roughness_in_blue_and_ao_in_alpha() -> void:
	var job := TerrainTextures._Job.new(CACHE_TEST_SIZE)
	job.pack_layer(0)
	var packed: Image = job.images[0]["normal_rough_ao"]
	assert_eq(packed.get_format(), Image.FORMAT_RGBA8)
	assert_true(packed.has_mipmaps(), "mipmaps")
	var normal := TerrainTextures._load_map(0, "normal_gl", CACHE_TEST_SIZE, Image.FORMAT_RGBA8)
	var rough := TerrainTextures._load_map(0, "roughness", CACHE_TEST_SIZE, Image.FORMAT_L8)
	var ao := TerrainTextures._load_map(0, "ao", CACHE_TEST_SIZE, Image.FORMAT_L8)
	var data := packed.get_data()
	var pixels := CACHE_TEST_SIZE * CACHE_TEST_SIZE
	for i: int in [0, pixels / 2 + 3, pixels - 1]:
		assert_eq(data[i * 4], normal.get_data()[i * 4], "normal x")
		assert_eq(data[i * 4 + 1], normal.get_data()[i * 4 + 1], "normal y")
		assert_eq(data[i * 4 + 2], rough.get_data()[i], "roughness")
		assert_eq(data[i * 4 + 3], ao.get_data()[i], "ambient occlusion")
