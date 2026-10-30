class_name SalvoTrail
extends MeshInstance3D
## One rocket's smoke trail (TASK-075): a thin camera-facing ribbon through the points the rocket
## passed while its motor burned (assets/shaders/salvo_trail.gdshader widens, thins, lifts and
## drifts each point as it ages). Owned by SalvoFxPool and reused round-robin, so it outlives the
## volley and fades by itself. Its own clock runs in real time (process_mode ALWAYS).

const LIFE := 4.5
const MAX_POINTS := 160
const WIDTH_START := 0.022
const WIDTH_END := 0.32
const COLOR := Color(0.25, 0.24, 0.23, 0.8)
const SHADER := preload("res://assets/shaders/salvo_trail.gdshader")

static var _material: ShaderMaterial

## Points laid so far (tests, debugging).
var point_count := 0

var _points := PackedVector3Array()
var _births := PackedFloat32Array()
var _head := Vector3.ZERO
var _growing := false
var _clock := 0.0
var _mesh := ArrayMesh.new()


## `bounds`: the culling box (the vertex shader moves the ribbon, so it is set by hand).
func _init(bounds: AABB) -> void:
	name = "Trail"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mesh = _mesh
	material_override = shared_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = bounds
	visible = false


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("life", LIFE)
		_material.set_shader_parameter("width_start", WIDTH_START)
		_material.set_shader_parameter("width_end", WIDTH_END)
		_material.set_shader_parameter("color", COLOR)
		var dir := Wind.DIRECTION.normalized()
		_material.set_shader_parameter("wind", Vector3(dir.x, 0.0, dir.y) * Wind.STRENGTH * 0.12)
		_material.set_shader_parameter("noise", _noise_texture())
	return _material


## Starts a new trail at `at` (the tube mouth), dropping whatever this ribbon showed before.
func start(at: Vector3) -> void:
	_points.clear()
	_births.clear()
	point_count = 0
	_clock = 0.0
	_growing = true
	_head = at
	_add(at)
	visible = true
	_rebuild()


## Lays `points` (from SalvoFxPool.trail_points) and moves the trail's head to `head` (the
## rocket's tail now), while the motor burns.
func extend(points: Array[Vector3], head: Vector3) -> void:
	if not _growing:
		return
	for point in points:
		_add(point)
	_head = head
	_rebuild()


## The motor burnt out: the trail ends at its head and only fades from now on.
func stop() -> void:
	if not _growing:
		return
	_growing = false
	if _points.size() > 0 and _points[_points.size() - 1].distance_to(_head) > 0.001:
		_add(_head)
	_rebuild()


## True while the trail grows or any of it is still visible.
func is_active() -> bool:
	return _growing or (visible and _clock - _last_birth() < LIFE)


## Seconds since the trail started (its own clock).
func age() -> float:
	return _clock


func _process(delta: float) -> void:
	if not visible:
		return
	advance(delta)


## Moves the trail's clock on by `delta` seconds; hides the ribbon once its last point has faded.
func advance(delta: float) -> void:
	_clock += delta
	set_instance_shader_parameter("now", _clock)
	if not _growing and _clock - _last_birth() >= LIFE:
		visible = false


func _last_birth() -> float:
	return _births[_births.size() - 1] if _births.size() > 0 else -INF


func _add(point: Vector3) -> void:
	if _points.size() >= MAX_POINTS:
		return
	_points.append(point)
	_births.append(_clock)
	point_count += 1


## Two vertices per point (and one pair for the moving head): the ribbon's centre line, its
## direction in NORMAL, the side and distance along in UV, the birth time in UV2.
func _rebuild() -> void:
	_mesh.clear_surfaces()
	var line := _points.duplicate()
	var births := _births.duplicate()
	if _growing and line.size() > 0 and line[line.size() - 1].distance_to(_head) > 0.001:
		line.append(_head)
		births.append(_clock)
	var n := line.size()
	if n < 2:
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var along := 0.0
	for i in n:
		if i > 0:
			along += line[i].distance_to(line[i - 1])
		var tangent := (line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)]).normalized()
		if tangent == Vector3.ZERO:
			tangent = Vector3.UP
		for side in [-1.0, 1.0]:
			vertices.append(line[i])
			normals.append(tangent)
			uvs.append(Vector2(side, along))
			uv2s.append(Vector2(births[i], 0.0))
		if i > 0:
			var k := (i - 1) * 2
			indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Tileable noise that breaks the ribbon into wisps.
static func _noise_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 7501
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var image := noise.get_seamless_image(128, 64)
	image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
