extends TestCase
## Real tree features in the open country (TASK-199b): OSM trees, tree rows, orchards, farmyard
## orchards, roadside lines, solitary field trees and copses (TreeFeatures), only on the `true`
## VisualScale preset.

const Fixtures := preload("res://tests/fixtures.gd")

const SEED := 4242


func after_each() -> void:
	VisualScale.reset()
	MapScale.reset()


func _grid(terrain: Terrain.Type, radius: int) -> HexGrid:
	var grid := Fixtures.plains_grid(radius)
	for c in grid.coords():
		grid.set_terrain(c, terrain)
	return grid


func _plan(
	grid: HexGrid, rect: Rect2, parcels: ParcelMap = null, features: TreeFeatureSet = null
) -> Array[Dictionary]:
	return TreeFeatures.plan(grid, TerrainSurface.new(grid), SEED, rect, parcels, null, features)


func _hex_of(tree: Dictionary) -> Vector2i:
	return Hex.from_world(tree["position"], TerrainField.HEX_SIZE)


func _square(origin: Vector2, size: Vector2) -> Array[PackedVector2Array]:
	var ring := PackedVector2Array(
		[origin, origin + Vector2(0, size.y), origin + size, origin + Vector2(size.x, 0)]
	)
	var rings: Array[PackedVector2Array] = [ring]
	return rings


func _straight(length: float) -> PackedVector2Array:
	var line := PackedVector2Array()
	var x := 0.0
	while x < length:
		line.append(Vector2(x, 0.0))
		x += 100.0
	line.append(Vector2(length, 0.0))
	return line


func _distance_to_line(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, p.distance_to(q))
	return best


func _positions(list: Array) -> Dictionary:
	var result := {}
	for item: Dictionary in list:
		result[item["position"]] = item
	return result


# --- OSM data -----------------------------------------------------------------------------------


func test_osm_trees_stand_at_their_positions() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.PLAINS, 4)
	var m := MapScale.metres_per_unit
	var points := PackedVector2Array(
		[Vector2(30, 40), Vector2(-200, 130), Vector2(400, -310), Vector2(15, 500)]
	)
	var features := TreeFeatureSet.make(points, [], [], [])
	var trees := _plan(grid, Rect2(-8, -8, 16, 16), null, features)
	for p in points:
		var found := false
		for tree in trees:
			var q: Vector3 = tree["position"]
			if Vector2(q.x, q.z).distance_to(p / m) * m <= 0.5:
				found = true
		assert_true(found, "a tree within 0.5 m of %s" % p)


func test_tree_rows_are_dense_along_the_polyline() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var line := PackedVector2Array([Vector2(0, 0), Vector2(300, 40), Vector2(500, 200)])
	var positions := TreeFeatures.row_positions(line, 3)
	assert_true(positions.size() > 40, "a 500 m row has many trees: %d" % positions.size())
	for i in positions.size():
		assert_true(_distance_to_line(positions[i], line) <= 1.5, "tree %d off the row" % i)
	var gaps: Array[float] = []
	for i in range(1, positions.size()):
		gaps.append(positions[i].distance_to(positions[i - 1]))
	for gap in gaps:
		assert_true(gap > 4.0 and gap < 10.9, "spacing %.2f" % gap)
	assert_true(gaps.max() - gaps.min() > 0.5, "the spacing varies")


func test_orchard_trees_stand_in_rows_inside_the_polygon() -> void:
	var rings := _square(Vector2(100, 200), Vector2(220, 140))
	var hole := PackedVector2Array(
		[Vector2(180, 250), Vector2(180, 290), Vector2(230, 290), Vector2(230, 250)]
	)
	rings.append(hole)
	var positions := TreeFeatures.orchard_positions(rings, 5)
	assert_true(positions.size() > 200, "an orchard of 3 ha: %d" % positions.size())
	for p in positions:
		assert_true(TreeFeatures.inside(rings, p), "%s inside" % p)
		assert_false(Geometry2D.is_point_in_polygon(p, hole), "not in the hole")
	for i in range(0, positions.size(), 7):
		var nearest := INF
		for j in positions.size():
			if j != i:
				nearest = minf(nearest, positions[i].distance_to(positions[j]))
		assert_true(nearest >= 4.99 and nearest <= 8.01, "row spacing %.2f" % nearest)


