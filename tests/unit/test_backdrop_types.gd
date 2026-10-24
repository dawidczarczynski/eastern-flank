extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")


func _types(grid: HexGrid) -> BackdropTypes:
	return BackdropTypes.new(grid, 1.0, Vector2(-4.0, -4.0), Vector2(0.25, 0.25))


func test_nearest_tile_type_off_the_map_is_the_closest_tile() -> void:
	var grid := Fixtures.plains_grid(1)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	var forest := Hex.to_world(Vector2i(1, 0), 1.0)
	var beyond := Vector2(forest.x, forest.z) * 3.0
	assert_eq(_types(grid).nearest_tile_type(beyond), Terrain.Type.FOREST)
	assert_eq(_types(grid).nearest_tile_type(-beyond), Terrain.Type.PLAINS)


func test_border_shares_sum_to_one_and_count_the_samples() -> void:
	var grid := Fixtures.plains_grid(1)
	for c in grid.coords():
		if Hex.to_world(c, 1.0).x > 0.1:
			grid.set_terrain(c, Terrain.Type.FOREST)
	var types := _types(grid)
	var mixed := 0
	for ca in 17:
		var shares := types.border_shares(ca, 0)
		var total := 0.0
		for type: int in shares:
			total += shares[type]
			var samples: float = shares[type] * BackdropTypes.SAMPLES.size()
			assert_true(is_equal_approx(samples, roundf(samples)), "whole samples")
		assert_true(is_equal_approx(total, 1.0), "shares at %d sum to %s" % [ca, total])
		if shares.size() > 1:
			mixed += 1
	assert_true(mixed > 0, "plains and forest mix along the north border")


func test_border_shares_are_cached() -> void:
	var types := _types(Fixtures.plains_grid(1))
	var first := types.border_shares(3, 2)
	assert_true(is_same(first, types.border_shares(3, 2)), "the cached Dictionary")
	assert_eq(first, {Terrain.Type.PLAINS: 1.0})
