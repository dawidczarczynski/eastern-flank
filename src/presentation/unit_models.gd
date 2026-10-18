class_name UnitModels
extends RefCounted
## Unit miniatures built from primitives. Port of makeInf / soldier / makeTank in
## docs/design/game_screen.scene.js. Models face +X and stand on y = 0 of their root.
## Meshes and materials are created once and shared between all instances.

const MODEL_SCALE := 1.3
const SOLDIER_SCALE := 1.5
const INFANTRY := &"infantry"
const CAVALRY := &"cavalry"
const ROCKET_ARTILLERY := &"rocket_artillery"
## Models driven by vehicle locomotion (wheel spin, hull rocking, slope tilt) instead of a march.
const VEHICLES: Array[StringName] = [CAVALRY, ROCKET_ARTILLERY]
## Faction colours come from FactionDefinition: body = camo[0], vest = vest_color, accent =
## color (TASK-038). Neutral stand-ins for a null faction:
const NEUTRAL_BODY := Color("#5a5a52")
const NEUTRAL_VEST := Color("#44443d")
const NEUTRAL_ACCENT := Color("#a8a598")
const CAMO_SHADER := preload("res://assets/shaders/camo.gdshader")
## PBR palette: [colour, roughness, metallic] (TASK-029, docs/design/v2 "PBR materials").
const DARK := [Color("#24251f"), 0.85, 0.15]
const STEEL := [Color("#55564f"), 0.42, 0.75]
const RUBBER := [Color("#171715"), 0.95, 0.0]
const GLASS := [Color("#0b1820"), 0.06, 0.9]
const TRACK := [Color("#2f2d28"), 0.7, 0.55]
const SKIN := [Color("#a87c5f"), 0.75, 0.0]
const GUN := [Color("#1b1c19"), 0.45, 0.55]
const ACCENT_ROUGHNESS := 0.55
const ACCENT_METALLIC := 0.1
## Camo presets: pattern scale, mud height, base roughness, metallic.
const CAMO_VEHICLE := {"scale": 9.0, "dirt": 0.12, "rough": 0.8, "metal": 0.12}
const CAMO_TRUCK := {"scale": 9.0, "dirt": 0.11, "rough": 0.8, "metal": 0.12}
const CAMO_UNIFORM := {"scale": 70.0, "dirt": 0.03, "rough": 0.95, "metal": 0.0}
## Shader pattern mode (0 = blotches, 1 = digital). Not per faction yet: change the
## `pattern_mode` uniform of a camo material to switch.
const PATTERN_BLOTCHES := 0
const WHEELS_PER_SIDE := 6
## Rocket artillery layout: truck axle x positions, pod elevation (rad) and pod length.
const TRUCK_AXLES: Array[float] = [-0.3, -0.12, 0.27]
const POD_ELEVATION := 0.5
const POD_LENGTH := 0.52
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
## Keyed by faction id, not owner: a faction resource edited at runtime under the same id keeps
## its old materials until the game restarts.
static var _faction_materials: Dictionary = {}  # "faction_id:role" -> Material


## Yaw of a model root: player 0 faces east (+X), player 1 faces west.
static func facing_yaw(owner_id: int) -> float:
	return 0.0 if owner_id == 0 else PI


static func is_vehicle(definition_id: StringName) -> bool:
	return definition_id in VEHICLES


## `faction` colours the model (null = neutral grey); `owner_id` only sets the facing.
static func build(definition_id: StringName, owner_id: int, faction: FactionDefinition) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = facing_yaw(owner_id)
	var model: Node3D
	match definition_id:
		INFANTRY:
			model = _make_infantry(faction)
		CAVALRY:
			model = _make_tank(faction)
		ROCKET_ARTILLERY:
			model = _make_rocket_artillery(faction)
		_:
			push_warning("UnitModels: no model for '%s', using a placeholder box" % definition_id)
			model = Node3D.new()
			var size := Vector3(0.4, 0.4, 0.4)
			_add(model, _box_mesh(size), _material(Color.MAGENTA, 0.8, 0.0), Vector3(0, 0.2, 0))
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE
	root.add_child(model)
	return root


