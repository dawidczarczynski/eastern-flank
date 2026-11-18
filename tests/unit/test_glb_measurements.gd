extends TestCase
## Measurements of a normalised reference GLB (TASK-180, tools/glb_measurements.gd) on synthetic
## tanks: a box hull, a cylinder turret, a cylinder gun and cylinder road wheels.

const GlbReference := preload("res://tools/glb_reference.gd")
const GlbMeasurements := preload("res://tools/glb_measurements.gd")
const GLB_PATH := "user://test_glb_measurements.glb"
## The fixture is built in metres with the gun at +x: overall 9.0 m (hull 7.0 + gun 2.0).
const REAL := {"length": 9.0, "width": 3.2, "height": 2.1}
const CATALOG := {"hull_length": 7.0, "overall_length": 9.0, "width": 3.2, "height": 2.1}
const TOLERANCE := 0.06

static var _measured: Dictionary


func before_all() -> void:
	_measured = _measure_scene(_tank(), REAL, CATALOG)


func _add_mesh(root: Node3D, mesh: Mesh, position: Vector3, rotation := Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	root.add_child(instance)


func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	return cylinder


## Hull x -3.5..3.5 (nose at +3.5), y 0.6..1.5, half width 1.6; tracks 1.0..1.6 off the centre
## line, y 0..0.6; turret r 1.0, y 1.5..2.1 centred at x -0.5; gun r 0.08 at h 1.8 from the
## turret to x 5.5; five road wheels r 0.35 per side at h 0.4. In model frame (x from the nose):
## HULL_LENGTH 7, DECK_H 1.5, ROOF_H 2.1, TURRET_X 4, TURRET_RING_R 1, TRUNNION (3, 1.8),
## UPPER_HW 1.6, LOWER_HW 1.0, GUN_OVERHANG 2, wheels at 1.1, 2.3, 3.5, 4.7, 5.9.
func _tank() -> Node3D:
	var root := Node3D.new()
	_add_mesh(root, _box(Vector3(7.0, 0.9, 3.2)), Vector3(0.0, 1.05, 0.0))
	for side in [-1.0, 1.0]:
		_add_mesh(root, _box(Vector3(6.6, 0.6, 0.6)), Vector3(0.0, 0.3, side * 1.3))
		for x in [-2.4, -1.2, 0.0, 1.2, 2.4]:
			_add_mesh(
				root, _cylinder(0.35, 0.3), Vector3(x, 0.4, side * 1.3), Vector3(PI / 2.0, 0.0, 0.0)
			)
	_add_mesh(root, _cylinder(1.0, 0.6), Vector3(-0.5, 1.8, 0.0))
	_add_mesh(root, _cylinder(0.08, 5.0), Vector3(3.0, 1.8, 0.0), Vector3(0.0, 0.0, PI / 2.0))
	return root


## Round trip through a GLB file, normalise, measure.
func _measure_scene(scene: Node3D, real: Dictionary, catalog: Dictionary) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(scene, state)
	document.write_to_filesystem(state, GLB_PATH)
	scene.free()
	var loaded := GlbReference.load_scene(ProjectSettings.globalize_path(GLB_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GLB_PATH))
	var foot := not real.has("length")
	GlbReference.normalise(loaded, real)
	var mesh := GlbReference.triangles(loaded)
	loaded.free()
	return GlbMeasurements.measure(mesh["positions"], mesh["indices"], catalog, foot)


func _constant(name: String) -> Variant:
	var constants: Dictionary = _measured["constants"]
	assert_true(constants.has(name), "%s measured" % name)
	return constants.get(name, {}).get("value", 0.0)


func _assert_near(name: String, expected: float) -> void:
	var value: float = _constant(name)
	assert_true(
		absf(value - expected) <= TOLERANCE, "%s = %s, expected %s" % [name, value, expected]
	)


func test_hull_levels_and_widths_match_the_fixture() -> void:
	_assert_near("HULL_LENGTH", 7.0)
	_assert_near("DECK_H", 1.5)
	_assert_near("ROOF_H", 2.1)
	_assert_near("UPPER_HW", 1.6)
	_assert_near("LOWER_HW", 1.0)
	_assert_near("GUN_OVERHANG", 2.0)


func test_turret_and_gun_are_detected() -> void:
	_assert_near("TURRET_X", 4.0)
	_assert_near("TURRET_RING_R", 1.0)
	var trunnion: Array = _constant("TRUNNION")
	assert_true(absf(float(trunnion[0]) - 3.0) <= 0.15, "trunnion x %s" % trunnion[0])
	assert_true(absf(float(trunnion[1]) - 1.8) <= TOLERANCE, "trunnion h %s" % trunnion[1])
	_assert_near("GUN_ELEVATION_DEG", 0.0)


func test_road_wheels_count_positions_and_radius() -> void:
	var wheels: Dictionary = _constant("ROAD_WHEELS")
	assert_eq(wheels.get("count_per_side"), 5)
	assert_true(absf(float(wheels.get("radius", 0.0)) - 0.35) <= 0.02, "radius %s" % wheels)
	assert_true(absf(float(wheels.get("h", 0.0)) - 0.4) <= 0.02, "wheel h %s" % wheels)
	var xs: Array = wheels.get("x", [])
	var expected := [1.1, 2.3, 3.5, 4.7, 5.9]
	for i in mini(xs.size(), expected.size()):
		assert_true(absf(float(xs[i]) - expected[i]) <= 0.02, "wheel %d at %s" % [i, xs[i]])


func test_every_constant_has_a_confidence() -> void:
	var constants: Dictionary = _measured["constants"]
	for name: String in constants:
		var confidence: float = constants[name]["confidence"]
		assert_true(confidence >= 0.0 and confidence <= 1.0, "%s confidence" % name)
	assert_true(float(constants["ROAD_WHEELS"]["confidence"]) >= 0.8, "5 + 5 wheels: confident")


func test_profiles_every_tenth_of_a_metre_for_the_hull_and_above_the_deck() -> void:
	var profiles: Dictionary = _measured["profiles"]
	var hull: Array = profiles["hull"]
	var above: Array = profiles["above_deck"]
	assert_true(
		hull.size() >= 69 and hull.size() <= 72, "7 m hull = 70 slabs, got %d" % hull.size()
	)
	assert_true(absf(float(hull[1]["x"]) - float(hull[0]["x"]) - 0.1) < 0.001, "step 0.1")
	var middle: Dictionary = hull[35]
	assert_true(absf(float(middle["h"]) - 1.5) < 0.03, "hull top at the deck: %s" % middle)
	assert_true(absf(float(middle["hw"]) - 1.6) < 0.03, "hull half width: %s" % middle)
	var turret_top := 0.0
	var gun_slabs := 0
	for row: Dictionary in above:
		if absf(float(row["x"]) - 4.0) < 0.1:
			turret_top = row["h"]
		if float(row["x"]) < 0.0:
			gun_slabs += 1
	assert_true(absf(turret_top - 2.1) < 0.03, "turret roof in the above-deck profile")
	assert_true(gun_slabs >= 19, "the gun ahead of the nose is in the profile: %d" % gun_slabs)


func test_a_consistent_fixture_has_no_warnings() -> void:
	assert_eq(_measured["warnings"], [])


func test_catalog_conflicts_and_low_confidence_go_to_warnings() -> void:
	var constants := {
		"HULL_LENGTH": {"value": 7.0, "confidence": 0.8, "note": ""},
		"LOWER_HW": {"value": 0.1, "confidence": 0.2, "note": "inner edge"},
	}
	var conflicts := GlbMeasurements.catalog_warnings(constants, AABB(), {"hull_length": 6.0})
	assert_eq(conflicts.size(), 1)
	assert_true(conflicts[0].begins_with("HULL_LENGTH"), conflicts[0])
	var low := GlbMeasurements.low_confidence_warnings(constants)
	assert_eq(low.size(), 1)
	assert_true(low[0].begins_with("LOWER_HW"), low[0])


func test_fused_wheels_are_a_warning_not_a_guess() -> void:
	var positions := PackedVector3Array()
	var indices := PackedInt32Array()
	var box := _box(Vector3(6.0, 1.5, 3.0)).get_mesh_arrays()
	for point: Vector3 in box[Mesh.ARRAY_VERTEX]:
		positions.append(point + Vector3(0.0, 0.75, 0.0))
	indices.append_array(box[Mesh.ARRAY_INDEX])
	var result := GlbMeasurements.measure(positions, indices, {}, false)
	assert_false((result["constants"] as Dictionary).has("ROAD_WHEELS"))
	var mentions := false
	for warning: String in result["warnings"]:
		mentions = mentions or warning.begins_with("wheels not detected")
	assert_true(mentions, "missing wheels are reported: %s" % [result["warnings"]])


func test_foot_unit_gets_height_and_proportions_only() -> void:
	var soldier := Node3D.new()
	_add_mesh(soldier, _box(Vector3(0.3, 1.0, 0.5)), Vector3(0.0, 0.5, 0.0))
	_add_mesh(soldier, _box(Vector3(0.25, 0.8, 0.45)), Vector3(0.0, 1.4, 0.0))
	var result := _measure_scene(soldier, {"height": 1.8}, {"height": 1.8})
	assert_eq(result["kind"], "foot")
	var constants: Dictionary = result["constants"]
	assert_true(absf(float(constants["HEIGHT"]["value"]) - 1.8) < 0.01)
	assert_true(constants.has("WIDTH_TO_HEIGHT") and constants.has("DEPTH_TO_HEIGHT"))
	assert_false(constants.has("DECK_H") or constants.has("TURRET_X"), "no vehicle constants")
	assert_false(result.has("profiles"))


func test_wheels_of_a_fused_mesh_come_from_the_side_depth_map() -> void:
	var positions := PackedVector3Array()
	var indices := PackedInt32Array()
	var parts := [[_box(Vector3(7.0, 1.5, 2.0)), Transform3D(Basis(), Vector3(0.0, 0.75, 0.0))]]
	for x in [-2.4, -1.2, 0.0, 1.2, 2.4]:
		var turned := Basis(Vector3.RIGHT, PI / 2.0)
		parts.append([_cylinder(0.35, 0.3), Transform3D(turned, Vector3(x, 0.4, 1.2))])
	for part: Array in parts:
		var arrays := (part[0] as PrimitiveMesh).get_mesh_arrays()
		var base := positions.size()
		positions.append_array(
			(part[1] as Transform3D) * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		)
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + index)
	var wheels := GlbMeasurements.road_wheels_from_side(positions, indices, 3.5, 7.0, 1.5)
	assert_false(wheels.is_empty(), "wheels found")
	var value: Dictionary = wheels.get("value", {})
	assert_eq(value.get("count_per_side"), 5)
	assert_true(absf(float(value.get("radius", 0.0)) - 0.35) <= 0.04, "radius %s" % value)
	assert_true(absf(float(value.get("h", 0.0)) - 0.4) <= 0.05, "h %s" % value)
	assert_true(float(wheels["confidence"]) < GlbMeasurements.LOW_CONFIDENCE, "a fallback warns")
