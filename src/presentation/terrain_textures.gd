class_name TerrainTextures
extends RefCounted
## The six CC0 ground layers of the terrain shader (TASK-055, credits in
## assets/third_party/credits.json), packed into three Texture2DArrays with one layer each, in
## TerrainSplat order: `albedo_height` (RGB albedo, height in alpha), `normal` (OpenGL normal
## map) and `roughness_ao` (R roughness, G ambient occlusion). Packing decodes and merges
## 30 images, so `request(size)` starts it on the WorkerThreadPool (MapView calls it before
## building the terrain mesh, which hides the cost) and `arrays(size)` waits for it and caches
## the result per size for the rest of the run.
## Usage: TerrainTextures.request(1024); ...; var maps := TerrainTextures.arrays(1024)

const ROOT := "res://assets/third_party/textures/ground/"
## Folder per layer, in TerrainSplat layer order.
const LAYERS: Array[String] = ["grass", "dry_grass", "dirt", "mud", "gravel", "rock"]
## Real-world size of one texture repeat in metres (from the sources, see credits.json).
const SOURCE_METRES: Array[float] = [1.4, 2.0, 2.0, 1.3, 2.0, 1.5]

## size -> {"albedo_height", "normal", "roughness_ao": Texture2DArray}
static var _cache: Dictionary = {}
## size -> _Job still running
static var _jobs: Dictionary = {}


## Starts packing the layers at `size` x `size` texels (power of two, at most the 1024 source)
## in the background; does nothing if they are cached or already being packed.
static func request(size: int) -> void:
	if _cache.has(size) or _jobs.has(size):
		return
	var job := _Job.new(size)
	job.task_id = WorkerThreadPool.add_group_task(job.pack_layer, LAYERS.size())
	_jobs[size] = job


## The three arrays at `size` (waits for request(size), or packs them now).
static func arrays(size: int) -> Dictionary:
	if _cache.has(size):
		return _cache[size]
	request(size)
	var job: _Job = _jobs[size]
	WorkerThreadPool.wait_for_group_task_completion(job.task_id)
	_jobs.erase(size)
	var result := {}
	for key: String in ["albedo_height", "normal", "roughness_ao"]:
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
	## Per layer: {"albedo_height", "normal", "roughness_ao": Image}
	var images: Array = []
	var _mutex := Mutex.new()

	func _init(texture_size: int) -> void:
		size = texture_size
		images.resize(TerrainTextures.LAYERS.size())

	func pack_layer(layer: int) -> void:
		var albedo := TerrainTextures._load_map(layer, "albedo", size, Image.FORMAT_RGBA8)
		var height := TerrainTextures._load_map(layer, "height", size, Image.FORMAT_L8)
		var data := albedo.get_data()
		var heights := height.get_data()
		for i in heights.size():
			data[i * 4 + 3] = heights[i]
		var albedo_height := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
		albedo_height.generate_mipmaps()
		var normal := TerrainTextures._load_map(layer, "normal_gl", size, Image.FORMAT_RGBA8)
		normal.generate_mipmaps(true)
		var rough := TerrainTextures._load_map(layer, "roughness", size, Image.FORMAT_L8).get_data()
		var ao := TerrainTextures._load_map(layer, "ao", size, Image.FORMAT_L8).get_data()
		var packed := PackedByteArray()
		packed.resize(rough.size() * 2)
		for i in rough.size():
			packed[i * 2] = rough[i]
			packed[i * 2 + 1] = ao[i]
		var roughness_ao := Image.create_from_data(size, size, false, Image.FORMAT_RG8, packed)
		roughness_ao.generate_mipmaps()
		_mutex.lock()
		images[layer] = {
			"albedo_height": albedo_height, "normal": normal, "roughness_ao": roughness_ao
		}
		_mutex.unlock()
