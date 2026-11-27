class_name RiparianPlanner
extends RefCounted
## Riparian vegetation along rivers (TASK-108c follow-up): a patchy belt of shrubs close to the
## bank and scattered alder-like trees farther out, planned by position hash only (no RNG stream,
## no GameState) in the formats of ScatterPlanner (`edge_shrubs`, `trees`), so the existing
## scatter chunks draw them. Distances are metres converted with MapScale. Nothing grows on the
## ribbon, its 3 m clearance, roads and bridges, on URBAN tiles, on forest (already wooded) or in
## water. Maps without rivers plan nothing (the generated default battle is unchanged).

const SAMPLE_STEP_M := 5.0
## Shrubs stand from SHRUB_NEAR_M to SHRUB_FAR_M beyond the ribbon's outer edge (the water edge
## itself lies about 3 m inside it), trees from TREE_NEAR_M to TREE_FAR_M.
const SHRUB_NEAR_M := 3.5
const SHRUB_FAR_M := 17.0
const TREE_NEAR_M := 5.0
const TREE_FAR_M := 21.0
## Largest distance from the ribbon's edge any item stands at.
const MAX_REACH_M := 25.0
## Per sample and side, at full patch strength.
const SHRUB_CHANCE := 0.55
const TREE_CHANCE := 0.14
## Patchiness: noise wavelength (metres) and the strength ramp.
const PATCH_WAVELENGTH_M := 70.0
const PATCH_FROM := 0.35
const PATCH_TO := 0.7
const PATCH_SEED := 211.0
## Cap per tile, so a long river never floods the instance budget.
const MAX_SHRUBS_PER_TILE := 110
const MAX_TREES_PER_TILE := 28
const TREE_SPECIES := &"alder"
const SALT := 9100
const SHRUB_SCALE_MIN := 0.8
const TREE_SCALE_MIN := 0.85


## {"trees": [...], "edge_shrubs": [...]} for the tiles whose centre lies in `within` (all tiles
## when it has no area). Items follow the formats of ScatterPlanner.plan; `look` (optional) is
## the land-cover raster that says what the ground is.
static func plan(
	grid: HexGrid,
	surface: TerrainSurface,
	parcels: ParcelMap = null,
	within := Rect2(),
	look: CoverLook = null
) -> Dictionary:
	var trees: Array[Dictionary] = []
	var shrubs: Array[Dictionary] = []
	if not grid.has_links():
		return {"trees": trees, "edge_shrubs": shrubs}
	var coords: Array[Vector2i] = (
		ScatterPlanner.coords_near(grid, within) if within.has_area() else grid.coords()
	)
	for coord in coords:
		_plan_tile(grid, surface, coord, look, trees, shrubs)
	if parcels != null:
		trees = _off_parcels(trees, parcels)
		shrubs = _off_parcels(shrubs, parcels)
	# Nothing grows on the ribbons' clearance, roads and bridges.
	var kept_trees: Array[Dictionary] = []
	kept_trees.assign(FeatureRibbonPlanner.without_ribbons(grid, trees))
	var kept_shrubs: Array[Dictionary] = []
	kept_shrubs.assign(FeatureRibbonPlanner.without_ribbons(grid, shrubs))
	return {"trees": kept_trees, "edge_shrubs": kept_shrubs}


static func _off_parcels(items: Array[Dictionary], parcels: ParcelMap) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for item in items:
		var p: Vector3 = item["position"]
		if not parcels.blocks_standing_exact(p.x, p.z):
			kept.append(item)
	return kept


