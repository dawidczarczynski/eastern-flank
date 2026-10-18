class_name RocketVolley
extends Node3D
## Rocket salvo effect (TASK-011): ROCKET_COUNT rockets leave the launcher tubes GAP seconds apart,
## each flying a ballistic arc to the target with an emissive trail, a muzzle flash at launch and
## an impact flash. Everything is a pure function of the volley time `t` (update(t)), so the
## caller drives it from one tween and the speed scale applies automatically. Purely visual:
## the only randomness is a view-local RandomNumberGenerator for the landing scatter.

const ROCKET_COUNT := 6
const GAP := 0.15
const FLIGHT := 1.0
const MUZZLE_TIME := 0.14
const IMPACT_TIME := 0.25
const SCATTER := 0.3
const APEX_BASE := 0.7
const APEX_PER_UNIT := 0.22
const APEX_MAX := 3.2
const TRAIL_STEPS := 4
const TRAIL_SPACING := 0.045
const FLAME := Color("#ffb347")

var _origins: Array[Vector3] = []
var _landings: Array[Vector3] = []
var _apex := 1.0
var _rockets: Array[Node3D] = []
var _trails: Array = []  # per rocket: Array[MeshInstance3D]
var _muzzles: Array[MeshInstance3D] = []
var _impacts: Array[MeshInstance3D] = []
var _flash_materials: Array[StandardMaterial3D] = []  # muzzle + impact, per rocket


## Time (seconds at speed 1) from the first launch to the last impact flash fading out.
static func total_duration() -> float:
	return (ROCKET_COUNT - 1) * GAP + FLIGHT + IMPACT_TIME


## Time when the last rocket lands (the target's hit reaction starts here).
static func last_impact_time() -> float:
	return (ROCKET_COUNT - 1) * GAP + FLIGHT


## Point on a parabolic arc: horizontal straight line from `from` to `to`, height the straight
## chord plus `apex` * 4t(1-t) – so the middle is `apex` above the chord's midpoint.
static func arc_point(from: Vector3, to: Vector3, apex: float, t: float) -> Vector3:
	var u := clampf(t, 0.0, 1.0)
	var p := from.lerp(to, u)
	p.y += apex * 4.0 * u * (1.0 - u)
	return p


## Apex height for a shot over world distance `distance` (longer shots fly higher).
static func apex_height(distance: float) -> float:
	return minf(APEX_BASE + APEX_PER_UNIT * distance, APEX_MAX)


## Flight progress 0..1 of rocket `index` at volley time `t`; below 0 before launch, above 1
## after landing (not clamped).
static func progress(t: float, index: int) -> float:
	return (t - index * GAP) / FLIGHT


## `origins`: world positions of the launch tubes (cycled when there are fewer than rockets);
## `target`: world point of the target tile. `rng` jitters the landing points.
func setup(origins: Array[Vector3], target: Vector3, rng: RandomNumberGenerator) -> void:
	_origins = origins
	var centre := Vector3.ZERO
	for o in origins:
		centre += o
	centre /= maxf(1.0, origins.size())
	_apex = apex_height(Vector2(target.x - centre.x, target.z - centre.z).length())
	var glow := _unshaded(FLAME, 1.0)
	var rocket_mesh := CylinderMesh.new()
	rocket_mesh.top_radius = 0.018
	rocket_mesh.bottom_radius = 0.018
	rocket_mesh.height = 0.14
	rocket_mesh.radial_segments = 6
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("#d8d4c4")
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 8
	ball.rings = 4
	for i in ROCKET_COUNT:
		_landings.append(target + Vector3(rng.randfn(0.0, SCATTER), 0.0, rng.randfn(0.0, SCATTER)))
		var rocket := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = rocket_mesh
		body.material_override = body_material
		body.rotation.x = PI / 2.0  # cylinder axis along the node's -Z (its forward)
		rocket.add_child(body)
		var flame := MeshInstance3D.new()
		flame.mesh = ball
		flame.material_override = glow
		flame.scale = Vector3.ONE * 0.06
		flame.position = Vector3(0.0, 0.0, 0.08)
		rocket.add_child(flame)
		rocket.visible = false
		add_child(rocket)
		_rockets.append(rocket)
		var trail: Array[MeshInstance3D] = []
		for k in TRAIL_STEPS:
			var puff := MeshInstance3D.new()
			puff.mesh = ball
			puff.material_override = glow
			puff.visible = false
			puff.top_level = true
			add_child(puff)
			trail.append(puff)
		_trails.append(trail)
		var muzzle := _flash_node(ball, _origins[i % _origins.size()])
		_muzzles.append(muzzle)
		_impacts.append(_flash_node(ball, _landings[i]))
	update(0.0)


## Poses the whole effect at volley time `t`; the effect hides itself outside its lifetime.
func update(t: float) -> void:
	if _origins.is_empty():
		return
	for i in ROCKET_COUNT:
		var origin := _origins[i % _origins.size()]
		var landing := _landings[i]
		var u := progress(t, i)
		var flying := u >= 0.0 and u < 1.0
		var rocket := _rockets[i]
		rocket.visible = flying
		if flying:
			var here := arc_point(origin, landing, _apex, u)
			var ahead := arc_point(origin, landing, _apex, u + 0.02)
			if ahead.distance_squared_to(here) > 0.000001:
				rocket.global_transform = Transform3D(
					Basis.looking_at(ahead - here, Vector3.UP), here
				)
			else:
				rocket.global_position = here
		var trail: Array = _trails[i]
		for k in TRAIL_STEPS:
			var puff := trail[k] as MeshInstance3D
			puff.visible = flying
			if flying:
				var fade := 1.0 - float(k) / TRAIL_STEPS
				puff.global_position = arc_point(
					origin, landing, _apex, u - (k + 1) * TRAIL_SPACING
				)
				puff.scale = Vector3.ONE * 0.07 * fade
		_pose_flash(_muzzles[i], t - i * GAP, MUZZLE_TIME, 0.22, i * 2)
		_pose_flash(_impacts[i], t - (i * GAP + FLIGHT), IMPACT_TIME, 0.6, i * 2 + 1)


## Expanding, fading glow ball: `age` seconds since it started, lasting `life`.
func _pose_flash(node: MeshInstance3D, age: float, life: float, size: float, mat: int) -> void:
	var v := age / life
	node.visible = v >= 0.0 and v < 1.0
	if not node.visible:
		return
	node.scale = Vector3.ONE * size * (0.4 + 0.6 * v)
	_flash_materials[mat].albedo_color.a = 1.0 - v


func _flash_node(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var material := _unshaded(Color("#fff0c0"), 1.0)
	_flash_materials.append(material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.top_level = true
	node.visible = false
	add_child(node)
	node.global_position = at
	return node


static func _unshaded(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, alpha)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
