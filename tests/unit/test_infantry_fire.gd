extends TestCase
## Infantry fire effects (TASK-188b): the tracer rhythm, the plan's timing, the squad model's
## muzzles and the pooled playback.

const PlSquad := preload("res://src/presentation/models/pl_mech_infantry.gd")
const RuSquad := preload("res://src/presentation/models/ru_motor_rifle.gd")

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	DevTunables.reset_all()
	DevTunables.deactivate()


func _squad(russian: bool) -> Node3D:
	var faction := load("res://data/factions/%s.tres" % ("russia" if russian else "poland"))
	var root := Node3D.new()
	_nodes.append(root)
	var model := (RuSquad if russian else PlSquad).build(faction)
	model.name = "Model"
	root.add_child(model)
	return root


func test_tracer_every_fourth_round() -> void:
	assert_false(TracerPlan.is_tracer(0, 4))
	assert_true(TracerPlan.is_tracer(3, 4))
	assert_false(TracerPlan.is_tracer(4, 4))
	assert_true(TracerPlan.is_tracer(7, 4))
	assert_true(TracerPlan.is_tracer(11, 4))


func test_interval_one_makes_every_round_a_tracer() -> void:
	for i in 6:
		assert_true(TracerPlan.is_tracer(i, 1))


func test_tracer_interval_tunable() -> void:
	assert_eq(DevTunables.get_int(DevTunables.TRACER_INTERVAL), 2)
	assert_eq(DevTunables.SPECS[DevTunables.TRACER_INTERVAL]["min"], 1.0)
	assert_eq(DevTunables.SPECS[DevTunables.TRACER_INTERVAL]["max"], 12.0)
	DevTunables.activate()
	DevTunables.set_value(DevTunables.TRACER_INTERVAL, 99.0)
	assert_eq(DevTunables.get_int(DevTunables.TRACER_INTERVAL), 12)


func test_rifle_shots_follow_the_interval() -> void:
	var muzzles: Array[Vector3] = []
	muzzles.resize(5)
	muzzles.fill(Vector3.ZERO)
	var shots := TracerPlan.rifle_shots(muzzles, Vector3(3, 0, 0), 4)
	assert_eq(shots.size(), 5 * TracerPlan.ROUNDS)
	var tracers := shots.filter(func(s: Dictionary) -> bool: return s["tracer"]).size()
	assert_eq(tracers, 2)
	assert_true(shots[3]["tracer"])
	assert_true(shots[7]["tracer"])


func test_duration_covers_the_rocket_and_never_undercuts_a_plain_attack() -> void:
	var muzzles: Array[Vector3] = [Vector3.ZERO]
	var shots := TracerPlan.rifle_shots(muzzles, Vector3(1, 0, 0), 4)
	assert_true(TracerPlan.duration(shots, -1.0) >= EventQueue.ATTACK_DURATION)
	var with_rocket := TracerPlan.duration(shots, 10.0)
	assert_true(with_rocket >= TracerPlan.ROCKET_DELAY + TracerPlan.rocket_flight(10.0))


func test_both_squads_have_one_anti_tank_gunner_with_a_muzzle() -> void:
	for russian in [false, true]:
		var root := _squad(russian)
		var slot := UnitModels.at_slot(root)
		assert_true(slot >= 0)
		assert_true(UnitModels.at_muzzle_of(root, slot) != null)
		assert_eq(UnitModels.squad_muzzles(root, -1).size(), UnitModels.SQUAD_SIZE)
		assert_eq(UnitModels.squad_muzzles(root, slot).size(), UnitModels.SQUAD_SIZE - 1)


func test_model_without_soldiers_has_no_muzzles() -> void:
	var root := Node3D.new()
	_nodes.append(root)
	root.add_child(Node3D.new())
	assert_eq(UnitModels.at_slot(root), -1)
	assert_true(UnitModels.squad_muzzles(root, -1).is_empty())


func test_playback_shows_tracers_only_in_flight_and_hides_after() -> void:
	var fx := InfantryFire.new()
	_nodes.append(fx)
	fx.setup(false, null)
	var muzzles: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 0.1)]
	var shots := TracerPlan.rifle_shots(muzzles, Vector3(4, 0, 0), 1)
	fx._begin(shots, {})
	fx.pose(0.0)
	var streaks := fx._streaks.filter(func(s: MeshInstance3D) -> bool: return s.visible).size()
	assert_true(streaks >= 1)
	fx.pose(5.0)
	assert_eq(fx._streaks.filter(func(s: MeshInstance3D) -> bool: return s.visible).size(), 0)
	fx._end()
	assert_false(fx._rocket_body.visible)


func test_non_tracer_rounds_have_no_streak() -> void:
	var fx := InfantryFire.new()
	_nodes.append(fx)
	fx.setup(false, null)
	var muzzles: Array[Vector3] = [Vector3.ZERO]
	var shots := TracerPlan.rifle_shots(muzzles, Vector3(4, 0, 0), 12)
	fx._begin(shots, {})
	fx.pose(0.05)
	assert_eq(fx._streaks.filter(func(s: MeshInstance3D) -> bool: return s.visible).size(), 0)


func test_rocket_flies_and_hides_on_arrival() -> void:
	var fx := InfantryFire.new()
	_nodes.append(fx)
	fx.setup(false, null)
	var rocket := InfantryFire.rocket_plan(Vector3.ZERO, Vector3(5, 0, 0))
	fx._begin([], rocket)
	fx.pose(float(rocket["t0"]) + 0.1)
	assert_true(fx._rocket_body.visible)
	fx.pose(float(rocket["t0"]) + float(rocket["flight"]) + 0.01)
	assert_false(fx._rocket_body.visible)


func test_rocket_explodes_on_arrival_and_the_blast_fits_the_duration() -> void:
	var fx := InfantryFire.new()
	_nodes.append(fx)
	fx.setup(false, null)
	var rocket := InfantryFire.rocket_plan(Vector3.ZERO, Vector3(5, 0, 0))
	fx._begin([], rocket)
	var landing := float(rocket["t0"]) + float(rocket["flight"])
	fx.pose(landing - 0.01)
	assert_false(fx._blast_flash.visible)
	fx.pose(landing + 0.05)
	assert_true(fx._blast_flash.visible)
	assert_eq(InfantryFire.BLAST_TIME, TracerPlan.ROCKET_BLAST)
	assert_true(TracerPlan.duration([], 5.0) >= landing + InfantryFire.BLAST_TIME)
	fx._end()
	assert_false(fx._blast_flash.visible)


func test_annotation_copy_keeps_the_event_fields() -> void:
	var event := {"type": &"unit_attacked", "damage": 3, "target_hp": 7}
	var copy := EventQueue.with_view_duration(event, 0.5)
	copy[EventQueue.VIEW_FX_KEY] = EventQueue.FX_INFANTRY_AT
	assert_false(event.has(EventQueue.VIEW_FX_KEY))
	assert_eq(copy["damage"], 3)
	assert_eq(copy["target_hp"], 7)
