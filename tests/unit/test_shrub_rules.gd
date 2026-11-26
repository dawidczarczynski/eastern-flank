extends TestCase
## ShrubRules, the GDScript reference of the GPU-placed shrubs (TASK-217a, ADR 0033), over one
## synthetic 2 x 2 km fixture map (metres, converted with MapScale): a forest (x < 400 m), strip
## parcels with a balk, a hedge, a river with its banks, a road that crosses it (the bridge), a
## built-up block, a heath patch and open meadow. Determinism, keep-off, parcel edges, habitat
## densities, kinds, metre heights and the noise-driven scrub.

const SEED := 20240518
const FOREST_EDGE_M := 400.0
const HEDGE_Z_M := 1000.0
const HEDGE_X_M := Vector2(600.0, 1600.0)
const RIVER_X_M := 1800.0
const RIVER_HALF_M := 10.0
const ROAD_Z_M := 1500.0
const ROAD_HALF_M := 4.0
const URBAN_M := Rect2(1000.0, 1700.0, 400.0, 250.0)
const HEATH_M := Rect2(600.0, 1100.0, 400.0, 300.0)
const PARCELS_M := Rect2(600.0, 100.0, 1000.0, 800.0)
const BALK_X_M := Vector2(1100.0, 1110.0)
const RASTER_CELL_M := 20.0

static var _rules: ShrubRules


func before_all() -> void:
	MapScale.reset()
	_rules = make_rules(SEED)


func after_all() -> void:
	_rules = null
	MapScale.reset()


func after_each() -> void:
	MapScale.reset()


static func u(metres: float) -> float:
	return MapScale.to_units(metres)


static func rect_u(metres: Rect2) -> Rect2:
	return Rect2(metres.position / MapScale.metres_per_unit, metres.size / MapScale.metres_per_unit)


static func _flat(_x: float, _z: float) -> float:
	return 1.0


## The fixture's masks and rules at the current MapScale.
static func make_rules(seed_value: int) -> ShrubRules:
	var area := rect_u(Rect2(0.0, 0.0, 2000.0, 2000.0))
	var masks := VegetationMasks.build(area, fixture_inputs(area))
	return ShrubRules.new(masks, _flat, seed_value, fixture_parcels(), LookPreset.vegetation())


static func fixture_inputs(area: Rect2) -> Dictionary:
	var per_unit := MapScale.metres_per_unit / VegetationMasks.TEXEL_M
	var size := ForestMaskSource.mask_size(area, per_unit)
	var forest := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	forest.fill_rect(Rect2i(0, 0, roundi(u(FOREST_EDGE_M) * per_unit), size.y), Color.WHITE)
	var hedge := PackedVector2Array(
		[Vector2(u(HEDGE_X_M.x), u(HEDGE_Z_M)), Vector2(u(HEDGE_X_M.y), u(HEDGE_Z_M))]
	)
	var river := PackedVector2Array([Vector2(u(RIVER_X_M), 0.0), Vector2(u(RIVER_X_M), u(2000.0))])
	var road := PackedVector2Array(
		[Vector2(u(450.0), u(ROAD_Z_M)), Vector2(u(1950.0), u(ROAD_Z_M))]
	)
	return {
		"forest": forest,
		"forest_area": area,
		"cover": fixture_cover(),
		"hedges": [hedge],
		"rivers": [[river, PackedFloat32Array([u(RIVER_HALF_M), u(RIVER_HALF_M)])]],
		"roads": [[road, PackedFloat32Array([u(ROAD_HALF_M), u(ROAD_HALF_M)])]],
	}


## A land-cover raster (20 m cells): open land with the built-up block, the heath patch and the
## field cover under the parcels.
static func fixture_cover() -> LandCover:
	var n := roundi(2000.0 / RASTER_CELL_M)
	var cells := PackedByteArray()
	cells.resize(n * n)
	for j in n:
		for i in n:
			var c := Vector2((i + 0.5) * RASTER_CELL_M, (j + 0.5) * RASTER_CELL_M)
			var kind := LandCover.Kind.OPEN
			if URBAN_M.has_point(c):
				kind = LandCover.Kind.URBAN
			elif HEATH_M.has_point(c):
				kind = LandCover.Kind.SCRUB
			elif PARCELS_M.grow(20.0).has_point(c):
				kind = LandCover.Kind.FIELD
			cells[j * n + i] = kind
	var cell := u(RASTER_CELL_M)
	return LandCover.from_cells(cells, n, n, Vector2.ONE * cell * 0.5, cell)


