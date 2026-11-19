extends TestCase
## Silhouette rasterising and comparison (TASK-181, tools/silhouette.gd).

const Silhouette := preload("res://tools/silhouette.gd")
const PIXEL := 0.05


## A box as a triangle list: {"positions", "indices"}.
func _box(low: Vector3, size: Vector3) -> Dictionary:
	var positions := PackedVector3Array()
	for i in 8:
		positions.append(
			low + Vector3(size.x * (i & 1), size.y * ((i >> 1) & 1), size.z * ((i >> 2) & 1))
		)
	var quads := [
		[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]
	]
	var indices := PackedInt32Array()
	for quad: Array in quads:
		indices.append_array(
			PackedInt32Array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]])
		)
	return {"positions": positions, "indices": indices}


func _frame(view: String) -> Dictionary:
	return Silhouette.frame(AABB(Vector3(-1.0, 0.0, -2.0), Vector3(14.0, 5.0, 4.0)), view, PIXEL)


func _mask(box: Dictionary, view: String) -> PackedByteArray:
	return Silhouette.rasterize(box["positions"], box["indices"], view, _frame(view))


func test_identical_shapes_have_iou_one() -> void:
	var box := _box(Vector3(0, 0, -1), Vector3(10, 3, 2))
	for view in Silhouette.VIEWS:
		assert_eq(Silhouette.iou(_mask(box, view), _mask(box, view)), 1.0, view)


func test_area_matches_the_projected_rectangle() -> void:
	var box := _box(Vector3(0, 0, -1), Vector3(10, 3, 2))
	var side := Silhouette.area_pixels(_mask(box, "side")) * PIXEL * PIXEL
	var top := Silhouette.area_pixels(_mask(box, "top")) * PIXEL * PIXEL
	assert_true(absf(side - 30.0) < 1.0, "side 10 x 3 m, got %s" % side)
	assert_true(absf(top - 20.0) < 1.0, "top 10 x 2 m, got %s" % top)


func test_a_box_shifted_along_x_gives_the_expected_iou() -> void:
	var box := _box(Vector3(0, 0, -1), Vector3(10, 3, 2))
	var shifted := _box(Vector3(1, 0, -1), Vector3(10, 3, 2))
	# side: intersection 9 x 3, union 11 x 3
	var value := Silhouette.iou(_mask(box, "side"), _mask(shifted, "side"))
	assert_true(absf(value - 9.0 / 11.0) < 0.02, "side iou %s" % value)
	# front: the shift along x is invisible
	assert_eq(Silhouette.iou(_mask(box, "front"), _mask(shifted, "front")), 1.0)


func test_empty_masks_have_iou_one_and_disjoint_ones_zero() -> void:
	var a := PackedByteArray([0, 0])
	assert_eq(Silhouette.iou(a, a), 1.0)
	assert_eq(Silhouette.iou(PackedByteArray([1, 0]), PackedByteArray([0, 1])), 0.0)


func test_diff_image_colours_extra_missing_and_common_pixels() -> void:
	var model := PackedByteArray([1, 1, 0, 0])
	var reference := PackedByteArray([1, 0, 1, 0])
	var image := Silhouette.diff_image(model, reference, Vector2i(4, 1), "top")
	assert_eq(image.get_pixel(0, 0), Silhouette.COLOR_MATCH)
	assert_eq(image.get_pixel(1, 0), Silhouette.COLOR_EXTRA)
	assert_eq(image.get_pixel(2, 0), Silhouette.COLOR_MISSING)
	assert_eq(image.get_pixel(3, 0), Silhouette.COLOR_EMPTY)


func test_the_largest_mismatch_region_is_found_in_metres() -> void:
	var model := _box(Vector3(0, 0, -1), Vector3(10, 3, 2))
	var reference := _box(Vector3(0, 0, -1), Vector3(10, 3.5, 2))  # 0.5 m taller
	var frame := _frame("side")
	var regions := Silhouette.mismatch_regions(
		_mask(model, "side"), _mask(reference, "side"), frame, 3
	)
	assert_eq(regions.size(), 1)
	var region: Dictionary = regions[0]
	assert_eq(region["kind"], "missing")
	assert_true(absf(float(region["thickness_m"]) - 0.5) < 0.06, "got %s" % region["thickness_m"])
	assert_true(absf(float(region["v0"]) - 3.0) < 0.1 and absf(float(region["v1"]) - 3.5) < 0.1)
	assert_eq(region["thin_axis"], "v")
	assert_true(Silhouette.describe_region(region, "side").contains("-0.50 m high"))


func test_no_regions_when_masks_are_equal() -> void:
	var box := _box(Vector3(0, 0, -1), Vector3(10, 3, 2))
	var mask := _mask(box, "top")
	assert_true(Silhouette.mismatch_regions(mask, mask, _frame("top")).is_empty())
