extends TestCase
## TASK-065: destroyed vehicles stay as burnt wrecks. Headless: the death is played by jumping to
## times of the timeline (set_wreck_time) instead of running tweens.

const Fixtures := preload("res://tests/fixtures.gd")
const TANK := "res://data/units/m1a2_sepv3.tres"
const INFANTRY := "res://data/units/pl_mech_infantry.tres"
const TANK_TILE := Vector2i(1, 0)

var _state: GameState
var _hud: Control
var _field: WreckField
var _views: Array[UnitView] = []


func before_each() -> void:
	_state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	_hud = Control.new()
	_field = WreckField.new()
	_views = []


func after_each() -> void:
	for view in _views:
		view.free()
	_field.free()
	_hud.free()


func _view_of(path: String, particles := true, coord := TANK_TILE) -> UnitView:
	var unit := _state.add_unit(0, load(path) as UnitDefinition, coord)
	var view := UnitView.new()
	view.quality = {"particles": particles}
	view.setup(unit, _state.faction_of(0), Vector3.ZERO, _hud, Callable())
	_views.append(view)
	return view


## Plays the whole wreck death of a tank and returns its wreck.
func _wreck_of(view: UnitView, coord := TANK_TILE) -> WreckView:
	_field.quality = view.quality
	view.begin_wreck_death()
	view.set_wreck_time(WreckPlan.BURN_END)
	view.set_wreck_time(UnitView.WRECK_DURATION)
	return _field.adopt(view, coord)


