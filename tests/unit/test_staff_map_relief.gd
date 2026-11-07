extends TestCase
## StaffMapRelief (TASK-125): the displaced ground surface, its hillshade, picking against it
## through the tilted camera, and the anti-compression check of the camera.

const Fixtures := preload("res://tests/fixtures.gd")
const VIEW := Vector2(1280, 720)
const UNIT_M := 2886.75  # 5 km hexes


## A 9-ring grid with a north-south ridge along q = 0 (the hexes x ~ 0), heights in metres.
func _ridge_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(9)
	for c in grid.coords():
		var x := Hex.to_world(c, 1.0).x
		grid.set_elevation_m(c, 100.0 + maxf(0.0, 600.0 - absf(x) * 150.0))
	return grid


func test_flat_ground_is_at_zero_and_unshaded() -> void:
	var grid := Fixtures.plains_grid(3)
	for c in grid.coords():
		grid.set_elevation_m(c, 120.0)
	var relief := StaffMapRelief.new(grid, UNIT_M, 3.0)
	assert_true(absf(relief.height_at(Vector2(0.3, 0.7))) < 0.00001)
	assert_true(absf(relief.shade_at(Vector2(0.3, 0.7))) < 0.00001)


func test_surface_is_continuous_and_matches_the_hex_centres() -> void:
	var relief := StaffMapRelief.new(_ridge_grid(), UNIT_M, 3.0)
	for c in [Vector2i(0, 0), Vector2i(2, -1), Vector2i(-3, 2)]:
		var w := Hex.to_world(c, 1.0)
		assert_true(absf(relief.height_at(Vector2(w.x, w.z)) - relief.height_of(c)) < 0.0001)
	# Across a lattice triangle edge the two sides agree.
	var p := Vector2(0.5 * Hex.SQRT3, 0.0)  # midpoint between (0,0) and (1,0)
	var a := relief.height_at(p + Vector2(0, -0.0001))
	var b := relief.height_at(p + Vector2(0, 0.0001))
	assert_true(absf(a - b) < 0.001)
	assert_true(relief.max_height > relief.min_height)


func test_exaggeration_scales_the_height() -> void:
	var one := StaffMapRelief.new(_ridge_grid(), UNIT_M, 1.0)
	var three := StaffMapRelief.new(_ridge_grid(), UNIT_M, 3.0)
	assert_true(absf(three.height_of(Vector2i.ZERO) - 3.0 * one.height_of(Vector2i.ZERO)) < 0.0001)


func test_slopes_facing_the_north_west_light_are_lit() -> void:
	var relief := StaffMapRelief.new(_ridge_grid(), UNIT_M, 3.0, 315.0, 38.0, 20.0)
	assert_true(relief.shade_of(Vector2i(-2, 0)) > 0.0, "west flank faces the light")
	assert_true(relief.shade_of(Vector2i(2, 0)) < 0.0, "east flank is in shade")


func _pick(
	relief: StaffMapRelief, cursor: Vector2, target: Vector3, scale: float, pitch: float
) -> Vector2:
	var ray := StaffMapCameraMath.screen_ray(cursor, VIEW, target, scale, pitch)
	return relief.raycast(ray["origin"], ray["direction"])


func test_picking_on_a_ridge_returns_the_hex_under_the_cursor() -> void:
	# Strong exaggeration so the ridge really shifts on screen (worst case for a plane pick).
	var relief := StaffMapRelief.new(_ridge_grid(), UNIT_M, 30.0)
	assert_true(relief.max_height - relief.min_height > 3.0, "the ridge must be tall")
	var target := Vector3(0, 0, 0)
	var scale := 30.0
	var probes: Array[Vector2] = []
	for c in Fixtures.plains_grid(6).coords():
		var w := Hex.to_world(c, 1.0)
		probes.append(Vector2(w.x, w.z))
		probes.append(Vector2(w.x, w.z) + Vector2(0.35, -0.3))
	for pitch in [0.0, 35.0, 50.0]:
		var worst := 0.0
		for p in probes:
			var screen := StaffMapCameraMath.project(
				relief.surface_point(p), VIEW, target, scale, pitch
			)
			var picked := _pick(relief, screen, target, scale, pitch)
			worst = maxf(worst, picked.distance_to(p))
			assert_eq(
				StaffMapLayers.hex_at(picked),
				StaffMapLayers.hex_at(p),
				"pitch %s at %s" % [pitch, p]
			)
		# Error far below half a hex (centre to edge = sqrt(3) / 2).
		assert_true(worst < 0.05, "pitch %s worst error %s" % [pitch, worst])


func test_a_plane_pick_would_miss_on_the_ridge() -> void:
	# Guards the test above: without the surface ray the tilted view picks a neighbour.
	var relief := StaffMapRelief.new(_ridge_grid(), UNIT_M, 30.0)
	var p := Vector2.ZERO
	var screen := StaffMapCameraMath.project(
		relief.surface_point(p), VIEW, Vector3.ZERO, 30.0, 50.0
	)
	var plane := StaffMapCameraMath.plane_point(screen, VIEW, Vector3.ZERO, 30.0, 50.0)
	assert_false(StaffMapLayers.hex_at(plane) == StaffMapLayers.hex_at(p))


## Projected area (screen px^2) of the hex whose centre is under `cursor`.
func _hex_pixels(cursor: Vector2, target: Vector3, scale: float, pitch: float) -> float:
	var centre := StaffMapCameraMath.plane_point(cursor, VIEW, target, scale, pitch)
	var corners := PackedVector2Array()
	for k in 6:
		var angle := deg_to_rad(60.0 * k - 30.0)
		var corner := centre + Vector2(cos(angle), sin(angle))
		corners.append(
			StaffMapCameraMath.project(Vector3(corner.x, 0, corner.y), VIEW, target, scale, pitch)
		)
	var sum := 0.0
	for i in 6:
		sum += corners[i].x * corners[(i + 1) % 6].y - corners[(i + 1) % 6].x * corners[i].y
	return absf(sum) * 0.5


func test_far_edge_keeps_at_least_70_percent_of_the_near_edge_pixels_per_hex() -> void:
	var pitch := StaffMapCameraMath.PITCH_DEFAULT
	var target := Vector3(40, 0, 30)
	var far := _hex_pixels(Vector2(VIEW.x * 0.5, 10), target, 24.0, pitch)
	var near := _hex_pixels(Vector2(VIEW.x * 0.5, VIEW.y - 10), target, 24.0, pitch)
	assert_true(near > 0.0)
	# Orthographic: measured 1.00 (a 30 degree perspective camera would give ~0.56 here).
	assert_true(far / near >= 0.7, "far / near = %s" % (far / near))
	assert_true(absf(far / near - 1.0) < 0.001)
