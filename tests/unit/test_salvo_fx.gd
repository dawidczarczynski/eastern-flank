extends TestCase
## Pooled salvo effects (TASK-075): backblast and trail helpers, camera shake, the quality
## switches and the pool driven headless by a RocketVolley of a built homar_k.

const TARGET := Vector3(8.0, 0.0, 3.0)
const STEPS: Array[float] = [0.016, 0.05, 0.37, 0.003, 0.2, 0.011]

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _shooter() -> UnitView:
	var definition: UnitDefinition = load("res://data/units/homar_k.tres")
	var unit := Unit.new(1, 0, definition, Vector2i.ZERO)
	var hud := Control.new()
	_nodes.append(hud)
	var view := UnitView.new()
	_nodes.append(view)
	view.setup(unit, FactionRegistry.get_faction(&"poland"), Vector3.ZERO, hud, Callable())
	view.set_launcher_pose(0.4, view.launcher_elevation())
	return view


func _pool() -> SalvoFxPool:
	var pool := SalvoFxPool.new()
	_nodes.append(pool)
	return pool


## A volley of the shooter with `effects`; the volley is owned by the test (freed by the caller
## or after_each).
func _volley(shooter: UnitView, effects: SalvoEffects) -> RocketVolley:
	var plan := VolleyPlayback.plan_for(shooter, TARGET)
	var rng := RandomNumberGenerator.new()
	rng.seed = 75
	var landings := VolleyPlayback.landing_points(rng, TARGET, plan["count"], 0.45)
	var volley := RocketVolley.new()
	_nodes.append(volley)
	volley.effects = effects
	var context := {"launcher_terrain": &"plains", "target_terrain": &"plains"}
	VolleyPlayback.setup_salvo(volley, shooter, TARGET, landings, plan, context)
	return volley


func _drive(volley: RocketVolley) -> void:
	var t := 0.0
	var k := 0
	while t < volley.duration():
		volley.update(t)
		t += STEPS[k % STEPS.size()]
		k += 1
	volley.update(volley.duration())


func _count(root: Node, type: String) -> int:
	return root.find_children("*", type, true, false).size()


# --- pure helpers -------------------------------------------------------------------------


func test_pod_length_falls_back_without_meshes() -> void:
	var shooter := _shooter()
	var pod := UnitModels.launcher_pod(shooter.model())
	for mesh in pod.find_children("*", "MeshInstance3D", true, false):
		mesh.get_parent().remove_child(mesh)
		mesh.free()
	assert_eq(SalvoFxPool.pod_length(shooter), SalvoFxPool.POD_LENGTH_FALLBACK)
	assert_eq(SalvoFxPool.pod_length(null), 0.4)


func test_pod_length_comes_from_the_pod_meshes() -> void:
	var length := SalvoFxPool.pod_length(_shooter())
	assert_true(length > 0.2 and length < 5.0, "pod length %.2f" % length)


func test_shake_caps_and_decays_on_the_camera_only() -> void:
	var rig := CameraRig.new()
	rig.add_shake(0.02)
	rig.add_shake(0.02)
	assert_eq(rig.shake(), CameraRig.SHAKE_MAX)
	rig._process(CameraRig.SHAKE_DECAY + 0.01)
	assert_eq(rig.shake(), 0.0)
	assert_eq(rig.target(), Vector2.ZERO)
	rig.free()


func test_pool_has_its_layers_within_the_budget() -> void:
	var pool := _pool()
	var layers := pool.find_children("*", "GPUParticles3D", true, false)
	assert_eq(layers.size(), SalvoFxPool.LAYER_AMOUNTS.size())
	var total := 0
	for layer: GPUParticles3D in layers:
		total += layer.amount
	assert_true(total <= SalvoFxPool.MAX_PARTICLES, "%d particles" % total)


func test_two_volleys_create_no_particle_nodes() -> void:
	var pool := _pool()
	var before := _count(pool, "GPUParticles3D")
	var shooter := _shooter()
	for i in 2:
		var volley := _volley(shooter, pool.effects_for_volley())
		_drive(volley)
		volley.free()
	assert_eq(_count(pool, "GPUParticles3D"), before)
	var volley := _volley(shooter, pool.effects_for_volley())
	assert_eq(_count(volley, "GPUParticles3D"), 0)


