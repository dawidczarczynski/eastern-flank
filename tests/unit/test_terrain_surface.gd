extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const EPSILON := 1e-6


func _generate(map_seed: int) -> HexGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	return MapGenerator.generate(12, 10, rng)


func _near(actual: float, expected: float, message := "") -> void:
	assert_true(
		absf(actual - expected) < EPSILON, "expected %f, got %f. %s" % [expected, actual, message]
	)


func test_height_at_tile_center_equals_elevation() -> void:
	var grid := _generate(12345)
	var surface := TerrainSurface.new(grid)
	for c in grid.coords():
		var center := Hex.to_world(c, TerrainField.HEX_SIZE)
		_near(surface.height_at(center.x, center.z), grid.elevation(c), str(c))


func test_height_at_follows_the_field_without_forced_tiles() -> void:
	var grid := _generate(12345)
	var surface := TerrainSurface.new(grid)
	var coords := grid.coords()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 50:
		# A random point inside a random tile (within the inradius of its centre).
		var center := Hex.to_world(coords[rng.randi_range(0, coords.size() - 1)], 1.0)
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.0, 0.85)
		var x := center.x + cos(angle) * radius
		var z := center.z + sin(angle) * radius
		_near(surface.height_at(x, z), grid.field.height(x, z), "point %d" % i)


## The first generated map (seeds 1, 2, ...) with a tile below 0, and that tile.
## Seed 12345 has no water, so the seed is searched deterministically.
func _map_with_low_tile() -> Array:
	for map_seed in range(1, 51):
		var grid := _generate(map_seed)
		for c in grid.coords():
			if grid.elevation(c) < 0.0:
				return [grid, c]
	assert_true(false, "no generated map has a tile below 0")
	return [_generate(1), Vector2i.ZERO]


func test_forced_tile_corrects_the_surface_near_its_centre() -> void:
	var found := _map_with_low_tile()
	var grid: HexGrid = found[0]
	var c: Vector2i = found[1]
	MapGenerator.force_terrain(grid, c, Terrain.Type.PLAINS)
	var surface := TerrainSurface.new(grid)
	var center := Hex.to_world(c, TerrainField.HEX_SIZE)
	var field := grid.field
	_near(surface.height_at(center.x, center.z), 0.12)

	# Within 0.35 of the centre the full correction applies.
	var x := center.x + 0.3
	var z := center.z
	var correction := 0.12 - field.height(center.x, center.z)
	_near(surface.height_at(x, z), field.height(x, z) + correction)

	# Beyond 0.8 there is no correction (still inside the hex: inradius 0.866).
	x = center.x + 0.82
	assert_eq(Hex.from_world(Vector3(x, 0.0, z), 1.0), c)
	assert_eq(surface.height_at(x, z), field.height(x, z))


func test_hand_made_grid_uses_tile_elevation() -> void:
	var grid := Fixtures.plains_grid(2)
	var surface := TerrainSurface.new(grid)
	assert_eq(surface.height_at(0.0, 0.0), 0.2)
	assert_eq(surface.ground_height(100.0, 100.0), 0.0)


func test_water_tile_is_below_the_water_surface() -> void:
	var grid := Fixtures.plains_grid(2)
	var c := Vector2i(1, 0)
	grid.set_terrain(c, Terrain.Type.WATER)
	var surface := TerrainSurface.new(grid)
	var p := Hex.to_world(c, 1.0)
	assert_eq(surface.height_at(p.x, p.z), -0.3)
	assert_eq(surface.ground_height(p.x, p.z), TerrainSurface.WATER_SURFACE)
	assert_eq(surface.ground_height(p.x, p.z), 0.0)


func _assert_hit_near(hit: Variant, expected: Vector3, tolerance: float) -> void:
	assert_true(hit is Vector3, "expected a hit, got %s" % [hit])
	if hit is Vector3:
		var p: Vector3 = hit
		assert_true(p.distance_to(expected) < tolerance, "expected %s, got %s" % [expected, p])


