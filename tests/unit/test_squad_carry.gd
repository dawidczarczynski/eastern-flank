extends TestCase
## Squad carries and facings (TASK-068): mixed weapon carries keep a squad from looking like five
## copies of one figure.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")


func _poland() -> FactionDefinition:
	return load("res://data/factions/poland.tres") as FactionDefinition


func _first_mesh(node: Node) -> Mesh:
	for child in node.get_children():
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh
	return null


func test_carry_angle_picks_aim_low_or_the_kits_ready_angle() -> void:
	assert_eq(Soldier.carry_angle(Soldier.READY, false, -0.45, -0.25), -0.45)
	assert_eq(Soldier.carry_angle(Soldier.READY, true, -0.45, -0.25), -0.25)
	assert_eq(Soldier.carry_angle(Soldier.AIM, true, -0.45, -0.25), Soldier.AIM_ANGLE)
	assert_eq(Soldier.carry_angle(Soldier.LOW, false, -0.45, -0.25), Soldier.LOW_ANGLE)


func test_riflemen_with_different_carries_get_different_meshes() -> void:
	# TASK-068: Soldier0 aims, Soldier3 carries low – same kit, so only the carry tells them apart.
	for id: StringName in [&"pl_mech_infantry", &"ru_motor_rifle"]:
		var model := UnitModels.build(id, 0, _poland())
		var aiming := _first_mesh(model.get_node("Model/Soldier0/Rig"))
		var low := _first_mesh(model.get_node("Model/Soldier3/Rig"))
		assert_true(aiming != low, "%s: carries share a mesh" % id)
		model.free()
