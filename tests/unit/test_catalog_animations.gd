extends TestCase

const IDS := preload("res://src/presentation/catalog/catalog_animations.gd")


func _animations(unit_id: StringName) -> Array[StringName]:
	var model := UnitModels.build(unit_id, 0, null)
	var result := IDS.for_model(model)
	model.free()
	return result


func test_homar_k_offers_drive_deploy_raise_traverse_fire() -> void:
	assert_eq(_animations(&"homar_k"), [IDS.DRIVE, IDS.DEPLOY, IDS.RAISE, IDS.TRAVERSE, IDS.FIRE])


func test_uragan_offers_the_same_set() -> void:
	assert_eq(
		_animations(&"bm27_uragan"), [IDS.DRIVE, IDS.DEPLOY, IDS.RAISE, IDS.TRAVERSE, IDS.FIRE]
	)


func test_launcher_and_stabilisers_alone_give_deploy_raise_traverse_fire() -> void:
	var model := Node3D.new()
	model.set_meta(&"mechanisms", {"launcher": {}, "stabilisers": {}})
	model.add_child(Node3D.new())
	model.get_child(0).name = "Launcher"
	assert_eq(IDS.for_model(model), [IDS.DEPLOY, IDS.RAISE, IDS.TRAVERSE, IDS.FIRE])
	model.free()


func test_squads_march_and_kneel() -> void:
	assert_eq(_animations(&"pl_mech_infantry"), [IDS.MARCH, IDS.KNEEL])
	assert_eq(_animations(&"ru_motor_rifle"), [IDS.MARCH, IDS.KNEEL])


func test_tanks_only_drive_until_the_turret_animates() -> void:
	assert_eq(_animations(&"m1a2_sepv3"), [IDS.DRIVE])
	assert_eq(_animations(&"t72b3"), [IDS.DRIVE])


func test_a_model_without_metadata_offers_nothing() -> void:
	var model := Node3D.new()
	assert_eq(IDS.for_model(model), [] as Array[StringName])
	model.free()


func test_mechanism_table_maps_declared_mechanisms() -> void:
	var model := Node3D.new()
	model.set_meta(&"mechanisms", {"wheels": {}, "stabilisers": {}})
	assert_eq(IDS.for_model(model), [IDS.DRIVE, IDS.DEPLOY])
	# `launcher` without a turntable in the model offers no launcher animations
	model.set_meta(&"mechanisms", {"launcher": {}})
	assert_eq(IDS.for_model(model), [] as Array[StringName])
	model.free()


func test_every_animation_has_a_translatable_label_and_order() -> void:
	for id in IDS.ORDER + IDS.COMMON:
		assert_true(IDS.LABELS.has(id), "label for %s" % id)
	for mechanism: String in IDS.TABLE:
		for id: StringName in IDS.TABLE[mechanism]:
			assert_true(id in IDS.ORDER, "%s is in ORDER" % id)


func test_traverse_angle_stays_inside_the_range() -> void:
	var uragan := UnitModels.build(&"bm27_uragan", 0, null)
	var params := UnitModels.launcher_params(uragan)
	var angle := IDS.traverse_angle(uragan)
	if params["traverse_deg"] is Array:
		var lo := deg_to_rad(float(params["traverse_deg"][0]))
		var hi := deg_to_rad(float(params["traverse_deg"][1]))
		assert_true(angle >= lo and angle <= hi)
	assert_true(absf(angle) > 0.1, "a visible turn")
	uragan.free()
	var homar := UnitModels.build(&"homar_k", 0, null)
	assert_true(absf(IDS.traverse_angle(homar)) > 0.1)
	homar.free()
