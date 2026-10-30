class_name SalvoFxPool
extends Node3D
## Pooled effects of rocket salvos (TASK-075), the HIGH implementation of SalvoEffects:
## - launch: a short column of motor fire out of the tube, a flash of fire at the tube's rear and
##   billowing smoke and dust clouds behind the launcher that build up over the salvo;
## - flight: a thin dark smoke trail per rocket while its motor burns (SalvoTrail ribbons);
## - impact: a fireball, dark smoke, dust thrown up and rolling along the ground, a smoke column
##   that lingers over the target, short light pulses and a small camera shake.
## The puffs live in one world-space GPUParticles3D per layer for the whole battle, simulated by
## assets/shaders/smoke_particles.gdshader (drag towards the wind drift, rise, gravity) and drawn
## by smoke_puff / fire_puff (sun-lit soft puffs / additive fire, ParticleFx.puff_emitter); every
## volley emits into them
## with emit_particle() – no particle node is ever created per volley. Trails are a fixed set of
## reused ribbons. The per-volley nodes (flame cones, two OmniLight3D) are children of the
## RocketVolley and are freed with it. Purely visual: own RNG, never GameState.rng.
##
## Usage: the battle creates one pool when `quality["particles"]` (SalvoFxPool.create) and
## assigns `SalvoFxPool.effects(pool, quality)` to each volley's `effects`.

const LAYER_AMOUNTS := {&"fire": 192, &"smoke": 256, &"blast": 256, &"dust": 256, &"debris": 128}
const MAX_PARTICLES := 1250
const TRAILS := 20

## Puffs per launch (behind the launcher) and per impact.
const BACKBLAST_FIRE := 3
const BACKBLAST_SMOKE := 8
const BACKBLAST_DUST := 5
const FIREBALL := 8
const IMPACT_SMOKE := 5
const DEBRIS := 7
const DUST_RING := 8
const COLUMN_PER_IMPACT := 2
## Pod length along its +X when the pod has no meshes (world units).
const POD_LENGTH_FALLBACK := 0.4
## A trail gets a new point every TRAIL_SPACING world units of the rocket's path.
const TRAIL_SPACING := 0.07
## Smoke column: how long after the last impact it is still fed, how many are fed at once, and the
## feed rate (puffs per second) right after the last impact (it decays linearly to 0).
const COLUMN_LINGER := 4.0
const MAX_COLUMNS := 2
const COLUMN_FEED_RATE := 5.0
const COLUMN_SPREAD := 0.3

## Motor fire at launch: full length (world units) shortly after the launch, gone after
## PLUME_TIME seconds – the motor's flame is only shown while the rocket leaves the tube.
const PLUME_LENGTH := 1.0
const PLUME_WIDTH := 0.11
const PLUME_TIME := 0.32
const LAUNCH_LIGHT := Color("#ffb060")
const LAUNCH_LIGHT_ENERGY := 4.0
const LAUNCH_LIGHT_TIME := 0.25
const LAUNCH_LIGHT_RANGE := 2.5
const IMPACT_LIGHT := Color("#ffa050")
const IMPACT_LIGHT_ENERGY := 8.0
const IMPACT_LIGHT_TIME := 0.25
const IMPACT_LIGHT_RANGE := 3.0
const SPRAY := Color("#e8eef0")
const BACKBLAST_SMOKE_COLOR := Color("#b3aea4")
const IMPACT_SMOKE_COLOR := Color("#45413c")
const COLUMN_COLOR := Color("#58534c")

## Position, velocity, colour (tint and opacity), an identity basis and the custom data the
## process shader reads (x rotation, y age, z size, w lifetime fraction): left unset, a recycled
## slot keeps stale values.
const EMIT_FLAGS := (
	GPUParticles3D.EMIT_FLAG_POSITION
	| GPUParticles3D.EMIT_FLAG_ROTATION_SCALE
	| GPUParticles3D.EMIT_FLAG_VELOCITY
	| GPUParticles3D.EMIT_FLAG_COLOR
	| GPUParticles3D.EMIT_FLAG_CUSTOM
)
const SEED := 7500
const PLUME_SHADER := preload("res://assets/shaders/salvo_plume.gdshader")

