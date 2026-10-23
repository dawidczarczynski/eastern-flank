extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var _hud: Control
var _view: UnitView


func before_each() -> void:
	_hud = Control.new()
	_view = null


func after_each() -> void:
	if _view != null:
		_view.free()
	_hud.free()


func _view_of(unit_path: String, particles: bool) -> UnitView:
	var state := GameState.new(Fixtures.plains_grid(2), 2, 1)
	var definition := load(unit_path) as UnitDefinition
	var unit := state.add_unit(0, definition, Vector2i(0, 0))
	_view = UnitView.new()
	_view.quality = {"particles": particles}
	_view.setup(unit, state.faction_of(0), Vector3.ZERO, _hud, Callable())
	return _view


func _emitters(node: Node) -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	if node is GPUParticles3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_emitters(child))
	return found


func test_no_particle_nodes_without_particles() -> void:
	for path in ["m1a2_sepv3", "homar_k", "pl_mech_infantry"]:
		var view := _view_of("res://data/units/%s.tres" % path, false)
		assert_eq(_emitters(view).size(), 0, path)
		view.free()
		_view = null


func test_tank_has_two_dust_emitters_and_one_exhaust_at_rest() -> void:
	var view := _view_of("res://data/units/m1a2_sepv3.tres", true)
	var emitters := _emitters(view)
	assert_eq(emitters.size(), 3)
	for emitter in emitters:
		assert_false(emitter.emitting, "%s idle" % emitter.name)


func test_infantry_has_no_emitters() -> void:
	var view := _view_of("res://data/units/pl_mech_infantry.tres", true)
	assert_eq(_emitters(view).size(), 0)


func test_emitters_run_during_a_move_and_stop_on_arrival() -> void:
	var view := _view_of("res://data/units/m1a2_sepv3.tres", true)
	view._fx.begin()
	view._fx.update(0.0, 0.0, 0.0, Terrain.Type.PLAINS)
	for emitter in _emitters(view):
		assert_true(emitter.emitting, "%s moving" % emitter.name)
	var start_puff := view._fx.exhaust_emitter().amount_ratio
	view._fx.update(3.0, MotionEffects.FULL_SPEED, 0.0, Terrain.Type.PLAINS)
	var cruising := view._fx.exhaust_emitter().amount_ratio
	assert_true(
		start_puff > 2.0 * cruising, "more exhaust at the start (%s vs %s)" % [start_puff, cruising]
	)
	assert_true(view._fx.dust_emitters()[0].amount_ratio > 0.0, "dust at speed")
	view._fx.update(3.0, MotionEffects.FULL_SPEED, 0.0, Terrain.Type.WATER)
	assert_eq(view._fx.dust_emitters()[0].amount_ratio, 0.0, "no dust on water")
	view._fx.end()
	for emitter in _emitters(view):
		assert_false(emitter.emitting, "%s arrived" % emitter.name)


func test_the_cloud_lingers_after_the_emitter_stops() -> void:
	var view := _view_of("res://data/units/m1a2_sepv3.tres", true)
	assert_true(view._fx.exhaust_emitter().lifetime >= 2.0)
	assert_true(view._fx.dust_emitters()[0].lifetime >= 2.0)
	assert_false(view._fx.exhaust_emitter().local_coords, "world space: the cloud stays behind")


func test_only_tracked_vehicles_pivot_in_place() -> void:
	assert_true(UnitModels.is_tracked(load("res://data/units/m1a2_sepv3.tres")))
	assert_false(UnitModels.is_tracked(load("res://data/units/homar_k.tres")))
	assert_false(UnitModels.is_tracked(load("res://data/units/pl_mech_infantry.tres")))
