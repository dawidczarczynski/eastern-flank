extends TestCase
## The view on a land-cover raster (TASK-108g, ADR 0028 "Sub-hex land cover; hexes are mechanics
## only"): CoverLook and the planners' raster paths read the cover, never the hex types, and maps
## without a raster keep the hex-type paths.

const SEED := 4242
const F := LandCover.Kind.FOREST
const O := LandCover.Kind.OPEN
const U := LandCover.Kind.URBAN
const A := LandCover.Kind.FIELD
## Raster cells of the synthetic covers (world units) and their half extent around the origin.
const CELL := 0.1
const HALF := 6.0
## Appearance files whose raster path must not read the hex type (`_cover` functions), and files
## that are raster-only.
const PATH_FILES: Array[String] = [
	"res://src/presentation/terrain_splat.gd",
	"res://src/presentation/scatter_planner.gd",
	"res://src/presentation/grass_planner.gd",
	"res://src/presentation/field_parcels.gd",
]
const RASTER_FILES: Array[String] = [
	"res://src/presentation/cover_look.gd",
	"res://src/presentation/land_cover_forest_mask_source.gd",
]


## A square raster around the origin: `west` where x < 0, `east` elsewhere.
func _split(west: int, east: int) -> CoverLook:
	var n := roundi(2.0 * HALF / CELL)
	var cells := PackedByteArray()
	cells.resize(n * n)
	for j in n:
		for i in n:
			var x := -HALF + (i + 0.5) * CELL
			cells[j * n + i] = west if x < 0.0 else east
	var origin := Vector2(-HALF + 0.5 * CELL, -HALF + 0.5 * CELL)
	return CoverLook.make(LandCover.from_cells(cells, n, n, origin, CELL))


## Plains tiles within `radius` of the origin: the hex types say there is no forest anywhere.
func _plains(radius: int = 2) -> HexGrid:
	var grid := HexGrid.new()
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			if absi(q + r) <= radius:
				grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	return grid


func test_make_is_null_for_the_fallback_cover() -> void:
	assert_eq(CoverLook.make(null), null)
	assert_eq(CoverLook.make(LandCover.from_grid(_plains())), null, "no raster: hex-type paths")
	assert_true(_split(F, O) != null)


func test_forest_edge_is_noisy_but_interiors_are_untouched() -> void:
	var look := _split(F, O)
	assert_true(look.is_forest(-1.0, 0.3), "deep inside")
	assert_false(look.is_forest(1.0, 0.3), "far outside")
	assert_eq(look.terrain_at(-1.0, 0.0), Terrain.Type.FOREST)
	assert_eq(look.terrain_at(1.0, 0.0), Terrain.Type.PLAINS)
	# Along the edge the outline wanders by up to half a cell, not more, and not on a straight line.
	var crossings := {}
	for k in 200:
		var z := -3.0 + k * 0.03
		var edge := -CELL
		while edge < CELL and look.is_forest(edge, z):
			edge += 0.005
		assert_true(edge > -CELL and edge < CELL, "edge near x = 0 at z = %f" % z)
		crossings[snappedf(edge, 0.01)] = true
	assert_true(crossings.size() > 3, "the outline is not a straight line")
	var soft := look.forest_k(-1.0, 0.0)
	assert_true(is_equal_approx(soft, 1.0) and is_zero_approx(look.forest_k(1.0, 0.0)))


func test_a_forest_covering_half_a_hex_gets_trees_only_on_that_half() -> void:
	# The east half is a village: no tree stands there at all.
	var grid := _plains()
	var surface := TerrainSurface.new(grid)
	var look := _split(F, U)
	var plan := ScatterPlanner.plan(grid, surface, SEED, null, [Vector2i.ZERO], look)
	var trees: Array = plan["trees"]
	assert_true(trees.size() >= 8, "the forest half is planted (%d trees)" % trees.size())
	for tree: Dictionary in trees:
		var p: Vector3 = tree["position"]
		assert_true(p.x < CELL, "tree at x = %f stands on the forest part" % p.x)
	for key: String in ["bushes", "ground_cover"]:
		for item: Dictionary in plan[key]:
			var p: Vector3 = item["position"]
			assert_true(p.x < CELL or not look.is_forest(p.x, p.z), key)
	# The hex type is not read: a forest hex under the same raster plans the same.
	var forest_grid := HexGrid.new()
	for c in grid.coords():
		forest_grid.set_terrain(c, Terrain.Type.FOREST)
	var same := ScatterPlanner.plan(
		forest_grid, TerrainSurface.new(forest_grid), SEED, null, [Vector2i.ZERO], look
	)
	assert_eq((same["trees"] as Array).size(), trees.size())