static var _cone_mesh: CylinderMesh
static var _plume_material: ShaderMaterial

## The camera that shakes at every impact (set by the battle; null = no shake).
var camera_rig: CameraRig
## Particles emitted per layer since creation, and trail points laid under &"trail" (tests).
var emitted: Dictionary = {}

var _layers: Dictionary = {}  # StringName -> GPUParticles3D
var _trails: Array[SalvoTrail] = []
var _columns: Array[Dictionary] = []  # lingering columns: {position, age, carry}
var _rng := RandomNumberGenerator.new()
var _wind := Vector3.ZERO  # horizontal drift of smoke (world units / s)


## `bounds`: the map rectangle in XZ (the particles' and trails' culling box).
func _init(bounds := Rect2(-60.0, -60.0, 120.0, 120.0)) -> void:
	name = "SalvoFxPool"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = SEED
	var dir := Wind.DIRECTION.normalized()
	_wind = Vector3(dir.x, 0.0, dir.y) * Wind.STRENGTH * 0.25
	var aabb := AABB(
		Vector3(bounds.position.x - 4.0, -4.0, bounds.position.y - 4.0),
		Vector3(bounds.size.x + 8.0, 14.0, bounds.size.y + 8.0)
	)
	for layer: StringName in LAYER_AMOUNTS:
		var particles := _make_layer(layer)
		particles.visibility_aabb = aabb
		add_child(particles)
		_layers[layer] = particles
		emitted[layer] = 0
		# Warm-up: one particle 50 units below the map (never seen) compiles the layer's shaders
		# now, not at the first salvo.
		_emit(layer, Vector3(0.0, -50.0, 0.0), Vector3.ZERO, Color.WHITE, 1.0, 0.1)
		emitted[layer] = 0
	for i in TRAILS:
		var trail := SalvoTrail.new(aabb)
		add_child(trail)
		_trails.append(trail)
	emitted[&"trail"] = 0


## The pool for a battle, added to `parent`; null (no particles, no pool) when `quality` has them
## off. `rig` is shaken by impacts. Smoke is lit by `parent`'s "Sun" light when it has one.
static func create(parent: Node, quality: Dictionary, bounds: Rect2, rig: CameraRig) -> SalvoFxPool:
	if not quality.get("particles", false):
		return null
	var pool := SalvoFxPool.new(bounds)
	pool.camera_rig = rig
	parent.add_child(pool)
	var sun := parent.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		pool.set_sun(sun.global_transform.basis.z, sun.light_color)
	pool.warm_up(bounds.get_center(), quality.get("fx_lights", false))
	return pool


## Lights the smoke from world direction `towards_sun` with `color`.
func set_sun(towards_sun: Vector3, color: Color) -> void:
	for layer: StringName in _layers:
		var material := (_layers[layer] as GPUParticles3D).draw_pass_1.surface_get_material(0)
		if (material as ShaderMaterial).shader == ParticleFx.SMOKE_SHADER:
			material.set_shader_parameter("sun_dir", towards_sun.normalized())
			material.set_shader_parameter("lit_color", color.lerp(Color.WHITE, 0.4))


