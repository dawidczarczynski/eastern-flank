class_name TerrainTextures
extends RefCounted
## The seven CC0 ground layers of the terrain shader (TASK-055, credits in
## assets/third_party/credits.json), packed into two Texture2DArrays with one layer each, in
## TerrainSplat order: `albedo_height` (RGB albedo, height in alpha) and `normal_rough_ao` (RG the
## x, y of the OpenGL normal map – the shader rebuilds z –, B roughness, A ambient occlusion; one
## array instead of two, so a ground sample costs two texture fetches, not three). Packing decodes
## and merges 35 images, so `request(size)` starts it on the WorkerThreadPool (MapView calls it
## before building the terrain mesh, which hides the cost) and `arrays(size)` waits for it and
## caches the result per size for the rest of the run. The packed images are also kept on disk
## (`cache_dir`, one file per size, keyed by the source files' modification times and the look's
## layer tints), so only the first run after a texture change pays for the packing: later runs
## read the file on a worker thread.
## Usage: TerrainTextures.request(1024); ...; var maps := TerrainTextures.arrays(1024)

const ROOT := "res://assets/third_party/textures/ground/"
## Folder per layer, in TerrainSplat layer order.
const LAYERS: Array[String] = ["grass", "dry_grass", "dirt", "mud", "gravel", "rock", "soil"]
## Real-world size of one texture repeat in metres (from the sources, see credits.json).
const SOURCE_METRES: Array[float] = [1.4, 2.0, 2.0, 1.3, 2.0, 1.5, 3.0]

## The maps of a layer folder (`<name>.jpg`).
const SOURCE_MAPS: Array[String] = ["albedo", "height", "normal_gl", "roughness", "ao"]
## The packed arrays, in cache file order, with their image formats.
const PACKED_MAPS: Array[String] = ["albedo_height", "normal_rough_ao"]
const PACKED_FORMATS: Array[Image.Format] = [Image.FORMAT_RGBA8, Image.FORMAT_RGBA8]
## Bump when the packing changes, so older cache files are packed again.
const CACHE_VERSION := 2

## Folder of the packed-image cache; "" switches the cache off (the tests).
static var cache_dir := "user://cache"
## "cache" or "packed": where the last arrays() that built a size got its images (tests).
static var last_source := ""
## size -> {"albedo_height", "normal_rough_ao": Texture2DArray, "average_colors"}
static var _cache: Dictionary = {}
## size -> _Job still running
static var _jobs: Dictionary = {}


## Starts packing the layers at `size` x `size` texels (power of two, at most the 1024 source)
## in the background; does nothing if they are cached or already being packed.
static func request(size: int) -> void:
	if _cache.has(size) or _jobs.has(size):
		return
	var job := _Job.new(size)
	job.key = cache_key(size)
	if job.key != "" and _stored_key(size) == job.key:
		job.reading = true
		job.task_id = WorkerThreadPool.add_task(job.read_cache.bind(cache_path(size)))
	else:
		job.task_id = WorkerThreadPool.add_group_task(job.pack_layer, LAYERS.size())
	_jobs[size] = job


static func cache_path(size: int) -> String:
	return cache_dir.path_join("terrain_textures_%d.bin" % size)


## What the cache file of `size` must have been packed from: the cache version, the look's layer
## tints (the average colours carry them) and every source file's modification time. "" when
## there is no cache: switched off, or the source files are not on disk (an exported build).
static func cache_key(size: int) -> String:
	if cache_dir == "":
		return ""
	var parts: Array = [CACHE_VERSION, size, LookPreset.layer_tints(TerrainGround.LAYER_TINTS)]
	for layer: String in LAYERS:
		for map_name: String in SOURCE_MAPS:
			var path := ROOT + layer + "/" + map_name + ".jpg"
			if not FileAccess.file_exists(path):
				return ""
			parts.append(FileAccess.get_modified_time(path))
	return str(parts).sha256_text()


## The key stored in the cache file of `size` ("" without a file).
static func _stored_key(size: int) -> String:
	var file := FileAccess.open(cache_path(size), FileAccess.READ)
	return file.get_pascal_string() if file != null else ""


## The two arrays at `size` (waits for request(size), or packs them now).
static func arrays(size: int) -> Dictionary:
	if _cache.has(size):
		return _cache[size]
	request(size)
	var job: _Job = _jobs[size]
	if job.reading:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		if job.failed:  # a damaged cache file: pack after all
			job.reading = false
			job.task_id = WorkerThreadPool.add_group_task(job.pack_layer, LAYERS.size())
	if not job.reading:
		WorkerThreadPool.wait_for_group_task_completion(job.task_id)
		if job.key != "":
			job.write_cache(cache_path(size))
	last_source = "cache" if job.reading else "packed"
	_jobs.erase(size)
	var result := {"average_colors": job.averages}
	for key: String in PACKED_MAPS:
		var images: Array[Image] = []
		for layer in LAYERS.size():
			images.append(job.images[layer][key])
		var array := Texture2DArray.new()
		array.create_from_images(images)
		result[key] = array
	_cache[size] = result
	return result