func test_open_half_gets_far_fewer_trees_and_edge_plants_follow_the_outline() -> void:
	var grid := _plains()
	var surface := TerrainSurface.new(grid)
	var look := _split(F, O)
	var west := 0
	var east := 0
	for c in grid.coords():
		var plan := ScatterPlanner.plan(grid, surface, SEED, null, [c], look)
		for tree: Dictionary in plan["trees"]:
			var p: Vector3 = tree["position"]
			if p.x < 0.0:
				west += 1
			else:
				east += 1
		for shrub: Dictionary in plan["edge_shrubs"]:
			var p: Vector3 = shrub["position"]
			assert_true(
				absf(p.x) < ScatterPlanner.COVER_EDGE_REACH + CELL, "edge shrub at the edge"
			)
	assert_true(west > 5 * maxi(east, 1), "forest %d vs open %d trees" % [west, east])


func test_scatter_cover_plan_is_deterministic() -> void:
	var grid := _plains()
	var surface := TerrainSurface.new(grid)
	var look := _split(F, O)
	var a := ScatterPlanner.plan(grid, surface, SEED, null, [], look)
	var b := ScatterPlanner.plan(grid, surface, SEED, null, [], look)
	assert_eq(var_to_str(a), var_to_str(b))


func test_grass_follows_the_cover_not_the_hex() -> void:
	var grid := _plains(3)
	var surface := TerrainSurface.new(grid)
	var look := _split(F, O)
	var west := 0
	var east := 0
	for chunk in GrassPlanner.chunks_covering(Rect2(-2.0, -2.0, 4.0, 4.0)):
		for g: Dictionary in GrassPlanner.plan_chunk(
			chunk, grid, surface, SEED, 1.0, {}, null, look
		):
			var p: Vector3 = g["position"]
			if absf(p.x) > 0.3 and absf(p.z) < 2.0 and absf(p.x) < 2.0:
				if p.x < 0.0:
					west += 1
				else:
					east += 1
	# Forest floor grass is FOREST_DENSITY / PLAINS_DENSITY as dense as the meadow.
	var ratio := float(west) / maxf(east, 1.0)
	var expected := GrassPlanner.FOREST_DENSITY / GrassPlanner.PLAINS_DENSITY
	assert_true(east > 100, "meadow grass planted (%d)" % east)
	assert_true(absf(ratio - expected) < 0.15, "forest / meadow grass %f ~ %f" % [ratio, expected])


func test_farmland_parcels_end_where_the_field_cover_ends() -> void:
	var look := _split(A, O)
	var grid := _plains()
	var rect := Rect2(-HALF, -HALF, 2.0 * HALF, 2.0 * HALF)
	var parcels := FieldParcels.bake(
		grid, 1.0, rect, FieldParcels.DEFAULT_METRES_PER_PIXEL, {}, look
	)
	assert_true(parcels != null)
	var crops := 0
	var samples := 0
	for k in 40:
		var z := -3.0 + k * 0.15
		assert_eq(parcels.kind_at(0.5, z), FieldParcels.Kind.NONE, "no crops on open cover")
		assert_eq(parcels.kind_at(3.0, z), FieldParcels.Kind.NONE)
		samples += 1
		if parcels.kind_at(-2.0, z) != FieldParcels.Kind.NONE:
			crops += 1
	assert_true(crops > samples * 0.8, "the field cover is farmland (%d / %d)" % [crops, samples])
	assert_eq(FieldParcels.bake(grid, 1.0, rect, 5.0, {}, _split(O, O)), null, "no field cover")