## Shows one tiny instance of every per-volley node type (flame cone, trail, light) for a moment
## at `centre` (XZ), so their shaders and the light variant compile at battle start, not as a
## hitch at the first salvo. The nodes stay but are invisible.
func warm_up(centre: Vector2, with_lights: bool) -> void:
	var warm := Node3D.new()
	warm.name = "WarmUp"
	warm.position = Vector3(centre.x, 0.0, centre.y)
	var plume := make_plume()
	plume.visible = true
	plume.scale = Vector3.ONE * 0.001
	warm.add_child(plume)
	if with_lights:
		var light := SalvoLight.new().setup(LAUNCH_LIGHT, 0.01, 1.0, 0.1)
		light.light_energy = 0.01
		warm.add_child(light)
	add_child(warm)
	var below := Vector3(centre.x, -50.0, centre.y)
	_trails[0].start(below)
	_trails[0].extend([below + Vector3.UP * 0.1] as Array[Vector3], below + Vector3.UP * 0.2)
	_trails[0].stop()
	emitted[&"trail"] = 0


## The effects object for a volley: the pool's implementation when the pool exists and `quality`
## allows particles, otherwise the no-op base (LOW: mesh-only salvo).
static func effects(pool: SalvoFxPool, quality: Dictionary) -> SalvoEffects:
	if pool == null or not quality.get("particles", false):
		return SalvoEffects.new()
	return pool.effects_for_volley(quality.get("fx_lights", false))


## Pool implementation of SalvoEffects for one volley. Without `with_impacts` only the launch and
## the flight show (the unit catalog's rockets land far off-screen, over no ground).
func effects_for_volley(with_lights := true, with_impacts := true) -> SalvoEffects:
	return VolleyFx.new(self, with_lights, with_impacts)


## Direction the backblast leaves in: opposite to the tube horizontally, but never into the ground
## (a raised pod points its rear at the dirt, so the downward part turns into a sideways one).
static func backblast_dir(tube_dir: Vector3) -> Vector3:
	var back := -tube_dir.normalized()
	return Vector3(back.x, absf(back.y) * 0.25 + 0.1, back.z).normalized()


## Dust colour over `terrain` (a Terrain.Type name, plains if unknown); water: none (alpha 0), or
## white spray when `spray_on_water`.
static func dust_for(terrain: StringName, spray_on_water: bool) -> Color:
	var key := String(terrain).to_upper()
	var type: int = Terrain.Type[key] if Terrain.Type.has(key) else Terrain.Type.PLAINS
	if type == Terrain.Type.WATER and spray_on_water:
		return SPRAY
	return MotionEffects.dust_color(type)


## World point where the rear of the launch tube is: `pod_length` behind the mouth, opposite to
## the launch direction (the backblast leaves from here).
static func backblast_origin(mouth: Vector3, tube_dir: Vector3, pod_length: float) -> Vector3:
	return mouth - tube_dir.normalized() * pod_length


## Length of the pod along its +X from its meshes (world units), POD_LENGTH_FALLBACK without any.
static func pod_length(shooter: UnitView) -> float:
	if shooter == null or not is_instance_valid(shooter):
		return POD_LENGTH_FALLBACK
	var pod := UnitModels.launcher_pod(shooter.model())
	if pod == null:
		return POD_LENGTH_FALLBACK
	var low := INF
	var high := -INF
	var pod_xf := UnitModels.world_transform(pod)
	for node in pod.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var to_pod := pod_xf.affine_inverse() * UnitModels.world_transform(instance)
		var box := instance.mesh.get_aabb()
		for corner in 8:
			var point := to_pod * box.get_endpoint(corner)
			low = minf(low, point.x)
			high = maxf(high, point.x)
	if high <= low:
		return POD_LENGTH_FALLBACK
	# Local lengths to world: the pod's own scale in the world.
	return (high - low) * pod_xf.basis.x.length()


## Smoke-trail puffs along `from -> to`: one every `spacing` world units, `carry` = distance
## travelled since the last puff (0..spacing). Returns {"points": Array[Vector3], "carry": float}
## with the carry to pass to the next call, so uneven segments leave no gaps and no duplicates.
static func trail_points(from: Vector3, to: Vector3, spacing: float, carry: float) -> Dictionary:
	var points: Array[Vector3] = []
	var length := from.distance_to(to)
	if length < 0.000001 or spacing <= 0.0:
		return {"points": points, "carry": carry}
	var d := spacing - carry
	var last := -carry  # distance along the segment of the last puff (before it: the carry)
	while d <= length + 0.0000001:
		points.append(from.lerp(to, minf(d / length, 1.0)))
		last = d
		d += spacing
	return {"points": points, "carry": length - last}


