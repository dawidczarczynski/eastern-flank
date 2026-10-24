extends TestCase
## Soldier v4 (TASK-085): real proportions (ANSUR II), limbs placed by two-bone IK with fixed
## segment lengths, ambient occlusion baked into the vertex masks, mask-reading materials.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
const MODELS := {
	&"pl_mech_infantry": preload("res://src/presentation/models/pl_mech_infantry.gd"),
	&"ru_motor_rifle": preload("res://src/presentation/models/ru_motor_rifle.gd"),
}
const CAMO_SHADER := "res://assets/shaders/camo.gdshader"
const SKIN_SHADER := "res://assets/shaders/skin.gdshader"
## Joint lengths must match within 1 cm.
const LENGTH_TOLERANCE := 0.01
## Largest distance (m) from a limb joint to the nearest vertex of its sleeve / trousers / glove /
## boot (the limb's radius is 3–7 cm).
const REACH_TOLERANCE := 0.08


func _faction(id: StringName) -> FactionDefinition:
	return load("res://data/factions/%s.tres" % id) as FactionDefinition


## [pose, dress, kits] for every soldier of the model in every posture it is built in (kneelers also
## standing: the hidden Stand variant), the arms built so the joints are filled.
func _variants(model: GDScript) -> Array:
	var result := []
	var layout: Array = model.get(&"SQUAD")
	var stances: Dictionary = model.get(&"STANCES")
	var dress := Callable(model, &"dress")
	for i in layout.size():
		var entry: Array = layout[i]
		var postures := [true, false] if entry[2] else [false]
		for kneel: bool in postures:
			var pose := Soldier.entry_pose(entry, i, stances, kneel)
			var kits := Soldier.soldier_kits(pose, dress)
			result.append([pose, dress, kits])
	return result


## A standing rifleman at READY looking ahead.
func _standing() -> SoldierPose:
	return SoldierPose.make(false, 0, Soldier.READY, Soldier.RIFLE_STANCE, 0)


