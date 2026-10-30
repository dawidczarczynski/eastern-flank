class_name VolleyPlayback
extends RefCounted
## Tween steps of a rocket volley, shared by the battle (BattleController) and the unit catalog:
## deploy jacks and shields, raise the launcher, traverse, fire the salvo, stow again. Every
## step is appended to a caller-owned Tween, so the caller decides the speed scale and waits for
## `finished`. Purely visual – a `shooter` is any UnitView.

## Turntable launchers (Homar-K, Uragan) aim the launcher: the pod rises on its actuators to the
## unit's max elevation, the turntable turns to the target, and after the salvo both return to the
## stowed pose (seconds at speed 1, each way; global pacing, not per unit).
const LAUNCHER_RAISE_DURATION := 0.9
const LAUNCHER_TRAVERSE_DURATION := 0.9
## Jacks down / shields closed before a volley and back after it (seconds at speed 1, each way).
const DEPLOY_DURATION := 0.6
## A tank turns its turret and elevates its gun this long before / after the hit (seconds at
## speed 1, each way; global pacing).
const TURRET_AIM_DURATION := 0.5


## Appends the deploy (0 -> 1) or stow (1 -> 0) step of jacks and shields, eased in and out.
static func tween_deploy(tween: Tween, shooter: UnitView, from: float, to: float) -> void:
	var step := tween.tween_method(
		func(f: float) -> void:
			if is_instance_valid(shooter):
				shooter.set_deploy_pose(lerpf(from, to, f)),
		0.0,
		1.0,
		DEPLOY_DURATION
	)
	step.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Appends a launcher step from pose `from` to `to` (x traverse, y elevation, both in radians),
## eased in and out like a hydraulic drive.
static func tween_launcher(
	tween: Tween, shooter: UnitView, from: Vector2, to: Vector2, duration: float
) -> void:
	var step := tween.tween_method(
		func(f: float) -> void:
			if is_instance_valid(shooter):
				var pose := from.lerp(to, f)
				shooter.set_launcher_pose(pose.x, pose.y),
		0.0,
		1.0,
		duration
	)
	step.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Appends a turret step from pose `from` to `to` (x traverse, y gun elevation, radians), eased in
## and out.
static func tween_turret(
	tween: Tween, shooter: UnitView, from: Vector2, to: Vector2, duration: float
) -> void:
	var step := tween.tween_method(
		func(f: float) -> void:
			if is_instance_valid(shooter):
				var pose := from.lerp(to, f)
				shooter.set_turret_pose(pose.x, pose.y),
		0.0,
		1.0,
		duration
	)
	step.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Appends a turn of the whole vehicle by `turn` radians from its heading at the time of the call.
static func tween_body_turn(tween: Tween, shooter: UnitView, turn: float, duration: float) -> void:
	var from_yaw := shooter.facing_yaw()
	tween.tween_method(
		func(f: float) -> void:
			if is_instance_valid(shooter):
				shooter.set_facing_yaw(from_yaw + turn * f),
		0.0,
		1.0,
		duration
	)


## Appends the steps before the salvo: deploy (when the model has jacks / shields), raise the pod
## to `elevation`, traverse to `traverse` (radians).
static func append_aim(tween: Tween, shooter: UnitView, traverse: float, elevation: float) -> void:
	if shooter.has_deployables():
		tween_deploy(tween, shooter, 0.0, 1.0)
	tween_launcher(tween, shooter, Vector2.ZERO, Vector2(0.0, elevation), LAUNCHER_RAISE_DURATION)
	tween_launcher(
		tween,
		shooter,
		Vector2(0.0, elevation),
		Vector2(traverse, elevation),
		LAUNCHER_TRAVERSE_DURATION
	)


