extends TestCase
## The front line of the staff map (TASK-093c): who holds which hex, the edges between the
## blocs, smoothing.


## A land grid of `cols` x `rows` (axial (q, r) with r in 0 … rows-1) and the formations
## {coord: owner}.
static func _state(formations: Dictionary, cols := 13, rows := 7) -> OperationalState:
	var grid := HexGrid.new()
	for r in rows:
		for q in range(-(r / 2), cols - r / 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	var state := OperationalState.new()
	state.grid = grid
	var n := 0
	for coord: Vector2i in formations:
		n += 1
		var f := Formation.new()
		f.id = StringName("f%d" % n)
		f.owner_id = formations[coord] as int
		f.coord = coord
		state.formations.append(f)
	return state


func test_nearest_formation_owns_the_hex() -> void:
	var state := _state({Vector2i(1, 3): 0, Vector2i(6, 3): 1})
	var owners := FrontLine.ownership(state)
	assert_eq(owners[Vector2i(1, 3)], 0)
	assert_eq(owners[Vector2i(3, 3)], 0)
	assert_eq(owners[Vector2i(5, 3)], 1)
	assert_eq(owners[Vector2i(6, 3)], 1)


func test_tie_belongs_to_nobody() -> void:
	# 6 apart on a row: the middle hex is 3 from both.
	var state := _state({Vector2i(0, 3): 0, Vector2i(6, 3): 1})
	var owners := FrontLine.ownership(state)
	assert_false(owners.has(Vector2i(3, 3)))
	assert_eq(owners[Vector2i(2, 3)], 0)
	assert_eq(owners[Vector2i(4, 3)], 1)


func test_hexes_beyond_the_range_are_free() -> void:
	var state := _state({Vector2i(0, 3): 0})
	var owners := FrontLine.ownership(state)
	assert_true(owners.has(Vector2i(3, 3)))
	assert_false(owners.has(Vector2i(4, 3)))


func test_water_is_never_owned() -> void:
	var state := _state({Vector2i(1, 3): 0})
	state.grid.set_terrain(Vector2i(2, 3), Terrain.Type.WATER)
	assert_false(FrontLine.ownership(state).has(Vector2i(2, 3)))


func test_one_formation_per_side_gives_a_single_line() -> void:
	var state := _state({Vector2i(2, 3): 0, Vector2i(7, 3): 1})
	var lines := FrontLine.edges(state)
	assert_eq(lines.size(), 1)
	var line: PackedVector2Array = lines[0]
	assert_true(line.size() >= 2)
	# Runs across the whole rows of both zones, between the two formations.
	var mid := (Hex.to_world(Vector2i(2, 3), 1.0).x + Hex.to_world(Vector2i(7, 3), 1.0).x) / 2.0
	for p in line:
		assert_true(absf(p.x - mid) < 1.6)


func test_line_with_a_tie_band_is_still_one_line() -> void:
	var state := _state({Vector2i(0, 3): 0, Vector2i(6, 3): 1})
	assert_eq(FrontLine.edges(state).size(), 1)


func test_no_line_without_an_opponent() -> void:
	assert_eq(FrontLine.edges(_state({Vector2i(2, 3): 0})).size(), 0)
	assert_eq(FrontLine.edges(_state({Vector2i(2, 3): 0, Vector2i(10, 3): 1})).size(), 0)


func test_lines_have_player_zero_on_one_side() -> void:
	var state := _state({Vector2i(2, 3): 0, Vector2i(7, 3): 1})
	var line: PackedVector2Array = FrontLine.edges(state)[0]
	var normal := FrontLine.right_normal(line[0], line[1])
	var near_zero := Hex.to_world(Vector2i(2, 3), 1.0)
	var probe := Vector2(near_zero.x, near_zero.z) - line[0]
	assert_true(probe.dot(normal) > 0.0, "player 0 lies on the right of the direction of travel")


func test_moving_a_formation_changes_the_line() -> void:
	var state := _state({Vector2i(2, 3): 0, Vector2i(7, 3): 1})
	var before := FrontLine.edges(state)
	state.formations[0].coord = Vector2i(4, 3)
	assert_true(FrontLine.edges(state) != before)


func test_deterministic() -> void:
	var state := _state({Vector2i(2, 3): 0, Vector2i(7, 3): 1, Vector2i(5, 1): 0})
	assert_eq(FrontLine.edges(state), FrontLine.edges(state))
	assert_eq(FrontLine.ownership(state), FrontLine.ownership(state))


func test_lake_hex_cuts_the_line() -> void:
	var state := _state({Vector2i(2, 3): 0, Vector2i(7, 3): 1})
	var plain := FrontLine.edges(state)
	for q in range(3, 8):
		state.grid.set_terrain(Vector2i(q, 3), Terrain.Type.WATER)
	assert_true(FrontLine.edges(state) != plain)


func test_smoothed_keeps_the_ends_and_stays_near_the_exact_line() -> void:
	var state := _state({Vector2i(2, 3): 0, Vector2i(7, 4): 1, Vector2i(5, 1): 0})
	for exact: PackedVector2Array in FrontLine.edges(state):
		var smooth := FrontLine.smooth(exact)
		assert_eq(smooth[0], exact[0])
		assert_eq(smooth[smooth.size() - 1], exact[exact.size() - 1])
		for p in smooth:
			assert_true(_distance_to_polyline(p, exact) <= 1.0)


static func _distance_to_polyline(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, p.distance_to(closest))
	return best


func test_front_range_is_read_from_the_state() -> void:
	var state := _state({Vector2i(0, 3): 0})
	state.front_range = 1
	assert_true(FrontLine.ownership(state).has(Vector2i(1, 3)))
	assert_false(FrontLine.ownership(state).has(Vector2i(2, 3)))
