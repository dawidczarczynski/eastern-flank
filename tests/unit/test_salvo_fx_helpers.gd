extends TestCase
## Pure helpers of the pooled salvo effects (TASK-075): backblast, trail, shake, quality, dust.


func test_backblast_origin_is_behind_the_tube() -> void:
	var mouth := Vector3(1, 2, 3)
	var dir := Vector3(0.5, 0.7, -0.2).normalized()
	var origin := SalvoFxPool.backblast_origin(mouth, dir, 0.6)
	assert_true((origin - mouth).dot(dir) < 0.0)
	assert_true(absf(origin.distance_to(mouth) - 0.6) < 0.0001)


func test_trail_spacing_with_uneven_steps() -> void:
	var from := Vector3.ZERO
	var carry := 0.0
	var points: Array[Vector3] = []
	var x := 0.0
	for step in [0.013, 0.2, 0.0, 0.5, 0.287]:
		var result := SalvoFxPool.trail_points(
			Vector3(x, 0, 0), Vector3(x + step, 0, 0), 0.07, carry
		)
		points.append_array(result["points"])
		carry = result["carry"]
		x += step
	assert_true(absi(points.size() - 14) <= 1, "%d points" % points.size())
	for i in range(1, points.size()):
		var gap := points[i].distance_to(points[i - 1])
		assert_true(absf(gap - 0.07) < 0.001, "gap %d: %.4f" % [i, gap])
	assert_true(points[0].distance_to(from) > 0.06, "no puff at the start")


func test_trail_zero_length_segment_keeps_the_carry() -> void:
	var result := SalvoFxPool.trail_points(Vector3.ONE, Vector3.ONE, 0.07, 0.03)
	assert_true((result["points"] as Array).is_empty())
	assert_eq(result["carry"], 0.03)


func test_shake_strength() -> void:
	assert_eq(CameraRig.shake_strength(3.0), 0.03)
	assert_eq(CameraRig.shake_strength(6.0), 0.03)
	assert_eq(CameraRig.shake_strength(25.0), 0.0)
	assert_eq(CameraRig.shake_strength(40.0), 0.0)
	var last := INF
	for i in 31:
		var s := CameraRig.shake_strength(float(i))
		assert_true(s <= last, "non-increasing at %d" % i)
		last = s


func test_fx_lights_follow_the_quality() -> void:
	assert_true(GraphicsQuality.features(GraphicsQuality.Level.HIGH)["fx_lights"])
	assert_false(GraphicsQuality.features(GraphicsQuality.Level.LOW)["fx_lights"])


# --- pool ---------------------------------------------------------------------------------


func test_backblast_dir_is_opposite_and_never_into_the_ground() -> void:
	for tube in [Vector3(0.5, 0.7, 0.2), Vector3(1, 0, 0), Vector3(0.3, -0.9, 0.1), Vector3.UP]:
		var back := SalvoFxPool.backblast_dir(tube)
		assert_true(back.y > 0.0, "up from %s" % tube)
		assert_true(absf(back.length() - 1.0) < 0.0001)
		var flat := Vector2(tube.x, tube.z)
		if flat.length() > 0.01:
			assert_true(Vector2(back.x, back.z).dot(flat) < 0.0, "opposite for %s" % tube)


func test_dust_colours_by_terrain() -> void:
	assert_eq(SalvoFxPool.dust_for(&"water", false).a, 0.0, "no launcher dust on water")
	assert_eq(SalvoFxPool.dust_for(&"water", true), SalvoFxPool.SPRAY)
	assert_eq(SalvoFxPool.dust_for(&"forest", true), MotionEffects.dust_color(Terrain.Type.FOREST))
	assert_eq(
		SalvoFxPool.dust_for(&"nonsense", true), MotionEffects.dust_color(Terrain.Type.PLAINS)
	)