## Two crop parcels split by a 10 m balk (5 m pixels), NONE around them.
static func fixture_parcels() -> ParcelMap:
	var map := ParcelMap.new()
	map.metres_per_pixel = 5.0
	map.origin_m = Vector2.ZERO
	var n := 400
	var bytes := PackedByteArray()
	bytes.resize(n * n * 2)
	for j in n:
		for i in n:
			var c := Vector2((i + 0.5) * 5.0, (j + 0.5) * 5.0)
			if not PARCELS_M.has_point(c):
				continue
			var kind := 1
			if c.x >= BALK_X_M.x and c.x < BALK_X_M.y:
				kind = ShrubRules.PARCEL_BALK
			elif c.x >= BALK_X_M.y:
				kind = 2
			bytes[(j * n + i) * 2] = kind
	map.image = Image.create_from_data(n, n, false, Image.FORMAT_RG8, bytes)
	return map


## Shrubs whose point lies in `metres` (a rectangle in metres).
static func shrubs_in(rules: ShrubRules, metres: Rect2) -> Array[Dictionary]:
	return rules.plan_rect(rect_u(metres))


static func per_ha(count: int, metres: Rect2) -> float:
	return count / (metres.get_area() / 10000.0)


func test_the_same_cells_give_the_same_shrubs_in_any_order() -> void:
	var rect := Rect2(380.0, 900.0, 300.0, 200.0)
	var first := shrubs_in(_rules, rect)
	assert_true(first.size() > 50, "%d shrubs" % first.size())
	assert_eq(shrubs_in(make_rules(SEED), rect), first, "a second run gives the same shrubs")
	# Any chunk order: the cells of 4 chunks, last first.
	var by_cell := {}
	var chunks: Array[Rect2] = []
	for k in 4:
		chunks.append(Rect2(rect.position.x + k * 75.0, rect.position.y, 75.0, rect.size.y))
	chunks.reverse()
	for chunk in chunks:
		for shrub in shrubs_in(_rules, chunk):
			by_cell[shrub["cell"]] = shrub
	assert_eq(by_cell.size(), first.size(), "the chunks hold the same shrubs")
	for shrub in first:
		assert_eq(by_cell.get(shrub["cell"]), shrub, "same shrub in %s" % shrub["cell"])
	assert_true(shrubs_in(make_rules(SEED + 1), rect) != first, "another seed")


func test_no_shrub_stands_on_ribbons_bridges_buildings_or_parcel_interiors() -> void:
	# The river (with the bridge where the road crosses it) and the road.
	for shrub in shrubs_in(_rules, Rect2(RIVER_X_M - 60.0, 0.0, 120.0, 2000.0)):
		var p: Vector3 = shrub["position"]
		assert_true(absf(p.x * MapScale.metres_per_unit - RIVER_X_M) > RIVER_HALF_M, "off river")
	var road_band := Rect2(450.0, ROAD_Z_M - 30.0, 1500.0, 60.0)
	var near_road := shrubs_in(_rules, road_band)
	for shrub in near_road:
		var p: Vector3 = shrub["position"]
		assert_true(absf(p.z * MapScale.metres_per_unit - ROAD_Z_M) > ROAD_HALF_M, "off road")
	assert_true(near_road.size() > 20, "roadside scrub: %d" % near_road.size())
	var bridge := Rect2(RIVER_X_M - 30.0, ROAD_Z_M - 30.0, 60.0, 60.0)
	for shrub in shrubs_in(_rules, bridge):
		var p: Vector3 = shrub["position"] * MapScale.metres_per_unit
		var off_road := absf(p.z - ROAD_Z_M) > ROAD_HALF_M
		var off_river := absf(p.x - RIVER_X_M) > RIVER_HALF_M
		assert_true(off_road and off_river, "nothing on the bridge: %s" % p)
	# The built-up block (its raster cells, shrunk by one mask texel).
	assert_eq(shrubs_in(_rules, URBAN_M.grow(-5.0)).size(), 0, "no shrub on built-up land")
	# The crop parcels' interiors.
	var interior := Rect2(700.0, 200.0, 300.0, 600.0)
	assert_eq(shrubs_in(_rules, interior).size(), 0, "no shrub inside a crop parcel")


