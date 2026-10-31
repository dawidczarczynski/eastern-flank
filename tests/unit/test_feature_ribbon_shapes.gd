extends TestCase
## FeatureRibbonPlanner / FeatureRibbons (TASK-108): loops, crossings, draping over creases and
## scatter against the drawn strips.

const Fixtures := preload("res://tests/fixtures.gd")
const EPSILON := 1e-4
const KIND_ROAD := FeatureRibbonPlanner.Kind.ROAD
const KIND_RIVER := FeatureRibbonPlanner.Kind.RIVER


func _near(actual: float, expected: float, message := "") -> void:
	assert_true(
		absf(actual - expected) < EPSILON, "expected %f, got %f %s" % [expected, actual, message]
	)


func _lines(grid: HexGrid, kind: FeatureRibbonPlanner.Kind) -> Array[PackedVector2Array]:
	return FeatureRibbonPlanner.lines(grid, kind)


func _link(grid: HexGrid, kind: FeatureRibbonPlanner.Kind, a: Vector2i, b: Vector2i) -> void:
	var dir := Hex.DIRECTIONS.find(b - a)
	if kind == KIND_ROAD:
		grid.set_road_links(a, grid.road_links(a) | (1 << dir))
		grid.set_road_links(b, grid.road_links(b) | (1 << ((dir + 3) % 6)))
	else:
		grid.set_river_links(a, grid.river_links(a) | (1 << dir))
		grid.set_river_links(b, grid.river_links(b) | (1 << ((dir + 3) % 6)))


func _link_path(grid: HexGrid, kind: FeatureRibbonPlanner.Kind, path: Array[Vector2i]) -> void:
	for i in path.size() - 1:
		_link(grid, kind, path[i], path[i + 1])


func _max_turn(line: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(1, line.size() - 1):
		var a := line[i] - line[i - 1]
		var b := line[i + 1] - line[i]
		if a.length() > 1e-6 and b.length() > 1e-6:
			worst = maxf(worst, absf(a.angle_to(b)))
	return worst


func _road_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(3)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FOREST)
	for q in range(-3, 3):
		var a := Vector2i(q, 0)
		grid.set_road_links(a, grid.road_links(a) | (1 << 0))
		var b := Vector2i(q + 1, 0)
		grid.set_road_links(b, grid.road_links(b) | (1 << 3))
	grid.set_river_links(Vector2i(0, 2), 1 << 0)
	grid.set_river_links(Vector2i(1, 2), 1 << 3)
	return grid


func test_a_closed_loop_is_one_closed_smooth_line() -> void:
	var grid := Fixtures.plains_grid(3)
	var ring: Array[Vector2i] = []
	for dir in 6:
		ring.append(Hex.DIRECTIONS[dir])
	ring.append(ring[0])
	_link_path(grid, KIND_ROAD, ring)
	var lines := _lines(grid, KIND_ROAD)
	assert_eq(lines.size(), 1, "one chain")
	var line := lines[0]
	_near(line[0].distance_to(line[line.size() - 1]), 0.0, "closed")
	assert_true(_max_turn(line) < deg_to_rad(20.0), "smooth (%f)" % rad_to_deg(_max_turn(line)))
	var tris := FeatureRibbonPlanner.triangles(grid, KIND_ROAD)
	assert_true(tris.size() > 0 and tris.size() % 3 == 0)


func test_two_crossing_through_pieces_cross_at_the_centre() -> void:
	var grid := Fixtures.plains_grid(3)
	_link(grid, KIND_ROAD, Vector2i(-1, 0), Vector2i.ZERO)
	_link(grid, KIND_ROAD, Vector2i.ZERO, Vector2i(1, 0))
	_link(grid, KIND_ROAD, Vector2i(-1, 1), Vector2i.ZERO)
	_link(grid, KIND_ROAD, Vector2i.ZERO, Vector2i(1, -1))
	var lines := _lines(grid, KIND_ROAD)
	assert_eq(lines.size(), 2, "two through roads")
	for line in lines:
		var best := INF
		for p in line:
			best = minf(best, p.length())
		assert_true(best < 0.05, "passes the centre (%f)" % best)
	assert_eq(FeatureRibbonPlanner.discs(grid, KIND_ROAD).size(), 4, "only the dead-end discs")


func test_draped_ribbons_stay_above_a_sharp_crest() -> void:
	var grid := Fixtures.plains_grid(2)
	_link(grid, KIND_ROAD, Vector2i(-1, 0), Vector2i.ZERO)
	_link(grid, KIND_ROAD, Vector2i.ZERO, Vector2i(1, 0))
	_link(grid, KIND_RIVER, Vector2i(0, -1), Vector2i.ZERO)
	_link(grid, KIND_RIVER, Vector2i.ZERO, Vector2i(0, 1))
	# Piecewise linear ridges like the terrain mesh's creases, steep in both directions.
	var height := func(p: Vector2) -> float:
		return 0.5 - 1.5 * absf(p.x - 0.137) - 1.2 * absf(p.y + 0.061)
	var drape := func(points: PackedVector2Array, lift: float) -> PackedVector3Array:
		var out := PackedVector3Array()
		for p in points:
			out.append(Vector3(p.x, height.call(p) + lift, p.y))
		return out
	for kind: FeatureRibbonPlanner.Kind in [KIND_ROAD, KIND_RIVER]:
		var indexed := FeatureRibbonPlanner.mesh(grid, kind)
		var indices: PackedInt32Array = indexed["indices"]
		var points := FeatureRibbons.drape_lifted(indexed["points"], indices, 0.0, drape)
		var draped := PackedVector3Array()
		for index in indices:
			draped.append(points[index])
		var worst := 0.0
		for t in draped.size() / 3:
			for u in 6:
				for v in 6 - u:
					var w := 5 - u - v
					var p: Vector3 = (
						(draped[3 * t] * u + draped[3 * t + 1] * v + draped[3 * t + 2] * w) / 5.0
					)
					worst = maxf(worst, height.call(Vector2(p.x, p.z)) - p.y)
		assert_true(worst < 1e-4, "kind %d dips %f under the crest" % [kind, worst])


func test_no_scatter_inside_a_drawn_ribbon_triangle() -> void:
	var grid := _road_grid()
	var plan := ScatterPlanner.plan(grid, TerrainSurface.new(grid), 777)
	for kind: FeatureRibbonPlanner.Kind in [KIND_ROAD, KIND_RIVER]:
		var tris := FeatureRibbonPlanner.triangles(grid, kind)
		for key: String in plan:
			for item: Dictionary in plan[key]:
				var p3: Vector3 = item["position"]
				var p := Vector2(p3.x, p3.z)
				for t in range(0, tris.size(), 3):
					if Geometry2D.point_is_inside_triangle(p, tris[t], tris[t + 1], tris[t + 2]):
						_fail("%s %s inside a kind %d triangle" % [key, p, kind])
						return
