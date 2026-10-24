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
const SKIN_SHADER := preload("res://assets/shaders/skin.gdshader")
## PBR palette: [colour, roughness, metallic] (TASK-029, docs/design/v2 "PBR materials").
const DARK := [Color("#24251f"), 0.85, 0.15]
const STEEL := [Color("#55564f"), 0.42, 0.75]
const RUBBER := [Color("#171715"), 0.95, 0.0]
const GLASS := [Color("#0b1820"), 0.06, 0.9]
const TRACK := [Color("#2f2d28"), 0.7, 0.55]
## Soldiers' skin (TASK-085: the skin shader with baked AO and subsurface scattering, `skin()`).
const SKIN := [Color("#a2785f"), 0.6, 0.0]
const GUN := [Color("#1b1c19"), 0.45, 0.55]
## Default chamfer of the part helpers (box, cylinder, prism, loft, lathe rims), model units
## (1 unit = 10 m before the model scale, so ~4 cm). Smaller than `MIN_BEVEL` after limiting it to
## the part size = sharp. Pass `bevel = 0.0` for a sharp part (TASK-062).
const DEFAULT_BEVEL := 0.004
const MIN_BEVEL := 0.0015
## Vertex mask of parts without a chamfer or cavity (r edge, g openness, b tint seed), see
## MeshKit and ADR 0012.
const PLAIN_MASK := Color(0.0, 1.0, 0.5)
const ACCENT_ROUGHNESS := 0.55
const ACCENT_METALLIC := 0.1
## Camo presets: pattern scale, mud height, base roughness, metallic; optional camo shader
## uniforms by name (`OPTIONAL_CAMO_KEYS`).
const CAMO_VEHICLE := {"scale": 9.0, "dirt": 0.12, "rough": 0.8, "metal": 0.12}
const CAMO_TRUCK := {"scale": 9.0, "dirt": 0.11, "rough": 0.8, "metal": 0.12}
## Uniform fabric (TASK-085): blotches at the real scale of the printed patterns (dominant shapes
## ~5–15 cm on the unscaled soldier, 1 model unit = 10 m), softer contrast and saturation than
## painted vehicles, the cloth bump and sheen.
const CAMO_UNIFORM := {
	"scale": 150.0,
	"dirt": 0.015,
	"rough": 0.95,
	"metal": 0.0,
	"pattern_contrast": 0.72,
	"fade": 0.22,
	"fabric": 1.0,
	"mask_ao": 1.0,
	"wear_amount": 0.0,
	"dust_amount": 0.3,
}
const OPTIONAL_CAMO_KEYS: Array[String] = [
	"pattern_contrast", "fade", "fabric", "mask_ao", "wear_amount", "dust_amount"
]
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

static var _meshes: Dictionary = {}  # key string -> Mesh (or a Dictionary of meshes)
static var _materials: Dictionary = {}  # key string -> Material
## Keyed by faction id, not owner: a faction resource edited at runtime under the same id keeps
## its old materials until the game restarts.
static var _faction_materials: Dictionary = {}  # "faction_id:role" -> Material
## Prototypes live for the process lifetime on purpose (a few small trees, never in a scene tree).
static var _prototypes: Dictionary = {}  # "unit_id:faction_id" -> Node3D
## Fabric term of the uniform camo (GraphicsQuality "fabric") on or off, and the materials that
## have one (their preset's "fabric", stored as metadata, is the value when on).
static var _fabric_on := true
static var _fabric_materials: Array[ShaderMaterial] = []


## Drops the shared meshes so the next build generates them again (tests timing a cold build).
## Live models keep the meshes they already reference.
static func clear_mesh_cache() -> void:
	_meshes.clear()


## Builds a model once per `key` (unit id + faction id) and returns an independent copy of the
## stored prototype: own node tree (poses and visibility are per instance), shared meshes and
## materials. `wear_seed` (UnitModels.wear_seed) is applied to the camo parts of the copy.
static func cached(key: String, builder: Callable, wear_seed := 0.0) -> Node3D:
	if not _prototypes.has(key):
		var built: Node3D = builder.call()
		if built == null:
			return null
		_prototypes[key] = built
	var prototype := _prototypes[key] as Node3D
	var copy := prototype.duplicate() as Node3D
	_restore_camo(copy, wear_seed)
	return copy


