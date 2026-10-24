class_name RocketVolley
extends Node3D
## Ripple salvo of a rocket launcher (TASK-011, TASK-074): one rocket per tube leaves its mouth
## SalvoTiming.interval() apart, flies a cubic Bézier that starts along the tube and comes down
## steeply on its landing point inside the target tile. Simple look: a small rocket mesh with a
## tail glow while the motor burns, a launch flash at the mouth and an impact flash (FlashFx); no
## particles, no lights. Richer effects plug in through `effects` (SalvoEffects, TASK-075).
##
## Everything visible is a pure function of the salvo time `t` (update(t)), so one tween drives
## it and its speed scale applies; launches and impacts are found with SalvoTiming.crossings over
## (previous t, t], so none is skipped or repeated however long the frames are. The node keeps an
## identity transform as top_level, so its children's positions are world positions (and the
## effect works outside the scene tree, e.g. in headless tests). Purely visual.

signal rocket_launched(index: int)
signal rocket_impacted(index: int, point: Vector3)

const APEX_BASE := 0.7
const APEX_PER_UNIT := 0.22
const APEX_MAX := 3.2
## Bézier handles: along the tube (fraction of the horizontal distance, at least MIN) and back
## from the target towards the launcher (fraction of the distance) at the apex height.
const TUBE_HANDLE := 0.35
const TUBE_HANDLE_MIN := 0.6
const DESCENT_HANDLE := 0.25
## Fallback for models without "Mouth*" tubes: origin above the unit, launch 45° up.
const FALLBACK_LIFT := 0.4
const FALLBACK_PITCH := PI / 4.0
## Rocket size in metres, at the launcher models' scale (model units per metre, see homar_k.gd K)
## times VisualScale.unit_model_scale(). Slightly fat (real ~0.22-0.24 m) to read at battle zoom.
const MODEL_UNITS_PER_METRE := 0.078
const ROCKET_LENGTH_M := 4.0
const ROCKET_DIAMETER_M := 0.3
const NOSE_FRACTION := 0.18
const GLOW_SIZE := 0.05
const BODY_COLOR := Color("#c9c5b2")
const NOSE_COLOR := Color("#3d3f3a")
const FLAME := Color("#ffb347")
const LAUNCH_FLASH_COLOR := Color("#fff4d6")
const LAUNCH_FLASH_SIZE := 0.16
const LAUNCH_FLASH_TIME := 0.1
const IMPACT_FLASH_COLOR := Color("#fff0b0")
const IMPACT_FLASH_SIZE := 0.5
const IMPACT_FLASH_TIME := 0.12
## Pod recoil per launch (elevation offset, rad) and the time it eases back.
const JOLT := 0.012
const JOLT_TIME := 0.12

## The salvo's effect hooks; the base class does nothing. Assign before setup().
var effects: SalvoEffects = SalvoEffects.new()
var count := 0
var interval := 0.35
var flight := 1.1

var _origins: Array[Vector3] = []
var _directions: Array[Vector3] = []
var _landings: Array[Vector3] = []
var _apexes: Array[float] = []
var _rockets: Array[Node3D] = []
var _glows: Array[MeshInstance3D] = []
var _launch_flashes: Array[FlashFx] = []
var _impact_flashes: Array[FlashFx] = []
var _last_positions: Array[Vector3] = []  # per rocket: its position at the previous update
var _last_t := -1.0
var _target_centre := Vector3.ZERO
var _shooter: UnitView  # jolted per launch when it has a launcher
var _jolt := 0.0  # pod offset last applied
var _begun := false
var _ended := false


## Apex height for a shot over world distance `distance` (longer shots fly higher).
static func apex_height(distance: float) -> float:
	return minf(APEX_BASE + APEX_PER_UNIT * distance, APEX_MAX)


static func _controls(from: Vector3, tube_dir: Vector3, to: Vector3, apex: float) -> Array[Vector3]:
	var horizontal := Vector2(to.x - from.x, to.z - from.z)
	var distance := horizontal.length()
	var back := Vector3.ZERO
	if distance > 0.0001:
		back = Vector3(-horizontal.x, 0.0, -horizontal.y) / distance
	var p1 := from + tube_dir.normalized() * maxf(TUBE_HANDLE_MIN, TUBE_HANDLE * distance)
	var p2 := to + back * DESCENT_HANDLE * distance + Vector3.UP * apex
	return [from, p1, p2, to]


## Point of a rocket's path at parameter `u` (clamped 0..1): a cubic Bézier from the mouth `from`
## out along `tube_dir`, over the apex and steeply down onto the landing point `to`.
static func path_point(
	from: Vector3, tube_dir: Vector3, to: Vector3, apex: float, u: float
) -> Vector3:
	var c := _controls(from, tube_dir, to, apex)
	var x := clampf(u, 0.0, 1.0)
	var y := 1.0 - x
	return (
		c[0] * (y * y * y)
		+ c[1] * (3.0 * y * y * x)
		+ c[2] * (3.0 * y * x * x)
		+ c[3] * (x * x * x)
	)


