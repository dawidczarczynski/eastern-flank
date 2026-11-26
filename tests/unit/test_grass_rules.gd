extends TestCase
## GrassRules, the GDScript reference of the GPU-placed near grass (TASK-217b, ADR 0033), over the
## 2 x 2 km fixture map of test_shrub_rules (metres, converted with MapScale): determinism, five
## cells fixed to literals, keep-off, densities, kinds and heights in the old GrassPlanner ranges,
## flowers and bank reeds against the old rules, the slope / water / bare thinning, and the include
## carrying the same constants as the GDScript.

const Shrub := preload("res://tests/unit/test_shrub_rules.gd")
const INCLUDE := "res://assets/shaders/grass_rules.gdshaderinc"
const SEED := 20240518
## A 9 ha stretch of open meadow (no hedge, road, heath, parcel or river within it).
const MEADOW_M := Rect2(1100.0, 1150.0, 300.0, 300.0)
## The river's banks, west of the river (BANK habitat, reeds).
const BANK_M := Rect2(1700.0, 100.0, 100.0, 800.0)
## (cell, kind, x, z, vertical multiplier, scale, yaw, tint) of five cells (muted_summer meadow,
## flat lattice at 1.0): a nettle on the forest edge, a flower, a bank reed, a dry stalk and a tall
## clump on the meadow.
const FIXED := [
	[
		Vector2i(495, 52),
		3,
		2.747753,
		0.290359,
		1.35,
		1.23154076337814,
		0.90732529307752,
		0.86245489120483
	],
	[
		Vector2i(638, 0),
		5,
		3.539686,
		0.001383,
		1.25238662920211,
		0.92906233072281,
		0.83370432694877,
		0.46011286973953
	],
	[
		Vector2i(2233, 0),
		4,
		12.378860,
		0.005166,
		1.5,
		1.21147401332855,
		3.53704585997458,
		0.26121813058853
	],
	[
		Vector2i(561, 988),
		2,
		3.114289,
		5.480597,
		1.3,
		0.81544345617294,
		3.08054613544299,
		0.19032967090607
	],
	[
		Vector2i(924, 0),
		1,
		5.122789,
		0.004513,
		1.5,
		1.25900161266327,
		4.03884932521167,
		0.09713989496231
	],
]

static var _rules: GrassRules


func before_all() -> void:
	MapScale.reset()
	VisualScale.apply(VisualScale.TRUE_PRESET)
	LookPreset.apply(&"muted_summer")
	_rules = make_rules(SEED, Shrub._flat)


func after_all() -> void:
	_rules = null
	LookPreset.reset()
	VisualScale.reset()
	MapScale.reset()


func after_each() -> void:
	MapScale.reset()


static func make_rules(seed_value: int, lattice: Callable) -> GrassRules:
	var area := Shrub.rect_u(Rect2(0.0, 0.0, 2000.0, 2000.0))
	var masks := VegetationMasks.build(area, Shrub.fixture_inputs(area))
	return GrassRules.new(masks, lattice, Vector2.ZERO, seed_value, Shrub.fixture_parcels())


static func clumps_in(rules: GrassRules, metres: Rect2) -> Array[Dictionary]:
	return rules.plan_rect(Shrub.rect_u(metres))


static func per_100_m2(count: int, metres: Rect2) -> float:
	return count / (metres.get_area() / 100.0)


func test_the_same_cells_give_the_same_clumps_in_any_order() -> void:
	var rect := Rect2(380.0, 900.0, 60.0, 40.0)
	var first := clumps_in(_rules, rect)
	assert_true(first.size() > 500, "%d clumps" % first.size())
	assert_eq(clumps_in(make_rules(SEED, Shrub._flat), rect), first, "a second run: the same")
	var by_cell := {}
	var chunks: Array[Rect2] = []
	for k in 4:
		chunks.append(Rect2(rect.position.x + k * 15.0, rect.position.y, 15.0, rect.size.y))
	chunks.reverse()
	for chunk in chunks:
		for clump in clumps_in(_rules, chunk):
			by_cell[clump["cell"]] = clump
	assert_eq(by_cell.size(), first.size(), "the chunks hold the same clumps")
	for clump in first:
		assert_eq(by_cell.get(clump["cell"]), clump, "same clump in %s" % clump["cell"])
	assert_true(clumps_in(make_rules(SEED + 1, Shrub._flat), rect) != first, "another seed")


