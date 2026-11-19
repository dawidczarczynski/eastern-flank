extends TestCase
## Barrel-artillery barrage (presentation only): the gun lifts with the distance, three shells fly
## and land one after another, the gun recoils per shot and the pool fires the impact effects.

const MSTA := preload("res://data/units/2s19_msta_s.tres")
const TARGET := Vector3(6.0, 0.0, 2.0)

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _gunner() -> UnitView:
	var unit := Unit.new(1, 1, MSTA, Vector2i.ZERO)
	var hud := Control.new()
	_nodes.append(hud)
	var view := UnitView.new()
	_nodes.append(view)
	view.setup(unit, FactionRegistry.get_faction(&"russia"), Vector3.ZERO, hud, Callable())
	return view


func test_self_propelled_guns_fire_a_barrage_rocket_launchers_do_not() -> void:
	var homar: UnitDefinition = load("res://data/units/homar_k.tres")
	assert_true(UnitModels.fires_barrage(MSTA))
	assert_false(UnitModels.fires_barrage(homar))
	assert_false(UnitModels.fires_barrage(null))


func test_elevation_rises_with_distance_and_stays_within_bounds() -> void:
	var near := VolleyPlayback.barrage_elevation(1.0)
	var mid := VolleyPlayback.barrage_elevation(4.0)
	var far := VolleyPlayback.barrage_elevation(8.0)
	assert_true(near < mid and mid < far)
	var low := deg_to_rad(VolleyPlayback.BARREL_MIN_ELEVATION_DEG)
	var high := deg_to_rad(VolleyPlayback.BARREL_MAX_ELEVATION_DEG)
	assert_true(is_equal_approx(VolleyPlayback.barrage_elevation(0.0), low))
	assert_true(is_equal_approx(VolleyPlayback.barrage_elevation(50.0), high))


func test_plan_is_three_shells_with_a_shorter_flight_than_rockets() -> void:
	var plan := VolleyPlayback.barrage_plan(6.0)
	assert_eq(plan["count"], 3)
	assert_true(plan["interval"] > 0.0)
	assert_true(plan["flight"] < SalvoTiming.flight_time(6.0))


func test_event_queue_treats_a_barrage_as_a_volley() -> void:
	var event := {"type": &"unit_attacked", EventQueue.VIEW_FX_KEY: EventQueue.FX_BARRAGE}
	assert_true(EventQueue.is_volley(event))


func test_barrage_shells_land_in_order_and_the_gun_recoils_per_shot() -> void:
	var gunner := _gunner()
	assert_true(gunner.has_gun_recoil())
	var plan := VolleyPlayback.barrage_plan(6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var landings := VolleyPlayback.landing_points(rng, TARGET, plan["count"], 0.4)
	var volley := RocketVolley.new()
	_nodes.append(volley)
	volley.shells = true
	var impacts: Array[int] = []
	volley.rocket_impacted.connect(func(i: int, _p: Vector3) -> void: impacts.append(i))
	VolleyPlayback.setup_barrage(volley, gunner, TARGET, landings, plan)
	assert_eq(volley.count, 3)
	var peak := 0.0
	var t := 0.0
	while t < volley.duration():
		volley.update(t)
		peak = maxf(
			peak, VolleyPlayback.recoil_at(t - floorf(t / plan["interval"]) * plan["interval"])
		)
		t += 0.05
	volley.update(volley.duration())
	assert_eq(impacts, [0, 1, 2] as Array[int])
	assert_true(peak > 0.9)


func test_pool_effects_for_shells_emit_impacts_but_no_trails() -> void:
	var gunner := _gunner()
	var pool := SalvoFxPool.new()
	_nodes.append(pool)
	var plan := VolleyPlayback.barrage_plan(6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var landings := VolleyPlayback.landing_points(rng, TARGET, plan["count"], 0.4)
	var volley := RocketVolley.new()
	_nodes.append(volley)
	volley.shells = true
	volley.effects = SalvoFxPool.barrage_effects(pool, {"particles": true})
	var context := {"launcher_terrain": &"plains", "target_terrain": &"plains"}
	VolleyPlayback.setup_barrage(volley, gunner, TARGET, landings, plan, context)
	var t := 0.0
	while t < volley.duration():
		volley.update(t)
		t += 0.05
	volley.update(volley.duration())
	assert_eq(pool.active_trails(), 0)
	assert_true(pool.emitted.get(&"fire", 0) > 0)