func test_forest_mask_follows_the_cover() -> void:
	var look := _split(F, O)
	var grid := _plains()
	var area := Rect2(-2.0, -2.0, 4.0, 4.0)
	var masks := LandCoverForestMaskSource.new(look, 0.0).build(grid, area, 16.0)
	var forest: Image = masks["forest"]
	assert_eq(forest.get_size(), Vector2i(64, 64))
	assert_true(forest.get_pixel(8, 20).r > 0.5, "west: forest")
	assert_true(forest.get_pixel(56, 20).r < 0.5, "east: open")
	# The cut runs along x = 0 (texel 32) give or take the noise, across the whole height.
	for pz in range(0, 64, 4):
		assert_true(forest.get_pixel(28, pz).r > 0.5 and forest.get_pixel(36, pz).r < 0.5)


func test_backdrop_continues_the_cover_inside_the_raster() -> void:
	var look := _split(F, O)
	var types := BackdropTypes.new(_plains(), 1.0, Vector2.ZERO, Vector2.ONE, look)
	assert_eq(types.shares_at(-2.0, 1.0, 0, 0), {Terrain.Type.FOREST: 1.0})
	assert_eq(types.shares_at(2.0, 1.0, 0, 0), {Terrain.Type.PLAINS: 1.0})
	assert_true(is_equal_approx(types.forest_at(-2.0, 1.0, 0, 0), 1.0))
	assert_eq(types.ring_type(Vector2(-2.0, 1.0), Vector2.ZERO), Terrain.Type.FOREST)
	# Beyond the raster: the border tiles, as without a raster.
	var plain := BackdropTypes.new(_plains(), 1.0, Vector2.ZERO, Vector2.ONE)
	assert_eq(types.shares_at(50.0, 50.0, 0, 0), plain.border_shares(0, 0))


## Grep check: the raster path of the appearance code never reads the hex type.
func test_raster_paths_never_read_the_hex_type() -> void:
	for path in RASTER_FILES:
		assert_false(_source(path).contains("get_terrain"), path)
	assert_false(_source(PATH_FILES[0]).contains("get_terrain"), "TerrainSplat reads no grid")
	var checked := 0
	for path in PATH_FILES:
		for body in _cover_functions(_source(path)):
			checked += 1
			assert_false(body.contains("get_terrain"), "%s: %s" % [path, body.get_slice("\n", 0)])
	assert_true(checked >= 8, "the raster paths were found (%d functions)" % checked)


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The bodies of the functions whose name contains "_cover" (up to the next top-level line).
func _cover_functions(source: String) -> Array[String]:
	var result: Array[String] = []
	var lines := source.split("\n")
	var i := 0
	while i < lines.size():
		var line := lines[i]
		if line.begins_with("static func ") or line.begins_with("func "):
			var head := line.get_slice("(", 0)
			var name := head.substr(head.rfind(" ") + 1)
			if name.contains("_cover"):
				var body := line
				i += 1
				while (
					i < lines.size()
					and (lines[i] == "" or lines[i].begins_with("\t") or lines[i].begins_with(")"))
				):
					body += "\n" + lines[i]
					i += 1
				result.append(body)
				continue
		i += 1
	return result


## The terrain shader's twin of CoverLook.has_kind (the field outline) uses the same constants.
func test_terrain_shader_matches_the_cover_look_constants() -> void:
	var shader := _source("res://assets/shaders/terrain.gdshader")
	var expected := {
		"COVER_FIELD": str(LandCover.Kind.FIELD),
		"COVER_NOISE_CELLS": str(CoverLook.NOISE_CELLS),
		"COVER_NOISE_FINE_CELLS": str(CoverLook.NOISE_FINE_CELLS),
		"COVER_NOISE_AMPLITUDE": str(CoverLook.NOISE_AMPLITUDE),
		"COVER_NOISE_FINE_AMPLITUDE": str(CoverLook.NOISE_FINE_AMPLITUDE),
		"COVER_NOISE_SALT": "%du" % CoverLook.NOISE_SALT,
		"COVER_FINE_SALT": "%du" % CoverLook.FINE_SALT,
	}
	for name: String in expected:
		assert_true(shader.contains("%s = %s;" % [name, expected[name]]), name)


func test_beyond_the_raster_is_open_land() -> void:
	var look := _split(F, F)
	assert_true(look.is_forest(0.0, 0.0))
	assert_false(look.is_forest(-50.0, 0.0), "no stretched edge cells")
	assert_eq(look.terrain_at(0.0, 50.0), Terrain.Type.PLAINS)
	assert_true(is_zero_approx(look.forest_k(50.0, 50.0)))
