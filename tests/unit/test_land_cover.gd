extends TestCase
## LandCover (TASK-108g, ADR 0028 "Sub-hex land cover; hexes are mechanics only"): the sub-hex
## land-cover raster the view reads instead of the hex types, its fallback for maps without a
## raster, and where it comes from (imported map, tactical layer cut).

const SAMPLE_PATH := "res://tests/fixtures/maps/sample_map.tres"
const F := LandCover.Kind.FOREST
const A := LandCover.Kind.FIELD
const W := LandCover.Kind.WATER
const O := LandCover.Kind.OPEN


## 4 x 3 cells of 0.5 units, cell (0, 0) centred at (10, 20):
## row 0: F F A A / row 1: F F A W / row 2: O O W W.
func _small() -> LandCover:
	var cells := PackedByteArray([F, F, A, A, F, F, A, W, O, O, W, W])
	return LandCover.from_cells(cells, 4, 3, Vector2(10.0, 20.0), 0.5)


func test_class_at_reads_the_cell_under_the_point() -> void:
	var cover := _small()
	assert_true(cover.has_raster())
	assert_eq(cover.class_at(10.0, 20.0), F)
	assert_eq(cover.class_at(11.0, 20.0), A, "cell (2, 0)")
	assert_eq(cover.class_at(11.26, 20.74), W, "cell (3, 1), just inside")
	assert_eq(cover.class_at(10.26, 21.0), O, "cell (1, 2)")
	assert_eq(cover.class_at(-50.0, 20.0), F, "off the raster: the nearest edge cell")
	assert_eq(cover.class_at(50.0, 50.0), W)
	assert_eq(cover.world_rect(), Rect2(9.75, 19.75, 2.0, 1.5))


func test_share_in_counts_the_cells_whose_centre_lies_in_the_rect() -> void:
	var cover := _small()
	var all := Rect2(9.75, 19.75, 2.0, 1.5)
	assert_true(is_equal_approx(cover.share_in(all, F), 4.0 / 12.0))
	assert_true(is_equal_approx(cover.share_in(all, W), 3.0 / 12.0))
	var shares := cover.shares_in(all)
	var total := 0.0
	for s in shares:
		total += s
	assert_true(is_equal_approx(total, 1.0))
	# The right half of the top two rows: cells (2..3, 0..1) = A A A W.
	assert_true(is_equal_approx(cover.share_in(Rect2(10.8, 19.8, 0.8, 0.8), A), 0.75))
	# A rect between cell centres reads the cell under its centre.
	assert_eq(cover.share_in(Rect2(10.05, 20.05, 0.1, 0.1), F), 1.0)


func test_soft_weight_is_bilinear_between_cell_centres() -> void:
	var cover := _small()
	assert_eq(cover.weight(F, 10.0, 20.0), 1.0, "on a cell centre")
	assert_true(is_equal_approx(cover.weight(F, 10.75, 20.0), 0.5), "halfway to the field")
	assert_true(is_equal_approx(cover.weight(A, 10.75, 20.0), 0.5))
	var weights := cover.weights_at(10.6, 20.3)
	var total := 0.0
	for w in weights:
		total += w
	assert_true(is_equal_approx(total, 1.0))


## A forest raster whose edge runs east-west across the border of hexes (0, 0) and (1, 0)
## (x = sqrt(3) / 2): the weight is the same on both sides of the hex border and changes only
## gradually, never with a step.
func test_soft_weight_is_continuous_across_a_hex_border_of_one_class() -> void:
	var size := 0.1
	var columns := 40
	var rows := 20
	var cells := PackedByteArray()
	for j in rows:
		for i in columns:
			cells.append(F if j < 10 else A)
	var cover := LandCover.from_cells(cells, columns, rows, Vector2(-1.0, -1.0), size)
	var border := Hex.SQRT3 * 0.5
	assert_true(
		(
			Hex.from_world(Vector3(border - 0.01, 0, 0), 1.0)
			!= Hex.from_world(Vector3(border + 0.01, 0, 0), 1.0)
		)
	)
	for z: float in [-0.5, -0.05, -0.02, 0.0, 0.3]:
		var left := cover.weight(F, border - 0.001, z)
		var right := cover.weight(F, border + 0.001, z)
		assert_true(absf(left - right) < 1e-4, "z %s: %s vs %s" % [z, left, right])
	var previous := cover.weight(F, border, -0.5)
	var z := -0.5
	while z < 0.5:
		z += 0.01
		var w := cover.weight(F, border, z)
		assert_true(absf(w - previous) <= 0.01 / size + 1e-4, "no step at z %s" % z)
		previous = w
	assert_eq(cover.weight(F, border, -0.5), 1.0)
	assert_eq(cover.weight(F, border, 0.5), 0.0)