## The renderer has a small pool (4096) of slots for per-instance shader parameters, and every live
## MeshInstance3D whose material has such a parameter (camo `part_origin`) holds one. A stored
## prototype must not occupy any, so `add` only records camo materials and part origins as node
## metadata; every copy returned by `cached` is a live model and gets them applied here (plus the
## per-unit `wear_seed`).
static func _restore_camo(node: Node, wear_seed: float) -> void:
	var instance := node as MeshInstance3D
	if instance != null and instance.has_meta(&"camo_material"):
		instance.material_override = instance.get_meta(&"camo_material")
		instance.set_instance_shader_parameter(&"part_origin", instance.get_meta(&"part_origin"))
		instance.set_instance_shader_parameter(&"wear_seed", wear_seed)
		instance.remove_meta(&"camo_material")
		instance.remove_meta(&"part_origin")
	for child in node.get_children():
		_restore_camo(child, wear_seed)


## Stores the unit's catalog mechanisms (with all params) on the built model as the `mechanisms`
## metadata, read through UnitModels.mechanisms / mechanism. Survives `cached` copies; the
## dictionary is shared between copies, treat it as read-only.
static func declare_mechanisms(model: Node3D, mechanisms: Dictionary) -> void:
	model.set_meta(&"mechanisms", mechanisms)


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


## Switches the uniform camo's fabric bump and sheen on or off (LOW quality), for the existing and
## the later uniform materials.
static func set_fabric(enabled: bool) -> void:
	_fabric_on = enabled
	for m in _fabric_materials:
		m.set_shader_parameter(&"fabric", m.get_meta(&"fabric") if enabled else 0.0)


static func _build_camo(faction: FactionDefinition, preset: Dictionary) -> ShaderMaterial:
	var colors := camo_colors(faction)
	var m := ShaderMaterial.new()
	m.shader = CAMO_SHADER
	m.set_shader_parameter(&"color_a", colors[0])
	m.set_shader_parameter(&"color_b", colors[1])
	m.set_shader_parameter(&"color_c", colors[2])
	m.set_shader_parameter(&"pattern_scale", preset["scale"])
	m.set_shader_parameter(&"mud_height", preset["dirt"])
	m.set_shader_parameter(&"base_roughness", preset["rough"])
	m.set_shader_parameter(&"metallic", preset["metal"])
	m.set_shader_parameter(&"pattern_mode", PATTERN_BLOTCHES)
	for key in OPTIONAL_CAMO_KEYS:
		if preset.has(key):
			m.set_shader_parameter(StringName(key), preset[key])
	if preset.has("fabric"):
		m.set_meta(&"fabric", preset["fabric"])
		m.set_shader_parameter(&"fabric", preset["fabric"] if _fabric_on else 0.0)
		_fabric_materials.append(m)
	return m


## Plain PBR material from a palette entry ([colour, roughness, metallic]).
static func pbr(spec: Array) -> StandardMaterial3D:
	return std_material(spec[0], spec[1], spec[2])


## Plain weathered paint (one colour, the camo shader's wear, cavity, tint, dust and mud from the
## MeshKit vertex masks) cached by `key`: `values` = {"color": Color, <camo shader uniform>: value}.
## Not faction dependent (vehicle steel / track parts, soldiers' boots and gloves).
static func weathered_paint(key: String, values: Dictionary) -> ShaderMaterial:
	var cache_key := "weathered:%s" % key
	if not _materials.has(cache_key):
		var m := ShaderMaterial.new()
		m.shader = CAMO_SHADER
		for name: String in values:
			if name == "color":
				for slot: StringName in [&"color_a", &"color_b", &"color_c"]:
					m.set_shader_parameter(slot, values[name])
			else:
				m.set_shader_parameter(StringName(name), values[name])
		_materials[cache_key] = m
	return _materials[cache_key]


