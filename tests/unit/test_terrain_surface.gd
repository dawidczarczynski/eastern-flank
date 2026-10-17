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
