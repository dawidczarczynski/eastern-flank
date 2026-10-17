class_name UnitModels
extends RefCounted
## Unit miniatures built from primitives. Port of makeInf / soldier / makeTank in
## docs/design/game_screen.scene.js. Models face +X and stand on y = 0 of their root.
## Meshes and materials are created once and shared between all instances.

const MODEL_SCALE := 1.3
const SOLDIER_SCALE := 1.5
const INFANTRY := &"infantry"
const CAVALRY := &"cavalry"
## Indexed by owner id.
const BODY_COLORS: Array[Color] = [Color("#4f5934"), Color("#7a7354")]
const VEST_COLORS: Array[Color] = [Color("#3d4529"), Color("#5d5840")]
const SKIN := Color("#b98d6c")
const SOLDIER_DARK := Color("#1f201c")
const TANK_DARK := Color("#22231f")
const TANK_METAL := Color("#3c3e38")
## Squad layout: [x, z, kneeling].
const SQUAD: Array = [
	[0.13, 0.0, false],
	[-0.02, 0.15, true],
	[-0.03, -0.15, false],
	[-0.18, 0.06, false],
	[-0.15, -0.12, true],
]
const TURRET_OUTLINE: Array[Vector2] = [
	Vector2(-0.2, -0.15),
	Vector2(0.08, -0.165),
	Vector2(0.2, -0.07),
	Vector2(0.2, 0.07),
	Vector2(0.08, 0.165),
	Vector2(-0.2, 0.15),
	Vector2(-0.25, 0.1),
	Vector2(-0.25, -0.1),
]
const TURRET_DEPTH := 0.085

static var _meshes: Dictionary = {}  # key string -> Mesh
static var _materials: Dictionary = {}  # key string -> StandardMaterial3D


## Yaw of a model root: player 0 faces east (+X), player 1 faces west.
static func facing_yaw(owner_id: int) -> float:
	return 0.0 if owner_id == 0 else PI


static func build(definition_id: StringName, owner_id: int) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = facing_yaw(owner_id)
	var model: Node3D
	match definition_id:
		INFANTRY:
			model = _make_infantry(owner_id)
		CAVALRY:
			model = _make_tank(owner_id)
		_:
			push_warning("UnitModels: no model for '%s', using a placeholder box" % definition_id)
			model = Node3D.new()
			var size := Vector3(0.4, 0.4, 0.4)
			_add(model, _box_mesh(size), _material(Color.MAGENTA, 0.8, 0.0), Vector3(0, 0.2, 0))
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE
	root.add_child(model)
	return root


static func _faction_color(colors: Array[Color], owner_id: int) -> Color:
	return colors[clampi(owner_id, 0, colors.size() - 1)]


static func _make_infantry(owner_id: int) -> Node3D:
	var g := Node3D.new()
	for i in SQUAD.size():
		var entry: Array = SQUAD[i]
		var s := _make_soldier(owner_id, entry[2], i == 1)
		s.scale = Vector3.ONE * SOLDIER_SCALE
		s.position = Vector3(entry[0], 0.0, entry[1])
		s.rotation.y = (TerrainNoise.hash(i, 3, 1) - 0.5) * 0.6
		g.add_child(s)
	return g


static func _make_soldier(owner_id: int, kneel: bool, gun: bool) -> Node3D:
	var s := Node3D.new()
	var uni := _material(_faction_color(BODY_COLORS, owner_id), 0.9, 0.0)
	var vest := _material(_faction_color(VEST_COLORS, owner_id), 0.9, 0.0)
	var skin := _material(SKIN, 0.8, 0.0)
	var dark := _material(SOLDIER_DARK, 0.7, 0.3)
	var lh := 0.05 if kneel else 0.085
	_box(s, Vector3(0.024, lh, 0.026), uni, 0.02 if kneel else 0.0, lh / 2.0, -0.017)
	_box(s, Vector3(0.024, lh, 0.026), uni, -0.015 if kneel else 0.0, lh / 2.0, 0.017)
	_box(s, Vector3(0.045, 0.078, 0.064), vest, 0.0, lh + 0.04, 0.0)
	_box(s, Vector3(0.032, 0.055, 0.05), uni, -0.038, lh + 0.05, 0.0)
	_add(s, _sphere_mesh(0.02, false, 10, 8), skin, Vector3(0.004, lh + 0.1, 0.0))
	_add(s, _sphere_mesh(0.027, true, 12, 6), uni, Vector3(0.0, lh + 0.102, 0.0))
	_box(s, Vector3(0.06, 0.016, 0.016), uni, 0.03, lh + 0.06, 0.03)
	_box(s, Vector3(0.06, 0.016, 0.016), uni, 0.035, lh + 0.06, -0.025)
	var rifle := Vector3(0.15, 0.022, 0.022) if gun else Vector3(0.12, 0.012, 0.012)
	_box(s, rifle, dark, 0.06, lh + 0.07, 0.01).rotation.z = 0.12
	return s


