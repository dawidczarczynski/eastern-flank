# gdlint: disable=max-public-methods
extends TestCase
## ImportedMap (TASK-087): maps imported from real geography by tools/import_map.py.
## tests/fixtures/maps/sample_map.tres is the importer's output on SYNTHETIC fixtures (6x5 hexes:
## forest NW, hill NE, lake SW, village, fields and wetland SE, a road east-west and a river
## north-south; see tools/test_import_map.py).

const SAMPLE_PATH := "res://tests/fixtures/maps/sample_map.tres"
const SAMPLE_TERRAIN := ["FFFPHH", "FPFPHH", "FFFPPA", "WWPUUA", "WWMUUA"]
const EPSILON := 1e-4
## terrain_rows of data/maps/suwalki.tres as imported by TASK-087 (P/F/H/W only).
const SUWALKI_087_TERRAIN := [
	"FPPHFFPPPPPPPPPPPPPFFFHPPPFPPW",
	"PHPFFPPPPPHPFHPPPHHFHHPPPPPPWW",
	"PPPPFPHPPPPFPHHPFWHPHHHPPPPPPP",
	"PPPHPPPPPPPHHHHHHHPHPFHPPPPPPP",
	"PPHPPPPPPPPHPHPPPPHFHWFPPPPPPP",
	"PPHPPPPPPHPPPHPPPPPPPWPPPPPPPP",
	"PHFPPHPPPHPPFFHHPPPHPFFPPPPPPP",
	"PFPPHHPPPHPPFHPPHPFHPPHPPPPPPP",
	"HPHPHHHFPPHPFFHPFFFPFPPHPPPPPP",
	"FHPPPPFFHHPFFFFFFWHPFPHPPPPPPF",
	"PHPPPPFFFPPFFFFFFWFPFPHPPPPPPP",
	"HPPPPPPFPPPFFFFFWPPHHPPPPPPPPP",
	"HHFFPFFFFFFHPHFFFFPFPWHHPPPPPP",
	"HFFFFFFFFFFHPPPPWFPWWPHPPPPPPP",
	"FFPPFFFFFFFHHHPPPPWWWHPPPPPPPP",
	"FFPFFFFFFFHPHHFWWWWWHPPPPPPPPP",
	"FPPPPFFFFFPPHPHFWWWFFPHPPPPPPP",
	"PHHPPPHPFHPHHHFHPPFFHPPPPPPPPH",
	"HHPHHPHPPPHHPPFHPHHFHPPPPHPFPP",
	"PPPPPPPPPPHHPPPHHPPPPFPPHPHPPH",
	"PPPPPPPPPPPPPHPPPHHPPPPPPPPPFP",
	"HPPPPPPPPFPPPPPHPPHPPPPPHPPHPH",
	"FHPPPPPPPFPPPPPPPPPHPPPPPPHHHP",
	"FPHPPPPPPPPPPPPPPPPHPPPPPHFPPP",
]
## Checksums of the TASK-087 elevation arrays: [sum, sum of |v| * (i % 7 + 1)].
const SUWALKI_087_ELEVATION_M := [148024.6, 591194.7]
const SUWALKI_087_ELEVATION := [499.81, 2071.341]


func _sample() -> ImportedMap:
	return load(SAMPLE_PATH) as ImportedMap


func _near(actual: float, expected: float, message := "", epsilon := EPSILON) -> void:
	assert_true(
		absf(actual - expected) < epsilon, "expected %f, got %f. %s" % [expected, actual, message]
	)


func test_sample_map_loads_with_its_metadata() -> void:
	var map := _sample()
	assert_true(map != null, "sample map loads as ImportedMap")
	assert_eq(map.id, &"sample_map")
	assert_eq(map.width, 6)
	assert_eq(map.height, 5)
	assert_eq(map.hex_spacing_m, 250.0)
	assert_eq(map.crs, "EPSG:32634")
	assert_eq(map.problem(), "")
	assert_true(map.sources.contains("OpenStreetMap"), "credits OSM")
	assert_true(map.sources.contains("Copernicus"), "credits the DEM")


func test_grid_has_every_tile_with_its_terrain_and_elevation() -> void:
	var map := _sample()
	var grid := map.to_grid()
	assert_eq(grid.coords().size(), 30)
	assert_true(grid.field == null, "authored elevation, no generated field")
	assert_true(grid.authored_elevation)
	var types := {
		"P": Terrain.Type.PLAINS,
		"F": Terrain.Type.FOREST,
		"H": Terrain.Type.HILLS,
		"W": Terrain.Type.WATER,
		"A": Terrain.Type.FIELDS,
		"U": Terrain.Type.URBAN,
		"M": Terrain.Type.MARSH,
	}
	for row in 5:
		for col in 6:
			var c := MapGenerator.offset_to_axial(col, row)
			assert_true(grid.has_tile(c), str(c))
			assert_eq(grid.get_terrain(c), types[SAMPLE_TERRAIN[row][col]], str(c))
			_near(grid.elevation(c), map.elevation[row * 6 + col], str(c))
			assert_true(grid.has_elevation_m(c))
			_near(grid.elevation_m(c), map.elevation_m[row * 6 + col], str(c), 0.01)
	assert_false(grid.has_tile(MapGenerator.offset_to_axial(6, 0)))


