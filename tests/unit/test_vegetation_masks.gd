extends TestCase
## VegetationMasks (TASK-217a, ADR 0033): the habitat and forest-edge textures of the GPU-placed
## vegetation are built once per map at <= 4.5 m per texel, cover the whole area, keep the ribbons
## off and are byte-identical when rebuilt.

const ShrubFixture := preload("res://tests/unit/test_shrub_rules.gd")
const Fixtures := preload("res://tests/fixtures.gd")


func after_each() -> void:
	MapScale.reset()


func test_size_and_texel_scale() -> void:
	var area := ShrubFixture.rect_u(Rect2(0.0, 0.0, 2000.0, 2000.0))
	var masks := VegetationMasks.build(area, ShrubFixture.fixture_inputs(area))
	assert_true(masks.texel_m() <= 4.5, "%.2f m per texel" % masks.texel_m())
	assert_true(absf(masks.texel_m() - VegetationMasks.TEXEL_M) < 1.0e-6)
	var expected := Vector2i(
		ceili(area.size.x * masks.per_unit - 1.0e-6), ceili(area.size.y * masks.per_unit - 1.0e-6)
	)
	assert_eq(masks.size, expected, "texels over the area")
	for image: Image in [masks.habitat_image(), masks.forest_image()]:
		assert_eq(image.get_size(), expected)
		assert_eq(image.get_format(), Image.FORMAT_L8)
	# Another map scale keeps the metres per texel.
	MapScale.metres_per_unit = 100.0
	var other := VegetationMasks.build(area, {})
	assert_true(absf(other.texel_m() - VegetationMasks.TEXEL_M) < 1.0e-6)


func test_rebuilding_gives_identical_bytes() -> void:
	var area := ShrubFixture.rect_u(Rect2(0.0, 0.0, 2000.0, 2000.0))
	var a := VegetationMasks.build(area, ShrubFixture.fixture_inputs(area))
	var b := VegetationMasks.build(area, ShrubFixture.fixture_inputs(area))
	assert_eq(a.habitat_image().get_data(), b.habitat_image().get_data(), "habitat")
	assert_eq(a.forest_image().get_data(), b.forest_image().get_data(), "forest edge")
	# A hex map (the fallback cover): forest tiles through ForestFill's stand mask, urban tiles.
	var grid := Fixtures.plains_grid(3)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(-1, 0), Terrain.Type.URBAN)
	var rect := Rect2(-6.0, -6.0, 12.0, 12.0)
	var flat := func(_x: float, _z: float) -> float: return 0.5
	var fill := ForestFill.new(grid, flat, 7, rect)
	var c := VegetationMasks.from_map(grid, rect, fill, LandCover.from_grid(grid), null)
	var d := VegetationMasks.from_map(grid, rect, fill, LandCover.from_grid(grid), null)
	assert_eq(c.habitat_image().get_data(), d.habitat_image().get_data())
	assert_eq(c.forest_image().get_data(), d.forest_image().get_data())
	var urban := Hex.to_world(Vector2i(-1, 0), TerrainField.HEX_SIZE)
	assert_eq(c.habitat_at(urban.x, urban.z), VegetationMasks.Habitat.KEEP_OFF, "urban tile")
	var forest := Hex.to_world(Vector2i(1, 0), TerrainField.HEX_SIZE)
	assert_true(c.forest_at(forest.x + 0.4, forest.z) > 200, "inside the forest tile")


func test_ribbons_are_kept_off_and_banks_and_hedges_marked() -> void:
	var area := ShrubFixture.rect_u(Rect2(0.0, 0.0, 2000.0, 2000.0))
	var masks := VegetationMasks.build(area, ShrubFixture.fixture_inputs(area))
	var river := ShrubFixture.u(ShrubFixture.RIVER_X_M)
	var keep := VegetationMasks.Habitat.KEEP_OFF
	assert_eq(masks.habitat_at(river, ShrubFixture.u(300.0)), keep, "river ribbon")
	assert_eq(
		masks.habitat_at(river + ShrubFixture.u(20.0), ShrubFixture.u(300.0)),
		VegetationMasks.Habitat.BANK
	)
	assert_eq(
		masks.habitat_at(ShrubFixture.u(1000.0), ShrubFixture.u(ShrubFixture.ROAD_Z_M)),
		keep,
		"road"
	)
	assert_eq(
		masks.habitat_at(ShrubFixture.u(1000.0), ShrubFixture.u(ShrubFixture.HEDGE_Z_M)),
		VegetationMasks.Habitat.HEDGE
	)
	assert_eq(
		masks.habitat_at(ShrubFixture.u(800.0), ShrubFixture.u(1200.0)),
		VegetationMasks.Habitat.HEATH
	)
	assert_eq(
		masks.habitat_at(ShrubFixture.u(1200.0), ShrubFixture.u(1800.0)), keep, "built-up block"
	)
	assert_eq(masks.habitat_at(-1.0, -1.0), keep, "outside the area")
	assert_eq(masks.forest_at(ShrubFixture.u(100.0), ShrubFixture.u(300.0)), 255, "forest interior")
	assert_eq(masks.forest_at(ShrubFixture.u(700.0), ShrubFixture.u(300.0)), 0, "open land")
	var edge := masks.forest_at(ShrubFixture.u(ShrubFixture.FOREST_EDGE_M), ShrubFixture.u(300.0))
	assert_true(edge > ShrubRules.EDGE_FROM and edge < ShrubRules.EDGE_TO, "edge %d" % edge)
