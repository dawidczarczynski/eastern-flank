extends TestCase
## Chunked scatter (TASK-072b): a chunk's scatter equals the eager plan's items of the tiles whose
## centre lies in that chunk, whatever order the chunks are planned in; tile streams are seeded per
## tile.

const Fixtures := preload("res://tests/fixtures.gd")

const SEED := 777

static var _grid: HexGrid
static var _surface: TerrainSurface
static var _eager: Dictionary


func before_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_grid = MapGenerator.generate(12, 10, rng)
	_surface = TerrainSurface.new(_grid)
	_eager = ScatterPlanner.plan(_grid, _surface, SEED)


func after_all() -> void:
	_grid = null
	_surface = null
	_eager = {}


func _chunks() -> Array[Vector2i]:
	var bounds := Rect2()
	var first := true
	for c in _grid.coords():
		var w := Hex.to_world(c, 1.0)
		var p := Vector2(w.x, w.z)
		bounds = Rect2(p, Vector2.ZERO) if first else bounds.expand(p)
		first = false
	bounds = bounds.grow(2.0)
	var result: Array[Vector2i] = []
	var lo := TreeField.chunk_of(Vector3(bounds.position.x, 0.0, bounds.position.y))
	var hi := TreeField.chunk_of(Vector3(bounds.end.x, 0.0, bounds.end.y))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			result.append(Vector2i(x, z))
	return result


func _rect(chunk: Vector2i) -> Rect2:
	return Rect2(Vector2(chunk) * TreeField.CHUNK_SIZE, Vector2.ONE * TreeField.CHUNK_SIZE)


## Sorted positions (x, y, z, scale per item) of `items`.
func _packed(items: Array) -> PackedFloat32Array:
	var rows: Array = []
	for item: Dictionary in items:
		var p: Vector3 = item["position"]
		rows.append([p.x, p.y, p.z, item["scale"]])
	rows.sort()
	var result := PackedFloat32Array()
	for row: Array in rows:
		for value: float in row:
			result.append(value)
	return result


func test_chunks_planned_in_shuffled_order_equal_the_eager_plan() -> void:
	var chunks := _chunks()
	var order := chunks.duplicate()
	var shuffle := RandomNumberGenerator.new()
	shuffle.seed = 99
	for i in range(order.size() - 1, 0, -1):
		var k := shuffle.randi_range(0, i)
		var tmp: Vector2i = order[i]
		order[i] = order[k]
		order[k] = tmp
	var planned := {}
	for chunk: Vector2i in order:
		planned[chunk] = ScatterPlanner.plan_rect(_grid, _surface, SEED, _rect(chunk))
	# The eager plan's items, by the chunk of the tile they were planned for.
	var eager_by_chunk := {}
	for c in _grid.coords():
		var w := Hex.to_world(c, 1.0)
		var chunk := TreeField.chunk_of(w)
		var tile := ScatterPlanner.plan(_grid, _surface, SEED, null, [c] as Array[Vector2i])
		var lists: Dictionary = eager_by_chunk.get_or_add(chunk, {})
		for key: String in ScatterPlanner.PLAN_KEYS:
			(lists.get_or_add(key, []) as Array).append_array(tile[key])
	var total := 0
	for key: String in ScatterPlanner.PLAN_KEYS:
		var lazy_all: Array = []
		for chunk: Vector2i in chunks:
			var lazy: Array = (planned[chunk] as Dictionary)[key]
			total += lazy.size()
			lazy_all.append_array(lazy)
			var expected: Array = (eager_by_chunk.get(chunk, {}) as Dictionary).get(key, [])
			assert_eq(_packed(lazy), _packed(expected), "%s in %s" % [key, chunk])
			var rect := _rect(chunk).grow(ScatterPlanner.TILE_REACH)
			for item: Dictionary in lazy:
				assert_true(ScatterPlanner.in_rect(item["position"], rect), "near its chunk")
		assert_eq(
			_packed(lazy_all), _packed(_eager[key]), "%s: the chunks give the eager plan" % key
		)
	assert_true(total > 1000, "a real plan: %d items" % total)


func test_a_chunk_plan_does_not_depend_on_what_was_planned_before() -> void:
	var chunk := Vector2i(1, 1)
	var alone := ScatterPlanner.plan_rect(_grid, _surface, SEED, _rect(chunk))
	for other in [Vector2i(0, 0), Vector2i(2, 1), Vector2i(1, 2)]:
		ScatterPlanner.plan_rect(_grid, _surface, SEED, _rect(other))
	assert_eq(ScatterPlanner.plan_rect(_grid, _surface, SEED, _rect(chunk)), alone)


func test_tile_streams_are_seeded_per_tile() -> void:
	var c := Vector2i(3, 2)
	var tile_only := ScatterPlanner.plan(_grid, _surface, SEED, null, [c] as Array[Vector2i])
	var with_others := ScatterPlanner.plan(
		_grid, _surface, SEED, null, [Vector2i(2, 2), c, Vector2i(4, 1)] as Array[Vector2i]
	)
	for key: String in ScatterPlanner.PLAN_KEYS:
		for item: Dictionary in tile_only[key]:
			assert_true((with_others[key] as Array).has(item), "%s item kept" % key)
	assert_true(
		(
			ScatterPlanner.tile_seed(SEED, c, 1)
			!= ScatterPlanner.tile_seed(SEED, c + Vector2i.RIGHT, 1)
		)
	)
	assert_true(ScatterPlanner.tile_seed(SEED, c, 1) != ScatterPlanner.tile_seed(SEED, c, 2))
	assert_eq(ScatterPlanner.tile_seed(SEED, c, 1), ScatterPlanner.tile_seed(SEED, c, 1))


func test_hedges_of_a_chunk_equal_the_eager_hedges_there() -> void:
	var grid := Fixtures.plains_grid(8)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FIELDS)
	var parcels := FieldParcels.bake(grid, 1.0, Rect2(-16.0, -16.0, 32.0, 32.0))
	var surface := TerrainSurface.new(grid)
	var eager := ScatterPlanner.plan_hedges(grid, surface, parcels)
	var lazy_total := 0
	for x in range(-2, 2):
		for z in range(-2, 2):
			var rect := _rect(Vector2i(x, z))
			var chunk := ScatterPlanner.plan_hedges(grid, surface, parcels, rect)
			for key: String in ["trees", "edge_shrubs"]:
				var expected: Array = (eager[key] as Array).filter(
					func(item: Dictionary) -> bool:
						return ScatterPlanner.in_rect(item["position"], rect)
				)
				assert_eq(_packed(chunk[key]), _packed(expected), "%s in %s" % [key, rect])
				lazy_total += (chunk[key] as Array).size()
	assert_eq(lazy_total, (eager["trees"] as Array).size() + (eager["edge_shrubs"] as Array).size())
	assert_true(lazy_total > 0, "the fields have hedges")
