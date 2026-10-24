extends TestCase
## Unit mechanisms contract (TASK-043): the model's `MECHANISMS` metadata, its catalog entry and
## the registry (docs/design/units/mechanisms.json) agree. Synthetic trees test the checks.

const Contract := preload("res://tests/mechanism_contract.gd")
const MODELS_DIR := "res://src/presentation/models/"


func _model_ids() -> Array[String]:
	var ids: Array[String] = []
	for file in DirAccess.get_files_at(MODELS_DIR):
		if file.get_extension() == "gd" and file != "model_parts.gd":
			ids.append(file.get_basename())
	ids.sort()
	return ids


## Adds `Parent/Name` chains below `root`; returns the last node.
func _node(root: Node, path: String) -> Node3D:
	var current: Node = root
	for part in path.split("/"):
		var next := current.get_node_or_null(part)
		if next == null:
			next = Node3D.new()
			next.name = part
			current.add_child(next)
		current = next
	return current as Node3D


func _launcher(mouths: int) -> Node3D:
	var root := Node3D.new()
	for i in mouths:
		_node(root, "Launcher/Pod/Mouth%d" % i)
	return root


func _entry(id: String) -> Dictionary:
	return Contract.load_registry()[id]


func _homar() -> Node3D:
	return UnitModels.build(&"homar_k", 0, FactionRegistry.get_faction(&"poland"))