## Appends the steps after the salvo, the reverse of append_aim: traverse back, lower the pod,
## stow jacks and shields.
static func append_stow(tween: Tween, shooter: UnitView, traverse: float, elevation: float) -> void:
	tween_launcher(
		tween,
		shooter,
		Vector2(traverse, elevation),
		Vector2(0.0, elevation),
		LAUNCHER_TRAVERSE_DURATION
	)
	tween_launcher(tween, shooter, Vector2(0.0, elevation), Vector2.ZERO, LAUNCHER_RAISE_DURATION)
	if shooter.has_deployables():
		tween_deploy(tween, shooter, 1.0, 0.0)


## Salvo parameters of `unit_id` with `mouth_count` tubes firing over the horizontal world
## `distance`: {"count", "interval", "flight"} (SalvoTiming). The event annotation and the
## playback both use it, so the queued duration matches the tween.
static func salvo_plan(unit_id: StringName, mouth_count: int, distance: float) -> Dictionary:
	return {
		"count": SalvoTiming.rocket_count(unit_id, mouth_count),
		"interval": SalvoTiming.interval(unit_id),
		"flight": SalvoTiming.flight_time(distance),
	}


## Salvo phase length of a salvo_plan().
static func plan_duration(plan: Dictionary) -> float:
	return SalvoTiming.salvo_duration(plan["count"], plan["interval"], plan["flight"])


## Horizontal world distance between two points (the salvo's flight time depends on it).
static func horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## Terrain.Type `type` as a lower-case name (&"plains", &"forest", ...) for the effect hooks.
static func terrain_name(type: int) -> StringName:
	return StringName(String(Terrain.Type.keys()[type]).to_lower())


## Effect-hook context terrains of a salvo from `from` to `to` (world); `terrain_at` is
## Callable(x, z) -> Terrain.Type.
static func terrain_context(from: Vector3, to: Vector3, terrain_at: Callable) -> Dictionary:
	return {
		"launcher_terrain": terrain_name(terrain_at.call(from.x, from.z)),
		"target_terrain": terrain_name(terrain_at.call(to.x, to.z)),
	}


## Aims `shooter` at `aim_point` before a salvo: a limited launcher turns the hull first (taking
## `body_turn_duration`), then the pod rises and traverses (append_aim); a model without a launcher
## turns the whole vehicle. Returns Vector2(traverse, elevation) for append_stow (zero without a
## launcher).
static func append_aim_at(
	tween: Tween, shooter: UnitView, aim_point: Vector3, body_turn_duration: float
) -> Vector2:
	if not shooter.has_launcher():
		var turn := wrapf(shooter.yaw_towards(aim_point) - shooter.facing_yaw(), -PI, PI)
		tween_body_turn(tween, shooter, turn, body_turn_duration)
		return Vector2.ZERO
	var aim := shooter.launcher_aim_towards(aim_point)
	var elevation := shooter.launcher_elevation()
	if shooter.launcher_limited():
		tween_body_turn(tween, shooter, aim.x, body_turn_duration)
	append_aim(tween, shooter, aim.y, elevation)
	return Vector2(aim.y, elevation)


## A view-only `unit_attacked` event for showing a volley without a command (screenshot hook):
## no damage, the target keeps `target_hp`.
static func show_attack(attacker_id: int, target_id: int, target_hp: int) -> Dictionary:
	return {
		"type": &"unit_attacked",
		"attacker_id": attacker_id,
		"target_id": target_id,
		"damage": 0,
		"target_hp": target_hp,
		"counter": false,
	}