func test_five_cells_are_fixed_to_literals() -> void:
	for row: Array in FIXED:
		var clump := _rules.cell_clump(row[0])
		assert_true(not clump.is_empty(), "%s holds a clump" % row[0])
		assert_eq(clump["kind"], row[1], "kind of %s" % row[0])
		var p: Vector3 = clump["position"]
		assert_true(absf(p.x - float(row[2])) < 1.0e-5 and absf(p.z - float(row[3])) < 1.0e-5)
		assert_eq(p.y, 1.0, "stands on the lattice")
		for k in 4:
			var key: String = ["height", "scale", "yaw", "tint"][k]
			assert_true(
				absf(float(clump[key]) - float(row[4 + k])) < 1.0e-6, "%s of %s" % [key, row[0]]
			)
	# The flower's species is the first group (white) of the muted summer meadow.
	var flower := _rules.cell_clump(FIXED[1][0])
	assert_eq(flower["group"], 0)
	assert_true((flower["flower_color"] as Color).is_equal_approx(Color("#e4e0cf")))
	# A cell in the forest interior holds none.
	assert_true(_rules.cell_clump(Vector2i(10, 10)).is_empty())


func test_nothing_grows_on_ribbons_bridges_buildings_or_crop_interiors_but_on_balks() -> void:
	for clump in clumps_in(_rules, Rect2(Shrub.RIVER_X_M - 60.0, 0.0, 120.0, 2000.0)):
		var p: Vector3 = clump["position"]
		assert_true(absf(p.x * MapScale.metres_per_unit - Shrub.RIVER_X_M) > Shrub.RIVER_HALF_M)
	var road := clumps_in(_rules, Rect2(450.0, Shrub.ROAD_Z_M - 30.0, 1500.0, 60.0))
	for clump in road:
		var p: Vector3 = clump["position"]
		assert_true(absf(p.z * MapScale.metres_per_unit - Shrub.ROAD_Z_M) > Shrub.ROAD_HALF_M)
	assert_true(road.size() > 1000, "grass along the road: %d" % road.size())
	var bridge := Rect2(Shrub.RIVER_X_M - 30.0, Shrub.ROAD_Z_M - 30.0, 60.0, 60.0)
	for clump in clumps_in(_rules, bridge):
		var p: Vector3 = (clump["position"] as Vector3) * MapScale.metres_per_unit
		var off_road := absf(p.z - Shrub.ROAD_Z_M) > Shrub.ROAD_HALF_M
		var off_river := absf(p.x - Shrub.RIVER_X_M) > Shrub.RIVER_HALF_M
		assert_true(off_road and off_river, "nothing on the bridge: %s" % p)
	assert_eq(clumps_in(_rules, Shrub.URBAN_M.grow(-25.0)).size(), 0, "no clump on built-up land")
	assert_eq(clumps_in(_rules, Rect2(700.0, 200.0, 300.0, 600.0)).size(), 0, "no crop interior")
	# The balk between the two parcels and the western strip carry grass.
	var balk := Rect2(Shrub.BALK_X_M.x, 150.0, Shrub.BALK_X_M.y - Shrub.BALK_X_M.x, 700.0)
	assert_true(clumps_in(_rules, balk).size() > 500, "grass on the balk")
	assert_true(clumps_in(_rules, Rect2(600.0, 150.0, 3.0, 700.0)).size() > 100, "and the edge")
	assert_eq(clumps_in(_rules, Rect2(20.0, 20.0, 330.0, 1900.0)).size(), 0, "no forest interior")