## Decodes one map of a layer at `size` in `format`: from the source file when it is present
## (the project run from the repository), else from the imported texture (exported builds; that
## path is unverified – no export exists yet). A map that fails to load is reported with
## push_error and replaced by a neutral image, so arrays() never gets a missing layer.
static func _load_map(layer: int, map_name: String, size: int, format: Image.Format) -> Image:
	var path := ROOT + LAYERS[layer] + "/" + map_name + ".jpg"
	var image: Image = null
	if FileAccess.file_exists(path):
		image = Image.new()
		if image.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			image = null
	elif ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		image = texture.get_image() if texture != null else null
		if image != null and image.is_compressed():
			image.decompress()
	if image == null or image.is_empty():
		push_error("TerrainTextures: cannot load %s, using a neutral fallback" % path)
		return _fallback_map(map_name, size, format)
	# Box-filter halving keeps the texture crisp without aliasing.
	while image.get_width() > size:
		image.shrink_x2()
	if image.get_width() != size or image.get_height() != size:
		image.resize(size, size, Image.INTERPOLATE_BILINEAR)
	image.convert(format)
	return image


## Mean linear albedo of `albedo` times the layer's shader tint; used to colour things that
## should match the ground (grass clumps).
static func _average_color(albedo: Image, layer: int) -> Color:
	var small := albedo.duplicate() as Image
	while small.get_width() > 16:
		small.shrink_x2()
	var sum := Vector3.ZERO
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y).srgb_to_linear()
			sum += Vector3(c.r, c.g, c.b)
	sum /= float(small.get_width() * small.get_height())
	var tint := LookPreset.layer_tints(TerrainGround.LAYER_TINTS)[layer]
	return Color(sum.x * tint.x, sum.y * tint.y, sum.z * tint.z)


## Neutral stand-in for a missing map: mid-grey albedo / height / roughness, flat normal, no AO.
static func _fallback_map(map_name: String, size: int, format: Image.Format) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	match map_name:
		"normal_gl":
			image.fill(Color(0.5, 0.5, 1.0))
		"ao":
			image.fill(Color.WHITE)
		_:
			image.fill(Color(0.5, 0.5, 0.5))
	image.convert(format)
	return image


## Packs the images of each layer on a worker thread; every call writes only its own slot.
class _Job:
	extends RefCounted
	var size: int
	var task_id := -1
	## TerrainTextures.cache_key of the job ("" = no cache); `reading`: the task reads the cache
	## file instead of packing, `failed`: it could not.
	var key := ""
	var reading := false
	var failed := false
	## Per layer: {"albedo_height", "normal_rough_ao": Image}
	var images: Array = []
	## Per layer: the mean albedo (linear) times TerrainGround.LAYER_TINTS (what the shader shows).
	var averages: Array[Color] = []
	var _mutex := Mutex.new()

	func _init(texture_size: int) -> void:
		size = texture_size
		images.resize(TerrainTextures.LAYERS.size())
		averages.resize(TerrainTextures.LAYERS.size())

	func pack_layer(layer: int) -> void:
		var albedo := TerrainTextures._load_map(layer, "albedo", size, Image.FORMAT_RGBA8)
		var height := TerrainTextures._load_map(layer, "height", size, Image.FORMAT_L8)
		var average := TerrainTextures._average_color(albedo, layer)
		var data := albedo.get_data()
		var heights := height.get_data()
		for i in heights.size():
			data[i * 4 + 3] = heights[i]
		var albedo_height := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
		albedo_height.generate_mipmaps()
		# The normal's mipmaps are renormalised, those of roughness / AO plain averages: build
		# both chains, then put roughness and AO into the normal's blue and alpha.
		var normal := TerrainTextures._load_map(layer, "normal_gl", size, Image.FORMAT_RGBA8)
		normal.generate_mipmaps(true)
		var rough := TerrainTextures._load_map(layer, "roughness", size, Image.FORMAT_L8)
		rough.generate_mipmaps()
		var ao := TerrainTextures._load_map(layer, "ao", size, Image.FORMAT_L8)
		ao.generate_mipmaps()
		var packed := normal.get_data()
		var rough_data := rough.get_data()
		var ao_data := ao.get_data()
		for i in rough_data.size():
			packed[i * 4 + 2] = rough_data[i]
			packed[i * 4 + 3] = ao_data[i]
		var normal_rough_ao := Image.create_from_data(size, size, true, Image.FORMAT_RGBA8, packed)
		_mutex.lock()
		averages[layer] = average
		images[layer] = {"albedo_height": albedo_height, "normal_rough_ao": normal_rough_ao}
		_mutex.unlock()

	## Reads the images and averages write_cache() stored (runs on a worker thread).
	func read_cache(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_pascal_string() != key:
			failed = true
			return
		for layer in images.size():
			var color := Color()
			for channel in 4:
				color[channel] = file.get_float()
			averages[layer] = color
			var maps := {}
			for m in TerrainTextures.PACKED_MAPS.size():
				var data := file.get_buffer(file.get_64())
				var probe := Image.create_empty(size, size, true, TerrainTextures.PACKED_FORMATS[m])
				if data.size() != probe.get_data().size():
					failed = true
					return
				maps[TerrainTextures.PACKED_MAPS[m]] = Image.create_from_data(
					size, size, true, TerrainTextures.PACKED_FORMATS[m], data
				)
			images[layer] = maps
		failed = file.get_error() != OK

	## Stores the packed images (mipmaps included) and averages under `key`; a temp file renamed
	## over the old one, so a crash never leaves half a cache.
	func write_cache(path: String) -> void:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			return
		file.store_pascal_string(key)
		for layer in images.size():
			for channel in 4:
				file.store_float(averages[layer][channel])
			for map_name: String in TerrainTextures.PACKED_MAPS:
				var data: PackedByteArray = (images[layer][map_name] as Image).get_data()
				file.store_64(data.size())
				file.store_buffer(data)
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