func _verts(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_limbs_keep_their_anatomical_lengths_in_every_pose() -> void:
	for id: StringName in MODELS:
		for variant: Array in _variants(MODELS[id]):
			var pose: SoldierPose = variant[0]
			var j := pose.joints
			var label := "%s slot %d kneel %s" % [id, pose.slot, pose.kneel]
			for tag in ["l", "r"]:
				var pairs := [
					["shoulder_", "elbow_", SoldierPose.UPPER_ARM],
					["elbow_", "wrist_", SoldierPose.FOREARM],
					["hip_", "knee_", SoldierPose.THIGH],
					["knee_", "ankle_", SoldierPose.SHIN],
				]
				for pair: Array in pairs:
					var a: Vector3 = j[StringName(pair[0] + tag)]
					var b: Vector3 = j[StringName(pair[1] + tag)]
					var length := a.distance_to(b)
					assert_true(
						absf(length - pair[2]) <= LENGTH_TOLERANCE,
						"%s: %s%s–%s%s %.3f m" % [label, pair[0], tag, pair[1], tag, length]
					)


## The built limbs reach the solved joints: sleeve / trouser vertices around the elbows and knees,
## glove and boot vertices around the wrists and ankles (within a limb's radius + a few cm).
func test_built_limbs_reach_the_solved_joints() -> void:
	for id: StringName in MODELS:
		for variant: Array in _variants(MODELS[id]):
			var pose: SoldierPose = variant[0]
			var meshes := (variant[2] as MeshKits).commit_all()
			var checks := {
				&"uniform": [&"elbow_l", &"elbow_r", &"knee_l", &"knee_r"],
				&"dark": [&"wrist_l", &"wrist_r", &"ankle_l", &"ankle_r"],
			}
			for role: StringName in checks:
				var joints: Array = checks[role]
				var nearest := []
				nearest.resize(joints.size())
				nearest.fill(INF)
				for v in _verts(meshes[role]):
					var p := v / Soldier.M
					for j in joints.size():
						var d := p.distance_squared_to(pose.joints[joints[j]])
						if d < nearest[j]:
							nearest[j] = d
				for j in joints.size():
					assert_true(
						sqrt(nearest[j]) <= REACH_TOLERANCE,
						(
							"%s slot %d kneel %s: %s %.3f m from the mesh"
							% [id, pose.slot, pose.kneel, joints[j], sqrt(nearest[j])]
						)
					)


func test_elbows_hang_below_the_shoulder_hand_line() -> void:
	for id: StringName in MODELS:
		for variant: Array in _variants(MODELS[id]):
			var pose: SoldierPose = variant[0]
			for tag in ["l", "r"]:
				var shoulder: Vector3 = pose.joints[StringName("shoulder_" + tag)]
				var hand: Vector3 = pose.joints[StringName("hand_" + tag)]
				var elbow: Vector3 = pose.joints[StringName("elbow_" + tag)]
				var line := hand - shoulder
				var t := clampf((elbow - shoulder).dot(line) / line.length_squared(), 0.0, 1.0)
				var on_line := shoulder + line * t
				assert_true(
					elbow.y < on_line.y,
					(
						"%s slot %d %s: elbow %s above the line %s"
						% [id, pose.slot, tag, elbow, on_line]
					)
				)


func test_head_and_helmet_are_at_most_a_seventh_of_the_figure() -> void:
	for id: StringName in MODELS:
		var pose := _standing()
		var meshes := Soldier.soldier_kits(pose, Callable(MODELS[id], &"dress")).commit_all()
		var top := 0.0
		for role: StringName in meshes:
			for v in _verts(meshes[role]):
				top = maxf(top, v.y / Soldier.M)
		var chin: Vector3 = pose.joints[&"chin"]
		assert_true(top > 1.7 and top < 1.9, "%s figure height %.3f m" % [id, top])
		assert_true(
			top - chin.y <= top / 7.0,
			(
				"%s: head + helmet %.3f m of %.3f m (%.2f heads)"
				% [id, top - chin.y, top, top / (top - chin.y)]
			)
		)


func test_helmets_have_their_real_outer_size() -> void:
	for id: StringName in MODELS:
		var pose := _standing()
		var meshes := Soldier.soldier_kits(pose, Callable(MODELS[id], &"dress")).commit_all()
		var to_helmet := pose.helmet.affine_inverse()
		var box := AABB()
		var first := true
		for v in _verts(meshes[&"uniform"]):
			var local := to_helmet * (v / Soldier.M)
			if local.y < -0.05 or Vector2(local.x, local.z).length() > 0.25:
				continue
			if first:
				box = AABB(local, Vector3.ZERO)
				first = false
			box = box.expand(local)
		assert_true(
			box.size.z >= 0.27 and box.size.z <= 0.31, "%s helmet width %.3f" % [id, box.size.z]
		)
		assert_true(
			box.size.x >= 0.3 and box.size.x <= 0.34, "%s helmet length %.3f" % [id, box.size.x]
		)


func test_soldier_meshes_carry_baked_occlusion() -> void:
	for id: StringName in MODELS:
		var pose := _standing()
		var meshes := Soldier.variant_meshes(pose, Callable(MODELS[id], &"dress"))
		for role: StringName in meshes:
			var colors: PackedColorArray = (meshes[role] as ArrayMesh).surface_get_arrays(0)[
				Mesh.ARRAY_COLOR
			]
			assert_eq(colors.size(), _verts(meshes[role]).size(), "%s %s masks" % [id, role])
		# Body and helmet (uniform): occluded creases, mostly open; the skin (face and neck, mostly
		# under the helmet) only needs its shading.
		# Body and helmet (uniform): occluded creases, mostly open. Skin (face and neck, mostly under
		# the helmet, dark by design) and vest (under the pouches and the pack): occluded vertices.
		for role: StringName in [&"uniform", &"skin", &"vest"]:
			var colors: PackedColorArray = (meshes[role] as ArrayMesh).surface_get_arrays(0)[
				Mesh.ARRAY_COLOR
			]
			var dark := 0
			var open := 0
			for c in colors:
				if c.g <= 0.6:
					dark += 1
				if c.g >= 0.9:
					open += 1
			assert_true(dark > 0, "%s %s: no occluded vertices" % [id, role])
			if role == &"uniform":
				assert_true(
					open > colors.size() / 2,
					"%s %s: open %d of %d" % [id, role, open, colors.size()]
				)


func test_the_helmet_is_darker_under_the_brim_than_on_top() -> void:
	for id: StringName in MODELS:
		var pose := _standing()
		var meshes := Soldier.variant_meshes(pose, Callable(MODELS[id], &"dress"))
		var arrays := (meshes[&"uniform"] as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var to_helmet := pose.helmet.affine_inverse()
		var under := []
		var top := []
		for i in verts.size():
			var local := to_helmet * (verts[i] / Soldier.M)
			if Vector2(local.x, local.z).length() > 0.25 or local.y < -0.05:
				continue
			var up := (to_helmet.basis * normals[i]).normalized().y
			if local.y < 0.0 and up < -0.5:
				under.append(colors[i].g)
			elif local.y > 0.1 and up > 0.5:
				top.append(colors[i].g)
		assert_true(not under.is_empty() and not top.is_empty(), "%s: brim and crown found" % id)
		var mean_under: float = under.reduce(func(a: float, b: float) -> float: return a + b, 0.0)
		var mean_top: float = top.reduce(func(a: float, b: float) -> float: return a + b, 0.0)
		mean_under /= under.size()
		mean_top /= top.size()
		assert_true(
			mean_under < mean_top - 0.1, "%s: under %.2f, top %.2f" % [id, mean_under, mean_top]
		)


func test_every_soldier_material_reads_the_vertex_masks() -> void:
	for id: StringName in MODELS:
		for faction_id: StringName in [&"poland", &"russia"]:
			var model := UnitModels.build(id, 0, _faction(faction_id))
			var meshes := 0
			for instance in _all_meshes(model):
				meshes += 1
				var material := instance.material_override as ShaderMaterial
				assert_true(
					material != null, "%s %s: %s" % [id, faction_id, instance.material_override]
				)
				if material == null:
					continue
				var code := material.shader.code
				assert_true(
					code.contains("COLOR.g"),
					"%s: %s ignores the AO mask" % [id, material.shader.resource_path]
				)
				if material.shader.resource_path == CAMO_SHADER:
					var mask_ao: Variant = material.get_shader_parameter(&"mask_ao")
					assert_true(
						mask_ao != null and float(mask_ao) > 0.0, "%s: camo without mask_ao" % id
					)
				else:
					assert_eq(material.shader.resource_path, SKIN_SHADER)
					assert_true(code.contains("AO = COLOR.g"), "skin uses COLOR.g as AO")
			assert_true(meshes > 0)
			model.free()


func _all_meshes(node: Node, into: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			into.append(child)
		_all_meshes(child, into)
	return into
