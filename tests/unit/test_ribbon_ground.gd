extends TestCase
## Ribbons and bridges lie on the drawn ground (TASK-108c playtest fix): a ribbon vertex is the
## exact surface height plus a small lift in metres, at any map scale; overlapping bridge decks
## are merged into the steepest crossing.

const Fixtures := preload("res://tests/fixtures.gd")

static var _shared: MapView


static func _grid() -> HexGrid:
	var grid := Fixtures.plains_grid(4)
	for c in grid.coords():
		grid.set_elevation(c, 0.3 * c.x + 0.2 * c.y)
	for q in range(-3, 3):
		var a := Vector2i(q, 0)
		grid.set_road_links(a, grid.road_links(a) | 1)
		grid.set_road_links(a + Vector2i.RIGHT, grid.road_links(a + Vector2i.RIGHT) | (1 << 3))
	var down := Hex.DIRECTIONS.find(Vector2i(0, 1))
	for r in range(-3, 3):
		var a := Vector2i(0, r)
		var b := Vector2i(0, r + 1)
		grid.set_river_links(a, grid.river_links(a) | (1 << down))
		grid.set_river_links(b, grid.river_links(b) | (1 << ((down + 3) % 6)))
	return grid


func before_all() -> void:
	var features := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	features["foliage"] = false
	_shared = Fixtures.map_view(_grid(), features)


func after_all() -> void:
	_shared.free()


func before_each() -> void:
	Fixtures.reset_map_view(_shared)


func after_each() -> void:
	MapScale.reset()


func _check_node(node_name: String, kind: FeatureRibbonPlanner.Kind) -> void:
	var node := _shared._tiles_root.get_node(node_name) as MeshInstance3D
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(vertices.size() > 10, "%s has vertices" % node_name)
	var lift := FeatureRibbonPlanner.lift(kind)
	var surface := _shared.surface()
	for v in vertices:
		var ground := surface.ground_height(v.x, v.z)
		assert_true(
			absf(v.y - ground - lift) < 1e-4,
			"%s vertex on the ground (%f)" % [node_name, v.y - ground]
		)
	# The lift is a fraction of a metre, not metres.
	assert_true(lift * MapScale.metres_per_unit < 0.5)


func test_road_and_river_vertices_lie_on_the_exact_ground() -> void:
	_check_node("Roads", FeatureRibbonPlanner.Kind.ROAD)
	_check_node("Rivers", FeatureRibbonPlanner.Kind.RIVER)


func test_the_lift_is_metres_at_any_map_scale() -> void:
	var normal := FeatureRibbonPlanner.lift(FeatureRibbonPlanner.Kind.RIVER)
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT / 2.0
	assert_true(
		absf(FeatureRibbonPlanner.lift(FeatureRibbonPlanner.Kind.RIVER) - 2.0 * normal) < 1e-9
	)
	assert_true(FeatureRibbonPlanner.lift(FeatureRibbonPlanner.Kind.ROAD) > normal)


func _site(at: Vector2, span_m: float) -> Dictionary:
	return {"position": at, "span_m": span_m}


func test_overlapping_decks_are_merged_and_distant_ones_kept() -> void:
	var kept: Array[Dictionary] = [_site(Vector2.ZERO, 40.0)]
	var m := MapScale.to_units(1.0)
	assert_true(BridgeSites.overlaps(kept, _site(Vector2(20.0 * m, 0.0), 18.0)), "20 m apart")
	assert_true(BridgeSites.overlaps(kept, _site(Vector2(5.0 * m, 3.0 * m), 10.0)), "within 10 m")
	assert_false(BridgeSites.overlaps(kept, _site(Vector2(120.0 * m, 0.0), 30.0)), "120 m apart")


func test_suwalki_decks_never_overlap() -> void:
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	MapScale.apply_map_id(Scenario.SUWALKI_MAP_ID)
	var sites := BridgeSites.find(grid)
	for i in sites.size():
		for j in range(i + 1, sites.size()):
			var rest: Array[Dictionary] = [sites[i]]
			assert_false(BridgeSites.overlaps(rest, sites[j]), "sites %d and %d" % [i, j])