func test_a_third_of_the_farmyards_get_a_small_orchard() -> void:
	var with_orchard := 0
	var total := 300
	for key in total:
		var rings := _square(Vector2(key * 500.0, 0), Vector2(160, 130))
		var positions := TreeFeatures.farmyard_positions(rings, key)
		if positions.is_empty():
			continue
		with_orchard += 1
		assert_true(positions.size() >= 8 and positions.size() <= 30, "%d trees" % positions.size())
		for p in positions:
			assert_true(TreeFeatures.inside(rings, p))
	var share := float(with_orchard) / total
	assert_true(share > 0.2 and share < 0.4, "share %.2f" % share)


func test_a_farmyard_orchard_stays_out_of_the_holes() -> void:
	for key in 200:
		var rings := _square(Vector2(0, 0), Vector2(150, 120))
		rings.append(
			PackedVector2Array(
				[Vector2(40, 30), Vector2(40, 90), Vector2(110, 90), Vector2(110, 30)]
			)
		)
		for p in TreeFeatures.farmyard_positions(rings, key):
			assert_true(TreeFeatures.inside(rings, p), "inside, outside the hole")


# --- rule fill ----------------------------------------------------------------------------------


func test_a_kilometre_of_road_carries_a_roadside_line_on_a_quarter() -> void:
	var line := _straight(1000.0)
	var carried := {}
	var trees := 0
	for key in 12:
		var positions := TreeFeatures.roadside_positions(line, key)
		carried.clear()
		var previous := Vector2.INF
		var previous_segment := -1
		for p in positions:
			var offset := absf(p.y)
			assert_true(offset >= 2.99 and offset <= 6.01, "offset %.2f" % offset)
			var segment := floori(p.x / TreeFeatures.ROAD_SEGMENT_M)
			carried[segment] = true
			if segment == previous_segment:
				var gap := p.distance_to(previous)
				assert_true(gap >= 5.99 and gap <= 12.05, "spacing %.2f" % gap)
			previous = p
			previous_segment = segment
		trees += positions.size()
		var length := 0.0
		for segment: int in carried:
			length += minf(1000.0 - segment * 80.0, 80.0)
		var share := length / 1000.0
		assert_true(share >= 0.2 and share <= 0.4, "key %d: share %.2f" % [key, share])
	assert_true(trees > 12 * 15, "trees: %d" % trees)


func test_roadside_positions_of_an_area_are_a_subset_of_the_whole() -> void:
	var line := _straight(1000.0)
	var area := Rect2(300, -10, 300, 20)
	var all := TreeFeatures.roadside_positions(line, 2)
	var part := TreeFeatures.roadside_positions(line, 2, area)
	var expected := PackedVector2Array()
	for p in all:
		if area.has_point(p):
			expected.append(p)
	assert_eq(part, expected)
	assert_true(part.size() > 0)


func test_solitary_trees_are_few_and_stand_near_an_edge() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.FIELDS, 5)
	var parcels := FieldParcels.bake(grid, 1.0, Rect2(-12.0, -12.0, 24.0, 24.0))
	var trees := _plan(grid, Rect2(-9, -9, 18, 18), parcels)
	assert_true(trees.size() > 10, "some solitary trees: %d" % trees.size())
	var per_hex := {}
	var m := MapScale.metres_per_unit
	for tree in trees:
		var c := _hex_of(tree)
		per_hex[c] = int(per_hex.get(c, 0)) + 1
		var p: Vector3 = tree["position"]
		var here := TreeFeatures.boundary_label(parcels, p.x * m, p.z * m)
		var near := false
		for i in 16:
			var a := i * TAU / 16.0
			var q := Vector2(p.x, p.z) * m + Vector2(cos(a), sin(a)) * TreeFeatures.BOUNDARY_M
			near = near or TreeFeatures.boundary_label(parcels, q.x, q.y) != here
		assert_true(near, "within 15 m of a boundary")
	for c: Vector2i in per_hex:
		assert_true(per_hex[c] <= 3, "%s has %d" % [c, per_hex[c]])