func test_water_below_and_land_above_the_water_surface() -> void:
	var map := _sample()
	var grid := map.to_grid()
	for c in grid.coords():
		if grid.get_terrain(c) == Terrain.Type.WATER:
			assert_true(grid.elevation(c) < TerrainSurface.WATER_SURFACE, str(c))
		else:
			assert_true(grid.elevation(c) > TerrainSurface.WATER_SURFACE, str(c))


func test_hill_tiles_are_higher_than_the_lake_shore() -> void:
	var map := _sample()
	assert_true(map.elevation_m[5] > map.elevation_m[3 * 6 + 2] + 20.0, "NE hill above the SE")


func test_tile_centres_follow_the_hex_layout_in_projected_metres() -> void:
	var map := _sample()
	var origin := Hex.to_world(Vector2i.ZERO, 1.0)
	_near(map.easting(origin), map.origin_easting)
	_near(map.northing(origin), map.origin_northing)
	# East neighbour: one spacing east; row 1 (south): half a spacing east, 0.75 hex height south.
	var east := Hex.to_world(MapGenerator.offset_to_axial(1, 0), 1.0)
	_near(map.easting(east) - map.origin_easting, 250.0)
	_near(map.northing(east) - map.origin_northing, 0.0)
	var south := Hex.to_world(MapGenerator.offset_to_axial(0, 1), 1.0)
	_near(map.easting(south) - map.origin_easting, 125.0)
	_near(map.northing(south) - map.origin_northing, -250.0 * Hex.SQRT3 / 2.0)


func test_projected_to_tile_inverts_the_tile_centres() -> void:
	var map := _sample()
	for c in map.to_grid().coords():
		var p := Hex.to_world(c, 1.0)
		assert_eq(map.projected_to_tile(map.easting(p), map.northing(p)), c)
		assert_eq(map.projected_to_tile(map.easting(p) + 100.0, map.northing(p)), c, "inradius")


func test_world_and_projected_metres_share_the_scale() -> void:
	var map := _sample()
	_near(map.metres_per_world_unit(), 250.0 / Hex.SQRT3)
	var p := Vector3(1.0, 0.0, 2.0)
	_near(map.easting(p) - map.origin_easting, map.metres_per_world_unit())
	_near(map.northing(p) - map.origin_northing, -2.0 * map.metres_per_world_unit(), "+z is south")


func test_problem_reports_malformed_maps() -> void:
	var map := _sample().duplicate() as ImportedMap
	map.terrain_rows = PackedStringArray(["FFF"])
	assert_true(map.problem() != "", "row count")
	assert_true(map.to_grid() == null)
	map = _sample().duplicate() as ImportedMap
	map.terrain_rows[0] = "FFFPHX"
	assert_true(map.problem().contains("X"), map.problem())
	map = _sample().duplicate() as ImportedMap
	map.elevation = PackedFloat32Array([0.1])
	assert_true(map.problem() != "", "elevation size")
	map = _sample().duplicate() as ImportedMap
	map.width = 0
	assert_true(map.problem() != "", "empty")


func test_find_loads_maps_from_the_maps_folder() -> void:
	assert_true(ImportedMap.find(&"suwalki") != null, "the committed Suwalki sample")
	assert_true(ImportedMap.find(&"no_such_map") == null)
	assert_true(ImportedMap.find(&"../units/t72b3") == null, "ids are plain names")


# --- TerrainSurface on authored elevation ---


func test_surface_passes_through_tile_centres() -> void:
	var grid := _sample().to_grid()
	var surface := TerrainSurface.new(grid)
	for c in grid.coords():
		var p := Hex.to_world(c, TerrainField.HEX_SIZE)
		_near(surface.height_at(p.x, p.z), grid.elevation(c), str(c))


func test_surface_is_continuous_across_hex_edges() -> void:
	var grid := _sample().to_grid()
	var surface := TerrainSurface.new(grid)
	var max_step := 0.0
	for c in grid.coords():
		var a := Hex.to_world(c, TerrainField.HEX_SIZE)
		for n in Hex.neighbors(c):
			if not grid.has_tile(n):
				continue
			var b := Hex.to_world(n, TerrainField.HEX_SIZE)
			var prev := surface.height_at(a.x, a.z)
			for i in range(1, 101):
				var p := a.lerp(b, i / 100.0)
				var h := surface.height_at(p.x, p.z)
				max_step = maxf(max_step, absf(h - prev))
				prev = h
	assert_true(max_step < 0.05, "largest jump %f" % max_step)