## Motor fire length (world units) and brightness `age` seconds after the launch: it flares up
## within a few hundredths of a second and is gone at PLUME_TIME. {"length", "intensity"}.
static func plume_at(age: float) -> Dictionary:
	if age < 0.0 or age >= PLUME_TIME:
		return {"length": 0.0, "intensity": 0.0}
	var left := 1.0 - age / PLUME_TIME
	return {
		"length": PLUME_LENGTH * smoothstep(0.0, 0.03, age) * pow(left, 0.6),
		"intensity": pow(left, 1.2),
	}


## Shakes the camera for an impact at `point`, by its distance from the camera.
func shake_at(point: Vector3) -> void:
	if camera_rig == null or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		camera_rig.add_shake(CameraRig.shake_strength(camera.global_position.distance_to(point)))


## Number of columns being fed now.
func column_count() -> int:
	return _columns.size()


## Hands a column at `position` to the linger list (called at the end of a volley). The oldest
## column stops early when MAX_COLUMNS are already fed.
func add_column(position: Vector3) -> void:
	_columns.append({"position": position, "age": 0.0, "carry": 0.0})
	while _columns.size() > MAX_COLUMNS:
		_columns.pop_front()


## A trail ribbon for a new rocket: a faded one if any, else the oldest.
func acquire_trail() -> SalvoTrail:
	var oldest := _trails[0]
	for trail in _trails:
		if not trail.is_active():
			return trail
		if trail.age() > oldest.age():
			oldest = trail
	return oldest


## Trails that are growing or still visible.
func active_trails() -> int:
	return _trails.filter(func(trail: SalvoTrail) -> bool: return trail.is_active()).size()


func _process(delta: float) -> void:
	advance(delta)


## Feeds the lingering columns for `delta` seconds and drops those older than COLUMN_LINGER.
func advance(delta: float) -> void:
	for column in _columns:
		var age: float = column["age"]
		var rate := COLUMN_FEED_RATE * clampf(1.0 - age / COLUMN_LINGER, 0.0, 1.0)
		var carry: float = column["carry"] + rate * delta
		var n := int(carry)
		column["carry"] = carry - n
		column["age"] = age + delta
		for i in n:
			emit_column(column["position"], 1)
	var alive: Array[Dictionary] = []
	for column in _columns:
		if column["age"] < COLUMN_LINGER:
			alive.append(column)
	_columns = alive


# --- emitting ----------------------------------------------------------------------------


## One puff on `layer`: `tint` (sRGB, alpha = opacity), `size` x the layer's size curve, `life` x
## the layer's lifetime.
func _emit(
	layer: StringName, position: Vector3, velocity: Vector3, tint: Color, size: float, life: float
) -> void:
	var particles: GPUParticles3D = _layers[layer]
	var linear := tint.srgb_to_linear()
	linear.a = tint.a
	particles.emit_particle(
		Transform3D(Basis.IDENTITY, position),
		velocity,
		linear,
		Color(_rng.randf() * TAU, 0.0, size, life),
		EMIT_FLAGS
	)
	emitted[layer] += 1


## Random unit vector within `half_angle_deg` of `axis`.
func _cone(axis: Vector3, half_angle_deg: float) -> Vector3:
	var a := axis.normalized()
	var helper := Vector3.UP if absf(a.y) < 0.95 else Vector3.RIGHT
	var u := a.cross(helper).normalized()
	var v := a.cross(u)
	var angle := deg_to_rad(half_angle_deg) * sqrt(_rng.randf())
	var around := _rng.randf() * TAU
	return (a * cos(angle) + (u * cos(around) + v * sin(around)) * sin(angle)).normalized()