func test_homar_mechanism_params_on_cached_copies() -> void:
	var expected := {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"}
	var a := _homar()
	var b := _homar()
	for model in [a, b]:
		assert_eq(UnitModels.mechanism(model, "launcher"), expected)
		assert_eq(UnitModels.mechanism(model, "turret_traverse"), {})
		assert_true(UnitModels.has_mechanism(model, "wheels"))
		assert_false(UnitModels.has_mechanism(model, "turret_traverse"))
		assert_eq(UnitModels.mechanisms(model.get_node("Model")), UnitModels.mechanisms(model))
	a.free()
	b.free()


func test_model_without_metadata_has_no_mechanisms() -> void:
	var model := Node3D.new()
	assert_eq(UnitModels.mechanisms(model), {})
	assert_eq(UnitModels.mechanism(model, "launcher"), {})
	assert_false(UnitModels.has_mechanism(model, "launcher"))
	model.free()


func test_launcher_mouths_are_counted() -> void:
	var ok := _launcher(6)
	assert_eq(Contract.pivot_violations(ok, _entry("launcher")).size(), 0)
	var few := _launcher(5)
	var violations := Contract.pivot_violations(few, _entry("launcher"))
	assert_eq(violations.size(), 1, str(violations))
	if violations.size() == 1:
		assert_true(
			"Launcher/Pod/Mouth{i}" in violations[0] and "5" in violations[0], violations[0]
		)
		assert_true("6" in violations[0], violations[0])
	ok.free()
	few.free()


func test_actuator_needs_its_rod_and_mount() -> void:
	var model := _launcher(6)
	_node(model, "Launcher/Actuator0")
	var violations := Contract.pivot_violations(model, _entry("launcher"))
	assert_true(violations.size() >= 1)
	assert_true(
		violations.any(func(v: String) -> bool: return "ActuatorRod0" in v), str(violations)
	)
	_node(model, "Launcher/ActuatorRod0")
	_node(model, "Launcher/Pod/ActuatorMount0")
	assert_eq(Contract.pivot_violations(model, _entry("launcher")).size(), 0)
	model.free()


func test_actuator_without_rod_is_exactly_one_violation_when_mount_exists() -> void:
	var model := _launcher(6)
	_node(model, "Launcher/Actuator0")
	_node(model, "Launcher/Pod/ActuatorMount0")
	assert_eq(Contract.pivot_violations(model, _entry("launcher")).size(), 1)
	model.free()


func test_wheels_need_four() -> void:
	var four := Node3D.new()
	var three := Node3D.new()
	for i in 4:
		_node(four, "Wheel%d" % i)
	for i in 3:
		_node(three, "Wheel%d" % i)
	assert_eq(Contract.pivot_violations(four, _entry("wheels")).size(), 0)
	assert_eq(Contract.pivot_violations(three, _entry("wheels")).size(), 1)
	four.free()
	three.free()


func test_meta_pivots_need_their_metadata() -> void:
	var model := Node3D.new()
	var entry := {"id": "x", "pivots": [{"path": "Jack{i}", "min": 1, "meta": ["deployed"]}]}
	_node(model, "Jack0")
	assert_eq(Contract.pivot_violations(model, entry).size(), 1)
	_node(model, "Jack0").set_meta(&"deployed", 0.0)
	assert_eq(Contract.pivot_violations(model, entry).size(), 0)
	model.free()


func test_owned_pivots_of_undeclared_mechanisms() -> void:
	var model := _launcher(6)
	var registry := Contract.load_registry()
	assert_eq(Contract.owned_pivots(model, registry, {}), ["Launcher"])
	assert_eq(Contract.owned_pivots(model, registry, {"launcher": {}}), [])
	model.free()


func test_metadata_matches_the_catalog_or_names_the_model_file() -> void:
	var registry := Contract.load_registry()
	var model := _homar()
	var inner := model.get_node("Model") as Node3D
	var catalog: Variant = Contract.load_catalog_mechanisms("homar_k")
	assert_eq(Contract.problems("homar_k", inner, catalog, registry), [])
	var drifted: Dictionary = catalog.duplicate(true)
	drifted["launcher"]["max_elevation_deg"] = 45
	var problems := Contract.problems("homar_k", inner, drifted, registry)
	assert_eq(problems.size(), 1, str(problems))
	if problems.size() == 1:
		assert_true("src/presentation/models/homar_k.gd" in problems[0], problems[0])
	model.free()


func test_missing_metadata_missing_entry_and_empty_catalog_fail() -> void:
	var registry := Contract.load_registry()
	var bare := _launcher(6)
	var missing := Contract.problems("x", bare, {"launcher": {}}, registry)
	assert_eq(missing.size(), 1)
	assert_true("copy the catalog mechanisms into MECHANISMS" in missing[0], str(missing))
	var no_entry := Contract.problems("x", bare, null, registry)
	assert_eq(no_entry.size(), 1)
	assert_true("no catalog entry" in no_entry[0], str(no_entry))
	var empty := Contract.problems("x", bare, {}, registry)
	assert_eq(empty.size(), 1)
	assert_true("declare and verify" in empty[0], str(empty))
	bare.free()


func test_every_model_agrees_with_its_catalog_entry_and_the_registry() -> void:
	var registry := Contract.load_registry()
	assert_false(registry.is_empty(), "registry readable")
	var faction := FactionRegistry.get_faction(FactionRegistry.DEFAULT_IDS[0])
	var ids := _model_ids()
	assert_true(ids.size() >= 6)
	for id in ids:
		var root := UnitModels.build(StringName(id), 0, faction)
		var catalog: Variant = Contract.load_catalog_mechanisms(id)
		for problem in Contract.problems(id, root.get_node("Model"), catalog, registry):
			assert_true(false, problem)
		root.free()


## The tank pivots the registry doesn't cover yet (turret_traverse is planned, TASK-047).
func test_tanks_have_a_turret_with_a_gun() -> void:
	var faction := FactionRegistry.get_faction(FactionRegistry.DEFAULT_IDS[0])
	for id in [&"m1a2_sepv3", &"t72b3"]:
		var root := UnitModels.build(id, 0, faction)
		assert_true(root.get_node_or_null("Model/Turret/Gun/Muzzle") is Node3D, "%s turret" % id)
		root.free()


## Details of the former per-kind pivot check that the registry doesn't express.
func test_mouths_sit_on_the_front_face_and_kneelers_have_a_stand_pose() -> void:
	var faction := FactionRegistry.get_faction(FactionRegistry.DEFAULT_IDS[0])
	for id in _model_ids():
		var root := UnitModels.build(StringName(id), 0, faction)
		var pod := UnitModels.launcher_pod(root)
		if pod != null:
			for child in pod.get_children():
				if String(child.name).begins_with("Mouth"):
					assert_true((child as Node3D).position.x > 0.2, "%s: %s" % [id, child.name])
		for i in UnitModels.SQUAD_SIZE:
			var rig := root.get_node_or_null("Model/Soldier%d/Rig" % i)
			if rig != null and rig.get_node_or_null("Kneel") != null:
				assert_true(rig.get_node_or_null("Stand") != null, "%s: Soldier%d" % [id, i])
		root.free()