## Soldiers' skin: the skin shader (vertex-mask AO, subsurface scattering) in the SKIN palette
## colour, shared.
static func skin() -> ShaderMaterial:
	if not _materials.has("skin"):
		var m := ShaderMaterial.new()
		m.shader = SKIN_SHADER
		m.set_shader_parameter(&"albedo", SKIN[0])
		m.set_shader_parameter(&"roughness", SKIN[1])
		_materials["skin"] = m
	return _materials["skin"]


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


## Box of `size` (centred) with chamfered edges (`bevel`, limited to a fifth of the thinnest side;
## 0 = sharp, 24 vertices like a BoxMesh), vertex masks per ADR 0012.
static func box_mesh(size: Vector3, bevel := DEFAULT_BEVEL) -> ArrayMesh:
	var b := _limited(bevel, minf(size.x, minf(size.y, size.z)) * 0.2)
	var key := "box:%s:%s" % [size, b]
	if not _meshes.has(key):
		var kit := MeshKit.new()
		kit.cbox(Vector3.ZERO, size, b)
		_meshes[key] = kit.commit(true)
	return _meshes[key]


## Cylinder along Y (cone when the radii differ; a radius of 0 gives a point) with both rims
## chamfered by `bevel` (limited by the radius and height; 0 = sharp).
static func cyl_mesh(
	top: float, bottom: float, height: float, segments: int, bevel := DEFAULT_BEVEL
) -> ArrayMesh:
	var key := "cyl:%s:%s:%s:%s:%s" % [top, bottom, height, segments, bevel]
	if not _meshes.has(key):
		var hh := height / 2.0
		var bt := _limited(bevel, minf(top * 0.4, height * 0.2))
		var bb := _limited(bevel, minf(bottom * 0.4, height * 0.2))
		var profile: Array[Vector2] = [Vector2(0.0, hh)]
		if bt > 0.0:
			profile.append(Vector2(top - bt, hh))
			profile.append(Vector2(top, hh - bt))
		else:
			profile.append(Vector2(top, hh))
		if bb > 0.0:
			profile.append(Vector2(bottom, -hh + bb))
			profile.append(Vector2(bottom - bb, -hh))
		else:
			profile.append(Vector2(bottom, -hh))
		profile.append(Vector2(0.0, -hh))
		var kit := MeshKit.new()
		kit.lathe(Vector3.ZERO, Basis.IDENTITY, profile, segments)
		_meshes[key] = kit.commit(true)
	return _meshes[key]


## `bevel`, or 0 when it is smaller than MIN_BEVEL after limiting it to `max_bevel`.
static func _limited(bevel: float, max_bevel: float) -> float:
	var b := minf(bevel, max_bevel)
	return b if b >= MIN_BEVEL else 0.0


## Meshes built once per `key` until `clear_mesh_cache`: `builder` returns a Dictionary of them
## (e.g. `MeshKits.commit_all()`, {material role: ArrayMesh}) and every later call gets the same
## Dictionary – geometry that does not depend on the faction is generated once for all factions.
static func cached_meshes(key: String, builder: Callable) -> Dictionary:
	var cache_key := "kits:%s" % key
	if not _meshes.has(cache_key):
		_meshes[cache_key] = builder.call()
	return _meshes[cache_key]


## One mesh from many primitives (`parts`: [Mesh, Transform3D] pairs, each transform pre-multiplied
## by `base`), cached by `key` – keeps a model under the mesh-instance budget: one instance per
## material instead of one per box. `key` must name the geometry (e.g. "homar_k:body").
static func merged_mesh(key: String, parts: Array, base := Transform3D.IDENTITY) -> ArrayMesh:
	var cache_key := "merged:%s" % key
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spans: Array[Vector2i] = []  # [vertex count, tint seed * 1000] per part
	for part: Array in parts:
		var mesh := part[0] as Mesh
		var t := base * (part[1] as Transform3D)
		st.append_from(mesh, 0, t)
		spans.append(
			Vector2i(mesh.surface_get_array_len(0), int(MeshKit.tint_seed(t.origin) * 1000.0))
		)
	var merged := st.commit()
	if merged.get_surface_count() == 0:
		_meshes[cache_key] = merged
		return merged
	# Vertex mask b = tint seed of the part (hash of its position), see MeshKit / ADR 0012.
	var arrays := merged.surface_get_arrays(0)
	var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	if colors.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var at := 0
		for span in spans:
			var tint := span.y / 1000.0
			for i in range(at, at + span.x):
				var c := colors[i]
				colors[i] = Color(c.r, c.g, tint)
			at += span.x
		arrays[Mesh.ARRAY_COLOR] = colors
		var tinted := ArrayMesh.new()
		tinted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		merged = tinted
	_meshes[cache_key] = merged
	return merged


