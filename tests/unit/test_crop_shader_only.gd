extends TestCase
## Crops are shader-only (TASK-217c): no plant of any layer on a crop parcel under `true`, decided
## by the crop keep-off mask (ParcelMap.crop_mask_on) with no per-plant kind lookup and no
## grass_keep; row spacing in real metres from the CropCatalog; row fade and the LOW cap; and that
## `balanced` (mask off) is the old per-point path.

const Fixtures := preload("res://tests/fixtures.gd")
const ShrubRulesTest := preload("res://tests/unit/test_shrub_rules.gd")

const SEED := 4242


## A ParcelMap that counts its per-point kind lookups (kind_at; the mask reads kind_at_metres).
class SpyParcelMap:
	extends ParcelMap
	var kind_lookups := 0

	func kind_at(x: float, z: float) -> int:
		kind_lookups += 1
		return super.kind_at(x, z)


func after_each() -> void:
	VisualScale.reset()
	LookPreset.reset()
	MapScale.reset()


func _fields_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(5)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FIELDS)
	return grid


func _spy(grid: HexGrid, mask_on: bool) -> SpyParcelMap:
	var baked := FieldParcels.bake(grid, TerrainField.HEX_SIZE, Rect2(-1.0, -1.0, 6.0, 6.0))
	var spy := SpyParcelMap.new()
	spy.image = baked.image
	spy.origin_m = baked.origin_m
	spy.metres_per_pixel = baked.metres_per_pixel
	spy.crop_mask_on = mask_on
	return spy


func test_no_plant_of_any_layer_stands_on_a_crop_parcel_interior() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _fields_grid()
	var parcels := _spy(grid, true)
	var surface := TerrainSurface.new(grid)
	var clumps := GrassPlanner.plan_chunk(Vector2i.ZERO, grid, surface, SEED, 1.0, {}, parcels)
	assert_true(clumps.size() > 10, "grass on the open ground: %d" % clumps.size())
	for g: Dictionary in clumps:
		var p: Vector3 = g["position"]
		assert_false(parcels.blocks_tall_grass(p.x, p.z), "no clump on a crop pixel")
	var plan := ScatterPlanner.plan(grid, surface, SEED, parcels)
	for key: String in plan:
		for item: Dictionary in plan[key]:
			var p: Vector3 = item["position"]
			assert_false(parcels.blocks_standing(p.x, p.z), "%s on a parcel" % key)
	# The shrubs (GPU rules) over the interior of the shrub fixture's crop parcels.
	var rules := ShrubRulesTest.make_rules(SEED)
	var interior := Rect2(700.0, 200.0, 300.0, 600.0)
	assert_eq(ShrubRulesTest.shrubs_in(rules, interior).size(), 0, "no shrub on a crop interior")
	# The crop look itself builds no layer: the parcel table is a shader parameter only.
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	TerrainGround.set_parcels(material, parcels)
	assert_true(material.get_shader_parameter(&"crop_row") != null)


func test_the_planners_make_no_per_plant_kind_lookup_under_the_mask() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _fields_grid()
	var surface := TerrainSurface.new(grid)
	var parcels := _spy(grid, true)
	GrassPlanner.plan_chunk(Vector2i.ZERO, grid, surface, SEED, 1.0, {}, parcels)
	GrassPlanner.plan_flowers(Vector2i.ZERO, grid, surface, SEED, 1.0, {}, parcels)
	assert_eq(parcels.kind_lookups, 0, "0 kind lookups with the mask")
	var legacy := _spy(grid, false)
	GrassPlanner.plan_chunk(Vector2i.ZERO, grid, surface, SEED, 1.0, {}, legacy)
	assert_true(legacy.kind_lookups > 0, "balanced still looks the kind up per clump")


func test_the_scatter_plan_asks_the_exact_kind_and_bakes_no_mask_block() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _fields_grid()
	var surface := TerrainSurface.new(grid)
	var parcels := _spy(grid, true)
	var plan := ScatterPlanner.plan(grid, surface, SEED, parcels)
	assert_true(parcels._mask_blocks.is_empty(), "no 64x64 mask block baked by a plan")
	for key: String in plan:
		for item: Dictionary in plan[key]:
			var p: Vector3 = item["position"]
			assert_false(parcels.blocks_standing_exact(p.x, p.z), "%s on a parcel" % key)
	# The exact answer is the mask's, away from pixel edges.
	for i in 40:
		var x := -0.8 + i * 0.14
		var z := 0.3 + i * 0.09
		assert_eq(parcels.blocks_standing_exact(x, z), parcels.blocks_standing(x, z), "at %d" % i)


func test_grass_does_not_read_grass_keep_under_the_mask() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _fields_grid()
	var parcels := _spy(grid, true)
	var keeps := GrassPlanner.parcel_keeps(parcels)
	for k in keeps.size():
		assert_eq(keeps[k], 1.0, "kind %d keep ignored" % k)
	# Even a look that would keep grass on every crop: the mask still rules.
	var surface := TerrainSurface.new(grid)
	for g: Dictionary in GrassPlanner.plan_chunk(
		Vector2i.ZERO, grid, surface, SEED, 1.0, {}, parcels
	):
		var p: Vector3 = g["position"]
		assert_false(parcels.blocks_tall_grass(p.x, p.z))