func test_raycast_straight_down_hits_the_ground() -> void:
	var surface := TerrainSurface.new(Fixtures.plains_grid(3))
	var hit: Variant = surface.raycast(Vector3(0.0, 10.0, 0.0), Vector3.DOWN)
	_assert_hit_near(hit, Vector3(0.0, 0.2, 0.0), 0.01)


func test_raycast_diagonal_hits_the_ground_at_the_right_x() -> void:
	var surface := TerrainSurface.new(Fixtures.plains_grid(3))
	var hit: Variant = surface.raycast(
		Vector3(-5.0, 5.2, 0.0), Vector3(1.0, -1.0, 0.0).normalized()
	)
	assert_true(hit is Vector3, "expected a hit")
	if hit is Vector3:
		var p: Vector3 = hit
		assert_true(absf(p.x) < 0.01, "x = %f" % p.x)
		assert_true(absf(p.y - 0.2) < 0.01, "y = %f" % p.y)


func test_raycast_hits_a_hill_on_a_generated_map() -> void:
	var grid := _generate(6)  # seed 6 has hills well above 2.0
	var surface := TerrainSurface.new(grid)
	var top := grid.coords()[0]
	for c in grid.coords():
		if grid.elevation(c) > grid.elevation(top):
			top = c
	assert_true(grid.elevation(top) > 1.0, "expected a high tile, got %f" % grid.elevation(top))
	var center := Hex.to_world(top, TerrainField.HEX_SIZE)
	var straight: Variant = surface.raycast(center + Vector3.UP * 10.0, Vector3.DOWN)
	_assert_hit_on_surface(surface, straight)
	if straight is Vector3:
		var p: Vector3 = straight
		assert_true(absf(p.y - grid.elevation(top)) < 0.01, "y = %f" % p.y)
	var oblique: Variant = surface.raycast(
		center + Vector3(-6.0, 8.0, 5.0), Vector3(6.0, -8.0, -5.0)
	)
	_assert_hit_on_surface(surface, oblique)


func _assert_hit_on_surface(surface: TerrainSurface, hit: Variant) -> void:
	assert_true(hit is Vector3, "expected a hit")
	if hit is Vector3:
		var p: Vector3 = hit
		var ground := surface.ground_height(p.x, p.z)
		assert_true(absf(p.y - ground) < 0.01, "hit y %f, ground %f" % [p.y, ground])


func test_raycast_works_with_an_unnormalized_direction() -> void:
	var surface := TerrainSurface.new(Fixtures.plains_grid(3))
	var hit: Variant = surface.raycast(Vector3(-5.0, 5.2, 0.0), Vector3(3.0, -3.0, 0.0))
	_assert_hit_near(hit, Vector3(0.0, 0.2, 0.0), 0.01)


func test_raycast_up_or_horizontal_returns_null() -> void:
	var surface := TerrainSurface.new(Fixtures.plains_grid(3))
	assert_eq(surface.raycast(Vector3(0.0, 10.0, 0.0), Vector3.UP), null)
	assert_eq(surface.raycast(Vector3(0.0, 10.0, 0.0), Vector3.RIGHT), null)


func test_raycast_off_the_map_hits_the_water_surface() -> void:
	var surface := TerrainSurface.new(Fixtures.plains_grid(3))
	var hit: Variant = surface.raycast(Vector3(40.0, 10.0, 40.0), Vector3(0.3, -1.0, 0.2))
	assert_true(hit is Vector3, "expected a hit")
	if hit is Vector3:
		var p: Vector3 = hit
		assert_true(absf(p.y - TerrainSurface.WATER_SURFACE) < 0.01, "y = %f" % p.y)
		assert_true(p.x > 40.0 and p.z > 40.0, "hit %s" % p)


func test_raycast_from_below_the_start_height_starts_at_the_origin() -> void:
	var surface := TerrainSurface.new(Fixtures.plains_grid(3))
	var hit: Variant = surface.raycast(Vector3(0.0, 1.0, 0.0), Vector3.DOWN)
	_assert_hit_near(hit, Vector3(0.0, 0.2, 0.0), 0.01)