## Wheel pivot "Wheel<index>" (spins around its local Z, see UnitModels.pose_tank) at `pos`: a tyre
## of `radius` and `width` with `treads` tread blocks, and a hub on the outer face (`side` = sign of
## z of the vehicle side). Shared by the wheeled vehicles.
static func wheel(
	parent: Node3D,
	index: int,
	pos: Vector3,
	radius: float,
	width: float,
	side: float,
	hub_material: Material,
	treads := 16
) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Wheel%d" % index
	pivot.position = pos
	parent.add_child(pivot)
	var rubber := pbr(RUBBER)
	var tyre := cyl(pivot, radius * 0.94, radius * 0.94, width, 20, rubber, Vector3.ZERO)
	tyre.rotation.x = PI / 2.0
	var blocks: Array = []
	var block := box_mesh(Vector3(radius * 0.12, radius * 0.17, width * 0.96))
	for k in treads:
		var angle := TAU * k / treads
		var t := Transform3D(
			Basis(Vector3.BACK, angle), Vector3(cos(angle), sin(angle), 0.0) * radius * 0.94
		)
		blocks.append([block, t])
	add(
		pivot, merged_mesh("tread:%s:%s:%s" % [radius, width, treads], blocks), rubber, Vector3.ZERO
	)
	var hub := cyl(
		pivot, radius * 0.5, radius * 0.5, 0.004, 12, hub_material, Vector3(0, 0, side * width / 2)
	)
	hub.rotation.x = PI / 2.0
	var cap := cyl(
		pivot, radius * 0.16, radius * 0.2, 0.008, 8, pbr(DARK), Vector3(0, 0, side * width / 2)
	)
	cap.rotation.x = PI / 2.0
	return pivot