func _grid() -> HexGrid:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i(0, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.WATER)
	grid.set_terrain(Vector2i(0, 1), Terrain.Type.HILLS)
	grid.set_terrain(Vector2i(1, 1), Terrain.Type.FIELDS)
	return grid


func test_the_fallback_expands_the_hex_types() -> void:
	var grid := _grid()
	var cover := LandCover.from_grid(grid)
	assert_false(cover.has_raster())
	assert_eq(cover.cells().size(), 0)
	for c in grid.coords():
		var p := Hex.to_world(c, TerrainField.HEX_SIZE)
		var kind := LandCover.kind_of_terrain(grid.get_terrain(c))
		assert_eq(cover.class_at(p.x + 0.2, p.z - 0.2), kind, str(c))
		assert_eq(cover.weight(kind, p.x, p.z), 1.0, "hard inside the hex")
	assert_eq(cover.class_at(0.0, 0.0), F)
	assert_eq(LandCover.kind_of_terrain(Terrain.Type.HILLS), O)
	assert_eq(cover.class_at(50.0, 50.0), O, "off the grid")
	var border := Hex.SQRT3 * 0.5
	assert_eq(cover.weight(F, border - 0.01, 0.0), 1.0)
	assert_eq(cover.weight(F, border + 0.01, 0.0), 0.0, "the fallback keeps the hex edge")
	var share := cover.share_in(Rect2(-0.5, -0.5, 1.0, 1.0), F)
	assert_eq(share, 1.0, "inside the forest hex")


func test_maps_without_a_raster_get_the_fallback() -> void:
	var grid := _grid()
	var generated := LandCover.for_map(BattleSetup.MAP_GENERATED_RIVER, Rect2i(), grid)
	assert_false(generated.has_raster())
	assert_eq(generated.class_at(0.0, 0.0), F)
	assert_false(LandCover.for_map(&"no_such_map", Rect2i(), grid).has_raster())
	var layer := TacticalLayer.from_grid(grid, 2, 2)
	assert_false(layer.has_land_cover(), "a layer without a raster (old data)")
	assert_true(layer.region_land_cover(Rect2i(0, 0, 2, 2)) == null)
	assert_true(layer.region_grid(Rect2i(0, 0, 2, 2)) != null, "and its hexes still load")


func test_the_imported_sample_map_has_a_raster_aligned_with_its_hexes() -> void:
	var map := load(SAMPLE_PATH) as ImportedMap
	var cover := LandCover.from_imported(map)
	assert_true(cover != null and cover.has_raster())
	assert_true(is_equal_approx(cover.cell_size, 16.0 / map.metres_per_world_unit()))
	var grid := map.to_grid()
	var rect := cover.world_rect()
	for c in grid.coords():
		var p := Hex.to_world(c, TerrainField.HEX_SIZE)
		assert_true(rect.has_point(Vector2(p.x, p.z)), "the raster covers hex %s" % c)
	# Forest hexes are mostly forest cells, the others mostly not (alignment of the frames).
	var agree := 0
	for c in grid.coords():
		var p := Hex.to_world(c, TerrainField.HEX_SIZE)
		var forest := cover.share_in(Rect2(p.x - 0.6, p.z - 0.6, 1.2, 1.2), F)
		if (forest > 0.5) == (grid.get_terrain(c) == Terrain.Type.FOREST):
			agree += 1
	assert_true(agree >= grid.coords().size() - 3, "%d of %d" % [agree, grid.coords().size()])
	var setup_cover := LandCover.for_map(&"sample_map", Rect2i(), grid)
	assert_false(setup_cover.has_raster(), "only data/maps/ ids are looked up")


## Value of global raster cell (i, j) in the in-memory layer below.
func _cell_value(i: int, j: int) -> int:
	return (i * 3 + j * 7) % LandCover.KIND_COUNT


