extends TestCase
## WaterValidator (TASK-223a, ADR 0034 decision 5): each rule fires exactly once on a hand-made
## river that breaks only that rule, and a clean river has no violation.

## World units of 10 m at the default map scale: the tests lay out their rivers in steps of 10 m
## ("tens") so the sums stay easy without changing MapScale (other tests' caches read it).
var _u := MapScale.to_units(10.0)


func _at(x: float, z: float) -> Vector2:
	return Vector2(x * _u, z * _u)


## A ground Callable(x, z) in world units from one written in tens.
func _in_tens(ground: Callable) -> Callable:
	return func(x: float, z: float) -> float: return ground.call(x / _u, z / _u)


## A straight river along +x, one vertex per ten metres, `count` vertices,
## 10 m wide, surface 5 m falling 0.1 m per vertex (1 % gradient), bed 2 m below the surface,
## banks 1 m above it.
func _clean_sample(count := 8) -> WaterSample:
	var sample := WaterSample.new()
	var reach := WaterSample.Reach.new()
	for i in count:
		reach.points.append(_at(float(i), 0.0))
		reach.width_m.append(10.0)
		reach.level.append(5.0 - 0.1 * float(i))
	sample.reaches.append(reach)
	sample.ground = _in_tens(_ground)
	return sample


## Bed 2 m under the surface inside the 10 m water (|z| < 0.5 tens), 1 m above it outside.
func _ground(x: float, z: float) -> float:
	var level := 5.0 - 0.1 * clampf(x, 0.0, 7.0)
	return level - 2.0 if absf(z) < 0.5 else level + 1.0


func _rules(violations: Array[Dictionary]) -> Array:
	var rules := []
	for v in violations:
		rules.append(v["rule"])
	return rules


func test_clean_river_has_no_violation() -> void:
	assert_eq(WaterValidator.check(_clean_sample()), [] as Array[Dictionary])


func test_surface_rises() -> void:
	var sample := _clean_sample()
	sample.reaches[0].level[4] = sample.reaches[0].level[3] + 0.3
	var found := WaterValidator.check(sample)
	assert_eq(_rules(found).count(&"surface_rises"), 1)
	assert_eq(found[0]["position"], _at(4.0, 0.0))


func test_steep_water() -> void:
	var sample := _clean_sample()
	# 0.4 m over 10 m = 4 %, only at the last step (the rest stays 1 %).
	sample.reaches[0].level[7] = sample.reaches[0].level[6] - 0.4
	assert_eq(_rules(WaterValidator.check(sample)).count(&"steep_water"), 1)


func test_junction_step() -> void:
	var sample := _clean_sample()
	var tributary := WaterSample.Reach.new()
	for i in 4:
		tributary.points.append(_at(4.0, 4.0 - float(i) * 1.3))
		tributary.width_m.append(10.0)
		tributary.level.append(6.0 - 0.1 * float(i))
	# ends on the main river at (4, 0.1): main level there is 4.6; tributary ends 0.4 higher
	tributary.points[3] = _at(4.0, 0.0)
	tributary.level[3] = 5.0
	sample.reaches.append(tributary)
	var rules := _rules(WaterValidator.check(sample))
	assert_eq(rules.count(&"junction_step"), 1)


func test_lake_step() -> void:
	var sample := _clean_sample()
	sample.lake_at = func(p: Vector2) -> float: return 0.0 if p.x / _u > 7.5 else NAN
	# river ends at 5.0 - 0.7 = 4.3 m, the lake is at 0.0 m
	var found := WaterValidator.check(sample)
	assert_eq(_rules(found).count(&"lake_step"), 1)
	assert_eq(found[0]["position"], _at(7.0, 0.0))


func test_dry_bed() -> void:
	var sample := _clean_sample()
	var ground := _ground  # in tens
	sample.ground = _in_tens(
		func(x: float, z: float) -> float:
			return 6.0 if absf(x - 3.0) < 0.01 and absf(z) < 0.01 else ground.call(x, z)
	)
	var rules := _rules(WaterValidator.check(sample))
	assert_eq(rules.count(&"dry_bed"), 1)
	assert_eq(rules.count(&"shallow"), 0)


func test_flooded_bank() -> void:
	var sample := _clean_sample()
	var ground := _ground  # in tens
	# the bank beside vertex 5 (z = 0.6 units, just outside the water) lies under the surface
	sample.ground = _in_tens(
		func(x: float, z: float) -> float:
			return 1.0 if absf(x - 5.0) < 0.01 and z > 0.5 and z < 0.8 else ground.call(x, z)
	)
	assert_eq(_rules(WaterValidator.check(sample)).count(&"flooded_bank"), 1)