## Derivative of path_point with respect to `u` (the flight direction, not normalised).
static func path_tangent(
	from: Vector3, tube_dir: Vector3, to: Vector3, apex: float, u: float
) -> Vector3:
	var c := _controls(from, tube_dir, to, apex)
	var x := clampf(u, 0.0, 1.0)
	var y := 1.0 - x
	return (
		(c[1] - c[0]) * (3.0 * y * y)
		+ (c[2] - c[1]) * (6.0 * y * x)
		+ (c[3] - c[2]) * (3.0 * x * x)
	)


## Launch direction for a model without tubes: horizontally towards `to`, tilted up 45°.
static func fallback_direction(from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3.RIGHT
	return (flat.normalized() * cos(FALLBACK_PITCH) + Vector3.UP * sin(FALLBACK_PITCH)).normalized()


## Tube mouths and launch directions of `shooter` for a salvo at `target` (world): one per
## "Mouth*" node (UnitView.launch_points / launch_directions) or, without any, `fallback_count`
## copies of the fallback origin above the unit and fallback_direction. {"origins", "directions"}.
static func launch_frames(shooter: UnitView, target: Vector3, fallback_count: int) -> Dictionary:
	var origins := shooter.launch_points()
	var directions := shooter.launch_directions()
	if origins.is_empty():
		var origin := UnitModels.world_transform(shooter).origin + Vector3(0.0, FALLBACK_LIFT, 0.0)
		var direction := fallback_direction(origin, target)
		for i in fallback_count:
			origins.append(origin)
			directions.append(direction)
	return {"origins": origins, "directions": directions}


## One rocket per entry of `origins` (world mouth positions), each launched along `directions[i]`
## (normalised here) and landing on `landings[i]`; launches `launch_interval` apart, each flying
## `flight_time` seconds. `context` is passed to effects.begin() after the keys `volley`, `count`,
## `interval`, `flight` (and `target_centre`, `shooter` when missing) are filled in; a `shooter`
## with a launcher gets the pod jolt per launch.
func setup(
	origins: Array[Vector3],
	directions: Array[Vector3],
	landings: Array[Vector3],
	launch_interval: float,
	flight_time: float,
	context: Dictionary = {}
) -> void:
	assert(origins.size() == directions.size() and origins.size() == landings.size())
	top_level = true
	transform = Transform3D.IDENTITY
	count = origins.size()
	interval = launch_interval
	flight = flight_time
	_origins = origins
	_landings = landings
	_target_centre = Vector3.ZERO
	for i in count:
		_directions.append(directions[i].normalized())
		_target_centre += landings[i]
		var span := Vector2(landings[i].x - origins[i].x, landings[i].z - origins[i].z).length()
		_apexes.append(apex_height(span))
		_last_positions.append(origins[i])
	_target_centre /= maxf(1.0, count)
	_target_centre = context.get("target_centre", _target_centre)
	var shooter: UnitView = context.get("shooter")
	_shooter = shooter if shooter != null and shooter.has_launcher() else null
	_build_meshes()
	var full := context.duplicate()
	full["volley"] = self
	full["count"] = count
	full["interval"] = interval
	full["flight"] = flight
	full["target_centre"] = _target_centre
	full["shooter"] = shooter
	_begun = true
	effects.begin(full)


func _build_meshes() -> void:
	var s := MODEL_UNITS_PER_METRE * VisualScale.unit_model_scale()
	var length := ROCKET_LENGTH_M * s
	var radius := ROCKET_DIAMETER_M * s / 2.0
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = radius
	body_mesh.bottom_radius = radius
	body_mesh.height = length * (1.0 - NOSE_FRACTION)
	body_mesh.radial_segments = 8
	body_mesh.rings = 1
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = radius
	nose_mesh.height = length * NOSE_FRACTION
	nose_mesh.radial_segments = 8
	nose_mesh.rings = 1
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.5
	glow_mesh.height = 1.0
	glow_mesh.radial_segments = 8
	glow_mesh.rings = 4
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = BODY_COLOR
	body_material.roughness = 0.6
	var nose_material := StandardMaterial3D.new()
	nose_material.albedo_color = NOSE_COLOR
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = FLAME
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var body_length := length * (1.0 - NOSE_FRACTION)
	for i in count:
		var rocket := Node3D.new()
		rocket.name = "Rocket%d" % i
		# The rocket flies along its -Z (Basis.looking_at): cylinders' Y axis turned onto -Z.
		var body := _part(
			body_mesh, body_material, Vector3(0.0, 0.0, length / 2.0 - body_length / 2.0)
		)
		body.name = "Body"
		rocket.add_child(body)
		var nose := _part(
			nose_mesh,
			nose_material,
			Vector3(0.0, 0.0, -length / 2.0 + length * NOSE_FRACTION / 2.0)
		)
		nose.name = "Nose"
		rocket.add_child(nose)
		var glow := MeshInstance3D.new()
		glow.name = "Glow"
		glow.mesh = glow_mesh
		glow.material_override = flame_material
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.scale = Vector3.ONE * GLOW_SIZE
		glow.position = Vector3(0.0, 0.0, length / 2.0 + GLOW_SIZE * 0.3)
		glow.visible = false
		rocket.add_child(glow)
		rocket.visible = false
		add_child(rocket)
		_rockets.append(rocket)
		_glows.append(glow)
		var launch_flash := FlashFx.new().setup(
			LAUNCH_FLASH_COLOR, LAUNCH_FLASH_SIZE, LAUNCH_FLASH_TIME
		)
		launch_flash.position = _origins[i]
		add_child(launch_flash)
		_launch_flashes.append(launch_flash)
		var impact_flash := FlashFx.new().setup(
			IMPACT_FLASH_COLOR, IMPACT_FLASH_SIZE, IMPACT_FLASH_TIME
		)
		impact_flash.position = _landings[i]
		add_child(impact_flash)
		_impact_flashes.append(impact_flash)


static func _part(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.rotation.x = -PI / 2.0  # the cylinder's +Y (the cone's tip) onto -Z
	part.position = at
	return part


## Salvo time of the last impact (the HP reaches the event's value here).
func last_impact_time() -> float:
	return SalvoTiming.impact_time(count - 1, interval, flight)


## Salvo phase length (SalvoTiming.salvo_duration).
func duration() -> float:
	return SalvoTiming.salvo_duration(count, interval, flight)


## World position of rocket `index` at salvo time `t` (its mouth before launch, its landing point
## after impact).
func rocket_position(index: int, t: float) -> Vector3:
	var s := (t - SalvoTiming.launch_time(index, interval)) / flight
	if s >= 1.0:
		return _landings[index]
	var u := SalvoTiming.flight_progress(s)
	return path_point(_origins[index], _directions[index], _landings[index], _apexes[index], u)


## Poses the whole effect at salvo time `t` and fires the hooks and signals for every launch and
## impact in (previous t, t]. Going back in time only re-poses (no hooks).
func update(t: float) -> void:
	if count == 0:
		return
	var t0 := _last_t
	var forward := t > t0
	if forward:
		_last_t = t
	var crossed := (
		SalvoTiming.crossings(t0, t, count, interval, flight)
		if forward
		else {"launches": [], "impacts": []}
	)
	for i: int in crossed["launches"]:
		_last_positions[i] = _origins[i]
		effects.on_launch(i, _origins[i], _directions[i])
		rocket_launched.emit(i)
	for i in count:
		var launch := SalvoTiming.launch_time(i, interval)
		var s := (t - launch) / flight
		var flying := s >= 0.0 and s < 1.0
		var rocket := _rockets[i]
		rocket.visible = flying
		_glows[i].visible = flying and s < SalvoTiming.MOTOR_BURN
		if flying:
			_pose_rocket(i, s)
		if forward and launch <= t and launch + flight > t0:
			var to := rocket_position(i, t)
			effects.on_flight(i, _last_positions[i], to, minf(s, 1.0), s < SalvoTiming.MOTOR_BURN)
			_last_positions[i] = to
		_launch_flashes[i].pose(t - launch)
		_impact_flashes[i].pose(t - launch - flight)
	for i: int in crossed["impacts"]:
		effects.on_impact(i, _landings[i], i == 0, i == count - 1)
		rocket_impacted.emit(i, _landings[i])
	_apply_jolt(t)


func _pose_rocket(index: int, s: float) -> void:
	var u := SalvoTiming.flight_progress(s)
	var here := path_point(_origins[index], _directions[index], _landings[index], _apexes[index], u)
	var ahead := path_tangent(
		_origins[index], _directions[index], _landings[index], _apexes[index], u
	)
	var rocket := _rockets[index]
	if ahead.length_squared() < 0.000001:
		rocket.position = here
		return
	var up := Vector3.UP if absf(ahead.normalized().y) < 0.999 else Vector3.RIGHT
	rocket.transform = Transform3D(Basis.looking_at(ahead, up), here)


## The pod kicks back by JOLT at every launch and eases to the aim pose over JOLT_TIME.
func _apply_jolt(t: float) -> void:
	if _shooter == null or not is_instance_valid(_shooter) or t < 0.0:
		return
	var latest := mini(count - 1, floori(t / interval + 0.000001))
	var age := t - SalvoTiming.launch_time(latest, interval)
	var offset := 0.0
	if age < JOLT_TIME:
		offset = -JOLT * (1.0 - smoothstep(0.0, JOLT_TIME, age))
	if offset != _jolt:
		_jolt = offset
		_shooter.set_launcher_jolt(offset)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _begun and not _ended:
		_ended = true
		if _jolt != 0.0 and _shooter != null and is_instance_valid(_shooter):
			_shooter.set_launcher_jolt(0.0)
		effects.end(_target_centre)