func test_low_quality_uses_the_base_effects() -> void:
	var pool := _pool()
	var low := GraphicsQuality.features(GraphicsQuality.Level.LOW)
	var effects := SalvoFxPool.effects(pool, low)
	assert_eq(effects.get_script(), SalvoEffects)
	assert_eq(
		(
			SalvoFxPool
			. effects(null, GraphicsQuality.features(GraphicsQuality.Level.HIGH))
			. get_script()
		),
		SalvoEffects
	)
	var volley := _volley(_shooter(), effects)
	_drive(volley)
	assert_eq(_count(volley, "GPUParticles3D"), 0)
	assert_eq(_count(volley, "OmniLight3D"), 0)
	assert_eq(pool.emitted[&"fire"], 0)


func test_lights_per_quality() -> void:
	var pool := _pool()
	var shooter := _shooter()
	var lit := _volley(shooter, pool.effects_for_volley(true))
	var lights := lit.find_children("*", "OmniLight3D", true, false)
	assert_true(lights.size() >= 1 and lights.size() <= 2)
	for light: OmniLight3D in lights:
		assert_false(light.shadow_enabled)
	_drive(lit)
	assert_true(_count(lit, "OmniLight3D") <= 2)
	var dark := _volley(shooter, pool.effects_for_volley(false))
	_drive(dark)
	assert_eq(_count(dark, "OmniLight3D"), 0)


func test_lights_are_freed_with_the_volley() -> void:
	var pool := _pool()
	var volley := _volley(_shooter(), pool.effects_for_volley(true))
	var lights := volley.find_children("*", "OmniLight3D", true, false)
	volley.free()
	for light in lights:
		assert_false(is_instance_valid(light))


func test_every_launch_and_impact_reaches_the_pool() -> void:
	var pool := _pool()
	var volley := _volley(_shooter(), pool.effects_for_volley())
	_drive(volley)
	assert_eq(volley.count, 12)
	assert_eq(pool.emitted[&"fire"], 12 * (SalvoFxPool.BACKBLAST_FIRE + SalvoFxPool.FIREBALL))
	assert_eq(
		pool.emitted[&"smoke"], 12 * (SalvoFxPool.IMPACT_SMOKE + SalvoFxPool.COLUMN_PER_IMPACT)
	)
	assert_eq(pool.emitted[&"dust"], 12 * (SalvoFxPool.BACKBLAST_DUST + SalvoFxPool.DUST_RING))
	assert_eq(pool.emitted[&"blast"], 12 * SalvoFxPool.BACKBLAST_SMOKE)
	assert_eq(pool.emitted[&"debris"], 12 * SalvoFxPool.DEBRIS)
	assert_true(pool.emitted[&"trail"] > 12 * 5, "trail points: %d" % pool.emitted[&"trail"])
	# Flames exist per rocket and are all out by the end.
	var plumes := volley.find_children("Plume", "Node3D", true, false)
	assert_true(plumes.size() > 0, "plumes exist")
	for plume in plumes:
		assert_false((plume as Node3D).visible)


func test_plume_burns_only_at_the_launch() -> void:
	var pool := _pool()
	var volley := _volley(_shooter(), pool.effects_for_volley())
	for t in [0.0, 0.03, 0.08]:
		volley.update(t)
	var plume := volley.find_child("Plume", true, false) as Node3D
	assert_true(plume != null and plume.visible, "visible right after the launch")
	var burn := SalvoTiming.MOTOR_BURN * volley.flight
	assert_true(SalvoFxPool.PLUME_TIME + 0.05 < burn, "the motor still burns")
	volley.update(SalvoFxPool.PLUME_TIME + 0.02)
	volley.update(SalvoFxPool.PLUME_TIME + 0.05)
	assert_false(plume.visible, "out after PLUME_TIME although the motor burns")