static func _plan_tile(
	grid: HexGrid,
	surface: TerrainSurface,
	coord: Vector2i,
	look: CoverLook,
	trees: Array[Dictionary],
	shrubs: Array[Dictionary]
) -> void:
	var step := MapScale.to_units(SAMPLE_STEP_M)
	var tile_shrubs := 0
	var tile_trees := 0
	for segment in FeatureRibbonPlanner.river_segments(grid, coord):
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var half: float = segment["half"]
		var length := a.distance_to(b)
		var direction := (b - a) / length
		var normal := Vector2(-direction.y, direction.x)
		var count := maxi(1, roundi(length / step))
		for i in count:
			var p := a + direction * (length * (i + 0.5) / count)
			var patch := TerrainNoise.smooth(
				PATCH_FROM,
				PATCH_TO,
				TerrainNoise.value_noise(
					p.x / MapScale.to_units(PATCH_WAVELENGTH_M),
					p.y / MapScale.to_units(PATCH_WAVELENGTH_M),
					PATCH_SEED
				)
			)
			if patch <= 0.0:
				continue
			for side in [-1.0, 1.0]:
				var salt := SALT + (0 if side < 0.0 else 40)
				if tile_shrubs < MAX_SHRUBS_PER_TILE:
					var h := _hashes(p, salt)
					if h[0] < SHRUB_CHANCE * patch:
						var d := _reach(SHRUB_NEAR_M, SHRUB_FAR_M, pow(h[1], 1.6))
						var item := _item(
							grid,
							surface,
							look,
							p + normal * side * (half + d) + direction * (h[2] - 0.5) * step,
							h,
							SHRUB_SCALE_MIN,
							0.6
						)
						if not item.is_empty():
							item["species"] = ScatterPlanner.SHRUB
							shrubs.append(item)
							tile_shrubs += 1
				if tile_trees < MAX_TREES_PER_TILE:
					var h := _hashes(p, salt + 17)
					if h[0] < TREE_CHANCE * patch:
						var d := _reach(TREE_NEAR_M, TREE_FAR_M, h[1])
						var item := _item(
							grid,
							surface,
							look,
							p + normal * side * (half + d) + direction * (h[2] - 0.5) * step,
							h,
							TREE_SCALE_MIN,
							0.5
						)
						if not item.is_empty():
							item["species"] = TREE_SPECIES
							trees.append(item)
							tile_trees += 1


static func _reach(near_m: float, far_m: float, k: float) -> float:
	return MapScale.to_units(lerpf(near_m, far_m, k))


static func _hashes(p: Vector2, salt: int) -> Array[float]:
	return [
		GrassPlanner.hash01(p.x, p.y, salt),
		GrassPlanner.hash01(p.x, p.y, salt + 1),
		GrassPlanner.hash01(p.x, p.y, salt + 2),
		GrassPlanner.hash01(p.x, p.y, salt + 3),
	]


## One planned item at `q` (an empty dictionary where nothing may stand: too far from the river,
## urban, forest, water or too low).
static func _item(
	grid: HexGrid,
	surface: TerrainSurface,
	look: CoverLook,
	q: Vector2,
	h: Array[float],
	scale_min: float,
	scale_range: float
) -> Dictionary:
	var edge := FeatureRibbonPlanner.edge_distance(grid, FeatureRibbonPlanner.Kind.RIVER, q.x, q.y)
	if (
		edge < MapScale.to_units(FeatureRibbonPlanner.ROAD_CLEARANCE_M)
		or edge > MapScale.to_units(MAX_REACH_M)
	):
		return {}
	var coord := Hex.from_world(Vector3(q.x, 0.0, q.y), TerrainField.HEX_SIZE)
	if not grid.has_tile(coord):
		return {}
	var terrain: int = look.terrain_at(q.x, q.y) if look != null else grid.get_terrain(coord)
	if (
		terrain == Terrain.Type.URBAN
		or terrain == Terrain.Type.WATER
		or terrain == Terrain.Type.FOREST
	):
		return {}
	var y := surface.ground_height(q.x, q.y)
	if y < ScatterPlanner.MIN_TREE_GROUND:
		return {}
	var s := scale_min + scale_range * h[3]
	return {
		"position": Vector3(q.x, y - ScatterPlanner.TREE_SINK, q.y),
		"scale": s,
		"height_scale": s * (0.9 + h[2] * 0.3),
		"yaw": h[3] * 6.0,
		"conifer": false,
		"k": h[3],
	}
