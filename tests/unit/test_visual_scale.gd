extends TestCase

const EPSILON := 1e-4


func before_each() -> void:
	VisualScale.reset()


func after_each() -> void:
	VisualScale.reset()


func _check(values: Dictionary, unit: float, tree: float, bush: float, rock: float) -> void:
	assert_eq(values["grass_scale"], bush, "grass follows bush")
	assert_eq(values["unit_model_scale"], unit)
	assert_eq(values["tree_scale"], tree)
	assert_eq(values["bush_scale"], bush)
	assert_eq(values["rock_scale"], rock)


func _bounds(node: Node3D, to_root: Transform3D) -> AABB:
	var result := AABB()
	var has := false
	for child: Node in node.get_children():
		var spatial := child as Node3D
		if spatial == null:
			continue
		var t := to_root * spatial.transform
		var box := AABB()
		var has_box := false
		var instance := spatial as MeshInstance3D
		if instance != null:
			box = t * instance.get_aabb()
			has_box = true
		var inner := _bounds(spatial, t)
		if inner.size != Vector3.ZERO:
			box = box.merge(inner) if has_box else inner
			has_box = true
		if has_box:
			result = result.merge(box) if has else box
			has = true
	return result


func _length(root: Node3D) -> float:
	return _bounds(root, Transform3D.IDENTITY).size.x


func test_preset_values() -> void:
	_check(VisualScale.preset(&"current"), 1.3, 1.0, 1.0, 1.0)
	_check(VisualScale.preset(&"balanced"), 1.1, 1.8, 1.4, 1.0)
	_check(VisualScale.preset(&"realistic"), 0.9, 2.6, 1.8, 1.0)


func test_unknown_preset_falls_back_to_default() -> void:
	_check(VisualScale.preset(&"nonsense"), 1.1, 1.8, 1.4, 1.0)


func test_default_active_preset_is_balanced() -> void:
	assert_eq(VisualScale.unit_model_scale(), 1.1)
	assert_eq(VisualScale.tree_scale(), 1.8)
	assert_eq(VisualScale.bush_scale(), 1.4)


func test_unit_model_shrinks_proportionally() -> void:
	var faction := load("res://data/factions/poland.tres") as FactionDefinition
	VisualScale.apply(&"current")
	var root_a := UnitModels.build(&"m1a2_sepv3", 0, faction)
	var length_a := _length(root_a)
	VisualScale.apply_values({"unit_model_scale": 0.9})
	var root_b := UnitModels.build(&"m1a2_sepv3", 0, faction)
	var length_b := _length(root_b)
	root_a.free()
	root_b.free()
	assert_true(length_a > 0.0)
	assert_true(absf(length_b / length_a - 0.9 / 1.3) < EPSILON, "ratio %f" % (length_b / length_a))


func test_tree_transform_scales_with_tree_scale() -> void:
	var tree := {
		"position": Vector3(1, 2, 3), "scale": 0.8, "height_scale": 0.9, "yaw": 0.5, "k": 0.1
	}
	var base := MapView._tree_transforms([tree])[0]
	var scaled := MapView._tree_transforms([tree], VisualScale.preset(&"balanced")["tree_scale"])[0]
	assert_true(scaled.origin.is_equal_approx(base.origin), "position unchanged")
	assert_true(absf(scaled.basis.y.length() / base.basis.y.length() - 1.8) < EPSILON)
	assert_true(absf(scaled.basis.x.length() / base.basis.x.length() - 1.8) < EPSILON)
