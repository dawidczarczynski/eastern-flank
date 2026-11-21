class_name ForestFill
extends RefCounted
## The dense trees of the real-scale forest (TASK-135, ADR 0026): on forest tiles ScatterPlanner
## plans FOREST_TREES trees; at real size a forest has ~2 000 per hex (VegetationRanges
## .trees_per_hex), so this planner adds the rest on a jittered grid in world space. Pure and
## deterministic without any random number generator: every grid cell's point and values are
## integer hashes of (seed, cell, salt) (ScatterPlanner.tile_seed), so the trees of a rectangle
## never depend on what else is planned (chunks in any order give the same forest) and nothing
## draws from ScatterPlanner's streams or GameState.rng.
##
## A cell's point is kept on a FOREST tile outside the tile-centre clearing, above the shore, off
## roads and rivers and off farmland parcels. The tree dictionaries have ScatterPlanner's tree
## format ({position, scale, height_scale, yaw, conifer, k}); `position.y` is the ground height
## from the caller's `ground` callable (the drawn near surface, TerrainNear.surface_height_at).

const POINT_SALT := 0xF0E5
const VALUE_SALT := 0xF11E
## Jitter of a point inside its cell (share of the cell), kept off the cell border so neighbours
## never stack.
const JITTER := 0.8
const SCALE_MIN := 0.8
const SCALE_RANGE := 0.4


## Grid spacing (world units) that gives VegetationRanges.trees_per_hex() trees per forest hex
## together with ScatterPlanner's FOREST_TREES, with the clearing's share made up for.
static func spacing(v: Dictionary = {}) -> float:
	var d := VegetationRanges.values(v)
	var hex_m2 := VegetationRanges.hex_area_m2()
	var clearing_m := float(d["forest_clearing_m"])
	var open_share := 1.0 - PI * clearing_m * clearing_m / hex_m2
	var fill := maxf(VegetationRanges.trees_per_hex(d) - ScatterPlanner.FOREST_TREES, 1.0)
	var cell_m2 := hex_m2 * open_share / fill
	return MapScale.to_units(sqrt(cell_m2))


## The fill trees whose point lies in `rect` (XZ, end exclusive), in cell order; `thin` keeps
## only every other cell (a checkerboard: far impostors, whose crowns are drawn wider).
## `ground` is Callable(x: float, z: float) -> float (thread-safe: runs on the planning threads).
static func plan_rect(
	grid: HexGrid,
	ground: Callable,
	seed_value: int,
	rect: Rect2,
	parcels: ParcelMap = null,
	v: Dictionary = {},
	thin := false
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var d := VegetationRanges.values(v)
	var a := spacing(d)
	var clearing := MapScale.to_units(float(d["forest_clearing_m"]))
	var first := Vector2i((rect.position / a).floor())
	var last := Vector2i((rect.end / a).ceil())
	# Per tile of this rectangle: [forest?, centre x, centre z, roads / rivers near?].
	var tiles: Dictionary = {}
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			if thin and (i + j) % 2 != 0:
				continue
			var cell := Vector2i(i, j)
			var h := ScatterPlanner.tile_seed(seed_value, cell, POINT_SALT)
			var x := (i + 0.5 + JITTER * (float(h & 0xFFFF) / 65536.0 - 0.5)) * a
			var z := (j + 0.5 + JITTER * (float((h >> 16) & 0xFFFF) / 65536.0 - 0.5)) * a
			if x < rect.position.x or x >= rect.end.x or z < rect.position.y or z >= rect.end.y:
				continue
			var coord := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
			var tile: Array = tiles.get(coord, [])
			if tile.is_empty():
				var centre := Hex.to_world(coord, TerrainField.HEX_SIZE)
				tile = [
					grid.has_tile(coord) and grid.get_terrain(coord) == Terrain.Type.FOREST,
					centre.x,
					centre.z,
					FeatureRibbonPlanner.has_ribbons(grid, coord),
				]
				tiles[coord] = tile
			if not tile[0]:
				continue
			var cx: float = tile[1]
			var cz: float = tile[2]
			if (x - cx) * (x - cx) + (z - cz) * (z - cz) < clearing * clearing:
				continue
			if parcels != null and parcels.blocks_standing(x, z):
				continue
			if tile[3] and not FeatureRibbonPlanner.is_clear(grid, x, z):
				continue
			var y: float = ground.call(x, z)
			if y < ScatterPlanner.MIN_TREE_GROUND:
				continue
			# Three values from one hash, 10 bits each.
			var values_hash := ScatterPlanner.tile_seed(seed_value, cell, VALUE_SALT)
			var s := SCALE_MIN + SCALE_RANGE * float(values_hash & 0x3FF) / 1024.0
			var k := float((values_hash >> 10) & 0x3FF) / 1024.0
			var conifer_roll := float((values_hash >> 20) & 0x3FF) / 1024.0
			var chance := (
				ScatterPlanner.CONIFER_CHANCE_HIGH
				if y > ScatterPlanner.HIGH_GROUND
				else ScatterPlanner.CONIFER_CHANCE_LOW
			)
			(
				result
				. append(
					{
						"position": Vector3(x, y, z),
						"scale": s,
						"height_scale": s * (0.9 + k * 0.3),
						"yaw": k * 6.0,
						"conifer": conifer_roll < chance,
						"k": k,
					}
				)
			)
	return result


## A value in [0, 1) from the 32-bit hash `h` (`part` picks one of a few independent ones).
static func unit(h: int, part: int) -> float:
	var x := (h ^ ((part + 1) * 0x9E3779B1)) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	x ^= x >> 16
	return float(x & 0xFFFFFF) / float(0x1000000)
