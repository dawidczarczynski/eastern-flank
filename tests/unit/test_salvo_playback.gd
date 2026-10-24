extends TestCase
## RocketVolley as a node (TASK-074), driven headless with update(t) from a built launcher model:
## one rocket per tube, signals and effect hooks for every launch / impact, visibility, pod jolt,
## the fallback for models without tubes, and the target's HP steps.

const TARGET := Vector3(8.0, 0.0, 3.0)
const STEPS: Array[float] = [0.016, 0.05, 0.37, 0.003, 0.2, 0.011]


## Records every hook call in order: [name, args...].
class Recorder:
	extends SalvoEffects
	var calls: Array = []

	func begin(context: Dictionary) -> void:
		calls.append(["begin", context])

	func on_launch(index: int, mouth: Vector3, tube_dir: Vector3) -> void:
		calls.append(["launch", index, mouth, tube_dir])

	func on_flight(index: int, from: Vector3, to: Vector3, s: float, motor: bool) -> void:
		calls.append(["flight", index, from, to, s, motor])

	func on_impact(index: int, point: Vector3, first: bool, last: bool) -> void:
		calls.append(["impact", index, point, first, last])

	func end(target_centre: Vector3) -> void:
		calls.append(["end", target_centre])

	func named(hook: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return c[0] == hook)


## A UnitView that counts its hit reactions.
class CountingView:
	extends UnitView
	var hits := 0

	func play_hit(hp: int) -> Tween:
		hits += 1
		return super(hp)


var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _view(unit_id: StringName, faction: StringName, hp := -1, view: UnitView = null) -> UnitView:
	var definition: UnitDefinition = load("res://data/units/%s.tres" % unit_id)
	var unit := Unit.new(1, 0, definition, Vector2i.ZERO)
	if hp >= 0:
		unit.hp = hp
	var hud := Control.new()
	_nodes.append(hud)
	var result := view if view != null else UnitView.new()
	_nodes.append(result)
	result.setup(unit, FactionRegistry.get_faction(faction), Vector3.ZERO, hud, Callable())
	return result


## The shooter with its pod raised and traversed, as after _play_volley's aim steps.
func _aimed(unit_id: StringName, faction: StringName) -> UnitView:
	var shooter := _view(unit_id, faction)
	if shooter.has_launcher():
		# Some traverse; the exact aim needs the scene tree (UnitView.yaw_towards).
		shooter.set_launcher_pose(0.4, shooter.launcher_elevation())
	return shooter


func _volley(shooter: UnitView, effects: SalvoEffects = null) -> RocketVolley:
	var plan := VolleyPlayback.plan_for(shooter, TARGET)
	var rng := RandomNumberGenerator.new()
	rng.seed = 74
	var landings := VolleyPlayback.landing_points(rng, TARGET, plan["count"], 0.45)
	var volley := RocketVolley.new()
	_nodes.append(volley)
	if effects != null:
		volley.effects = effects
	var context := {"launcher_terrain": &"plains", "target_terrain": &"forest"}
	VolleyPlayback.setup_salvo(volley, shooter, TARGET, landings, plan, context)
	return volley


## Salvo times from 0 to the volley's end in uneven steps (the last one exactly at the end).
func _times(volley: RocketVolley) -> Array[float]:
	var times: Array[float] = []
	var t := 0.0
	var k := 0
	while t < volley.duration():
		times.append(t)
		t += STEPS[k % STEPS.size()]
		k += 1
	times.append(volley.duration())
	return times


## Drives the volley; returns the signals as [["launched", i] / ["impacted", i, point]].
func _drive(volley: RocketVolley) -> Array:
	var signals: Array = []
	volley.rocket_launched.connect(func(i: int) -> void: signals.append(["launched", i]))
	volley.rocket_impacted.connect(
		func(i: int, p: Vector3) -> void: signals.append(["impacted", i, p])
	)
	for t in _times(volley):
		volley.update(t)
	return signals


func _indices(signals: Array, kind: String) -> Array[int]:
	var result: Array[int] = []
	for s: Array in signals:
		if s[0] == kind:
			result.append(s[1])
	return result


func _range(n: int) -> Array[int]:
	var result: Array[int] = []
	for i in n:
		result.append(i)
	return result


func test_one_rocket_per_tube_with_every_signal_once() -> void:
	var volley := _volley(_aimed(&"homar_k", &"poland"))
	assert_eq(volley.count, 12)
	var rockets := volley.get_children().filter(
		func(c: Node) -> bool: return c.name.begins_with("Rocket")
	)
	assert_eq(rockets.size(), 12)
	var signals := _drive(volley)
	assert_eq(_indices(signals, "launched"), _range(12))
	assert_eq(_indices(signals, "impacted"), _range(12))


func test_mouth_count_wins_over_the_profile() -> void:
	var shooter := _aimed(&"bm27_uragan", &"russia")
	var pod := UnitModels.launcher_pod(shooter.model())
	for child in pod.get_children():
		if child.name.begins_with("Mouth") and child.name != "Mouth0" and child.name != "Mouth1":
			if child.name != "Mouth2":
				pod.remove_child(child)
				child.free()
	var volley := _volley(shooter)
	assert_eq(volley.count, 3)
	assert_eq(_indices(_drive(volley), "impacted"), _range(3))


