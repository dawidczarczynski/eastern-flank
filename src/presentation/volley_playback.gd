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


## Appends the salvo itself (RocketVolley.total_duration()): the effect node is added to `parent`
## right away (freed with it if the tween dies), set up from the tube positions after the aiming
## steps, and removed at the end. `on_impact` (may be invalid) is called with the last impact,
## in parallel with the flashes fading out. Returns the effect node (the caller may free it early).
static func append_salvo(
	tween: Tween,
	parent: Node,
	shooter: UnitView,
	impact_point: Vector3,
	rng: RandomNumberGenerator,
	on_impact: Callable
) -> RocketVolley:
	var origins := shooter.launch_points()
	if origins.is_empty():
		origins.append(shooter.global_position + Vector3(0.0, 0.4, 0.0))
	var volley := RocketVolley.new()
	volley.name = "RocketVolley"
	parent.add_child(volley)
	tween.tween_callback(
		func() -> void:
			# Tubes move with the turned model: read their positions after aiming.
			var tubes := shooter.launch_points()
			volley.setup(tubes if not tubes.is_empty() else origins, impact_point, rng)
	)
	tween.tween_method(
		volley.update, 0.0, RocketVolley.total_duration(), RocketVolley.total_duration()
	)
	if on_impact.is_valid():
		# The hit reaction starts with the last impact.
		tween.parallel()
		var hit_step := tween.tween_callback(on_impact)
		hit_step.set_delay(RocketVolley.last_impact_time())
	tween.tween_callback(volley.queue_free)
	return volley