func test_parcel_edge_strips_and_balks_carry_shrubs() -> void:
	# The western strip of the first parcel (crop within 3 m of the unpainted land) and the balk.
	var strip := Rect2(PARCELS_M.position.x, 150.0, 3.0, 700.0)
	var on_strip := shrubs_in(_rules, strip)
	var balk := Rect2(BALK_X_M.x, 150.0, BALK_X_M.y - BALK_X_M.x, 700.0)
	var on_balk := shrubs_in(_rules, balk)
	var interior := Rect2(700.0, 200.0, 300.0, 600.0)
	var inside := per_ha(shrubs_in(_rules, interior).size(), interior)
	var edge := per_ha(on_strip.size() + on_balk.size(), Rect2(0.0, 0.0, 13.0, 700.0))
	assert_true(
		on_strip.size() > 0 and on_balk.size() > 0, "%d / %d" % [on_strip.size(), on_balk.size()]
	)
	assert_true(
		edge >= 3.0 * inside and edge > 20.0, "edge %.0f vs interior %.0f / ha" % [edge, inside]
	)
	for shrub in on_strip + on_balk:
		assert_eq(shrub["habitat"], ShrubRules.Habitat.FIELD_EDGE)


func test_habitat_densities_per_hectare() -> void:
	# Forest edge band: 10 m to both sides of the edge, 500 m long (1 ha).
	var edge := Rect2(FOREST_EDGE_M - 10.0, 50.0, 20.0, 500.0)
	_assert_density(edge, 150.0, 300.0, "forest edge")
	# Hedge: 1 per 2 m of line (+-25 %) within 5 m of it.
	var hedge := Rect2(HEDGE_X_M.x + 50.0, HEDGE_Z_M - 5.0, 900.0, 10.0)
	var per_m := shrubs_in(_rules, hedge).size() / hedge.size.x
	assert_true(per_m >= 0.375 and per_m <= 0.625, "hedge %.3f shrubs per m" % per_m)
	# River banks: 13-25 m from the centre line on both sides, 416.7 m long (1 ha).
	var length := 10000.0 / 24.0
	var count := 0
	for side: float in [-1.0, 1.0]:
		var x0 := RIVER_X_M + side * 19.0 - 6.0
		count += shrubs_in(_rules, Rect2(x0, 50.0, 12.0, length)).size()
	var bank := count / 1.0
	assert_true(bank >= 80.0 and bank <= 200.0, "bank %.0f / ha" % bank)
	# Heath (4 ha of the patch), open meadow (1 ha), forest interior (4 ha).
	_assert_density(Rect2(650.0, 1150.0, 300.0, 133.3), 40.0, 120.0, "heath")
	_assert_density(Rect2(450.0, 1150.0, 100.0, 100.0), 0.0, 10.0, "meadow")
	_assert_density(Rect2(100.0, 200.0, 200.0, 200.0), 0.0, 0.0, "forest interior")


func _assert_density(metres: Rect2, lo: float, hi: float, label: String) -> void:
	var density := per_ha(shrubs_in(_rules, metres).size(), metres)
	assert_true(
		density >= lo and density <= hi, "%s %.1f / ha (%.0f-%.0f)" % [label, density, lo, hi]
	)


func test_the_kind_follows_the_habitat_and_heights_lie_in_the_kinds_range() -> void:
	var shares := {
		"bank": [Rect2(RIVER_X_M + 13.0, 0.0, 12.0, 1400.0), ShrubRules.Kind.WILLOW, 0.7],
		"heath": [HEATH_M.grow(-20.0), ShrubRules.Kind.JUNIPER, 0.6],
		"hedge": [Rect2(HEDGE_X_M.x, HEDGE_Z_M - 5.0, 1000.0, 10.0), ShrubRules.Kind.HAZEL, 0.6],
		"edge": [Rect2(FOREST_EDGE_M - 10.0, 0.0, 20.0, 1400.0), ShrubRules.Kind.HAZEL, 0.6],
	}
	for label: String in shares:
		var entry: Array = shares[label]
		var shrubs := shrubs_in(_rules, entry[0])
		var hits := 0
		for shrub in shrubs:
			if shrub["kind"] == entry[1]:
				hits += 1
			var range_m: Vector2 = ShrubRules.KIND_HEIGHT_M[shrub["kind"]]
			var h: float = shrub["height_m"]
			assert_true(h >= range_m.x and h <= range_m.y, "%s height %.2f m" % [label, h])
		var share := float(hits) / maxf(shrubs.size(), 1.0)
		assert_true(shrubs.size() > 40, "%s: %d shrubs" % [label, shrubs.size()])
		assert_true(share >= float(entry[2]), "%s share %.2f" % [label, share])
	# Every kind's range as the task gives it.
	assert_eq(ShrubRules.KIND_HEIGHT_M[ShrubRules.Kind.LOW_BUSH], Vector2(0.5, 1.0))
	assert_eq(ShrubRules.KIND_HEIGHT_M[ShrubRules.Kind.HAZEL], Vector2(1.5, 3.0))
	assert_eq(ShrubRules.KIND_HEIGHT_M[ShrubRules.Kind.JUNIPER], Vector2(0.8, 1.5))
	assert_eq(ShrubRules.KIND_HEIGHT_M[ShrubRules.Kind.WILLOW], Vector2(2.0, 3.0))