func test_copses_have_5_to_30_trees_and_at_most_one_per_hex() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.MARSH, 6)
	var trees := _plan(grid, Rect2(-12, -12, 24, 24))
	var per_hex := {}
	for tree in trees:
		var c := _hex_of(tree)
		per_hex[c] = int(per_hex.get(c, 0)) + 1
	assert_true(per_hex.size() >= 3, "copses: %d" % per_hex.size())
	for c: Vector2i in per_hex:
		if Hex.distance(Vector2i.ZERO, c) > 4:
			continue
		assert_true(per_hex[c] >= 5 and per_hex[c] <= 30, "%s has %d" % [c, per_hex[c]])


func test_nothing_stands_in_forest_on_water_or_on_a_road() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.HILLS, 6)
	for c in grid.coords():
		if c.x == 2:
			grid.set_terrain(c, Terrain.Type.FOREST)
		elif c.x == -2:
			grid.set_terrain(c, Terrain.Type.WATER)
	for q in range(-5, 6):
		grid.set_road_links(Vector2i(q, 0), 0b001001)
	grid.set_road_links(Vector2i(-6, 0), 0b000001)
	grid.set_road_links(Vector2i(6, 0), 0b001000)
	var trees := _plan(grid, Rect2(-12, -12, 24, 24))
	assert_true(trees.size() > 20, "trees: %d" % trees.size())
	for tree in trees:
		var c := _hex_of(tree)
		assert_false(grid.get_terrain(c) in [Terrain.Type.FOREST, Terrain.Type.WATER])
		var p: Vector3 = tree["position"]
		# Off the 5 m carriageway; the 2.5 m verges may carry a roadside line.
		var verge := FeatureRibbonPlanner.ROAD_VERGE_M / MapScale.metres_per_unit
		var edge := FeatureRibbonPlanner.edge_distance(
			grid, FeatureRibbonPlanner.Kind.ROAD, p.x, p.z
		)
		assert_true(edge > -verge, "on the carriageway")


func test_roadside_lines_follow_a_grid_road() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.FIELDS, 6)
	for q in range(-5, 6):
		grid.set_road_links(Vector2i(q, 0), 0b001001)
	grid.set_road_links(Vector2i(-6, 0), 0b000001)
	grid.set_road_links(Vector2i(6, 0), 0b001000)
	var trees := _plan(grid, Rect2(-12, -12, 24, 24))
	var road := FeatureRibbonPlanner.lines(grid, FeatureRibbonPlanner.Kind.ROAD)
	assert_false(road.is_empty())
	var m := MapScale.metres_per_unit
	var near := 0
	for tree in trees:
		var p: Vector3 = tree["position"]
		for line in road:
			if _distance_to_line(Vector2(p.x, p.z), line) * m <= 6.5:
				near += 1
	assert_true(near > 10, "trees along the road: %d" % near)


# --- the whole plan ----------------------------------------------------------------------------


func test_other_presets_plan_nothing() -> void:
	var grid := _grid(Terrain.Type.HILLS, 4)
	var features := TreeFeatureSet.make(PackedVector2Array([Vector2(10, 10)]), [], [], [])
	for preset in [&"balanced", &"current"]:
		VisualScale.apply(preset)
		assert_eq(_plan(grid, Rect2(-8, -8, 16, 16), null, features).size(), 0, str(preset))