## View-local generator for a salvo's landing scatter, seeded from the played event's serial and
## the attacker: the same event scatters the same way; never GameState.rng.
static func scatter_rng(event_serial: int, attacker_id: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([event_serial, attacker_id])
	return rng


## The shooter's salvo_plan for a target at `target_centre` (world).
static func plan_for(shooter: UnitView, target_centre: Vector3) -> Dictionary:
	var shooter_at := UnitModels.world_transform(shooter).origin
	return salvo_plan(
		shooter.definition_id,
		shooter.launch_points().size(),
		horizontal_distance(shooter_at, target_centre)
	)


## `count` landing points in a disc of `radius` around `centre` (SalvoTiming.landing_points from
## the view-local `rng`), dropped onto `ground_height` (x, z) -> y when it is valid.
static func landing_points(
	rng: RandomNumberGenerator,
	centre: Vector3,
	count: int,
	radius: float,
	ground_height: Callable = Callable()
) -> Array[Vector3]:
	var points := SalvoTiming.landing_points(rng, centre, count, radius)
	if ground_height.is_valid():
		for i in count:
			points[i].y = ground_height.call(points[i].x, points[i].z)
	return points


## Sets `volley` up from the shooter's tubes as they are now (call it after aiming): mouths and
## directions (RocketVolley.launch_frames), `landings`, the `plan`'s interval and flight; `context`
## (plus `shooter` and `target_centre`) goes to the effect hooks.
static func setup_salvo(
	volley: RocketVolley,
	shooter: UnitView,
	target_centre: Vector3,
	landings: Array[Vector3],
	plan: Dictionary,
	context: Dictionary = {}
) -> void:
	var count := landings.size()
	var frames := RocketVolley.launch_frames(shooter, target_centre, count)
	var origins: Array[Vector3] = frames["origins"]
	var directions: Array[Vector3] = frames["directions"]
	origins.resize(count)
	directions.resize(count)
	var full := context.duplicate()
	full["shooter"] = shooter
	full["target_centre"] = target_centre
	volley.setup(origins, directions, landings, plan["interval"], plan["flight"], full)


## Appends the salvo itself (plan_duration of plan_for): the effect node is added to `parent`
## right away (freed with it if the tween dies), set up from the tube positions and directions
## after the aiming steps (setup_salvo), driven by one tween_method and freed at the end. The
## rockets land in a disc of `landing_radius` around `target_centre` (landing_points from `rng`, a
## view-local generator). `context` goes to the effect hooks (SalvoEffects.begin). The caller
## connects the volley's signals (connect_hp_steps) and may assign its `effects` before the salvo
## starts; it may free the node early.
static func append_salvo(
	tween: Tween,
	parent: Node,
	shooter: UnitView,
	target_centre: Vector3,
	rng: RandomNumberGenerator,
	landing_radius: float,
	context: Dictionary = {},
	ground_height: Callable = Callable()
) -> RocketVolley:
	var plan := plan_for(shooter, target_centre)
	var landings := landing_points(rng, target_centre, plan["count"], landing_radius, ground_height)
	var volley := RocketVolley.new()
	volley.name = "RocketVolley"
	parent.add_child(volley)
	# Tubes move with the turned model: read their positions after aiming.
	tween.tween_callback(setup_salvo.bind(volley, shooter, target_centre, landings, plan, context))
	var duration := plan_duration(plan)
	tween.tween_method(volley.update, 0.0, duration, duration)
	tween.tween_callback(volley.queue_free)
	return volley


## The target's HP steps down as the rockets of `volley` land (TASK-074): after impact k it shows
## SalvoTiming.hp_after_impact from the HP it shows now to `target_hp` (exactly at the last
## impact); the first and the last impact play the hit reaction (at `speed`), the first also calls
## `on_first_impact` (ground marks).
static func connect_hp_steps(
	volley: RocketVolley,
	target: UnitView,
	target_hp: int,
	speed: float = 1.0,
	on_first_impact: Callable = Callable()
) -> void:
	var hp_before := target.shown_hp()
	volley.rocket_impacted.connect(
		func(index: int, _point: Vector3) -> void:
			if not is_instance_valid(target):
				return
			if index == 0 and on_first_impact.is_valid():
				on_first_impact.call()
			var hp := SalvoTiming.hp_after_impact(hp_before, target_hp, index, volley.count)
			if index == 0 or index == volley.count - 1:
				var hit := target.play_hit(hp)
				if hit != null:
					hit.set_speed_scale(speed)
			else:
				target.set_shown_hp(hp)
	)