func _camo_meshes(node: Node, found: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	var mesh := node as MeshInstance3D
	if mesh != null:
		var shader := mesh.material_override as ShaderMaterial
		if shader != null and shader.shader == ModelParts.CAMO_SHADER:
			found.append(mesh)
	for child in node.get_children():
		_camo_meshes(child, found)
	return found


func _turret_yaw_deg(node: Node3D) -> float:
	var turret := node.find_child("Turret", true, false) as Node3D
	var forward := turret.basis.x
	return rad_to_deg(atan2(-forward.z, forward.x))


func _all_nodes(node: Node, found: Array[Node] = []) -> Array[Node]:
	found.append(node)
	for child in node.get_children():
		_all_nodes(child, found)
	return found


func test_shader_has_burnt_default_zero() -> void:
	var code := (load("res://assets/shaders/camo.gdshader") as Shader).code
	assert_true(code.contains("instance uniform float burnt = 0.0;"))


func test_tank_death_leaves_one_burnt_wreck_with_turret_askew() -> void:
	var view := _view_of(TANK)
	var before := _turret_yaw_deg(view)
	var wreck := _wreck_of(view)
	assert_eq(_field.wrecks().size(), 1)
	assert_eq(wreck.unit_id, view.unit_id)
	assert_eq(wreck.coord(), TANK_TILE)
	var meshes := _camo_meshes(wreck)
	assert_true(meshes.size() > 0)
	for mesh in meshes:
		assert_eq(mesh.get_instance_shader_parameter(&"burnt"), 1.0)
	var yaw := _turret_yaw_deg(wreck) - before
	assert_true(yaw >= 20.0 - 0.01 and yaw <= 35.0 + 0.01, "yaw %f" % yaw)
	assert_true(view.take_body() == null, "the body moved to the wreck")


func test_burn_and_turret_progress_with_time() -> void:
	var view := _view_of(TANK)
	var before := _turret_yaw_deg(view)
	view.begin_wreck_death()
	view.set_wreck_time(0.0)
	assert_eq(_turret_yaw_deg(view), before)
	assert_eq(WreckPlan.burnt_at(0.0), 0.0)
	view.set_wreck_time(0.25)
	var mid := _turret_yaw_deg(view) - before
	assert_true(mid > 0.0 and mid < WreckPlan.TURRET_YAW_MIN, "mid-way %f" % mid)
	assert_eq(WreckPlan.burnt_at(WreckPlan.BURN_END), 1.0)


func test_turret_offsets_are_deterministic_per_unit_id() -> void:
	for id in [1, 2, 7, 99]:
		assert_eq(WreckPlan.turret_yaw(id), WreckPlan.turret_yaw(id))
		var yaw := rad_to_deg(WreckPlan.turret_yaw(id))
		assert_true(yaw >= 20.0 and yaw <= 35.0, "yaw %f" % yaw)
		var tilt := rad_to_deg(WreckPlan.turret_tilt(id))
		assert_true(tilt >= 6.0 and tilt <= 10.0, "tilt %f" % tilt)
	var distinct := {}
	for id in 30:
		distinct[WreckPlan.turret_yaw(id)] = true
	assert_true(distinct.size() > 5, "ids differ")


func test_death_timeline_keeps_the_event_queue_duration() -> void:
	assert_eq(UnitView.WRECK_DURATION, EventQueue.DEATH_DURATION)
	assert_eq(EventQueue.DEATH_DURATION, 0.85)
	assert_true(WreckPlan.TURRET_END <= EventQueue.DEATH_DURATION)
	assert_true(WreckPlan.BURN_END <= EventQueue.DEATH_DURATION)
	assert_eq(WreckPlan.flash_energy(0.0), WreckPlan.FLASH_ENERGY)
	assert_eq(WreckPlan.flash_energy(WreckPlan.FLASH_DURATION), 0.0)


func test_wreck_is_not_pickable_and_the_tile_is_free() -> void:
	var view := _view_of(TANK)
	var wreck := _wreck_of(view)
	_state.get_unit(view.unit_id).hp = 0
	assert_true(_state.unit_at(TANK_TILE) == null, "no unit to hover or pick")
	for node in _all_nodes(wreck):
		assert_false(node is CollisionObject3D, "%s" % node.name)
		assert_false(node is UnitView)


func test_unit_ending_a_move_on_the_tile_hides_the_wreck() -> void:
	var wreck := _wreck_of(_view_of(TANK))
	_field.on_unit_moved(Vector2i(2, 0))
	assert_false(wreck.is_hidden(), "ended elsewhere")
	assert_true(wreck.visible)
	_field.on_unit_moved(TANK_TILE)
	assert_true(wreck.is_hidden())
	assert_false(wreck.visible)
	assert_true(_field.visible_wreck_at(TANK_TILE) == null)


func test_smoke_thins_after_one_turn_and_stops_after_three() -> void:
	var wreck := _wreck_of(_view_of(TANK))
	var smoke := wreck.smoke_emitter()
	assert_true(smoke.emitting)
	assert_eq(smoke.amount_ratio, 1.0)
	assert_true(wreck.fire_light().visible)
	_field.on_turn_started()
	assert_true(smoke.emitting)
	assert_eq(smoke.amount_ratio, WreckLife.THIN_FACTOR)
	assert_false(wreck.fire_light().visible, "fire only the first turn")
	_field.on_turn_started()
	assert_true(smoke.emitting)
	_field.on_turn_started()
	assert_false(smoke.emitting)


func test_infantry_leaves_no_wreck() -> void:
	var unit := _state.add_unit(0, load(INFANTRY) as UnitDefinition, TANK_TILE)
	assert_false(WreckPlan.leaves_wreck(unit.definition))
	assert_true(WreckPlan.leaves_wreck(load(TANK) as UnitDefinition))
	assert_true(WreckPlan.leaves_wreck(load("res://data/units/homar_k.tres") as UnitDefinition))
	assert_true(_field.wrecks().is_empty())


func test_without_particles_the_wreck_has_no_particle_nodes() -> void:
	var view := _view_of(TANK, false)
	var wreck := _wreck_of(view)
	assert_true(wreck.smoke_emitter() == null)
	assert_true(wreck.fire_light() == null)
	for node in _all_nodes(wreck):
		assert_false(node is GPUParticles3D, node.name)
	assert_eq(_field.wrecks().size(), 1)
	for mesh in _camo_meshes(wreck):
		assert_eq(mesh.get_instance_shader_parameter(&"burnt"), 1.0)


func test_launcher_pods_stow_when_burnt() -> void:
	var view := _view_of("res://data/units/homar_k.tres")
	view.set_launcher_pose(0.5, 0.6)
	var wreck := _wreck_of(view)
	var pod := UnitModels.launcher_pod(wreck.body().find_child("Model", true, false) as Node3D)
	assert_true(pod != null)
	assert_eq(pod.transform, pod.get_meta(&"rest"))
