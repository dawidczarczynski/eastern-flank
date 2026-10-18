class_name ModelParts
extends RefCounted
## Shared building blocks of the unit models (src/presentation/models/<unit_id>.gd): primitive
## mesh helpers with shared mesh/material caches, the faction camo materials, the PBR palette and
## the per-(unit, faction) prototype cache. Static only.

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
const TURRET_DEPTH := 0.085
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

static var _meshes: Dictionary = {}  # key string -> Mesh
static var _materials: Dictionary = {}  # key string -> StandardMaterial3D
## Keyed by faction id, not owner: a faction resource edited at runtime under the same id keeps
## its old materials until the game restarts.
static var _faction_materials: Dictionary = {}  # "faction_id:role" -> Material
## Prototypes live for the process lifetime on purpose (a few small trees, never in a scene tree).
static var _prototypes: Dictionary = {}  # "unit_id:faction_id" -> Node3D


## Builds a model once per `key` (unit id + faction id) and returns an independent copy of the
## stored prototype: own node tree (poses and visibility are per instance), shared meshes and
## materials. Model builders may call `MeshKit.bake` before returning once TASK-030 lands.
static func cached(key: String, builder: Callable) -> Node3D:
	if not _prototypes.has(key):
		var built: Node3D = builder.call()
		if built == null:
			return null
		_prototypes[key] = built
	var prototype := _prototypes[key] as Node3D
	var copy := prototype.duplicate() as Node3D
	_restore_camo(copy)
	return copy


## The renderer has a small pool (4096) of slots for per-instance shader parameters, and every live
## MeshInstance3D whose material has such a parameter (camo `part_origin`) holds one. A stored
## prototype must not occupy any, so `add` only records camo materials and part origins as node
## metadata; every copy returned by `cached` is a live model and gets them applied here.
static func _restore_camo(node: Node) -> void:
	var instance := node as MeshInstance3D
	if instance != null and instance.has_meta(&"camo_material"):
		instance.material_override = instance.get_meta(&"camo_material")
		instance.set_instance_shader_parameter(&"part_origin", instance.get_meta(&"part_origin"))
		instance.remove_meta(&"camo_material")
		instance.remove_meta(&"part_origin")
	for child in node.get_children():
		_restore_camo(child)


## Magenta box for unit ids without a model file.
static func placeholder() -> Node3D:
	var model := Node3D.new()
	add(
		model,
		box_mesh(Vector3(0.4, 0.4, 0.4)),
		std_material(Color.MAGENTA, 0.8, 0.0),
		Vector3(0, 0.2, 0)
	)
	return model


## Shared faction material for `role` (&"body", &"truck_body", &"uniform", &"vest" or
## &"accent"), cached per faction id.
static func faction_material(faction: FactionDefinition, role: StringName) -> Material:
	var faction_id: StringName = faction.id if faction != null else &""
	var key := "%s:%s" % [faction_id, role]
	if _faction_materials.has(key):
		return _faction_materials[key]
	var material: Material
	match role:
		&"vest":
			var vest_color := faction.vest_color if faction != null else NEUTRAL_VEST
			material = std_material(vest_color, 0.9, 0.0)
		&"accent":
			var accent_color := faction.color if faction != null else NEUTRAL_ACCENT
			material = std_material(accent_color, ACCENT_ROUGHNESS, ACCENT_METALLIC)
		&"uniform":
			material = camo(faction, CAMO_UNIFORM)
		&"body":
			material = camo(faction, CAMO_VEHICLE)
		&"truck_body":
			material = camo(faction, CAMO_TRUCK)
		_:
			push_error("ModelParts: unknown material role '%s'" % role)
			material = std_material(NEUTRAL_BODY, 0.8, 0.15)
	_faction_materials[key] = material
	return material


## Three camo colours of the faction; a null faction or incomplete camo gets neutral tones.
static func camo_colors(faction: FactionDefinition) -> Array[Color]:
	if faction == null or faction.camo.size() < 3:
		return [NEUTRAL_BODY, NEUTRAL_BODY.darkened(0.3), NEUTRAL_BODY.lightened(0.2)]
	return [faction.camo[0], faction.camo[1], faction.camo[2]]


static func _build_camo(faction: FactionDefinition, preset: Dictionary) -> ShaderMaterial:
	var colors := camo_colors(faction)
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
static func pbr(spec: Array) -> StandardMaterial3D:
	return std_material(spec[0], spec[1], spec[2])


## Faction accent colour material (plates, bands).
static func accent(faction: FactionDefinition) -> Material:
	return faction_material(faction, &"accent")


## Faction vest material.
static func vest(faction: FactionDefinition) -> Material:
	return faction_material(faction, &"vest")


## Faction camo material for a preset (CAMO_VEHICLE, CAMO_TRUCK, CAMO_UNIFORM): the one factory,
## cached per faction id and preset.
static func camo(faction: FactionDefinition, preset: Dictionary) -> ShaderMaterial:
	var faction_id: StringName = faction.id if faction != null else &""
	var key := "%s:camo:%s" % [faction_id, hash(preset)]
	if not _faction_materials.has(key):
		_faction_materials[key] = _build_camo(faction, preset)
	return _faction_materials[key]


static func add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	if material is ShaderMaterial:
		# Applied by `cached` (see there); the offset is only known while the tree is built.
		instance.set_meta(&"camo_material", material)
		instance.set_meta(&"part_origin", _model_offset(instance))
	else:
		instance.material_override = material
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


static func box(
	parent: Node3D, size: Vector3, material: Material, x: float, y: float, z: float
) -> MeshInstance3D:
	return add(parent, box_mesh(size), material, Vector3(x, y, z))


static func cyl(
	parent: Node3D,
	top: float,
	bottom: float,
	height: float,
	segments: int,
	material: Material,
	pos: Vector3
) -> MeshInstance3D:
	return add(parent, cyl_mesh(top, bottom, height, segments), material, pos)


static func std_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var key := "%s:%s:%s" % [color.to_html(), roughness, metallic]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		_materials[key] = m
	return _materials[key]


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func cyl_mesh(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
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


static func sphere_mesh(radius: float, hemisphere: bool, segments: int, rings: int) -> SphereMesh:
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
static func turret_mesh() -> ArrayMesh:
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
