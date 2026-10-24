extends TestCase
## RocketVolley path maths (TASK-011, TASK-074): the Bézier from the tube to the landing point.

const TOL := 0.0001
const TUBE_DIR := Vector3(-0.6, 0.8, 0.0)  # backwards and up, like a raised Homar-K pod


func _path(from: Vector3, dir: Vector3, to: Vector3, u: float) -> Vector3:
	var span := Vector2(to.x - from.x, to.z - from.z).length()
	return RocketVolley.path_point(from, dir, to, RocketVolley.apex_height(span), u)


func test_path_endpoints() -> void:
	var from := Vector3(0, 0.5, 0)
	var to := Vector3(6, 0.1, 3)
	assert_true(_path(from, TUBE_DIR, to, 0.0).distance_to(from) < TOL)
	assert_true(_path(from, TUBE_DIR, to, 1.0).distance_to(to) < TOL)
	assert_true(_path(from, TUBE_DIR, to, 5.0).distance_to(to) < TOL, "u is clamped")


func test_path_leaves_along_the_tube() -> void:
	var from := Vector3(0, 0.5, 0)
	var dir := Vector3(0.5, 0.7, 0.2).normalized()
	var to := Vector3(8, 0.0, 2)
	var start := _path(from, dir, to, 0.001) - _path(from, dir, to, 0.0)
	assert_true(rad_to_deg(start.angle_to(dir)) < 3.0, "%.2f°" % rad_to_deg(start.angle_to(dir)))


func test_path_comes_down_steeply() -> void:
	for distance in range(2, 11):
		var from := Vector3(0, 0.4, 0)
		var to := Vector3(float(distance), 0.0, 0.0)
		var end := _path(from, TUBE_DIR, to, 1.0) - _path(from, TUBE_DIR, to, 0.999)
		var below := rad_to_deg(atan2(-end.y, Vector2(end.x, end.z).length()))
		assert_true(end.y < 0.0 and below >= 30.0, "distance %d: %.1f° below" % [distance, below])


func test_path_highest_point_is_above_both_ends() -> void:
	var from := Vector3(0, 0.4, 0)
	var to := Vector3(5, 0.1, -2)
	var best := -INF
	for i in 50:
		best = maxf(best, _path(from, TUBE_DIR, to, i / 49.0).y)
	assert_true(best > from.y and best > to.y)


func test_tangent_matches_the_path() -> void:
	var from := Vector3(0, 0.4, 0)
	var to := Vector3(5, 0.1, -2)
	var apex := RocketVolley.apex_height(5.0)
	var numeric := (
		RocketVolley.path_point(from, TUBE_DIR, to, apex, 0.501)
		- RocketVolley.path_point(from, TUBE_DIR, to, apex, 0.5)
	)
	var tangent := RocketVolley.path_tangent(from, TUBE_DIR, to, apex, 0.5)
	assert_true(numeric.angle_to(tangent) < 0.01)


func test_fallback_direction_is_45_degrees_up_towards_the_target() -> void:
	var dir := RocketVolley.fallback_direction(Vector3.ZERO, Vector3(5, 0, 0))
	assert_true(dir.distance_to(Vector3(cos(PI / 4.0), sin(PI / 4.0), 0.0)) < TOL, "%s" % dir)


func test_apex_height_grows_with_distance_and_is_capped() -> void:
	assert_true(RocketVolley.apex_height(5.0) > RocketVolley.apex_height(1.0))
	assert_true(RocketVolley.apex_height(100.0) <= RocketVolley.APEX_MAX + TOL)
