extends RefCounted
## Real-vehicle measurements -> model space for the detailed models: `x` metres from the hull
## front backwards, `h` metres above the ground, `z` metres across (positive = vehicle's right,
## model +Z). `k` = model units per metre (uniform scale), `origin_x` = the x (from the front)
## that lands on model x = 0 (the centre of the model's length, gun included). The part helpers
## append [Mesh, Transform3D] pairs for ModelParts.merged_mesh.

var k: float
var origin_x: float


func _init(units_per_metre: float, centre_x: float) -> void:
	k = units_per_metre
	origin_x = centre_x


## Model-space point of a measurement.
func p(x: float, h: float, z := 0.0) -> Vector3:
	return Vector3((origin_x - x) * k, h * k, z * k)


## Box over x in [x0, x1], h in [h0, h1], z in [z0 - hw, z0 + hw]; `tilt` leans the top towards
## the front (radians).
func slab(
	parts: Array, x0: float, x1: float, h0: float, h1: float, hw: float, z0 := 0.0, tilt := 0.0
) -> void:
	var size := Vector3(absf(x1 - x0), h1 - h0, hw * 2.0) * k
	var t := Transform3D(Basis(Vector3.BACK, -tilt), p((x0 + x1) / 2.0, (h0 + h1) / 2.0, z0))
	parts.append([ModelParts.box_mesh(size), t])


## The same box on both sides (z0 = +-z).
func pair(parts: Array, x0: float, x1: float, h0: float, h1: float, hw: float, z: float) -> void:
	for s: float in [-1.0, 1.0]:
		slab(parts, x0, x1, h0, h1, hw, s * z)


## Cylinder of radius `r` and `length` centred at (x, h, z) along `axis` (&"x", &"y", &"z") or
## along an arbitrary model-space direction given as a Vector3.
func drum(
	parts: Array, x: float, h: float, z: float, r: float, length: float, axis: Variant, sides := 12
) -> void:
	var mesh := ModelParts.cyl_mesh(r * k, r * k, length * k, sides)
	parts.append([mesh, Transform3D(axis_basis(axis), p(x, h, z))])


## Basis whose +Y runs along `axis` (&"x", &"y", &"z" or a model-space Vector3).
static func axis_basis(axis: Variant) -> Basis:
	var dir := Vector3.UP
	if axis is Vector3:
		dir = (axis as Vector3).normalized()
	elif axis == &"x":
		dir = Vector3.RIGHT
	elif axis == &"z":
		dir = Vector3.BACK
	if dir.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	if dir.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	var rot_axis := Vector3.UP.cross(dir).normalized()
	return Basis(rot_axis, Vector3.UP.angle_to(dir))


## Model-space profile point (x from the front, h) for prisms built in the XY plane.
func xy(x: float, h: float) -> Vector2:
	return Vector2((origin_x - x) * k, h * k)


## Model-space plan point (x from the front, z across) for lofts built in the XZ plane.
func xz(x: float, z: float) -> Vector2:
	return Vector2((origin_x - x) * k, z * k)


## Prism of a side profile (`points`: Vector2(x, h) pairs) across the vehicle, `hw` half width,
## centred at `z0`.
func profile(parts: Array, key: String, points: Array, hw: float, z0 := 0.0) -> void:
	var outline: Array[Vector2] = []
	for point: Vector2 in points:
		outline.append(xy(point.x, point.y))
	var t := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z0 * k))
	parts.append([ModelParts.prism_mesh(key, outline, hw * 2.0 * k), t])


## Loft between two convex plan outlines (Vector2(x, z) pairs, same count): `bottom` at height
## h0, `top` at h1 (wedges, tapered turrets, ERA blocks).
func loft(parts: Array, key: String, bottom: Array, top: Array, h0: float, h1: float) -> void:
	var lo: Array[Vector2] = []
	var hi: Array[Vector2] = []
	for point: Vector2 in bottom:
		lo.append(xz(point.x, point.y))
	for point: Vector2 in top:
		hi.append(xz(point.x, point.y))
	parts.append([ModelParts.loft_mesh(key, lo, hi, h0 * k, h1 * k), Transform3D.IDENTITY])


## Materials of a tracked vehicle: faction camo &"body" and accent &"accent", PBR &"dark",
## &"steel", &"glass", &"rubber", &"track" (the keys TrackedRunningGear.build needs, plus glass).
static func tank_materials(faction: FactionDefinition) -> Dictionary:
	return {
		&"body": ModelParts.faction_material(faction, &"body"),
		&"dark": ModelParts.pbr(ModelParts.DARK),
		&"steel": ModelParts.pbr(ModelParts.STEEL),
		&"glass": ModelParts.pbr(ModelParts.GLASS),
		&"rubber": ModelParts.pbr(ModelParts.RUBBER),
		&"track": ModelParts.pbr(ModelParts.TRACK),
		&"accent": ModelParts.accent(faction),
	}


## "Turret" pivot on the model root at the turret ring (x, h); turns about its local Y.
func add_turret(model: Node3D, x: float, h: float) -> Node3D:
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = p(x, h)
	model.add_child(turret)
	return turret


## "Gun" pivot under `turret` at the trunnions (x, h; hinge = its local Z, level as built) with a
## "Muzzle" marker at `muzzle_x` on the bore axis.
func add_gun(turret: Node3D, trunnion: Vector2, muzzle_x: float) -> Node3D:
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = turret.transform.affine_inverse() * p(trunnion.x, trunnion.y)
	turret.add_child(gun)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = to_local(gun) * p(muzzle_x, trunnion.y)
	gun.add_child(muzzle)
	return gun


## Model space -> the space of `pivot` (a node below the model root): the `base` for merged parts
## measured in model space.
static func to_local(pivot: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var node := pivot
	while node.get_parent() is Node3D:
		t = node.transform * t
		node = node.get_parent()
	return t.affine_inverse()


## One mesh instance of the merged `parts` (cached by `key`) under `parent`; `base` maps the
## model-space parts into the parent's space (e.g. the inverse of a turret pivot's transform).
static func merged(
	parent: Node3D, key: String, parts: Array, material: Material, base := Transform3D.IDENTITY
) -> MeshInstance3D:
	return ModelParts.add(parent, ModelParts.merged_mesh(key, parts, base), material, Vector3.ZERO)
