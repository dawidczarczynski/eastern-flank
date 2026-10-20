extends TestCase
## Argument parsing for tools/render_unit.gd (TASK-036).

const RenderUnitOptions := preload("res://tools/render_unit_options.gd")
const CATALOG_DIR := "user://test_render_unit_catalog"


func before_each() -> void:
	_write_entry(
		"fake_tank",
		{
			"operators": ["atlantis", "russia", "poland"],
			"dimensions": {"hull_length": 9.5, "overall_length": 9.9, "width": 3.6, "height": 2.2},
			"images":
			[
				{"file": "drawing_1.png", "view": "drawing"},
				{"file": "side_1.jpg", "view": "side"},
				{"file": "side_2.jpg", "view": "side"},
			],
		}
	)
	_write_file("fake_tank/side_2.jpg", "not really a jpg")
	_write_entry("no_operators", {"real_name": "x"})


func after_each() -> void:
	_remove_dir(CATALOG_DIR)


func _parse(args: Array, existing: Array = ["fake_tank", "no_operators", "bare"]) -> Dictionary:
	var model_exists := func(unit_id: StringName) -> bool: return String(unit_id) in existing
	return RenderUnitOptions.parse(PackedStringArray(args), CATALOG_DIR, model_exists)


func test_defaults_without_catalog_entry() -> void:
	var options := _parse(["bare"])
	assert_eq(options["error"], "")
	assert_eq(options["unit_id"], "bare")
	assert_eq(options["faction"], "poland")
	assert_eq(options["views"], ["side", "front", "top", "three_quarter"])
	assert_eq(options["reference"], "")
	assert_eq(options["real"], {})
	assert_true(String(options["out"]).is_absolute_path())
	assert_true(String(options["out"]).ends_with(".screenshots/units/bare_poland_sheet.png"))


func test_default_faction_is_first_known_operator() -> void:
	assert_eq(_parse(["no_operators"])["faction"], "poland")
	var options := _parse(["fake_tank"])
	assert_eq(options["error"], "")
	assert_eq(options["faction"], "russia", "atlantis is not a faction, russia is the first known")
	assert_true(String(options["out"]).ends_with("fake_tank_russia_sheet.png"))


func test_default_reference_is_first_existing_side_image() -> void:
	var options := _parse(["fake_tank"])
	# side_1.jpg is not on disk, side_2.jpg is: the first existing side image wins over the drawing.
	assert_true(String(options["reference"]).ends_with("fake_tank/side_2.jpg"))
	assert_true(String(options["reference"]).is_absolute_path())


func test_real_dimensions_prefer_overall_length_else_hull_length() -> void:
	var real: Dictionary = _parse(["fake_tank"])["real"]
	assert_eq(real["length"], 9.9)
	assert_eq(real["width"], 3.6)
	assert_eq(real["height"], 2.2)
	real = RenderUnitOptions.real_dimensions(
		{"dimensions": {"hull_length": 9.5, "width": 3.6, "height": 2.2}}
	)
	assert_eq(real["length"], 9.5)
	assert_eq(RenderUnitOptions.real_dimensions({"dimensions": {"width": 3.6, "height": 2.2}}), {})


func test_explicit_faction_views_out_and_reference() -> void:
	var reference := ProjectSettings.globalize_path("%s/fake_tank/side_2.jpg" % CATALOG_DIR)
	var options := _parse(
		[
			"fake_tank",
			"--faction=poland",
			"--views=side,top",
			"--out=/tmp/x_sheet.png",
			"--reference=" + reference,
		]
	)
	assert_eq(options["error"], "")
	assert_eq(options["faction"], "poland")
	assert_eq(options["views"], ["side", "top"])
	assert_eq(options["out"], "/tmp/x_sheet.png")
	assert_eq(options["reference"], reference)


func test_views_keep_order_and_drop_duplicates() -> void:
	assert_eq(_parse(["bare", "--views=top,side,top"])["views"], ["top", "side"])


func test_faction_flag_and_unknown_faction() -> void:
	assert_eq(_parse(["bare", "--faction=russia"])["faction"], "russia")
	assert_eq(_parse(["bare", "--faction=atlantis"])["error"], "unknown_faction")


func test_empty_views_is_an_error() -> void:
	assert_eq(_parse(["bare", "--views="])["error"], "invalid_views")
	assert_eq(_parse(["bare", "--views=side,"])["error"], "invalid_views")
	assert_eq(_parse(["bare", "--views=side,rear"])["error"], "unknown_view")


func test_unit_without_model_file_is_an_error() -> void:
	assert_eq(_parse(["ghost"])["error"], "unknown_unit")


func test_default_model_lookup_knows_current_units() -> void:
	var options := RenderUnitOptions.parse(PackedStringArray(["cavalry", "--faction=russia"]))
	assert_eq(options["error"], "")
	assert_eq(options["faction"], "russia")
	assert_eq(RenderUnitOptions.parse(PackedStringArray(["no_such_unit"]))["error"], "unknown_unit")


func test_missing_explicit_reference_is_an_error() -> void:
	assert_eq(_parse(["bare", "--reference=/nonexistent/x.png"])["error"], "reference_not_found")