func test_plume_shape_over_time() -> void:
	assert_eq(SalvoFxPool.plume_at(-0.01)["length"], 0.0)
	assert_eq(SalvoFxPool.plume_at(SalvoFxPool.PLUME_TIME)["length"], 0.0)
	assert_true(SalvoFxPool.plume_at(0.04)["length"] > SalvoFxPool.PLUME_LENGTH * 0.7)
	var last := 2.0
	for i in 32:
		var intensity: float = SalvoFxPool.plume_at(i * SalvoFxPool.PLUME_TIME / 32.0)["intensity"]
		assert_true(intensity <= last + 0.0001, "intensity never grows")
		last = intensity


func test_trails_grow_while_the_motor_burns_then_fade() -> void:
	var pool := _pool()
	var volley := _volley(_shooter(), pool.effects_for_volley())
	var burn := SalvoTiming.MOTOR_BURN * volley.flight
	volley.update(0.0)
	volley.update(burn * 0.5)
	var trail := pool.acquire_trail()
	assert_true(pool.active_trails() >= 1, "the first rocket's trail grows")
	_drive(volley)
	var points := pool.emitted[&"trail"] as int
	volley.update(volley.duration())
	assert_eq(pool.emitted[&"trail"], points, "no points after the motors burnt out")
	assert_eq(_count(pool, "SalvoTrail"), SalvoFxPool.TRAILS)
	for child in pool.get_children():
		if child is SalvoTrail:
			(child as SalvoTrail).advance(SalvoTrail.LIFE + 0.1)
	assert_eq(pool.active_trails(), 0, "all trails faded")
	assert_true(trail != null)


func test_trail_ribbons_are_reused() -> void:
	var pool := _pool()
	var shooter := _shooter()
	for i in 3:
		var volley := _volley(shooter, pool.effects_for_volley())
		_drive(volley)
		volley.free()
	var trails := pool.get_children().filter(func(c: Node) -> bool: return c is SalvoTrail)
	assert_eq(trails.size(), SalvoFxPool.TRAILS)


func test_create_follows_the_quality() -> void:
	var low_parent := Node3D.new()
	_nodes.append(low_parent)
	var low := GraphicsQuality.features(GraphicsQuality.Level.LOW)
	assert_eq(SalvoFxPool.create(low_parent, low, Rect2(-10, -10, 20, 20), null), null)
	assert_eq(low_parent.get_child_count(), 0)
	assert_eq(_count(low_parent, "GPUParticles3D"), 0)
	var high_parent := Node3D.new()
	_nodes.append(high_parent)
	var high := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	var pool := SalvoFxPool.create(high_parent, high, Rect2(-10, -10, 20, 20), null)
	assert_true(pool != null)
	var pools := high_parent.get_children().filter(func(c: Node) -> bool: return c is SalvoFxPool)
	assert_eq(pools.size(), 1)
	assert_eq(
		pool.get_children().filter(func(c: Node) -> bool: return c is GPUParticles3D).size(),
		SalvoFxPool.LAYER_AMOUNTS.size()
	)


func test_column_lingers_then_drops() -> void:
	var pool := _pool()
	var volley := _volley(_shooter(), pool.effects_for_volley())
	_drive(volley)
	assert_eq(pool.column_count(), 0, "still owned by the volley")
	volley.free()
	assert_eq(pool.column_count(), 1)
	var before: int = pool.emitted[&"smoke"]
	pool.advance(SalvoFxPool.COLUMN_LINGER * 0.5)
	assert_true(pool.emitted[&"smoke"] > before, "the column is still fed")
	pool.advance(SalvoFxPool.COLUMN_LINGER * 0.5 + 0.1)
	assert_eq(pool.column_count(), 0)


func test_at_most_max_columns_are_fed() -> void:
	var pool := _pool()
	var shooter := _shooter()
	for i in 3:
		var volley := _volley(shooter, pool.effects_for_volley())
		_drive(volley)
		volley.free()
	assert_eq(pool.column_count(), SalvoFxPool.MAX_COLUMNS)