func test_rockets_show_only_in_flight_and_glow_only_while_the_motor_burns() -> void:
	var volley := _volley(_aimed(&"homar_k", &"poland"))
	for t in _times(volley):
		volley.update(t)
		for i in volley.count:
			var rocket := volley.get_node("Rocket%d" % i) as Node3D
			var glow := rocket.get_node("Glow") as Node3D
			var s := (t - SalvoTiming.launch_time(i, volley.interval)) / volley.flight
			var flying := s >= 0.0 and s < 1.0
			assert_eq(rocket.visible, flying, "rocket %d at %.3f" % [i, t])
			assert_eq(
				glow.visible, flying and s < SalvoTiming.MOTOR_BURN, "glow %d at %.3f" % [i, t]
			)
			if t >= volley.last_impact_time():
				assert_false(rocket.visible, "all down at %.3f" % t)


func test_pod_jolts_and_returns_to_the_aim_pose() -> void:
	var shooter := _aimed(&"homar_k", &"poland")
	var pod := UnitModels.launcher_pod(shooter.model())
	var aimed := pod.transform.basis
	var volley := _volley(shooter)
	var jolted := false
	var last_launch := SalvoTiming.launch_time(volley.count - 1, volley.interval)
	for t in _times(volley):
		volley.update(t)
		var off := pod.transform.basis.x.angle_to(aimed.x)
		jolted = jolted or off > 0.005
		if t >= last_launch + RocketVolley.JOLT_TIME:
			assert_true(off < 0.0005, "at %.3f the pod is %.5f rad off its aim pose" % [t, off])
	assert_true(jolted, "the pod kicks back at a launch")


func test_no_particles_and_no_lights() -> void:
	var volley := _volley(_aimed(&"bm27_uragan", &"russia"))
	_drive(volley)
	assert_eq(volley.find_children("*", "GPUParticles3D", true, false).size(), 0)
	assert_eq(volley.find_children("*", "OmniLight3D", true, false).size(), 0)


func test_model_without_tubes_uses_the_fallback() -> void:
	var shooter := _view(&"t72b3", &"russia")
	assert_true(shooter.launch_points().is_empty())
	var volley := _volley(shooter)
	assert_eq(volley.count, SalvoTiming.DEFAULT_PROFILE["count"])
	assert_eq(_indices(_drive(volley), "impacted"), _range(volley.count))


func test_effect_hooks() -> void:
	var shooter := _aimed(&"homar_k", &"poland")
	var mouths := shooter.launch_points()
	var recorder := Recorder.new()
	var volley := _volley(shooter, recorder)
	var signals := _drive(volley)
	assert_eq(recorder.calls[0][0], "begin", "begin comes first")
	assert_eq(recorder.named("begin").size(), 1)
	var context: Dictionary = recorder.calls[0][1]
	for key in [
		"volley",
		"shooter",
		"target_centre",
		"launcher_terrain",
		"target_terrain",
		"count",
		"interval",
		"flight"
	]:
		assert_true(context.has(key), "context has %s" % key)
	assert_eq(context["volley"], volley)
	assert_eq(context["count"], 12)
	var launches := recorder.named("launch")
	assert_eq(launches.size(), 12)
	for i in launches.size():
		var call: Array = launches[i]
		assert_eq(call[1], i)
		assert_true((call[2] as Vector3).distance_to(mouths[i]) < 0.0001, "mouth %d" % i)
		assert_true(absf((call[3] as Vector3).length() - 1.0) < 0.0001, "tube_dir normalised")
	var impacts := recorder.named("impact")
	assert_eq(impacts.size(), 12)
	for i in impacts.size():
		var call: Array = impacts[i]
		assert_eq(call[1], i)
		assert_eq(call[3], i == 0, "first %d" % i)
		assert_eq(call[4], i == 11, "last %d" % i)
	for i in 12:
		var segments := recorder.calls.filter(
			func(c: Array) -> bool: return c[0] == "flight" and c[1] == i
		)
		assert_true(segments.size() > 1, "rocket %d flies" % i)
		var previous: Vector3 = mouths[i]
		for seg: Array in segments:
			assert_true((seg[2] as Vector3).distance_to(previous) < 0.000001, "contiguous %d" % i)
			assert_eq(seg[5], seg[4] < SalvoTiming.MOTOR_BURN, "motor %d at s %.3f" % [i, seg[4]])
			previous = seg[3]
		var landing: Vector3 = impacts[i][2]
		assert_true(previous.distance_to(landing) < 0.001, "rocket %d ends at its landing" % i)
	assert_eq(recorder.named("end").size(), 0)
	volley.free()
	assert_eq(recorder.named("end").size(), 1, "end once when freed")
	# The base hooks (no subclass) play the same salvo.
	var plain := _drive(_volley(_aimed(&"homar_k", &"poland")))
	assert_eq(plain, signals)


func test_hp_steps_down_with_the_impacts() -> void:
	var target := _view(&"t72b3", &"russia", 6, CountingView.new()) as CountingView
	var volley := _volley(_aimed(&"homar_k", &"poland"))
	var marks := [0]
	VolleyPlayback.connect_hp_steps(volley, target, 1, 1.0, func() -> void: marks[0] += 1)
	var shown: Array[int] = []
	volley.rocket_impacted.connect(
		func(_i: int, _p: Vector3) -> void: shown.append(target.shown_hp())
	)
	_drive(volley)
	assert_eq(shown.size(), 12)
	for k in 12:
		assert_eq(shown[k], SalvoTiming.hp_after_impact(6, 1, k, 12), "after impact %d" % k)
	assert_eq(target.shown_hp(), 1)
	assert_eq(target.hits, 2, "hit reaction on the first and the last impact")
	assert_eq(marks[0], 1, "ground marks once")
