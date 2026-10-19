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