## An 8 x 8 hex layer (250 m, tile (0, 0) at E 0 N 0) in 4 x 4 chunks with a 50 m raster whose
## four windows split it at column 22 and row 19.
func _layer_with_raster() -> TacticalLayer:
	var grid := HexGrid.new()
	for r in 8:
		for c in 8:
			grid.set_terrain(MapGenerator.offset_to_axial(c, r), Terrain.Type.PLAINS)
	var layer := TacticalLayer.from_grid(grid, 8, 8, 250.0, 0.0, 0.0, 4)
	layer.land_cover_cell_m = 50.0
	layer.land_cover_width = 45
	layer.land_cover_height = 38
	layer.land_cover_origin_easting = -150.0
	layer.land_cover_origin_northing = 150.0
	var columns := [0, 22, 45]
	var rows := [0, 19, 38]
	for cy in 2:
		for cx in 2:
			var chunk := TacticalChunk.new()
			chunk.cover_column = columns[cx]
			chunk.cover_row = rows[cy]
			chunk.cover_width = columns[cx + 1] - columns[cx]
			chunk.cover_height = rows[cy + 1] - rows[cy]
			var cells := PackedByteArray()
			for j in range(rows[cy], rows[cy + 1]):
				for i in range(columns[cx], columns[cx + 1]):
					cells.append(_cell_value(i, j))
			chunk.cover = cells.compress(FileAccess.COMPRESSION_DEFLATE)
			layer.add_cover_chunk(Vector2i(cx, cy), chunk)
	return layer


func test_a_layer_cut_gathers_its_cells_from_the_chunk_windows() -> void:
	var layer := _layer_with_raster()
	assert_true(layer.has_land_cover())
	var region := Rect2i(2, 2, 4, 4)
	var cover := layer.region_land_cover(region)
	assert_true(cover != null and cover.has_raster())
	assert_true(is_equal_approx(cover.cell_size, 50.0 / layer.metres_per_world_unit()))
	var m := layer.metres_per_world_unit()
	# Local tile (0, 0) of the cut is layer tile (2, 2): E 500, N -433.
	var corner := layer.offset_to_projected(region.position)
	var checked := 0
	for r in region.size.y:
		for c in region.size.x:
			var local := Hex.to_world(MapGenerator.offset_to_axial(c, r), TerrainField.HEX_SIZE)
			for offset: Vector2 in [Vector2.ZERO, Vector2(0.37, -0.21), Vector2(-0.6, 0.45)]:
				var x := local.x + offset.x
				var z := local.z + offset.y
				var i := roundi((corner.x + x * m + 150.0) / 50.0)
				var j := roundi((150.0 - (corner.y - z * m)) / 50.0)
				assert_eq(cover.class_at(x, z), _cell_value(i, j), "cell %d, %d" % [i, j])
				checked += 1
	assert_eq(checked, 48)
	# The cut spans all four windows: cells on both sides of column 22 and row 19.
	var rect := cover.world_rect()
	var west := roundi((corner.x + rect.position.x * m + 150.0) / 50.0)
	var east := roundi((corner.x + rect.end.x * m + 150.0) / 50.0)
	assert_true(west < 22 and east > 22, "%d .. %d" % [west, east])
	var margin := layer.region_land_cover(region, 2.0)
	assert_true(margin.world_rect().encloses(rect), "a margin widens the raster")
	assert_true(layer.region_land_cover(Rect2i(0, 1, 2, 2)) == null, "a bad region")


## Share of the hexes of `grid` whose forest / not-forest type agrees with the raster around them.
func _forest_agreement(cover: LandCover, grid: HexGrid) -> float:
	var agree := 0
	for c in grid.coords():
		var p := Hex.to_world(c, TerrainField.HEX_SIZE)
		var forest := cover.share_in(Rect2(p.x - 0.6, p.z - 0.6, 1.2, 1.2), F)
		if (forest > 0.5) == (grid.get_terrain(c) == Terrain.Type.FOREST):
			agree += 1
	return float(agree) / grid.coords().size()


func test_the_shipped_suwalki_maps_have_rasters_aligned_with_their_hexes() -> void:
	var map := ImportedMap.find(&"suwalki")
	var grid := map.to_grid()
	var cover := LandCover.for_map(&"suwalki", Rect2i(), grid)
	assert_true(cover.has_raster(), "the imported Suwalki map")
	var agreement := _forest_agreement(cover, grid)
	assert_true(agreement > 0.9, "suwalki %.3f" % agreement)
	var layer := TacticalLayer.find(&"suwalki_tactical")
	assert_true(layer.has_land_cover(), "the tactical layer")
	# A cut across the corner of four chunks (128-hex chunks: column 512, row 768).
	var region := Rect2i(492, 752, 40, 30)
	var cut := layer.region_grid(region)
	var cut_cover := LandCover.for_map(&"suwalki_tactical", region, cut, 3.0)
	assert_true(cut_cover.has_raster())
	agreement = _forest_agreement(cut_cover, cut)
	assert_true(agreement > 0.9, "layer cut %.3f" % agreement)
	var rect := cut_cover.world_rect()
	assert_true(rect.position.x < -3.0 and rect.position.y < -3.0, "the margin: %s" % rect)