func test_heights_are_metres_at_any_map_scale() -> void:
	var rect := Rect2(FOREST_EDGE_M - 10.0, 0.0, 20.0, 600.0)
	var at_default := {}
	for shrub in shrubs_in(_rules, rect):
		at_default[shrub["cell"]] = shrub
	assert_true(at_default.size() > 20)
	MapScale.metres_per_unit = 100.0
	var other := make_rules(SEED)
	var same := 0
	for cell: Vector2i in at_default:
		var shrub := other.cell_shrub(cell)
		if shrub.is_empty():
			continue
		same += 1
		var want: Dictionary = at_default[cell]
		assert_true(absf(float(shrub["height_m"]) - float(want["height_m"])) < 1.0e-9, "metres")
		assert_true(
			absf(float(shrub["height"]) * 100.0 - float(want["height_m"])) < 1.0e-6, "units"
		)
	assert_true(
		same > at_default.size() / 2, "%d of %d cells keep their shrub" % [same, at_default.size()]
	)


func test_heath_scrub_density_varies_with_the_noise() -> void:
	var patch := HEATH_M.grow(-20.0)
	var counts := {}
	for shrub in shrubs_in(_rules, patch):
		var p: Vector3 = shrub["position"] * MapScale.metres_per_unit
		var key := Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))
		counts[key] = int(counts.get(key, 0)) + 1
	var cells := int(patch.size.x / 10.0) * int(patch.size.y / 10.0)
	var mean := 0.0
	for key: Vector2i in counts:
		mean += counts[key]
	mean /= cells
	var variance := 0.0
	for i in int(patch.size.x / 10.0):
		for j in int(patch.size.y / 10.0):
			var key := Vector2i(
				floori(patch.position.x / 10.0) + i, floori(patch.position.y / 10.0) + j
			)
			var d := float(counts.get(key, 0)) - mean
			variance += d * d
	assert_true(sqrt(variance / cells) > 0.0, "std dev of the 10 m counts")
	# The patch's noise spreads the density: its densest quarter holds clearly more.
	var quarters: Array[int] = [0, 0, 0, 0]
	for shrub in shrubs_in(_rules, patch):
		var p: Vector3 = shrub["position"] * MapScale.metres_per_unit
		var q := int(p.x > patch.get_center().x) + 2 * int(p.z > patch.get_center().y)
		quarters[q] += 1
	quarters.sort()
	assert_true(quarters[3] > quarters[0], "quarters %s" % str(quarters))


## The ParcelMap image is not clipped by the land cover: a crop texel only blocks where the cover
## carries parcels (FIELD for the strip parcels), and a meadow parcel is no crop.
func test_crop_texels_block_only_where_the_cover_carries_parcels() -> void:
	var inside := Vector2(u(800.0), u(500.0))
	assert_eq(_rules.habitat_at(inside), ShrubRules.Habitat.NONE, "a crop on field cover")
	var area := rect_u(Rect2(0.0, 0.0, 2000.0, 2000.0))
	var inputs := fixture_inputs(area)
	var cells := PackedByteArray()
	cells.resize(100 * 100)
	var cell := u(RASTER_CELL_M)
	inputs["cover"] = LandCover.from_cells(cells, 100, 100, Vector2.ONE * cell * 0.5, cell)
	var masks := VegetationMasks.build(area, inputs)
	var open := ShrubRules.new(masks, _flat, SEED, fixture_parcels(), LookPreset.vegetation())
	assert_eq(open.habitat_at(inside), ShrubRules.Habitat.MEADOW, "no field cover: no parcel")
	var meadow := fixture_parcels()
	meadow.image.fill(Color(ShrubRules.PARCEL_MEADOW / 255.0, 0.0, 0.0))
	var on_meadow := ShrubRules.new(_rules.masks, _flat, SEED, meadow, LookPreset.vegetation())
	assert_eq(on_meadow.habitat_at(inside), ShrubRules.Habitat.MEADOW, "a meadow parcel is no crop")