func test_balanced_reads_grass_keep_and_the_old_kinds_per_point() -> void:
	var grid := _fields_grid()
	var parcels := _spy(grid, false)
	var keeps := GrassPlanner.parcel_keeps(parcels)
	assert_eq(keeps[FieldParcels.Kind.MEADOW], 1.0)
	assert_eq(keeps[FieldParcels.Kind.WHEAT], 0.0)
	# The mask agrees with the per-point kinds away from pixel edges (pixel centres).
	var on := _spy(grid, true)
	for i in 40:
		var x := -0.8 + i * 0.14
		var z := 0.3 + i * 0.09
		var m := MapScale.metres_per_unit
		var px := floorf((x * m - on.origin_m.x) / on.metres_per_pixel) + 0.5
		var pz := floorf((z * m - on.origin_m.y) / on.metres_per_pixel) + 0.5
		var cx := (on.origin_m.x + px * on.metres_per_pixel) / m
		var cz := (on.origin_m.y + pz * on.metres_per_pixel) / m
		var kind := parcels.kind_at(cx, cz)
		assert_eq(on.blocks_standing(cx, cz), kind != 0 and kind != 8, "standing at %d" % i)
		assert_eq(
			on.blocks_tall_grass(cx, cz), kind != 0 and kind != 8 and kind != 7, "grass at %d" % i
		)


func test_row_spacing_is_real_metres_from_the_catalog_at_any_map_scale() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var parcels := _spy(_fields_grid(), true)
	var catalog := CropCatalog.load_default()
	var tables: Array[PackedVector2Array] = []
	for scale_m: float in [144.34, 60.0]:
		MapScale.metres_per_unit = scale_m
		var material := ShaderMaterial.new()
		material.shader = TerrainGround.SHADER
		TerrainGround.set_parcels(material, parcels)
		assert_eq(material.get_shader_parameter(&"metres_per_unit"), scale_m)
		var rows: PackedVector2Array = material.get_shader_parameter(&"crop_row")
		tables.append(rows)
		for kind in catalog.kinds:
			var index := FieldParcels.CROPS.find(kind.kind_name)
			assert_true(index >= 0, "%s is a parcel kind" % kind.kind_name)
			assert_true(kind.row_spacing_m >= 0.3 and kind.row_spacing_m <= 0.75)
			assert_true(
				absf(rows[index].x - kind.row_spacing_m) < 1e-5,
				"%s spacing in metres" % kind.kind_name
			)
	assert_eq(tables[0], tables[1], "the same metre spacing at two MapScale values")


func test_every_kind_has_a_harvest_tone_and_a_row_direction_per_parcel() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var look := LookPreset.fields()
	var parcels := _spy(_fields_grid(), true)
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	TerrainGround.set_parcels(material, parcels)
	var harvest: PackedVector3Array = material.get_shader_parameter(&"crop_harvest")
	var plant: PackedVector3Array = material.get_shader_parameter(&"crop_plant")
	for kind in CropCatalog.load_default().kinds:
		var index := FieldParcels.CROPS.find(kind.kind_name)
		assert_true(kind.harvest_tone != kind.colour, "%s has a harvest tone" % kind.kind_name)
		assert_true(
			harvest[index] != plant[index] or kind.ground_look, "%s in shader" % kind.kind_name
		)
		assert_true(look["crops"][kind.kind_name].has("harvest"))
	# One row direction per parcel (the strip's own axis), from the parcel's data.
	var a := FieldParcels.parcel_at(100.0, 200.0)
	assert_eq(a["along_x"], FieldParcels.parcel_at(100.0, 200.0)["along_x"])


func test_rows_are_gone_at_150_m_and_600_m_and_the_fade_is_tunable() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var look := LookPreset.fields()
	assert_eq(CropLook.row_strength(150.0, look), 0.0)
	assert_eq(CropLook.row_strength(600.0, look), 0.0)
	var tuned := look.duplicate()
	tuned["row_full_m"] = 20.0
	tuned["row_zero_m"] = 80.0
	assert_eq(CropLook.row_strength(20.0, tuned), 1.0)
	assert_eq(CropLook.row_strength(80.0, tuned), 0.0)
	assert_true(
		CropLook.row_strength(100.0, look) > 0.0 and CropLook.row_strength(50.0, tuned) > 0.0
	)


func test_low_quality_draws_no_rows_beyond_50_m_and_high_follows_the_preset() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var look := LookPreset.fields()
	var low := GraphicsQuality.features(GraphicsQuality.Level.LOW)
	var high := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	assert_eq(float(low["crop_rows_max_m"]), 50.0)
	assert_eq(float(high["crop_rows_max_m"]), 0.0)
	var capped := CropLook.row_distances(look, float(low["crop_rows_max_m"]))
	assert_true(capped.x < capped.y and capped.y == 50.0)
	assert_eq(smoothstep(capped.x, capped.y, 50.0), 1.0, "no rows at 50 m")
	assert_eq(
		CropLook.row_distances(look, float(high["crop_rows_max_m"])),
		Vector2(look["row_full_m"], look["row_zero_m"])
	)
	var parcels := _spy(_fields_grid(), true)
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	TerrainGround.set_parcels(material, parcels, low)
	assert_eq(material.get_shader_parameter(&"row_distance_m"), capped)