func test_density_is_100_to_300_clumps_per_100_m2_on_grass_ground() -> void:
	var meadow := per_100_m2(clumps_in(_rules, MEADOW_M).size(), MEADOW_M)
	assert_true(meadow >= 100.0 and meadow <= 300.0, "%.0f clumps per 100 m² of meadow" % meadow)
	# Every habitat that carries grass stays above the lower bound before the bare patches.
	for habitat in ShrubRules.Habitat.size():
		if habitat != ShrubRules.Habitat.NONE:
			var chance: float = GrassRules.HABITAT_CHANCE[habitat]
			assert_true(chance * 100.0 / pow(_rules.spacing * MapScale.metres_per_unit, 2) >= 100.0)
	# The same density at another map scale (metres, not units).
	MapScale.metres_per_unit = 100.0
	var other := make_rules(SEED, Shrub._flat)
	var rect := Shrub.rect_u(MEADOW_M)
	var at_100 := per_100_m2(other.plan_rect(rect).size(), MEADOW_M)
	assert_true(
		absf(at_100 - meadow) < meadow * 0.1, "%.0f vs %.0f at 100 m per unit" % [at_100, meadow]
	)


func test_no_clump_in_water_on_the_shore_or_on_steep_ground() -> void:
	var rect := MEADOW_M
	var water := make_rules(SEED, func(_x: float, _z: float) -> float: return 0.0)
	assert_eq(clumps_in(water, rect).size(), 0, "no clump at the water level")
	var shore := make_rules(
		SEED, func(_x: float, _z: float) -> float: return GrassPlanner.SHORE_BAND * 0.5
	)
	assert_eq(clumps_in(shore, rect).size(), 0, "none on the shore band")
	# Rise per unit: 0.3 is grass, 0.8 is rock (GrassPlanner.MAX_SLOPE 0.5).
	var gentle := make_rules(SEED, func(x: float, _z: float) -> float: return 1.0 + 0.3 * x)
	var steep := make_rules(SEED, func(x: float, _z: float) -> float: return 1.0 + 0.8 * x)
	assert_true(clumps_in(gentle, rect).size() > 10000, "grass on a gentle slope")
	assert_eq(clumps_in(steep, rect).size(), 0, "bare on a steep slope")
	assert_true(absf(gentle.lattice_slope(Vector2(7.0, 8.0)) - 0.3) < 1.0e-4)


func test_kinds_and_heights_follow_the_old_ranges() -> void:
	var meadow := LookPreset.meadow()
	var kinds := {}
	var lo := INF
	var hi := 0.0
	for rect: Rect2 in [
		MEADOW_M,
		Rect2(1100.0, 1550.0, 600.0, 150.0),
		Rect2(560.0, 1000.0, 600.0, 100.0),
		Rect2(380.0, 100.0, 40.0, 800.0)
	]:
		for clump in clumps_in(_rules, rect):
			var kind: int = clump["kind"]
			kinds[kind] = kinds.get(kind, 0) + 1
			var h: float = clump["height"]
			match kind:
				GrassRules.Kind.SHORT:
					assert_eq(h, 1.0)
				GrassRules.Kind.TALL:
					assert_eq(h, float(meadow["tall_height"]))
				GrassRules.Kind.DRY_STALK:
					assert_eq(h, float(meadow["dry_stalk_height"]))
				GrassRules.Kind.NETTLE:
					assert_eq(h, float(meadow["nettle_height"]))
					assert_eq(
						clump["habitat"], ShrubRules.Habitat.FOREST_EDGE, "nettle: forest edge"
					)
				GrassRules.Kind.FLOWER:
					var range_k: Vector2 = meadow["flower_height"]
					assert_true(h >= range_k.x and h <= range_k.y)
			lo = minf(lo, float(clump["scale"]))
			hi = maxf(hi, float(clump["scale"]))
	for kind in [
		GrassRules.Kind.SHORT,
		GrassRules.Kind.TALL,
		GrassRules.Kind.DRY_STALK,
		GrassRules.Kind.NETTLE,
		GrassRules.Kind.FLOWER
	]:
		assert_true(kinds.get(kind, 0) > 0, "kind %d occurs: %s" % [kind, kinds])
	assert_true(
		lo >= GrassPlanner.SCALE_MIN and hi <= GrassPlanner.SCALE_MIN + GrassPlanner.SCALE_RANGE
	)
	# Real size: 0.3 - 1.5 m tall under the `true` preset (the old near grass' range).
	var card_m := GrassField.CARD_HEIGHT * VisualScale.grass_scale() * MapScale.metres_per_unit
	assert_true(
		card_m * lo >= 0.3 and card_m * hi * float(meadow["reed_height"]) <= 1.5 * 1.35,
		"%.2f m card" % card_m
	)