func test_surface_lies_between_the_surrounding_tile_elevations() -> void:
	var grid := _sample().to_grid()
	var surface := TerrainSurface.new(grid)
	var lo := INF
	var hi := -INF
	for c in grid.coords():
		lo = minf(lo, grid.elevation(c))
		hi = maxf(hi, grid.elevation(c))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 200:
		var h := surface.height_at(rng.randf_range(-2.0, 12.0), rng.randf_range(-2.0, 8.0))
		assert_true(h >= lo - EPSILON and h <= hi + EPSILON, "h %f outside [%f, %f]" % [h, lo, hi])


func test_lake_dips_below_the_water_surface_between_water_tiles() -> void:
	var grid := _sample().to_grid()
	var surface := TerrainSurface.new(grid)
	var a := Hex.to_world(MapGenerator.offset_to_axial(0, 3), 1.0)
	var b := Hex.to_world(MapGenerator.offset_to_axial(1, 3), 1.0)
	var mid := (a + b) * 0.5
	assert_true(surface.height_at(mid.x, mid.z) < TerrainSurface.WATER_SURFACE)
	assert_eq(surface.ground_height(mid.x, mid.z), TerrainSurface.WATER_SURFACE)


func test_hand_made_grids_stay_flat_per_tile() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.PLAINS)
	assert_false(grid.has_elevation_m(Vector2i.ZERO), "no real metres on hand-made grids")
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.HILLS)
	var surface := TerrainSurface.new(grid)
	assert_eq(surface.height_at(0.8, 0.0), 0.2, "no authored_elevation: flat tiles")
	grid.authored_elevation = true
	surface = TerrainSurface.new(grid)
	var h := surface.height_at(Hex.SQRT3 / 2.0, 0.0)  # the shared edge's midpoint
	_near(h, (0.2 + 0.9) / 2.0, "authored: halfway on the shared edge")


# --- force_terrain on authored elevation ---


func test_forcing_land_to_plains_keeps_the_real_elevation() -> void:
	var grid := _sample().to_grid()
	var hill := MapGenerator.offset_to_axial(5, 0)
	assert_eq(grid.get_terrain(hill), Terrain.Type.HILLS)
	grid.set_elevation(hill, 1.5)  # above the generator's land band (land_max 0.7)
	MapGenerator.force_terrain(grid, hill, Terrain.Type.PLAINS)
	assert_eq(grid.get_terrain(hill), Terrain.Type.PLAINS)
	assert_eq(grid.elevation(hill), 1.5)


func test_forcing_water_to_land_still_lifts_it_into_the_band() -> void:
	var grid := _sample().to_grid()
	var lake := MapGenerator.offset_to_axial(0, 4)
	MapGenerator.force_terrain(grid, lake, Terrain.Type.PLAINS)
	assert_eq(grid.elevation(lake), MapGenerator.DEFAULT_SETTINGS.land_min)


# --- TASK-108: real-terrain types, road and river links ---


## 3x2 map: row 0 = P A U, row 1 = M P W (axial (0,0) (1,0) (2,0) / (0,1) (1,1) (2,1)).
## Roads: (0,0)-(1,0) on both tiles, (0,0) west off the map, (1,1) east into the water.
## River: (0,1)-(1,1) on both tiles.
func _linked_map() -> ImportedMap:
	var map := ImportedMap.new()
	map.id = &"linked"
	map.width = 3
	map.height = 2
	map.terrain_rows = PackedStringArray(["PAU", "MPW"])
	map.elevation = PackedFloat32Array([0.2, 0.2, 0.2, 0.2, 0.2, -0.4])
	var c := ImportedMap.LINK_CHARS
	map.road_rows = PackedStringArray(
		[c[(1 << 0) | (1 << 3)] + c[1 << 3] + ".", ".%s." % c[1 << 0]]
	)
	map.river_rows = PackedStringArray(["...", c[1 << 0] + c[1 << 3] + "."])
	return map


func test_real_terrain_chars_load_as_the_new_types() -> void:
	var grid := _linked_map().to_grid()
	assert_true(grid != null, _linked_map().problem())
	assert_eq(grid.get_terrain(Vector2i(1, 0)), Terrain.Type.FIELDS)
	assert_eq(grid.get_terrain(Vector2i(2, 0)), Terrain.Type.URBAN)
	assert_eq(grid.get_terrain(Vector2i(0, 1)), Terrain.Type.MARSH)