func test_the_plan_is_deterministic_and_chunks_add_up_to_the_whole() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.HILLS, 6)
	for c in grid.coords():
		if c.y == 3:
			grid.set_terrain(c, Terrain.Type.FIELDS)
	var parcels := FieldParcels.bake(grid, 1.0, Rect2(-12.0, -12.0, 24.0, 24.0))
	var features := TreeFeatureSet.make(
		PackedVector2Array([Vector2(60, 70), Vector2(-250, 90)]),
		[PackedVector2Array([Vector2(-300, -100), Vector2(400, 0), Vector2(450, 300)])],
		[_square(Vector2(-100, 300), Vector2(200, 150))],
		[_square(Vector2(500, -400), Vector2(160, 130))]
	)
	var whole := Rect2(-12, -12, 24, 24)
	var eager := _plan(grid, whole, parcels, features)
	assert_true(eager.size() > 100, "trees: %d" % eager.size())
	assert_eq(_plan(grid, whole, parcels, features), eager, "deterministic")
	var parts: Array[Dictionary] = []
	for x in range(-3, 3):
		for z in range(-3, 3):
			parts.append_array(_plan(grid, Rect2(x * 4.0, z * 4.0, 4.0, 4.0), parcels, features))
	assert_eq(parts.size(), eager.size(), "the chunks add up")
	var eager_positions := _positions(eager)
	for tree in parts:
		assert_true(eager_positions.has(tree["position"]), "a chunk tree is in the whole plan")


func test_trees_stand_on_the_ground_and_have_the_scatter_format() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.HILLS, 4)
	var surface := TerrainSurface.new(grid)
	var trees := TreeFeatures.plan(grid, surface, SEED, Rect2(-8, -8, 16, 16), null, null, null)
	assert_true(trees.size() > 0)
	for tree in trees:
		var p: Vector3 = tree["position"]
		var ground := surface.ground_height(p.x, p.z)
		assert_true(absf(p.y - (ground - ScatterPlanner.TREE_SINK)) < 1e-4)
		for key in ["scale", "height_scale", "yaw", "conifer", "k"]:
			assert_true(tree.has(key), key)
		assert_true(TreeSpecies.pick(tree)["species"] != &"", "has a species")


func test_the_added_trees_grow_the_open_plan_by_at_most_a_fifth() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _grid(Terrain.Type.FIELDS, 8)
	for c in grid.coords():
		if (c.x + 2 * c.y) % 5 == 0:
			grid.set_terrain(c, Terrain.Type.HILLS)
		elif (c.x - c.y) % 7 == 0:
			grid.set_terrain(c, Terrain.Type.MARSH)
	var surface := TerrainSurface.new(grid)
	var parcels := FieldParcels.bake(grid, 1.0, Rect2(-16.0, -16.0, 32.0, 32.0))
	var before := 0
	var plan := ScatterPlanner.plan(grid, surface, SEED, parcels)
	for key: String in plan:
		before += (plan[key] as Array).size()
	var hedges := ScatterPlanner.plan_hedges(grid, surface, parcels)
	before += (hedges["trees"] as Array).size() + (hedges["edge_shrubs"] as Array).size()
	var added := TreeFeatures.plan(
		grid, surface, SEED, Rect2(-14, -14, 28, 28), parcels, null, null
	)
	assert_true(added.size() > 0)
	assert_true(
		float(added.size()) <= 0.2 * before,
		"added %d to %d (%.1f %%)" % [added.size(), before, 100.0 * added.size() / before]
	)


func test_the_foliage_chunks_plan_the_osm_trees_on_the_true_preset_only() -> void:
	var grid := _grid(Terrain.Type.PLAINS, 4)
	var features := TreeFeatureSet.make(PackedVector2Array([Vector2(30, 40)]), [], [], [])
	var field := TreeField.new()
	var chunks := FoliageChunks.new(
		grid,
		TerrainSurface.new(grid),
		null,
		SEED,
		Rect2(-8, -8, 16, 16),
		Rect2(-6, -6, 12, 12),
		field
	)
	chunks.tree_features = features
	var m := MapScale.metres_per_unit
	var counts: Array[int] = []
	for preset in [&"balanced", VisualScale.TRUE_PRESET]:
		VisualScale.apply(preset)
		var found := 0
		for tree: Dictionary in chunks._plan_source(Vector2i.ZERO)["map"]["trees"]:
			var p: Vector3 = tree["position"]
			if Vector2(p.x, p.z).distance_to(Vector2(30, 40) / m) * m <= 0.5:
				found += 1
		counts.append(found)
	field.free()
	assert_eq(counts[0], 0, "balanced: no OSM tree")
	assert_eq(counts[1], 1, "true: the OSM tree")
