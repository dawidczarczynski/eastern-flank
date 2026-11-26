class_name NearHeightCache
extends RefCounted
## The drawn near-terrain heights around the camera target as a texture (TASK-217a; the option of
## ADR 0027 decision 2): GPU-placed plants close to the camera stand on the ground as it is drawn
## (TerrainNear's 4.5 m mesh) instead of on the 36 m lattice, which lies up to a few metres lower or
## higher in hilly ground and buried or floated the shrubs. No extra surface queries: a built near
## chunk's own vertex heights are copied into an RF window of WINDOW_CHUNKS x WINDOW_CHUNKS near
## chunks around the camera target; texels of chunks that are not built hold MISSING, where the
## shaders fall back to the lattice (which is what is drawn there). The window is re-blitted and
## uploaded at most once a frame, only when a near chunk changed or the target left its centre.
## Placement decisions (which cell holds a plant) never read it: only the drawn base height.

const WINDOW_CHUNKS := 12
## Texel value of a chunk that is not built (the lattice is drawn there).
const MISSING := -1.0e6

var _near: TerrainNear
var _lattice_origin := Vector2.ZERO
## Vector2i near chunk -> PackedFloat32Array vertex heights ((CELLS + 1)^2).
var _heights: Dictionary = {}
var _image: Image
var _texture: ImageTexture
var _origin_chunk := Vector2i.ZERO
var _dirty := true
var _side := WINDOW_CHUNKS * TerrainNear.CELLS + 1
var _materials: Array[ShaderMaterial] = []


## Follows `layer` (the "terrain_near" ChunkLayer of `near`): its build and free callables are
## wrapped so every change of the drawn near mesh reaches the cache.
func _init(near: TerrainNear, layer: ChunkLayer, lattice_origin: Vector2) -> void:
	_near = near
	_lattice_origin = lattice_origin
	_image = Image.create(_side, _side, false, Image.FORMAT_RF)
	_image.fill(Color(MISSING, 0.0, 0.0))
	_texture = ImageTexture.create_from_image(_image)
	var build := layer.build_chunk
	var drop := layer.free_chunk
	layer.build_chunk = func(chunk: Vector2i, plan: Variant) -> void:
		build.call(chunk, plan)
		_changed(chunk)
	layer.free_chunk = func(chunk: Vector2i) -> void:
		drop.call(chunk)
		_changed(chunk)
	for chunk in near.built_chunks():
		_changed(chunk)


## A near chunk was built or freed: its heights and its neighbours' (their shared edges switch
## between the surface and the lattice) are read again.
func _changed(chunk: Vector2i) -> void:
	var touched: Array[Vector2i] = [chunk]
	for n in TerrainNear.NEIGHBOURS:
		touched.append(chunk + n)
	for c in touched:
		var heights := _near.chunk_heights(c)
		if heights.is_empty():
			_heights.erase(c)
		else:
			_heights[c] = heights
	_dirty = true


## Binds the window to `material` (now and on every later upload): near_heights, near_origin,
## near_step, use_near.
func bind(material: ShaderMaterial) -> void:
	_materials.append(material)
	material.set_shader_parameter(&"near_heights", _texture)
	material.set_shader_parameter(&"near_step", TerrainNear.STEP)
	material.set_shader_parameter(&"use_near", true)
	material.set_shader_parameter(&"near_origin", origin())


## Recentres the window on `target` (world XZ) if it moved off the centre chunk's neighbourhood,
## re-blits and uploads it when anything changed. Main thread, once a frame.
func update(target: Vector2) -> void:
	var centre := Vector2i(((target - _lattice_origin) / TerrainNear.CHUNK_SIZE).floor())
	var wanted := centre - Vector2i.ONE * (WINDOW_CHUNKS / 2)
	if (wanted - _origin_chunk).abs().x > 1 or (wanted - _origin_chunk).abs().y > 1:
		_origin_chunk = wanted
		_dirty = true
	if not _dirty:
		return
	_dirty = false
	_image.fill(Color(MISSING, 0.0, 0.0))
	var n := TerrainNear.CELLS + 1
	for chunk: Vector2i in _heights:
		var at := (chunk - _origin_chunk) * TerrainNear.CELLS
		if at.x < 0 or at.y < 0 or at.x + n > _side or at.y + n > _side:
			continue
		var heights: PackedFloat32Array = _heights[chunk]
		var block := Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
		_image.blit_rect(block, Rect2i(0, 0, n, n), at)
	_texture.update(_image)
	for material in _materials:
		material.set_shader_parameter(&"near_origin", origin())


## World XZ of the window's first texel.
func origin() -> Vector2:
	return _lattice_origin + Vector2(_origin_chunk) * TerrainNear.CHUNK_SIZE


## The drawn near height at (x, z) as the shaders read it (the window's triangles), NAN where the
## window has no near chunk. Tests.
func height_at(x: float, z: float) -> float:
	var f := (Vector2(x, z) - origin()) / TerrainNear.STEP
	var i := floori(f.x)
	var j := floori(f.y)
	if i < 0 or j < 0 or i + 1 >= _side or j + 1 >= _side:
		return NAN
	var ha := _image.get_pixel(i, j).r
	var hb := _image.get_pixel(i + 1, j).r
	var hc := _image.get_pixel(i, j + 1).r
	var hd := _image.get_pixel(i + 1, j + 1).r
	if minf(minf(ha, hb), minf(hc, hd)) <= MISSING * 0.5:
		return NAN
	var u := f.x - i
	var v := f.y - j
	if u + v <= 1.0:
		return ha + u * (hb - ha) + v * (hc - ha)
	return hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd)
