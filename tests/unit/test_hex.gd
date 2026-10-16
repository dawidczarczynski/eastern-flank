extends TestCase


func test_distance_to_self_is_zero() -> void:
	assert_eq(Hex.distance(Vector2i(2, -1), Vector2i(2, -1)), 0)


func test_distance() -> void:
	assert_eq(Hex.distance(Vector2i.ZERO, Vector2i(2, -1)), 2)
	assert_eq(Hex.distance(Vector2i(-2, 0), Vector2i(2, 0)), 4)


func test_six_neighbors_at_distance_one() -> void:
	var neighbors := Hex.neighbors(Vector2i(1, 1))
	assert_eq(neighbors.size(), 6)
	for n in neighbors:
		assert_eq(Hex.distance(Vector2i(1, 1), n), 1)


func test_world_round_trip() -> void:
	for size: float in [1.0, 1.7]:
		for c: Vector2i in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-4, 5)]:
			assert_eq(Hex.from_world(Hex.to_world(c, size), size), c, "size=%s" % size)


func test_from_world_near_center_picks_same_hex() -> void:
	var p := Hex.to_world(Vector2i(2, 1), 1.0) + Vector3(0.4, 0.0, -0.3)
	assert_eq(Hex.from_world(p, 1.0), Vector2i(2, 1))