func test_shallow() -> void:
	var sample := _clean_sample()
	var ground := _ground  # in tens
	# bed only 0.2 m under the surface at vertex 2
	sample.ground = _in_tens(
		func(x: float, z: float) -> float:
			if absf(x - 2.0) < 0.01 and absf(z) < 0.01:
				return 5.0 - 0.1 * 2.0 - 0.2
			return ground.call(x, z)
	)
	var rules := _rules(WaterValidator.check(sample))
	assert_eq(rules.count(&"shallow"), 1)
	assert_eq(rules.count(&"dry_bed"), 0)


func test_narrow_river_may_be_shallow() -> void:
	var sample := _clean_sample()
	for i in sample.reaches[0].width_m.size():
		sample.reaches[0].width_m[i] = 4.0
	sample.ground = func(_x: float, _z: float) -> float: return -100.0
	var rules := _rules(WaterValidator.check(sample))
	assert_eq(rules.count(&"shallow"), 0)


func test_width_jump() -> void:
	var sample := _clean_sample(12)
	sample.reaches[0].width_m[6] = 20.0  # x2 within 10 m of its neighbours
	sample.ground = func(_x: float, _z: float) -> float: return -100.0
	var rules := _rules(WaterValidator.check(sample))
	assert_true(rules.has(&"width_jump"))
	assert_eq(rules.count(&"width_jump"), 1, "one violation per jump, not per vertex after it")


func test_width_jump_ignored_at_a_junction() -> void:
	var sample := _clean_sample(12)
	sample.reaches[0].width_m[6] = 20.0
	sample.ground = func(_x: float, _z: float) -> float: return -100.0
	var tributary := WaterSample.Reach.new()
	tributary.points = PackedVector2Array([_at(6.5, 5.0), _at(6.5, 0.0)])
	tributary.width_m = PackedFloat32Array([10.0, 10.0])
	tributary.level = PackedFloat32Array([4.35, 4.35])
	sample.reaches.append(tributary)
	assert_eq(_rules(WaterValidator.check(sample)).count(&"width_jump"), 0)


func test_bridge_short() -> void:
	var sample := _clean_sample()
	sample.bridges.append({"position": _at(3.0, 0.0), "span_m": 8.0})  # water is 10 m wide
	sample.bridges.append({"position": _at(5.0, 0.0), "span_m": 18.0})
	var found := WaterValidator.check(sample)
	assert_eq(_rules(found).count(&"bridge_short"), 1)
	assert_eq(found[0]["position"], _at(3.0, 0.0))
	assert_eq(found[0]["value"], 8.0)
	assert_eq(found[0]["limit"], 10.0)


func test_check_is_deterministic() -> void:
	var sample := _clean_sample()
	sample.reaches[0].level[4] = 9.0
	assert_eq(WaterValidator.check(sample), WaterValidator.check(sample))


func test_adapter_of_a_grid_without_rivers_is_empty_and_clean() -> void:
	var grid := HexGrid.new()
	var surface := TerrainSurface.new(grid)
	var sample := WaterSampleAdapter.build(grid, surface)
	assert_eq(sample.reaches.size(), 0)
	assert_eq(WaterValidator.check(sample), [] as Array[Dictionary])


func test_overlay_describes_a_violation() -> void:
	var text := WaterErrorOverlay.describe(
		{"rule": &"dry_bed", "position": Vector2.ZERO, "value": 2.165, "limit": 0.05}
	)
	assert_eq(text, "dry_bed  2.17 / 0.05")


func test_bank_probe_in_a_tributary_is_not_a_flooded_bank() -> void:
	var sample := _clean_sample()
	var ground := _ground  # in tens
	# the tributary's water beside vertex 4 lies under the main surface – it is water, not a bank
	sample.ground = _in_tens(
		func(x: float, z: float) -> float:
			return 1.0 if absf(x - 4.0) < 0.3 and z > 0.5 else ground.call(x, z)
	)
	var tributary := WaterSample.Reach.new()
	tributary.points = PackedVector2Array([_at(4.0, 5.0), _at(4.0, 0.0)])
	tributary.width_m = PackedFloat32Array([10.0, 10.0])
	tributary.level = PackedFloat32Array([4.6, 4.6])
	sample.reaches.append(tributary)
	var found := WaterValidator.check(sample)
	for v in found:
		if v["rule"] == &"flooded_bank":
			assert_true(
				absf((v["position"] as Vector2).x / _u - 4.0) > 0.01,
				"probe in the tributary flagged"
			)
