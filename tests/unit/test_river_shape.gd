extends TestCase
## Shape of the river ribbon (TASK-108c follow-up): irregular banks, meander, confluence fade.

const Fixtures := preload("res://tests/fixtures.gd")
const KIND_ROAD := FeatureRibbonPlanner.Kind.ROAD
const KIND_RIVER := FeatureRibbonPlanner.Kind.RIVER


func after_each() -> void:
	MapScale.reset()


func _link(grid: HexGrid, kind: FeatureRibbonPlanner.Kind, a: Vector2i, b: Vector2i) -> void:
	var dir := Hex.DIRECTIONS.find(b - a)
	if kind == KIND_ROAD:
		grid.set_road_links(a, grid.road_links(a) | (1 << dir))
		grid.set_road_links(b, grid.road_links(b) | (1 << ((dir + 3) % 6)))
	else:
		grid.set_river_links(a, grid.river_links(a) | (1 << dir))
		grid.set_river_links(b, grid.river_links(b) | (1 << ((dir + 3) % 6)))


## A river along the +x axis from (-3, 0) to (3, 0) on a plains grid.
func _river_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(4)
	for q in range(-3, 3):
		_link(grid, KIND_RIVER, Vector2i(q, 0), Vector2i(q + 1, 0))
	return grid


func _slope(grid: HexGrid, per_tile: float) -> void:
	for c in grid.coords():
		grid.set_elevation(c, per_tile * c.x)