static func sphere_mesh(radius: float, hemisphere: bool, segments: int, rings: int) -> ArrayMesh:
	var key := "sphere:%s:%s:%s:%s" % [radius, hemisphere, segments, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius if hemisphere else radius * 2.0
		m.is_hemisphere = hemisphere
		m.radial_segments = segments
		m.rings = rings
		var arrays := m.get_mesh_arrays()
		var colors := PackedColorArray()
		colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		colors.fill(PLAIN_MASK)
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_meshes[key] = mesh
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
	st.index()  # merged_mesh drops non-indexed vertices once an indexed part is appended
	var mesh := st.commit()
	_meshes["turret"] = mesh
	return mesh


## Prism: closed `outline` in the XY plane (either winding, simple polygon, e.g. a side profile or
## a gear) extruded along Z from -depth/2 to +depth/2, both rims chamfered by `bevel` (limited by
## the depth and the outline's size; 0 = sharp). Cached by `key` (must name the geometry).
static func prism_mesh(
	key: String, outline: Array[Vector2], depth: float, bevel := DEFAULT_BEVEL
) -> ArrayMesh:
	var cache_key := "prism:%s:%s" % [key, bevel]
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	var b := _limited(bevel, minf(depth * 0.25, _outline_room(outline)))
	var kit := MeshKit.new()
	kit.plate(
		outline, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -depth / 2.0, depth / 2.0, b
	)
	var mesh := kit.commit(true)
	_meshes[cache_key] = mesh
	return mesh


## How far a polygon's edges may be moved inwards without collapsing: 40 % of its inradius
## estimate (2 * area / perimeter) and 30 % of its shortest edge.
static func _outline_room(outline: Array) -> float:
	var area := 0.0
	var perimeter := 0.0
	var shortest := INF
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		area += a.cross(b)
		var length := a.distance_to(b)
		perimeter += length
		if length > 1e-5:
			shortest = minf(shortest, length)
	if perimeter < 1e-6:
		return 0.0
	return minf(absf(area) / perimeter * 0.4, shortest * 0.3)


## Loft between two convex outlines in the XZ plane with the same vertex count: `bottom` at
## height y0, `top` at y1 (wedges, tapered turrets), both ends capped, the roof edge chamfered by
## `bevel` (limited by the height and the top outline; 0 = sharp).
static func loft_mesh(
	key: String,
	bottom: Array[Vector2],
	top: Array[Vector2],
	y0: float,
	y1: float,
	bevel := DEFAULT_BEVEL
) -> ArrayMesh:
	var cache_key := "loft:%s:%s" % [key, bevel]
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	var b := _limited(bevel, minf(absf(y1 - y0) * 0.25, _outline_room(top)))
	var kit := MeshKit.new()
	if b > 0.0:
		kit.loft(bottom, top, y0, y1, b)
	else:
		var lo := []
		var hi := []
		for p in bottom:
			lo.append(Vector3(p.x, y0, p.y))
		for p in top:
			hi.append(Vector3(p.x, y1, p.y))
		kit.stack([lo, hi], [0.0])
	var mesh := kit.commit(true)
	_meshes[cache_key] = mesh
	return mesh


## Lathe around +Y: `profile` points are Vector2(radius, y), ordered from the top down around the
## outside (e.g. (0, top) -> (R, top) -> (R, bottom) -> (0, bottom)). Smooth around the axis, hard
## edges between profile segments (machined look), sharp corners of the profile chamfered by
## `bevel` (limited by the neighbouring segments; 0 = sharp). Rotate the part to lay it along X
## or Z.
static func lathe_mesh(
	key: String, profile: Array[Vector2], segments: int, bevel := DEFAULT_BEVEL
) -> ArrayMesh:
	var cache_key := "lathe:%s:%s:%s" % [key, segments, bevel]
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	var kit := MeshKit.new()
	kit.lathe(Vector3.ZERO, Basis.IDENTITY, _bevel_profile(profile, bevel), segments)
	var mesh := kit.commit(true)
	_meshes[cache_key] = mesh
	return mesh


## `profile` with every corner of more than ~30 degrees (not on the axis) replaced by a chamfer.
static func _bevel_profile(profile: Array[Vector2], bevel: float) -> Array:
	var result: Array = []
	var n := profile.size()
	for i in n:
		var p := profile[i]
		if i == 0 or i == n - 1 or p.x < 1e-5:
			result.append(p)
			continue
		var before := p - profile[i - 1]
		var after := profile[i + 1] - p
		var l0 := before.length()
		var l1 := after.length()
		var b := _limited(bevel, minf(l0, l1) * 0.35)
		if b == 0.0 or l0 < 1e-6 or l1 < 1e-6 or absf(before.angle_to(after)) < 0.5:
			result.append(p)
			continue
		result.append(p - before / l0 * b)
		result.append(p + after / l1 * b)
	return result


## Closed gear outline (`teeth` teeth between `root` and `tip` radius), counter-clockwise.
static func gear_outline(root: float, tip: float, teeth: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var step := TAU / teeth
	for i in teeth:
		var a := i * step
		for f: Array in [[0.0, root], [0.3, tip], [0.55, tip], [0.85, root]]:
			var angle: float = a + step * float(f[0])
			points.append(Vector2(cos(angle), sin(angle)) * float(f[1]))
	return points


## Convex hull (counter-clockwise) of circles given as Vector3(x, y, radius), each sampled with
## `samples` points – e.g. a track run around its wheels.
static func circle_hull(circles: Array[Vector3], samples: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for c in circles:
		for i in samples:
			var angle := TAU * i / samples
			points.append(Vector2(c.x + cos(angle) * c.z, c.y + sin(angle) * c.z))
	var hull: Array[Vector2] = []
	for p in Geometry2D.convex_hull(PackedVector2Array(points)):
		if hull.is_empty() or not p.is_equal_approx(hull[0]):
			hull.append(p)
	return _ccw(hull)


## Closed band of `thickness` outside the convex path `inner` (counter-clockwise, XY plane),
## `width` deep along Z (centred): a track loop around its wheels. Flat normals.
static func band_mesh(
	key: String, inner: Array[Vector2], thickness: float, width: float
) -> ArrayMesh:
	var cache_key := "band:%s" % key
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	var outer := offset_path(inner, thickness)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := width / 2.0
	var n := inner.size()
	for i in n:
		var j := (i + 1) % n
		var d := inner[j] - inner[i]
		var out := Vector3(d.y, -d.x, 0.0).normalized()
		var ia := Vector3(inner[i].x, inner[i].y, 0.0)
		var ib := Vector3(inner[j].x, inner[j].y, 0.0)
		var oa := Vector3(outer[i].x, outer[i].y, 0.0)
		var ob := Vector3(outer[j].x, outer[j].y, 0.0)
		var z := Vector3(0, 0, hz)
		_face(st, oa - z, ob - z, ob + z, out)
		_face(st, oa - z, ob + z, oa + z, out)
		_face(st, ia - z, ib - z, ib + z, -out)
		_face(st, ia - z, ib + z, ia + z, -out)
		for s: float in [-1.0, 1.0]:
			var w := z * s
			_face(st, ia + w, ib + w, ob + w, Vector3.BACK * s)
			_face(st, ia + w, ob + w, oa + w, Vector3.BACK * s)
	st.index()  # merged_mesh drops non-indexed vertices once an indexed part is appended
	var mesh := st.commit()
	_meshes[cache_key] = mesh
	return mesh


## `path` (convex, counter-clockwise) moved outwards by `distance` along its vertex normals.
static func offset_path(path: Array[Vector2], distance: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var n := path.size()
	for i in n:
		var before := path[i] - path[(i - 1 + n) % n]
		var after := path[(i + 1) % n] - path[i]
		var na := Vector2(before.y, -before.x).normalized()
		var nb := Vector2(after.y, -after.x).normalized()
		result.append(path[i] + (na + nb).normalized() * distance)
	return result


## Points every `spacing` along the closed `path` with the unit tangent at each:
## [[point, tangent], ...] (grousers on a track).
static func path_stations(path: Array[Vector2], spacing: float) -> Array:
	var result: Array = []
	var n := path.size()
	var carry := 0.0
	for i in n:
		var a := path[i]
		var b := path[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 1e-6:
			continue
		var tangent := (b - a) / length
		var at := carry
		while at < length:
			result.append([a + tangent * at, tangent])
			at += spacing
		carry = at - length
	return result


static func _ccw(outline: Array[Vector2]) -> Array[Vector2]:
	var area := 0.0
	for i in outline.size():
		area += outline[i].cross(outline[(i + 1) % outline.size()])
	if area >= 0.0:
		return outline
	var reversed := outline.duplicate()
	reversed.reverse()
	return reversed


## Flat triangle with the given outward `normal` (wound clockwise seen from outside).
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(PLAIN_MASK)
		st.set_normal(normal)
		st.add_vertex(v)


## Smooth-shaded triangle (per-vertex normals); skipped when degenerate (lathe axis points).
static func _smooth_face(st: SurfaceTool, v: Array, n: Array) -> void:
	var a: Vector3 = v[0]
	var b: Vector3 = v[1]
	var c: Vector3 = v[2]
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 1e-14:
		return
	var face: Vector3 = (n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)
	var order := [0, 1, 2] if cross.dot(face) <= 0.0 else [0, 2, 1]
	for k: int in order:
		st.set_color(PLAIN_MASK)
		st.set_normal(n[k])
		st.add_vertex(v[k])


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
		st.set_color(PLAIN_MASK)
		st.set_normal(normal)
		st.add_vertex(v)