static func _make_tank(owner_id: int) -> Node3D:
	var g := Node3D.new()
	var body := _material(_faction_color(BODY_COLORS, owner_id), 0.8, 0.15)
	var dark := _material(TANK_DARK, 0.95, 0.05)
	var metal := _material(TANK_METAL, 0.55, 0.45)
	var acc := _material(
		UiPalette.FACTION[clampi(owner_id, 0, UiPalette.FACTION.size() - 1)], 0.5, 0.1
	)
	for s: float in [-1.0, 1.0]:
		_box(g, Vector3(0.74, 0.1, 0.1), dark, 0.0, 0.06, s * 0.17)
		for i in 6:
			var wheel_pos := Vector3(-0.27 + i * 0.108, 0.055, s * 0.2)
			var wheel := _cyl(g, 0.045, 0.045, 0.03, 12, metal, wheel_pos)
			wheel.rotation.x = PI / 2.0
		_box(g, Vector3(0.62, 0.065, 0.012), body, 0.0, 0.135, s * 0.226)
	_box(g, Vector3(0.7, 0.09, 0.36), body, 0.0, 0.13, 0.0)
	_box(g, Vector3(0.64, 0.05, 0.46), body, -0.02, 0.195, 0.0)
	_box(g, Vector3(0.16, 0.02, 0.44), body, 0.33, 0.17, 0.0).rotation.z = -0.55
	_box(g, Vector3(0.13, 0.012, 0.3), dark, -0.27, 0.225, 0.0)
	var tur := Node3D.new()
	tur.name = "Turret"
	tur.position = Vector3(-0.03, 0.225, 0.0)
	g.add_child(tur)
	_add(tur, _turret_mesh(), body, Vector3.ZERO)
	_box(tur, Vector3(0.07, 0.07, 0.1), body, 0.22, 0.045, 0.0)
	_cyl(tur, 0.017, 0.019, 0.52, 10, metal, Vector3(0.5, 0.05, 0.0)).rotation.z = PI / 2.0
	_cyl(tur, 0.026, 0.026, 0.07, 10, metal, Vector3(0.42, 0.05, 0.0)).rotation.z = PI / 2.0
	_cyl(tur, 0.022, 0.022, 0.03, 10, dark, Vector3(0.76, 0.05, 0.0)).rotation.z = PI / 2.0
	_cyl(tur, 0.04, 0.046, 0.035, 12, body, Vector3(-0.07, 0.115, 0.07))
	_box(tur, Vector3(0.07, 0.012, 0.012), dark, -0.03, 0.142, 0.07)
	_cyl(tur, 0.032, 0.036, 0.025, 10, body, Vector3(-0.05, 0.11, -0.07))
	_cyl(tur, 0.004, 0.004, 0.34, 4, dark, Vector3(-0.2, 0.26, -0.11))
	for s: float in [-1.0, 1.0]:
		_box(tur, Vector3(0.06, 0.04, 0.005), acc, -0.02, 0.05, s * 0.172)
		for i in 3:
			var pos := Vector3(0.06 - i * 0.025, 0.08, s * 0.15)
			_cyl(tur, 0.012, 0.012, 0.04, 6, dark, pos).rotation.x = 0.4 * s
	return g


static func _add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


static func _box(
	parent: Node3D, size: Vector3, material: Material, x: float, y: float, z: float
) -> MeshInstance3D:
	return _add(parent, _box_mesh(size), material, Vector3(x, y, z))


static func _cyl(
	parent: Node3D,
	top: float,
	bottom: float,
	height: float,
	segments: int,
	material: Material,
	pos: Vector3
) -> MeshInstance3D:
	return _add(parent, _cyl_mesh(top, bottom, height, segments), material, pos)


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var key := "%s:%s:%s" % [color.to_html(), roughness, metallic]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		_materials[key] = m
	return _materials[key]


static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func _cyl_mesh(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var key := "cyl:%s:%s:%s:%s" % [top, bottom, height, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func _sphere_mesh(radius: float, hemisphere: bool, segments: int, rings: int) -> SphereMesh:
	var key := "sphere:%s:%s:%s:%s" % [radius, hemisphere, segments, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius if hemisphere else radius * 2.0
		m.is_hemisphere = hemisphere
		m.radial_segments = segments
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]


## The extruded turret outline: the design's polygon (x, y) lies in the XZ plane with
## z = -y, depth runs up from y = 0 (extrude + rotateX(-90°)); bevel skipped.
static func _turret_mesh() -> ArrayMesh:
	if _meshes.has("turret"):
		return _meshes["turret"]
	var ring: Array[Vector2] = []
	for p in TURRET_OUTLINE:
		ring.append(Vector2(p.x, -p.y))
	var center := Vector3.ZERO
	for p in ring:
		center += Vector3(p.x, TURRET_DEPTH / 2.0, p.y)
	center /= ring.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var a0 := Vector3(a.x, 0.0, a.y)
		var b0 := Vector3(b.x, 0.0, b.y)
		var a1 := Vector3(a.x, TURRET_DEPTH, a.y)
		var b1 := Vector3(b.x, TURRET_DEPTH, b.y)
		_tri(st, a0, b0, b1, center)
		_tri(st, a0, b1, a1, center)
		if i >= 1 and i < n - 1:
			var f := Vector3(ring[0].x, 0.0, ring[0].y)
			_tri(st, f, a0, b0, center)
			_tri(st, Vector3(f.x, TURRET_DEPTH, f.z), a1, b1, center)
	var mesh := st.commit()
	_meshes["turret"] = mesh
	return mesh


## Adds a flat-shaded triangle wound clockwise seen from outside (Godot's front face).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.dot((a + b + c) / 3.0 - inside) > 0.0:
		var t := b
		b = c
		c = t
	else:
		normal = -normal
	normal = normal.normalized()
	for v in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(v)