## Shared faction material for `role` (&"body", &"truck_body", &"uniform", &"vest" or
## &"accent"), cached per faction id.
static func _faction_material(faction: FactionDefinition, role: StringName) -> Material:
	var faction_id: StringName = faction.id if faction != null else &""
	var key := "%s:%s" % [faction_id, role]
	if _faction_materials.has(key):
		return _faction_materials[key]
	var material: Material
	match role:
		&"vest":
			var vest := faction.vest_color if faction != null else NEUTRAL_VEST
			material = _material(vest, 0.9, 0.0)
		&"accent":
			var accent := faction.color if faction != null else NEUTRAL_ACCENT
			material = _material(accent, ACCENT_ROUGHNESS, ACCENT_METALLIC)
		&"uniform":
			material = _camo_material(faction, CAMO_UNIFORM)
		&"body":
			material = _camo_material(faction, CAMO_VEHICLE)
		&"truck_body":
			material = _camo_material(faction, CAMO_TRUCK)
		_:
			push_error("UnitModels: unknown material role '%s'" % role)
			material = _material(NEUTRAL_BODY, 0.8, 0.15)
	_faction_materials[key] = material
	return material


## Three camo colours of the faction; a null faction or incomplete camo gets neutral tones.
static func _camo_colors(faction: FactionDefinition) -> Array[Color]:
	if faction == null or faction.camo.size() < 3:
		return [NEUTRAL_BODY, NEUTRAL_BODY.darkened(0.3), NEUTRAL_BODY.lightened(0.2)]
	return [faction.camo[0], faction.camo[1], faction.camo[2]]


static func _camo_material(faction: FactionDefinition, preset: Dictionary) -> ShaderMaterial:
	var colors := _camo_colors(faction)
	var m := ShaderMaterial.new()
	m.shader = CAMO_SHADER
	m.set_shader_parameter(&"color_a", colors[0])
	m.set_shader_parameter(&"color_b", colors[1])
	m.set_shader_parameter(&"color_c", colors[2])
	m.set_shader_parameter(&"pattern_scale", preset["scale"])
	m.set_shader_parameter(&"dirt_height", preset["dirt"])
	m.set_shader_parameter(&"base_roughness", preset["rough"])
	m.set_shader_parameter(&"metallic", preset["metal"])
	m.set_shader_parameter(&"pattern_mode", PATTERN_BLOTCHES)
	return m


## Plain PBR material from a palette entry ([colour, roughness, metallic]).
static func _pbr(spec: Array) -> StandardMaterial3D:
	return _material(spec[0], spec[1], spec[2])