func _jitter(amount: float) -> Vector3:
	return Vector3(
		_rng.randf_range(-amount, amount),
		_rng.randf_range(-amount, amount),
		_rng.randf_range(-amount, amount)
	)


func _range(low: float, high: float) -> float:
	return _rng.randf_range(low, high)


## Launch: a flash of fire at the tube's rear, smoke billowing out behind it and dust blown off the
## ground under it (`dust` alpha 0 = none, e.g. water).
func emit_backblast(rear: Vector3, tube_dir: Vector3, ground_y: float, dust: Color) -> void:
	var back := backblast_dir(tube_dir)
	for i in BACKBLAST_FIRE:
		var velocity := _cone(back, 20.0) * _range(1.5, 2.5)
		var size := _range(0.9, 1.2)
		_emit(&"fire", rear + _jitter(0.03), velocity, Color.WHITE, size, _range(0.35, 0.5))
	for i in BACKBLAST_SMOKE:
		var velocity := _cone(back, 35.0) * _range(1.2, 3.0)
		var tint := Color(BACKBLAST_SMOKE_COLOR, _range(0.5, 0.7))
		_emit(&"blast", rear + _jitter(0.06), velocity, tint, _range(0.8, 1.3), _range(0.65, 1.0))
	if dust.a <= 0.0:
		return
	var flat := Vector3(back.x, 0.0, back.z).normalized()
	if flat == Vector3.ZERO:
		flat = Vector3.FORWARD
	var ground := Vector3(rear.x, ground_y + 0.08, rear.z) + flat * 0.2
	for i in BACKBLAST_DUST:
		var spread := flat.rotated(Vector3.UP, _range(-1.0, 1.0))
		var velocity := spread * _range(1.2, 2.4) + Vector3.UP * _range(0.1, 0.3)
		var tint := Color(dust, _range(0.45, 0.6))
		var at := ground + _jitter(0.08) * Vector3(1, 0, 1)
		_emit(&"dust", at, velocity, tint, _range(0.8, 1.2), _range(0.6, 1.0))


## Impact at `point`: a fireball, dark smoke, dust thrown up and rolling out along the ground
## (`dust`: its colour, alpha 0 = none).
func emit_impact(point: Vector3, dust: Color) -> void:
	for i in FIREBALL:
		var velocity := Vector3(_range(-0.8, 0.8), _range(0.6, 1.6), _range(-0.8, 0.8))
		var at := point + Vector3(0, 0.12, 0) + _jitter(0.06)
		_emit(&"fire", at, velocity, Color.WHITE, _range(0.8, 1.2), _range(0.6, 1.0))
	for i in IMPACT_SMOKE:
		var velocity := Vector3(_range(-0.4, 0.4), _range(0.8, 1.4), _range(-0.4, 0.4))
		var tint := Color(IMPACT_SMOKE_COLOR, _range(0.7, 0.9))
		var at := point + Vector3(0, 0.15, 0) + _jitter(0.08)
		_emit(&"smoke", at, velocity, tint, _range(1.0, 1.4), _range(0.55, 0.9))
	if dust.a <= 0.0:
		return
	for i in DEBRIS:
		var velocity := _cone(Vector3.UP, 35.0) * _range(2.5, 4.0)
		var tint := Color(dust.darkened(0.25), _range(0.85, 1.0))
		_emit(&"debris", point + _jitter(0.05), velocity, tint, _range(0.8, 1.2), _range(0.6, 1.0))
	for i in DUST_RING:
		var around := (float(i) + _rng.randf()) / DUST_RING * TAU
		var velocity := Vector3(cos(around), 0.05, sin(around)) * _range(1.8, 2.8)
		var tint := Color(dust.lightened(0.1), _range(0.6, 0.75))
		var at := point + Vector3(0, 0.08, 0)
		_emit(&"dust", at, velocity, tint, _range(0.9, 1.2), _range(0.6, 1.0))