func test_reeds_grow_on_banks_and_nowhere_else_with_the_old_share() -> void:
	var meadow := LookPreset.meadow()
	var reeds := 0
	var on_bank := 0
	for clump in clumps_in(_rules, Rect2(1000.0, 100.0, 800.0, 800.0)):
		var is_reed: bool = clump["kind"] == GrassRules.Kind.REED
		if clump["habitat"] == ShrubRules.Habitat.BANK:
			on_bank += 1
			reeds += 1 if is_reed else 0
		else:
			assert_false(is_reed, "no reed off the banks")
	assert_true(on_bank > 5000, "%d bank clumps" % on_bank)
	var share := float(reeds) / on_bank
	assert_true(
		absf(share - float(meadow["bank_reeds"])) < 0.2 * float(meadow["bank_reeds"]),
		"%.2f of the bank clumps are reeds" % share
	)


func test_the_flower_share_matches_the_old_planner_within_20_percent() -> void:
	var meadow := LookPreset.meadow()
	# The old planner: flower candidates per clump candidate = flower_density / PLAINS_DENSITY,
	# accepted by the cluster noise. Over a 1 ha window the expectation is the sum over its cells.
	var best := 0.0
	var window := Rect2()
	for k in 6:
		var w := Rect2(1100.0 + 50.0 * k, 1150.0 + 40.0 * (k % 3), 100.0, 100.0)
		var expected := _expected_flowers(w)
		if expected > best:
			best = expected
			window = w
	assert_true(best > 100.0, "%.0f flowers expected in a 1 ha window" % best)
	var count := 0
	for clump in clumps_in(_rules, window):
		count += 1 if clump["kind"] == GrassRules.Kind.FLOWER else 0
	assert_true(absf(count - best) <= 0.2 * best, "%d flowers, %.0f expected" % [count, best])
	# The cluster noise: the same mean share as the old two-octave noise over a large area.
	var old_sum := 0.0
	var new_sum := 0.0
	var n := 4000
	for k in n:
		var p := Vector2(fposmod(k * 0.7311, 1.0), fposmod(k * 0.4137, 1.0)) * 60.0
		old_sum += TerrainNoise.smooth(
			float(meadow["flower_from"]),
			float(meadow["flower_to"]),
			GroundNoise.flower_k(p.x, p.y, meadow)
		)
		new_sum += _rules.flower_k(p)
	var old_mean := old_sum / n
	var new_mean := new_sum / n
	assert_true(
		absf(new_mean - old_mean) <= 0.2 * old_mean,
		"cluster share %.3f vs old %.3f" % [new_mean, old_mean]
	)


func _expected_flowers(metres: Rect2) -> float:
	var total := 0.0
	var rect := Shrub.rect_u(metres)
	var cells := _rules.cells_of(rect)
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			var p := _rules.point(Vector2i(i, j))
			if not rect.has_point(p) or _rules.ground.habitat_at(p) != ShrubRules.Habitat.MEADOW:
				continue
			var bare := _rules.bare_k(p)
			if bare >= 0.5:
				continue
			var keep := 1.0 - float(LookPreset.meadow()["bare_thinning"]) * bare
			total += keep * _rules.flower_share() * _rules.flower_k(p)
	return total