func test_invalid_unit_id_and_extra_arguments() -> void:
	assert_eq(_parse([])["error"], "missing_unit_id")
	assert_eq(_parse(["--faction=russia"])["error"], "missing_unit_id")
	assert_eq(_parse(["Bad-Id"])["error"], "invalid_unit_id")
	assert_eq(_parse(["bare", "other"])["error"], "too_many_arguments")
	assert_eq(_parse(["bare", "--zoom=3"])["error"], "unknown_option")


func test_empty_flag_values_are_errors() -> void:
	assert_eq(_parse(["bare", "--faction="])["error"], "empty_option")
	assert_eq(_parse(["bare", "--out="])["error"], "empty_option")
	assert_eq(_parse(["bare", "--reference="])["error"], "empty_option")
	assert_eq(_parse(["bare", "--faction=poland", "--faction=russia"])["faction"], "russia")


func test_foot_unit_compares_soldier_height_and_takes_any_soldier_photo() -> void:
	# A squad entry describes one soldier: the squad's footprint is not the soldier's width/depth.
	var entry := {
		"mobility": "foot", "dimensions": {"hull_length": 0.45, "width": 0.6, "height": 1.8}
	}
	var real := RenderUnitOptions.real_dimensions(entry)
	assert_eq(real, {"height": 1.8})
	assert_eq(
		RenderUnitOptions.real_line(Vector3(0.5, 1.98, 0.6), real),
		"Real: soldier height 1.8 m, diff: +10.0%"
	)
	assert_eq(RenderUnitOptions.real_dimensions({"mobility": "foot", "dimensions": {}}), {})
	# No drawings of soldiers: a front or three-quarter photo is the reference (not a detail shot).
	_write_entry(
		"fake_squad",
		{
			"mobility": "foot",
			"images":
			[
				{"file": "detail_1.jpg", "view": "detail"},
				{"file": "three_quarter_1.jpg", "view": "three_quarter"},
				{"file": "front_1.jpg", "view": "front"},
			],
		}
	)
	_write_file("fake_squad/detail_1.jpg", "x")
	_write_file("fake_squad/three_quarter_1.jpg", "x")
	_write_file("fake_squad/front_1.jpg", "x")
	var options := _parse(["fake_squad"], ["fake_squad"])
	assert_true(
		String(options["reference"]).ends_with("fake_squad/front_1.jpg"), options["reference"]
	)


func test_view_path_sits_next_to_the_sheet() -> void:
	assert_eq(
		RenderUnitOptions.view_path("/a/t72b3_russia_sheet.png", "side"), "/a/t72b3_russia_side.png"
	)
	assert_eq(RenderUnitOptions.view_path("/a/custom.png", "top"), "/a/custom_top.png")


func test_real_line_shows_signed_percent_difference() -> void:
	var real := {"length": 10.0, "width": 4.0, "height": 2.0}
	assert_eq(
		RenderUnitOptions.real_line(Vector3(11.0, 2.0, 3.0), real),
		"Real: 10x4x2 m, diff: +10.0%/-25.0%/+0.0%"
	)
	assert_eq(RenderUnitOptions.real_line(Vector3.ONE, {}), "")
	var rounded := RenderUnitOptions.real_line(Vector3(9.99999, 2.0, 4.0), real)
	assert_true(not rounded.contains("-0.0%"), rounded)


func test_ortho_size_fits_every_view_with_margin() -> void:
	# 10 long (x), 4 high (y), 3 wide (z), 16:9: the side view is width-limited.
	var size := RenderUnitOptions.ortho_size(AABB(Vector3.ZERO, Vector3(10, 4, 3)), 16.0 / 9.0)
	assert_true(absf(size - 10.0 / (16.0 / 9.0) * 1.1) < 0.0001, str(size))
	# A tall, narrow model is height-limited.
	var tall := RenderUnitOptions.ortho_size(AABB(Vector3.ZERO, Vector3(2, 6, 1)), 16.0 / 9.0)
	assert_true(absf(tall - 6.6) < 0.0001, str(tall))


func test_summarize_names_collapses_numbered_runs() -> void:
	var names := ["Wheel0", "Wheel1", "Wheel2", "Turret", "Wheel3", "Turret", "Wheel5"]
	assert_eq(RenderUnitOptions.summarize_names(names), "Wheel0-3,Wheel5,Turret")
	assert_eq(
		RenderUnitOptions.summarize_names(["Soldier0", "Rig", "Soldier1", "Rig"]), "Soldier0-1,Rig"
	)


func _write_entry(unit_id: String, entry: Dictionary) -> void:
	_write_file("%s/unit.json" % unit_id, JSON.stringify(entry))


func _write_file(relative: String, content: String) -> void:
	var path := "%s/%s" % [CATALOG_DIR, relative]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _remove_dir(path: String) -> void:
	for dir in DirAccess.get_directories_at(path):
		_remove_dir("%s/%s" % [path, dir])
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute("%s/%s" % [path, file])
	DirAccess.remove_absolute(path)