func _length_m(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	return total * MapScale.metres_per_unit


func test_the_two_banks_have_independent_irregular_edges() -> void:
	var grid := _river_grid()
	var indexed := FeatureRibbonPlanner.mesh(grid, KIND_RIVER)
	var points: PackedVector2Array = indexed["points"]
	var line := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var lefts := PackedFloat32Array()
	var rights := PackedFloat32Array()
	for k in range(line.size() / 4, line.size() * 3 / 4):
		lefts.append(points[2 * k].distance_to(line[k]))
		rights.append(points[2 * k + 1].distance_to(line[k]))
	var differing := 0
	var lo := INF
	var hi := 0.0
	for k in lefts.size():
		lo = minf(lo, lefts[k])
		hi = maxf(hi, lefts[k])
		if absf(lefts[k] - rights[k]) > MapScale.to_units(0.3):
			differing += 1
	assert_true(
		differing > lefts.size() / 4, "sides differ in %d of %d" % [differing, lefts.size()]
	)
	assert_true((hi - lo) * MapScale.metres_per_unit > 1.5, "left edge wanders")


func test_edge_noise_is_deterministic_bounded_and_per_channel() -> void:
	var p := Vector2(3.21, -4.5)
	for channel in 4:
		assert_eq(RiverShape.edge_noise(p, channel), RiverShape.edge_noise(p, channel))
	assert_true(RiverShape.edge_noise(p, 0) != RiverShape.edge_noise(p, 1))
	for i in 200:
		var q := Vector2(i * 0.173, i * 0.091)
		for channel in 4:
			assert_true(absf(RiverShape.edge_noise(q, channel)) <= 1.0)


func test_the_meander_swings_several_river_widths() -> void:
	var grid := _river_grid()
	var line := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var low := INF
	var high := -INF
	for p in line:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var swing_m := (high - low) * MapScale.metres_per_unit
	# A straight east-west river: the sideways range is far more than its 14 m ribbon.
	assert_true(swing_m > 25.0, "range %f m" % swing_m)
	var limit := FeatureRibbonPlanner.RIVER_MEANDER_M
	assert_true(swing_m <= 2.0 * limit + 0.1, "bounded %f m" % swing_m)


func test_meander_and_banks_are_deterministic() -> void:
	var first := FeatureRibbonPlanner.mesh(_river_grid(), KIND_RIVER)
	var second := FeatureRibbonPlanner.mesh(_river_grid(), KIND_RIVER)
	assert_eq(first["points"], second["points"])
	assert_eq(first["water_edge"], second["water_edge"])


## A river along +x with a tributary joining from the south-east in tile (0, 0).
func _confluence_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(3)
	_link(grid, KIND_RIVER, Vector2i(-2, 0), Vector2i(-1, 0))
	_link(grid, KIND_RIVER, Vector2i(-1, 0), Vector2i(0, 0))
	_link(grid, KIND_RIVER, Vector2i(0, 0), Vector2i(1, 0))
	_link(grid, KIND_RIVER, Vector2i(1, 0), Vector2i(2, 0))
	_link(grid, KIND_RIVER, Vector2i(0, 0), Vector2i(0, 1))
	_link(grid, KIND_RIVER, Vector2i(0, 1), Vector2i(-1, 2))
	return grid


func test_a_tributary_fades_out_into_the_through_river() -> void:
	var grid := _confluence_grid()
	var indexed := FeatureRibbonPlanner.mesh(grid, KIND_RIVER)
	var fade: PackedFloat32Array = indexed["fade"]
	var lines := FeatureRibbonPlanner.lines(grid, KIND_RIVER)
	assert_eq(lines.size(), 2)
	# The strips are ordered through river first, tributary after.
	var through_count := 0
	for l in lines:
		through_count = maxi(through_count, l.size())
	var first_strip_vertices := 2 * through_count
	var through_fade := fade.slice(
		first_strip_vertices / 4, first_strip_vertices - first_strip_vertices / 4
	)
	assert_eq(_min_of(through_fade), 1.0, "the through river is solid between its sources")
	var tributary_fade := fade.slice(
		first_strip_vertices,
		first_strip_vertices + 2 * (lines[0].size() + lines[1].size() - through_count)
	)
	assert_true(_min_of(tributary_fade) < 0.05, "the tributary ends transparent")
	assert_eq(_max_of(tributary_fade), 1.0, "and is solid further up")


func test_the_confluence_end_lies_on_the_through_centreline() -> void:
	var grid := _confluence_grid()
	var lines := FeatureRibbonPlanner.lines(grid, KIND_RIVER)
	var through: PackedVector2Array = lines[0] if lines[0].size() > lines[1].size() else lines[1]
	var spoke: PackedVector2Array = lines[1] if through == lines[0] else lines[0]
	var best := INF
	for end in [spoke[0], spoke[spoke.size() - 1]]:
		for i in through.size() - 1:
			var ab := through[i + 1] - through[i]
			var t := clampf((end - through[i]).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, end.distance_to(through[i] + ab * t))
	assert_true(best < MapScale.to_units(1.0), "tributary ends on the through line (%f)" % best)


func test_meander_and_bank_widths_are_metres_at_any_map_scale() -> void:
	var normal_swing := _swing_m(_river_grid())
	var normal_half := FeatureRibbonPlanner.max_half_width(KIND_RIVER)
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT / 2.0
	var half_swing := _swing_m(_river_grid())
	# The sideways swing stays tens of metres (the hex walls may trim it), the ribbon is the same
	# number of metres wide, i.e. twice the world units.
	assert_true(normal_swing > 20.0 and half_swing > 6.0, "%f / %f" % [normal_swing, half_swing])
	assert_true(half_swing <= 2.0 * FeatureRibbonPlanner.RIVER_MEANDER_M + 0.1)
	assert_true(absf(FeatureRibbonPlanner.max_half_width(KIND_RIVER) - 2.0 * normal_half) < 1e-6)
	var indexed := FeatureRibbonPlanner.mesh(_river_grid(), KIND_RIVER)
	var line := FeatureRibbonPlanner.lines(_river_grid(), KIND_RIVER)[0]
	var points: PackedVector2Array = indexed["points"]
	var k := line.size() / 2
	var width_m := points[2 * k].distance_to(points[2 * k + 1]) * MapScale.metres_per_unit
	assert_true(width_m > 8.0 and width_m < 24.0, "ribbon %f m" % width_m)


func _swing_m(grid: HexGrid) -> float:
	var line := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var low := INF
	var high := -INF
	for p in line:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	return (high - low) * MapScale.metres_per_unit


func _min_of(values: PackedFloat32Array) -> float:
	var result := INF
	for v in values:
		result = minf(result, v)
	return result


func _max_of(values: PackedFloat32Array) -> float:
	var result := -INF
	for v in values:
		result = maxf(result, v)
	return result