static func _make_infantry(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	for i in SQUAD.size():
		var entry: Array = SQUAD[i]
		var s := Node3D.new()
		s.name = "Soldier%d" % i
		var rig := Node3D.new()
		rig.name = "Rig"
		s.add_child(rig)
		if entry[2]:
			var kneel := _make_soldier(faction, true, i == 1)
			kneel.name = "Kneel"
			var stand := _make_soldier(faction, false, i == 1)
			stand.name = "Stand"
			stand.visible = false
			rig.add_child(kneel)
			rig.add_child(stand)
		else:
			_make_soldier(faction, false, i == 1, rig)
		s.scale = Vector3.ONE * SOLDIER_SCALE
		s.position = Vector3(entry[0], 0.0, entry[1])
		s.rotation.y = (TerrainNoise.hash(i, 3, 1) - 0.5) * 0.6
		g.add_child(s)
	return g


## Builds a soldier's meshes under `into` (a new Node3D when null) and returns it.
static func _make_soldier(
	faction: FactionDefinition, kneel: bool, gun: bool, into: Node3D = null
) -> Node3D:
	var s := into if into != null else Node3D.new()
	var uni := _faction_material(faction, &"uniform")
	var vest := _faction_material(faction, &"vest")
	var skin := _pbr(SKIN)
	var dark := _pbr(GUN)
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


## Self-propelled rocket artillery: 6-wheel truck with a cab at the front and a tilted pod of
## six launch tubes on the back. The "Pod" node holds "Mouth0".."Mouth5" (tube ends) – the
## volley effect spawns rockets there. Wheels are named Wheel0..5 (see pose_tank).
static func _make_rocket_artillery(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var body := _faction_material(faction, &"truck_body")
	var dark := _pbr(DARK)
	var metal := _pbr(STEEL)
	var rubber := _pbr(RUBBER)
	var glass := _pbr(GLASS)
	var acc := _faction_material(faction, &"accent")
	var wheel_index := 0
	for s: float in [-1.0, 1.0]:
		for x: float in TRUCK_AXLES:
			var pivot := Node3D.new()
			pivot.name = "Wheel%d" % wheel_index
			wheel_index += 1
			pivot.position = Vector3(x, 0.055, s * 0.17)
			g.add_child(pivot)
			var wheel := _cyl(pivot, 0.055, 0.055, 0.04, 12, rubber, Vector3.ZERO)
			wheel.rotation.x = PI / 2.0
			_box(pivot, Vector3(0.08, 0.014, 0.006), metal, 0.0, 0.0, s * 0.022)
		_box(g, Vector3(0.7, 0.03, 0.03), dark, -0.04, 0.13, s * 0.11)  # mudguard rail
	# Chassis, cab, hood and the flat deck behind the cab.
	_box(g, Vector3(0.82, 0.06, 0.24), dark, 0.0, 0.1, 0.0)
	_box(g, Vector3(0.17, 0.15, 0.28), body, 0.27, 0.21, 0.0)
	_box(g, Vector3(0.1, 0.08, 0.26), body, 0.4, 0.17, 0.0)
	_box(g, Vector3(0.012, 0.07, 0.22), glass, 0.358, 0.255, 0.0).rotation.z = 0.25  # windscreen
	_box(g, Vector3(0.1, 0.012, 0.2), acc, 0.27, 0.292, 0.0)  # faction roof panel
	_box(g, Vector3(0.52, 0.03, 0.3), body, -0.14, 0.145, 0.0)
	_box(g, Vector3(0.04, 0.05, 0.3), dark, -0.42, 0.11, 0.0)  # rear stabiliser bar
	# Launcher: cradle + tilted pod. The pod's +X side is the muzzle end.
	_box(g, Vector3(0.16, 0.05, 0.24), metal, -0.2, 0.18, 0.0)
	var pod := Node3D.new()
	pod.name = "Pod"
	pod.position = Vector3(-0.17, 0.25, 0.0)
	pod.rotation.z = POD_ELEVATION
	g.add_child(pod)
	_box(pod, Vector3(0.52, 0.17, 0.28), body, 0.0, 0.0, 0.0)
	# Large flat plates stay matte: a big steel panel only mirrors the dark ground.
	_box(pod, Vector3(0.5, 0.012, 0.3), dark, 0.0, 0.092, 0.0)
	_box(pod, Vector3(0.5, 0.012, 0.3), dark, 0.0, -0.092, 0.0)
	_box(pod, Vector3(0.08, 0.175, 0.285), acc, -0.12, 0.0, 0.0)  # faction band
	var mouth_index := 0
	for row: float in [1.0, -1.0]:
		for col: float in [-1.0, 0.0, 1.0]:
			var mouth_pos := Vector3(POD_LENGTH / 2.0 + 0.01, row * 0.04, col * 0.085)
			var tube := _cyl(pod, 0.034, 0.034, 0.03, 10, dark, mouth_pos - Vector3(0.015, 0, 0))
			tube.rotation.z = PI / 2.0
			var nose := _cyl(pod, 0.02, 0.02, 0.02, 8, acc, mouth_pos - Vector3(0.02, 0, 0))
			nose.rotation.z = PI / 2.0
			var mouth := Node3D.new()
			mouth.name = "Mouth%d" % mouth_index
			mouth_index += 1
			mouth.position = mouth_pos + Vector3(0.03, 0, 0)
			pod.add_child(mouth)
	return g


static func _make_tank(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var body := _faction_material(faction, &"body")
	var dark := _pbr(DARK)
	var metal := _pbr(STEEL)
	var rubber := _pbr(RUBBER)
	var track := _pbr(TRACK)
	var acc := _faction_material(faction, &"accent")
	var wheel_index := 0
	for s: float in [-1.0, 1.0]:
		_box(g, Vector3(0.74, 0.1, 0.1), track, 0.0, 0.06, s * 0.17)
		for i in WHEELS_PER_SIDE:
			var pivot := Node3D.new()
			pivot.name = "Wheel%d" % wheel_index
			wheel_index += 1
			pivot.position = Vector3(-0.27 + i * 0.108, 0.055, s * 0.2)
			g.add_child(pivot)
			var wheel := _cyl(pivot, 0.045, 0.045, 0.03, 12, rubber, Vector3.ZERO)
			wheel.rotation.x = PI / 2.0
			_box(pivot, Vector3(0.07, 0.012, 0.006), metal, 0.0, 0.0, s * 0.017)
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


## Root may be the built root or its "Model" child.
static func _model_of(node: Node3D) -> Node3D:
	var inner := node.get_node_or_null("Model") as Node3D
	return inner if inner != null else node


## Poses a squad: `moving` makes kneelers stand; at env 0 / not moving every Rig is exactly
## the identity transform.
static func pose_infantry(model: Node3D, distance: float, env: float, moving: bool) -> void:
	var m := _model_of(model)
	for i in SQUAD.size():
		var rig := m.get_node_or_null("Soldier%d/Rig" % i) as Node3D
		if rig == null:
			continue
		var kneel := rig.get_node_or_null("Kneel") as Node3D
		if kneel != null:
			kneel.visible = not moving
			(rig.get_node("Stand") as Node3D).visible = moving
		if not moving or env <= 0.0:
			rig.transform = Transform3D.IDENTITY
			continue
		var phase := Locomotion.step_phase(i)
		rig.position = Vector3(0.0, Locomotion.step_bob(distance, phase) * env, 0.0)
		rig.rotation = Vector3(
			Locomotion.step_sway(distance, phase) * env, 0.0, Locomotion.LEAN * env
		)


## Spins the wheels to the accumulated `wheel_distance` and sets the hull's pitch/roll to the
## slope `tilt` (x pitch, y roll) plus the env-scaled rocking.
static func pose_tank(model: Node3D, wheel_distance: float, env: float, tilt: Vector2) -> void:
	var m := _model_of(model)
	var angle := Locomotion.wheel_angle(wheel_distance)
	for i in WHEELS_PER_SIDE * 2:
		var pivot := m.get_node_or_null("Wheel%d" % i) as Node3D
		if pivot != null:
			pivot.rotation.z = angle
	var pitch := tilt.x
	var roll := tilt.y
	if env > 0.0:
		var bob := Locomotion.hull_bob(wheel_distance)
		pitch += bob.x * env
		roll += bob.y * env
	m.rotation = Vector3(roll, 0.0, pitch)


static func _add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	if material is ShaderMaterial:
		instance.set_instance_shader_parameter(&"part_origin", _model_offset(instance))
	return instance


## Position of `node` relative to the root of the (sub)tree it is being built in: sums the local
## positions of the node and its ancestors at build time, so pivots (Turret, Pod, wheels) must
## get their `position` before parts are added to them. Rotations and scales are ignored on
## purpose – it only has to line up the camo pattern and mud line between neighbouring parts.
static func _model_offset(node: Node3D) -> Vector3:
	var offset := Vector3.ZERO
	var current := node
	while current != null:
		offset += current.position
		current = current.get_parent() as Node3D
	return offset


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