func test_the_include_carries_the_grass_rules_constants() -> void:
	var text := FileAccess.get_file_as_string(INCLUDE)
	assert_true(text.contains('#include "res://assets/shaders/shrub_rules.gdshaderinc"'))
	var expected := {
		"GRASS_POINT_SALT": GrassRules.POINT_SALT,
		"GRASS_VALUE_SALT": GrassRules.VALUE_SALT,
		"GRASS_GROUP_SALT": GrassRules.GROUP_SALT,
		"GRASS_PATCH_SALT": GrassRules.PATCH_SALT,
		"GRASS_DRY_SALT": GrassRules.DRY_SALT,
		"GRASS_BARE_SALT": GrassRules.BARE_SALT,
		"GRASS_FLOWER_SALT": GrassRules.FLOWER_SALT,
		"GRASS_PART_CHANCE": GrassRules.PART_CHANCE,
		"GRASS_PART_KIND": GrassRules.PART_KIND,
		"GRASS_PART_TALL": GrassRules.PART_TALL,
		"GRASS_PART_SCALE": GrassRules.PART_SCALE,
		"GRASS_PART_YAW": GrassRules.PART_YAW,
		"GRASS_PART_TINT": GrassRules.PART_TINT,
		"GRASS_PART_REED": GrassRules.PART_REED,
		"GRASS_PART_FLOWER": GrassRules.PART_FLOWER,
		"GRASS_PART_FLOWER_HEIGHT": GrassRules.PART_FLOWER_HEIGHT,
		"GRASS_PART_FLOWER_ROLL": GrassRules.PART_FLOWER_ROLL,
		"GRASS_PART_FADE": GrassRules.PART_FADE,
		"GRASS_PART_PHASE": GrassRules.PART_PHASE,
		"GRASS_JITTER": GrassRules.JITTER,
		"GRASS_OCTAVE_FREQUENCY": GrassRules.OCTAVE_FREQUENCY,
		"GRASS_OCTAVE_AMPLITUDE": GrassRules.OCTAVE_AMPLITUDE,
		"GRASS_DIRT_FROM": TerrainSplat.DIRT_PATCH_FROM,
		"GRASS_DIRT_TO": TerrainSplat.DIRT_PATCH_TO,
		"GRASS_DRY_FROM": TerrainSplat.DRY_FROM,
		"GRASS_DRY_TO": TerrainSplat.DRY_TO,
		"GRASS_DRY_MAX": TerrainSplat.DRY_MAX,
		"GRASS_SCALE_MIN": GrassPlanner.SCALE_MIN,
		"GRASS_SCALE_RANGE": GrassPlanner.SCALE_RANGE,
		"GRASS_MAX_GROUPS": GrassRules.MAX_GROUPS,
		"GRASS_SHORT": GrassRules.Kind.SHORT,
		"GRASS_TALL": GrassRules.Kind.TALL,
		"GRASS_DRY_STALK": GrassRules.Kind.DRY_STALK,
		"GRASS_NETTLE": GrassRules.Kind.NETTLE,
		"GRASS_REED": GrassRules.Kind.REED,
		"GRASS_FLOWER": GrassRules.Kind.FLOWER,
	}
	var found := {}
	var regex := RegEx.create_from_string(
		"const\\s+\\w+\\s+(GRASS_\\w+)\\s*=\\s*([-0-9.xXa-fA-F]+)u?;"
	)
	for m in regex.search_all(text):
		found[m.get_string(1)] = m.get_string(2)
	for name: String in expected:
		assert_true(found.has(name), "%s in the include" % name)
		var value: Variant = expected[name]
		if value is int:
			assert_eq(int(found.get(name, "-1")), value, name)
		else:
			assert_eq(float(found.get(name, "-1")), value, name)
	assert_eq(found.size(), expected.size(), "every shared constant is checked")
	assert_eq(GrassRules.KIND_COUNT, GrassRules.Kind.size())
	assert_eq(GrassRules.HABITAT_CHANCE.size(), ShrubRules.Habitat.size())
