extends TestCase
## WeaponBlueprint (TASK-146): a drawing, dimensions and labels for every shipped weapon.


func test_every_shipped_means_has_a_blueprint() -> void:
	assert_eq(StrikeMeansDefinition.SHIPPED.size(), 12)
	for id in StrikeMeansDefinition.SHIPPED:
		assert_true(WeaponBlueprint.has_blueprint(id), "blueprint for %s" % id)
		var dims := WeaponBlueprint.dimensions(id)
		assert_true(dims["length_m"] > dims["diameter_m"], "%s is longer than wide" % id)


func test_unknown_id_has_no_blueprint() -> void:
	assert_false(WeaponBlueprint.has_blueprint(&"nope"))
	assert_eq(WeaponBlueprint.dimensions(&"nope"), {})
	assert_eq(WeaponBlueprint.labels(&"nope").size(), 0)


func test_labels_match_the_table() -> void:
	assert_eq(WeaponBlueprint.labels(&"iskander_m"), ["7.2 m", "Ø 0.92 m"] as Array[String])
	assert_eq(
		WeaponBlueprint.labels(&"geran_2"), ["3.5 m", "Ø 0.5 m", "span 2.5 m"] as Array[String]
	)
	assert_eq(
		WeaponBlueprint.labels(&"kalibr"), ["6.2 m", "Ø 0.53 m", "span 3.3 m"] as Array[String]
	)
	assert_eq(WeaponBlueprint.labels(&"homar_k")[0], "4 m")
	assert_eq(WeaponBlueprint.labels(&"jassm_er")[0], "4.27 m")
	for id in StrikeMeansDefinition.SHIPPED:
		var span: float = WeaponBlueprint.dimensions(id)["span_m"]
		assert_eq(WeaponBlueprint.labels(id).size(), 3 if span > 0.0 else 2, str(id))
