extends TestCase
## The squads' anti-tank launcher (parts/at_launcher.gd): a visual kind per country, one node
## contract – the gunner's posture nodes carry AtLauncher with its Muzzle at the tube's front,
## pointing along the tube (TASK-188b fires from it whatever the kind).

const AtLauncher := preload("res://src/presentation/models/parts/at_launcher.gd")
## Squad -> [AT gunner slot, launcher kind].
const SQUADS := {
	&"pl_mech_infantry": [1, AtLauncher.CARL_GUSTAF],
	&"ru_motor_rifle": [1, AtLauncher.RPG7],
}


func test_every_kind_gives_the_gunner_an_at_launcher_with_a_forward_muzzle() -> void:
	for id: StringName in SQUADS:
		var script := load("res://src/presentation/models/%s.gd" % id) as GDScript
		var constants := script.get_script_constant_map()
		assert_eq(constants[&"AT_LAUNCHER_KIND"], SQUADS[id][1], "%s kind" % id)
		var root := UnitModels.build(id, 0, null)
		var gunner := root.get_node("Model/Soldier%d/Rig" % SQUADS[id][0]) as Node3D
		var muzzles := gunner.find_children("Muzzle", "Node3D", true, false)
		assert_true(not muzzles.is_empty(), "%s: no AtLauncher/Muzzle" % id)
		for node: Node in muzzles:
			var muzzle := node as Node3D
			assert_eq(String(muzzle.get_parent().name), "AtLauncher", "%s muzzle parent" % id)
			var launcher := muzzle.get_parent() as Node3D
			# In front of the launcher's middle along its own x, about half a tube away.
			assert_true(muzzle.position.x > 0.03, "%s muzzle %s" % [id, muzzle.position])
			assert_true(absf(muzzle.position.y) < 0.001 and absf(muzzle.position.z) < 0.001)
			assert_true(muzzle.transform.basis.x.is_equal_approx(Vector3.RIGHT))
			assert_true(launcher.transform.basis.x.x > 0.9, "%s launcher faces +x" % id)
		root.free()
