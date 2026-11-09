extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

const SEED := 77

static var _grid: HexGrid
static var _parcels: ParcelMap


func before_all() -> void:
	_grid = Fixtures.plains_grid(10)
	for c in _grid.coords():
		_grid.set_terrain(c, Terrain.Type.FIELDS)
	_parcels = FieldParcels.bake(_grid, 1.0, Rect2(-12.0, -12.0, 24.0, 24.0))


func after_all() -> void:
	_grid = null
	_parcels = null


func after_each() -> void:
	MapScale.reset()
	LookPreset.reset()


func _positions(list: Array) -> Dictionary:
	var result := {}
	for item: Dictionary in list:
		result[item["position"]] = true
	return result


func test_nothing_stands_on_parcels_and_other_positions_are_unchanged() -> void:
	var surface := TerrainSurface.new(_grid)
	var plain := ScatterPlanner.plan(_grid, surface, SEED)
	var filtered := ScatterPlanner.plan(_grid, surface, SEED, _parcels)
	var removed := 0
	for key: String in plain:
		var after := _positions(filtered[key])
		for item: Dictionary in plain[key]:
			var p: Vector3 = item["position"]
			if _parcels.blocks_standing(p.x, p.z):
				removed += 1
				assert_false(after.has(p), "%s on a parcel was kept" % key)
			else:
				assert_true(after.has(p), "%s off the parcels was removed" % key)
		for item: Dictionary in filtered[key]:
			var p: Vector3 = item["position"]
			assert_false(_parcels.blocks_standing(p.x, p.z))
	assert_true(removed > 100, "the field map has scatter to remove: %d" % removed)


func test_without_parcels_the_plan_is_unchanged() -> void:
	var surface := TerrainSurface.new(_grid)
	assert_eq(
		ScatterPlanner.plan(_grid, surface, SEED), ScatterPlanner.plan(_grid, surface, SEED, null)
	)


func test_grass_and_flowers_stay_off_crop_parcels() -> void:
	var surface := TerrainSurface.new(_grid)
	var counted := 0
	for cx in range(-4, 4):
		for cz in range(-4, 4):
			var chunk := Vector2i(cx, cz)
			for g: Dictionary in GrassPlanner.plan_chunk(
				chunk, _grid, surface, SEED, 1.0, {}, _parcels
			):
				var p: Vector3 = g["position"]
				assert_false(_parcels.blocks_tall_grass(p.x, p.z), "grass on a crop parcel")
				counted += 1
			for f: Dictionary in GrassPlanner.plan_flowers(
				chunk, _grid, surface, SEED, 1.0, {}, _parcels
			):
				var p: Vector3 = f["position"]
				assert_false(_parcels.blocks_tall_grass(p.x, p.z), "flower on a crop parcel")
	assert_true(counted > 0)


func test_hedges_sit_on_balks_and_are_deterministic() -> void:
	var surface := TerrainSurface.new(_grid)
	var hedges := ScatterPlanner.plan_hedges(_grid, surface, _parcels)
	var total := 0
	for key: String in hedges:
		for item: Dictionary in hedges[key]:
			var p: Vector3 = item["position"]
			assert_eq(_parcels.kind_at(p.x, p.z), FieldParcels.Kind.BALK)
			total += 1
	assert_true(total > 20, "some balks carry a copse: %d" % total)
	assert_eq(hedges, ScatterPlanner.plan_hedges(_grid, surface, _parcels))
	assert_eq(ScatterPlanner.plan_hedges(_grid, surface, null)["trees"], [])