## `count` large dark puffs of a smoke column at `position`.
func emit_column(position: Vector3, count: int) -> void:
	for i in count:
		var velocity := Vector3(_range(-0.1, 0.1), _range(0.5, 0.8), _range(-0.1, 0.1)) + _wind
		var spread := Vector3(_range(-1, 1), 0.0, _range(-1, 1)) * COLUMN_SPREAD
		var tint := Color(COLUMN_COLOR, _range(0.55, 0.75))
		var at := position + Vector3(0, 0.3, 0) + spread
		_emit(&"smoke", at, velocity, tint, _range(1.2, 1.6), _range(0.8, 1.0))


# --- layers ------------------------------------------------------------------------------


## Physics, size and colour over life per layer. Ramps multiply the emitted tint.
func _layer_config(layer: StringName) -> Dictionary:
	match layer:
		&"fire":
			return {
				"lifetime": 0.8,
				"drag": 3.5,
				"rise": 0.6,
				"size_start": 0.15,
				"size_end": 0.7,
				"grow": 2.0,
				"fire": true,
				# White-hot -> orange -> deep red -> nothing (additive).
				"ramp":
				[
					0.0,
					Color("#fff6d8", 1.0),
					0.15,
					Color("#ffc060", 1.0),
					0.45,
					Color("#ff6a1a", 0.7),
					0.75,
					Color("#8a2a0a", 0.3),
					1.0,
					Color("#200800", 0.0),
				],
			}
		&"smoke":
			return {
				"lifetime": 7.0,
				"drag": 1.8,
				"rise": 0.28,
				"size_start": 0.18,
				"size_end": 1.3,
				"grow": 2.5,
				# Hidden behind the fire for a moment, then dense, thinning and paling as it spreads.
				"ramp":
				[
					0.0,
					Color(0.85, 0.85, 0.85, 0.0),
					0.04,
					Color(0.85, 0.85, 0.85, 1.0),
					0.35,
					Color(0.92, 0.92, 0.92, 0.75),
					1.0,
					Color(1.0, 1.0, 1.0, 0.0),
				],
			}
		&"blast":  # backblast cloud: spreads wide and low, rises slowly
			return {
				"lifetime": 6.5,
				"drag": 2.0,
				"rise": 0.1,
				"size_start": 0.2,
				"size_end": 1.4,
				"grow": 2.5,
				"ramp":
				[
					0.0,
					Color(1, 1, 1, 0.0),
					0.04,
					Color(1, 1, 1, 1.0),
					0.4,
					Color(1, 1, 1, 0.7),
					1.0,
					Color(1, 1, 1, 0.0),
				],
			}
		&"debris":
			return {
				"lifetime": 2.2,
				"drag": 1.3,
				"rise": 0.0,
				"gravity": 5.0,
				"size_start": 0.06,
				"size_end": 0.5,
				"grow": 1.5,
				"ramp":
				[
					0.0,
					Color(1, 1, 1, 0.0),
					0.05,
					Color(1, 1, 1, 1.0),
					0.6,
					Color(1, 1, 1, 0.7),
					1.0,
					Color(1, 1, 1, 0.0)
				],
			}
		_:  # dust: rolls out along the ground, hardly rises
			return {
				"lifetime": 4.0,
				"drag": 2.2,
				"rise": 0.06,
				"size_start": 0.12,
				"size_end": 0.8,
				"grow": 2.5,
				"ramp":
				[
					0.0,
					Color(1, 1, 1, 0.0),
					0.06,
					Color(1, 1, 1, 1.0),
					0.4,
					Color(1, 1, 1, 0.7),
					1.0,
					Color(1, 1, 1, 0.0)
				],
			}


## A resting world-space emitter of `layer` that only shows what emit_particle() adds.
func _make_layer(layer: StringName) -> GPUParticles3D:
	var config := _layer_config(layer)
	config["amount"] = LAYER_AMOUNTS[layer]
	config["wind"] = _wind
	var particles := ParticleFx.puff_emitter(config)
	particles.name = String(layer).capitalize()
	particles.amount_ratio = 1.0
	return particles


