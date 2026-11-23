extends TestCase
## Riparian vegetation (TASK-108c follow-up): placement rules, determinism, metre scaling.

const Fixtures := preload("res://tests/fixtures.gd")
const KIND_RIVER := FeatureRibbonPlanner.Kind.RIVER


func after_each() -> void:
	MapScale.reset()


func _river_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(5)
	for q in range(-4, 4):
		var a := Vector2i(q, 0)
		var b := Vector2i(q + 1, 0)
		var dir := Hex.DIRECTIONS.find(b - a)
		grid.set_river_links(a, grid.river_links(a) | (1 << dir))
		grid.set_river_links(b, grid.river_links(b) | (1 << ((dir + 3) % 6)))
	return grid


func _plan(grid: HexGrid) -> Dictionary:
	return RiparianPlanner.plan(grid, TerrainSurface.new(grid))


func test_a_map_without_rivers_plans_nothing() -> void:
	var grid := Fixtures.plains_grid(3)
	var result := _plan(grid)
	assert_eq(result["trees"].size(), 0)
	assert_eq(result["edge_shrubs"].size(), 0)


func test_a_river_gets_shrubs_and_trees() -> void:
	var result := _plan(_river_grid())
	assert_true(result["edge_shrubs"].size() > 20, "shrubs %d" % result["edge_shrubs"].size())
	assert_true(result["trees"].size() > 3, "trees %d" % result["trees"].size())
	assert_true(result["trees"].size() < result["edge_shrubs"].size())
	for tree: Dictionary in result["trees"]:
		assert_eq(tree["species"], RiparianPlanner.TREE_SPECIES)
		assert_false(tree["conifer"])


func test_items_stand_between_the_clearance_and_the_reach_of_the_river() -> void:
	var grid := _river_grid()
	var result := _plan(grid)
	var near := MapScale.to_units(FeatureRibbonPlanner.ROAD_CLEARANCE_M)
	var far := MapScale.to_units(RiparianPlanner.MAX_REACH_M)
	for key: String in ["trees", "edge_shrubs"]:
		for item: Dictionary in result[key]:
			var p: Vector3 = item["position"]
			var edge := FeatureRibbonPlanner.edge_distance(grid, KIND_RIVER, p.x, p.z)
			assert_true(edge >= near - 1e-5 and edge <= far + 1e-5, "edge distance %f" % edge)
			assert_true(FeatureRibbonPlanner.is_clear(grid, p.x, p.z))


func test_the_belt_is_patchy_not_a_uniform_line() -> void:
	var result := _plan(_river_grid())
	var cells := {}
	for item: Dictionary in result["edge_shrubs"]:
		var p: Vector3 = item["position"]
		cells[Vector2i((Vector2(p.x, p.z) / MapScale.to_units(40.0)).floor())] = true
	# Occupied 40 m cells are well below all cells the river passes through.
	var river_cells := 0.0
	for line in FeatureRibbonPlanner.lines(_river_grid(), KIND_RIVER):
		river_cells += line.size() * FeatureRibbonPlanner.SAMPLE_STEP / MapScale.to_units(40.0)
	assert_true(cells.size() < 3.0 * river_cells, "cells %d of %f" % [cells.size(), river_cells])


func test_deterministic_and_chunks_add_up_to_the_whole() -> void:
	var grid := _river_grid()
	var whole := _plan(grid)
	assert_eq(whole["edge_shrubs"].size(), _plan(grid)["edge_shrubs"].size())
	var surface := TerrainSurface.new(grid)
	var total_shrubs := 0
	var total_trees := 0
	for cx in range(-4, 4):
		var rect := Rect2(Vector2(cx * 2.0, -12.0), Vector2(2.0, 24.0))
		var part := RiparianPlanner.plan(grid, surface, null, rect)
		total_shrubs += part["edge_shrubs"].size()
		total_trees += part["trees"].size()
	# Tiles are owned by their centre: the chunks together give exactly the whole.
	assert_eq(total_shrubs, whole["edge_shrubs"].size(), "shrubs")
	assert_eq(total_trees, whole["trees"].size(), "trees")


func test_nothing_grows_on_urban_tiles() -> void:
	var grid := _river_grid()
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.URBAN)
	var result := _plan(grid)
	assert_eq(result["edge_shrubs"].size() + result["trees"].size(), 0)


func test_distances_follow_the_map_scale() -> void:
	var grid := _river_grid()
	var normal := _plan(grid)
	var span := 0.0
	for item: Dictionary in normal["edge_shrubs"]:
		var p: Vector3 = item["position"]
		span = maxf(span, FeatureRibbonPlanner.edge_distance(grid, KIND_RIVER, p.x, p.z))
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT / 2.0
	var half := _plan(grid)
	var half_span := 0.0
	for item: Dictionary in half["edge_shrubs"]:
		var p: Vector3 = item["position"]
		half_span = maxf(half_span, FeatureRibbonPlanner.edge_distance(grid, KIND_RIVER, p.x, p.z))
	# Half the metres per unit: the same metres are twice as many world units.
	assert_true(half_span > 1.6 * span * 0.9, "%f vs %f" % [half_span, span])
	assert_true(half_span <= MapScale.to_units(RiparianPlanner.MAX_REACH_M) + 1e-5)