func test_link_chars_encode_six_bit_masks() -> void:
	var chars := ImportedMap.LINK_CHARS
	assert_eq(chars.length(), 64)
	var seen := {}
	for ch in chars:
		seen[ch] = true
	assert_eq(seen.size(), 64, "unique")
	assert_eq(chars[0], ".")
	assert_eq(chars[63], "@")


func test_links_decode_to_the_grid_masks() -> void:
	var map := _linked_map()
	assert_eq(map.problem(), "")
	var grid := map.to_grid()
	assert_eq(grid.road_links(Vector2i(0, 0)), (1 << 0) | (1 << 3))
	assert_eq(grid.road_links(Vector2i(1, 0)), 1 << 3)
	assert_eq(grid.road_links(Vector2i(1, 1)), 1 << 0)
	assert_eq(grid.road_links(Vector2i(2, 0)), 0)
	assert_true(grid.has_road(Vector2i(0, 0), Vector2i(1, 0)))
	assert_true(grid.has_road(Vector2i(1, 0), Vector2i(0, 0)))
	assert_true(grid.is_river(Vector2i(0, 1)))
	assert_true(grid.is_river(Vector2i(1, 1)))
	assert_false(grid.is_river(Vector2i(0, 0)))
	assert_eq(grid.step_cost(Vector2i(0, 1), Vector2i(1, 1)), 2, "river hex")


func test_maps_without_links_are_valid() -> void:
	var map := _linked_map()
	map.road_rows = PackedStringArray()
	map.river_rows = PackedStringArray()
	assert_eq(map.problem(), "")
	var grid := map.to_grid()
	for c in grid.coords():
		assert_eq(grid.road_links(c), 0)
		assert_eq(grid.river_links(c), 0)
	assert_eq(_sample().problem(), "", "the synthetic sample")


func test_sample_map_has_its_road_and_river() -> void:
	var grid := _sample().to_grid()
	var road := MapGenerator.offset_to_axial(0, 2)
	assert_true(grid.road_links(road) != 0, "the road crosses row 2")
	var river := 0
	for c in grid.coords():
		if grid.is_river(c):
			river += 1
			assert_true(grid.get_terrain(c) != Terrain.Type.WATER)
	assert_eq(river, 5, "one river hex per row")


func test_problem_reports_malformed_links() -> void:
	var map := _linked_map()
	map.road_rows = PackedStringArray(["..."])
	assert_true(map.problem() != "", "row count")
	map = _linked_map()
	map.river_rows[0] = ".."
	assert_true(map.problem() != "", "row width")
	map = _linked_map()
	map.road_rows[1] = ".!."
	assert_true(map.problem().contains("!"), map.problem())
	map = _linked_map()
	map.road_rows[0] = ImportedMap.LINK_CHARS[1 << 0] + ".."
	assert_true(map.problem() != "", "land-land link on one side only")
	map = _linked_map()
	map.river_rows[1] = "..%s" % ImportedMap.LINK_CHARS[1 << 0]
	assert_true(map.problem() != "", "link on a water tile")
	assert_true(map.to_grid() == null)


# --- TASK-108: the regenerated Suwalki map against the TASK-087 import ---


func _checksums(values: PackedFloat32Array) -> Array[float]:
	var total := 0.0
	var weighted := 0.0
	for i in values.size():
		total += values[i]
		weighted += absf(values[i]) * (i % 7 + 1)
	return [total, weighted]


func test_suwalki_keeps_forest_water_and_elevation_of_task_087() -> void:
	var map := ImportedMap.find(&"suwalki")
	assert_eq(map.problem(), "")
	for row in map.height:
		for col in map.width:
			var old: String = SUWALKI_087_TERRAIN[row][col]
			var now := map.terrain_rows[row][col]
			if old == "F" or old == "W":
				assert_eq(now, old, "%d,%d" % [col, row])
			else:
				assert_true("PHAUM".contains(now), "%d,%d: %s was %s" % [col, row, now, old])
	var metres := _checksums(map.elevation_m)
	_near(metres[0], SUWALKI_087_ELEVATION_M[0], "elevation_m sum", 0.5)
	_near(metres[1], SUWALKI_087_ELEVATION_M[1], "elevation_m weighted", 2.0)
	var game := _checksums(map.elevation)
	_near(game[0], SUWALKI_087_ELEVATION[0], "elevation sum", 0.01)
	_near(game[1], SUWALKI_087_ELEVATION[1], "elevation weighted", 0.05)


func test_suwalki_has_roads_and_rivers() -> void:
	var grid := ImportedMap.find(&"suwalki").to_grid()
	var roads := 0
	var rivers := 0
	for c in grid.coords():
		if grid.road_links(c) != 0:
			roads += 1
		if grid.is_river(c):
			rivers += 1
	assert_true(roads >= 1, "road links")
	assert_true(rivers >= 1, "river hexes")