## The motor's flame behind a rocket: one additive cone pointing its -Z along the flight, the
## flame extending along +Z, scaled by the plume's Z scale (its length).
static func make_plume() -> Node3D:
	var plume := Node3D.new()
	plume.name = "Plume"
	plume.visible = false
	if _cone_mesh == null:
		_cone_mesh = CylinderMesh.new()
		_cone_mesh.top_radius = 0.0
		_cone_mesh.bottom_radius = 0.5
		_cone_mesh.height = 1.0
		_cone_mesh.radial_segments = 12
		_cone_mesh.rings = 4
		_cone_mesh.cap_top = false
		_cone_mesh.cap_bottom = false
	if _plume_material == null:
		_plume_material = ShaderMaterial.new()
		_plume_material.shader = PLUME_SHADER
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	flame.mesh = _cone_mesh
	flame.material_override = _plume_material
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cylinder +Y (the cone's tip) onto +Z; the base sits at the plume origin.
	flame.rotation.x = PI / 2.0
	flame.scale = Vector3(PLUME_WIDTH, 1.0, PLUME_WIDTH)
	flame.position = Vector3(0.0, 0.0, 0.5)
	plume.add_child(flame)
	return plume


## The pool's implementation of SalvoEffects for one volley.
class VolleyFx:
	extends SalvoEffects

	var _pool: SalvoFxPool
	var _with_lights: bool
	var _with_impacts: bool
	var _volley: Node3D
	var _shooter: UnitView
	var _pod_length := SalvoFxPool.POD_LENGTH_FALLBACK
	var _ground_y := 0.0
	var _launcher_dust := Color(0, 0, 0, 0)
	var _target_dust := Color(0, 0, 0, 0)
	var _target_centre := Vector3.ZERO
	var _flight := 1.1
	var _carries: Dictionary = {}  # rocket index -> distance since its last trail point
	var _trails: Dictionary = {}  # rocket index -> SalvoTrail
	var _plumes: Dictionary = {}  # rocket index -> Node3D
	var _launch_light: SalvoLight
	var _impact_light: SalvoLight
	var _rocket_length := 0.3

	func _init(pool: SalvoFxPool, with_lights: bool, with_impacts: bool) -> void:
		_pool = pool
		_with_lights = with_lights
		_with_impacts = with_impacts

	func begin(context: Dictionary) -> void:
		_volley = context["volley"]
		_shooter = context.get("shooter")
		_target_centre = context["target_centre"]
		_flight = context["flight"]
		_pod_length = SalvoFxPool.pod_length(_shooter)
		_ground_y = _target_centre.y
		if _shooter != null and is_instance_valid(_shooter):
			_ground_y = UnitModels.world_transform(_shooter).origin.y
		_launcher_dust = SalvoFxPool.dust_for(context.get("launcher_terrain", &"plains"), false)
		_target_dust = SalvoFxPool.dust_for(context.get("target_terrain", &"plains"), true)
		_rocket_length = (
			RocketVolley.ROCKET_LENGTH_M
			* RocketVolley.MODEL_UNITS_PER_METRE
			* VisualScale.unit_model_scale()
		)
		if _with_lights:
			_launch_light = SalvoLight.new().setup(
				SalvoFxPool.LAUNCH_LIGHT,
				SalvoFxPool.LAUNCH_LIGHT_ENERGY,
				SalvoFxPool.LAUNCH_LIGHT_TIME,
				SalvoFxPool.LAUNCH_LIGHT_RANGE
			)
			_impact_light = SalvoLight.new().setup(
				SalvoFxPool.IMPACT_LIGHT,
				SalvoFxPool.IMPACT_LIGHT_ENERGY,
				SalvoFxPool.IMPACT_LIGHT_TIME,
				SalvoFxPool.IMPACT_LIGHT_RANGE
			)
			_volley.add_child(_launch_light)
			_volley.add_child(_impact_light)

	func on_launch(index: int, mouth: Vector3, tube_dir: Vector3) -> void:
		var rear := SalvoFxPool.backblast_origin(mouth, tube_dir, _pod_length)
		_pool.emit_backblast(rear, tube_dir, _ground_y, _launcher_dust)
		_carries[index] = 0.0
		var trail := _pool.acquire_trail()
		trail.start(mouth)
		_trails[index] = trail
		if _launch_light != null:
			_launch_light.position = rear
			_launch_light.pulse()

	func on_flight(index: int, from: Vector3, to: Vector3, s: float, motor: bool) -> void:
		var trail: SalvoTrail = _trails.get(index)
		var step := to - from
		_pose_plume(index, step, to, s * _flight)
		if trail == null:
			return
		if not motor:
			trail.stop()
			return
		var result := SalvoFxPool.trail_points(
			from, to, SalvoFxPool.TRAIL_SPACING, _carries.get(index, 0.0)
		)
		_carries[index] = result["carry"]
		var points: Array[Vector3] = result["points"]
		trail.extend(points, to)
		_pool.emitted[&"trail"] += points.size()

	func on_impact(index: int, point: Vector3, _first: bool, _last: bool) -> void:
		var trail: SalvoTrail = _trails.get(index)
		if trail != null:
			trail.stop()
		if not _with_impacts:
			return
		_pool.emit_impact(point, _target_dust)
		_pool.emit_column(_target_centre, SalvoFxPool.COLUMN_PER_IMPACT)
		if _impact_light != null:
			_impact_light.position = point + Vector3(0, 0.3, 0)
			_impact_light.pulse()
		_pool.shake_at(point)

	func end(target_centre: Vector3) -> void:
		for index: int in _trails:
			if is_instance_valid(_trails[index]):
				(_trails[index] as SalvoTrail).stop()
		if _with_impacts and is_instance_valid(_pool):
			_pool.add_column(target_centre)

	## The flame `age` seconds after the launch, behind the rocket's tail (hidden after PLUME_TIME).
	func _pose_plume(index: int, step: Vector3, to: Vector3, age: float) -> void:
		var shape := SalvoFxPool.plume_at(age)
		var length: float = shape["length"]
		var plume: Node3D = _plumes.get(index)
		if length <= 0.001 or step.length_squared() < 0.0000001:
			if plume != null and length <= 0.001:
				plume.visible = false
			return
		if plume == null:
			plume = SalvoFxPool.make_plume()
			_plumes[index] = plume
			_volley.add_child(plume)
		var dir := step.normalized()
		var up := Vector3.UP if absf(dir.y) < 0.999 else Vector3.RIGHT
		plume.transform = Transform3D(
			Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1.0, 1.0, length)),
			to - dir * _rocket_length * 0.5
		)
		var flame := plume.get_child(0) as MeshInstance3D
		flame.set_instance_shader_parameter("intensity", shape["intensity"])
		flame.set_instance_shader_parameter("seed", float(index) * 7.3)
		plume.visible = true


## An OmniLight3D that flashes at `pulse()` and fades to 0 in real time (no shadow).
class SalvoLight:
	extends OmniLight3D

	var _energy := 1.0
	var _life := 0.1
	var _age := 1.0

	func setup(color: Color, energy: float, life: float, light_range: float) -> SalvoLight:
		light_color = color
		omni_range = light_range
		shadow_enabled = false
		process_mode = Node.PROCESS_MODE_ALWAYS
		_energy = energy
		_life = life
		light_energy = 0.0
		return self

	func pulse() -> void:
		_age = 0.0
		light_energy = _energy

	func _process(delta: float) -> void:
		if _age >= _life:
			return
		_age += delta
		light_energy = _energy * clampf(1.0 - _age / _life, 0.0, 1.0)
