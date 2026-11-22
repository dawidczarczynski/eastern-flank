class_name ForestFill
extends RefCounted
## The dense trees of the real-scale forest (TASK-135, ADR 0026; GPU placement TASK-189, ADR
## 0027): on forest tiles ScatterPlanner plans FOREST_TREES trees; at real size a forest has
## ~2 000 per hex (VegetationRanges.trees_per_hex), so the fill adds the rest on a jittered grid
## in world space. Every tree is a pure function of its grid cell: 32-bit integer hashes of (seed,
## cell, salt) give its point, size, species, variant and colour, and the map – the forest tiles,
## the tile-centre clearing, roads and rivers (one stand mask at ~4.5 m from a ForestMaskSource,
## built once), the farmland parcels and the drawn lattice height – decide whether it stands. No
## random number generator, no draws from ScatterPlanner's streams or GameState.rng; chunks in any
## order give the same forest.
##
## This is the reference implementation: the full trees (ForestField's CPU-planned LOD0 layer) and
## the tests use it, and assets/shaders/forest_hash.gdshaderinc + forest_impostor.gdshader compute
## the same trees on the GPU for the impostors (same constants, uint32 arithmetic – the GDScript
## hashes mask to 32 bits after every multiply). Change both together (tests/unit/test_forest_fill
## fixes the values of a few cells and compares the constants).
##
## Every decision reads the same data on both sides – the stand mask texel and the drawn lattice
## height (`lattice`, TerrainLattice.mesh_height_at – the shader's height texture) for the shore
## and the conifer share – so the CPU and the GPU agree on which cells hold a tree; only the drawn
## base height differs: the full trees stand on the near surface (plan_rect's `ground`), the
## impostors on the lattice, sunk a little.

const POINT_SALT := 0xF0E5
const VALUE_SALT := 0xF11E
const PICK_SALT := 0xF1C5
## ScatterPlanner._mix's multiplier and unit()'s per-part offset (golden ratio).
const MIX_MULTIPLIER := 0x45D9F3B
const UNIT_MULTIPLIER := 0x9E3779B1
## Jitter of a point inside its cell (share of the cell), kept off the cell border so neighbours
## never stack.
const JITTER := 0.8
const SCALE_MIN := 0.8
const SCALE_RANGE := 0.4
## Keep-off mask texels per world unit (~4.5 m at 144 m per unit).
const MASK_PER_UNIT := 32.0
## unit() parts of the pick hash.
const PART_SPECIES := 0
const PART_VARIANT := 1
const PART_HUE := 2
const PART_VALUE := 3
const PART_SATURATION := 4
const PART_PHASE := 5
const PART_AUTUMN := 6
const PART_AUTUMN_HUE := 7

## Grid spacing (world units).
var spacing := 1.0
var area := Rect2()

var _grid: HexGrid
var _lattice := Callable()
var _seed := 0
var _clearing := 0.0
var _parcels: ParcelMap
## L8 over `area` at MASK_PER_UNIT: 255 where a tree may stand (the source's forest minus its
## keep-off); the shader reads the same texels.
var _mask: Image
var _mask_bytes := PackedByteArray()
var _mask_size := Vector2i.ZERO
## Cumulative species shares per group (TreeSpecies.CONIFERS / DECIDUOUS order, LookPreset).
var _conifer_shares := PackedFloat64Array()
var _deciduous_shares := PackedFloat64Array()
var _autumn := 0.0


## The fill of `grid` over `area`: `lattice` is Callable(x, z) -> float, the drawn lattice height
## (thread-safe; MapView.mesh_height_at); `source` says where forest may stand (default: the hex
## tiles, HexForestMaskSource – transitional until TASK-108g's land-cover raster).
func _init(
	grid: HexGrid,
	lattice: Callable,
	seed_value: int,
	fill_area: Rect2,
	parcels: ParcelMap = null,
	v: Dictionary = {},
	source: ForestMaskSource = null
) -> void:
	_grid = grid
	_lattice = lattice
	_seed = seed_value
	area = fill_area
	_parcels = parcels
	var d := VegetationRanges.values(v)
	spacing = spacing_of(d)
	_clearing = MapScale.to_units(float(d["forest_clearing_m"]))
	_conifer_shares = _cumulative(TreeSpecies.CONIFERS)
	_deciduous_shares = _cumulative(TreeSpecies.DECIDUOUS)
	_autumn = LookPreset.autumn_share(TreeSpecies.AUTUMN_SHARE)
	_build_mask(source if source != null else HexForestMaskSource.new(_clearing))


## Grid spacing (world units) that gives VegetationRanges.trees_per_hex() trees per forest hex
## together with ScatterPlanner's FOREST_TREES, with the clearing's share made up for.
static func spacing_of(v: Dictionary = {}) -> float:
	var d := VegetationRanges.values(v)
	var hex_m2 := VegetationRanges.hex_area_m2()
	var clearing_m := float(d["forest_clearing_m"])
	var open_share := 1.0 - PI * clearing_m * clearing_m / hex_m2
	var fill := maxf(VegetationRanges.trees_per_hex(d) - ScatterPlanner.FOREST_TREES, 1.0)
	var cell_m2 := hex_m2 * open_share / fill
	return MapScale.to_units(sqrt(cell_m2))


static func _cumulative(group: Array[StringName]) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	var acc := 0.0
	for species in group:
		acc += LookPreset.share(species, TreeSpecies.SHARES[species])
		result.append(acc)
	return result


## The fill trees whose point lies in `rect` (XZ, end exclusive), in cell order. `ground` is
## Callable(x, z) -> float for the drawn base height (thread-safe; the near surface for the full
## trees), else the lattice height. Thread-safe.
func plan_rect(rect: Rect2, ground := Callable()) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first := Vector2i((rect.position / spacing).floor())
	var last := Vector2i((rect.end / spacing).ceil())
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			var p := point(Vector2i(i, j))
			if p.x < rect.position.x or p.x >= rect.end.x:
				continue
			if p.y < rect.position.y or p.y >= rect.end.y:
				continue
			var tree := cell_tree(Vector2i(i, j))
			if tree.is_empty():
				continue
			if ground.is_valid():
				var at: Vector3 = tree["position"]
				tree["position"] = Vector3(at.x, ground.call(at.x, at.z), at.z)
			result.append(tree)
	return result


## The cells whose centre lies in `rect`: Rect2i(first cell, cell counts). Adjacent rectangles
## share no cell (the impostor chunks of the GPU layer).
func cells_of(rect: Rect2) -> Rect2i:
	var first := Vector2i(
		ceili(rect.position.x / spacing - 0.5), ceili(rect.position.y / spacing - 0.5)
	)
	var end := Vector2i(ceili(rect.end.x / spacing - 0.5), ceili(rect.end.y / spacing - 0.5))
	return Rect2i(first, end - first)


## The jittered point (world XZ) of a cell.
func point(cell: Vector2i) -> Vector2:
	var h := ScatterPlanner.tile_seed(_seed, cell, POINT_SALT)
	return Vector2(
		(cell.x + 0.5 + JITTER * (float(h & 0xFFFF) / 65536.0 - 0.5)) * spacing,
		(cell.y + 0.5 + JITTER * (float((h >> 16) & 0xFFFF) / 65536.0 - 0.5)) * spacing
	)


## The tree of a grid cell in ScatterPlanner's tree format ({position (y: lattice height),
## scale, height_scale, yaw, conifer, k}) plus its TreeSpecies-style pick ({species, variant,
## custom}) and `cell`; {} when the cell holds none. Thread-safe.
func cell_tree(cell: Vector2i) -> Dictionary:
	var p := point(cell)
	var x := p.x
	var z := p.y
	if not _stands(p):
		return {}
	var y: float = _lattice.call(x, z)
	if y < ScatterPlanner.MIN_TREE_GROUND:
		return {}
	# Three values from one hash, 10 bits each.
	var values_hash := ScatterPlanner.tile_seed(_seed, cell, VALUE_SALT)
	var s := SCALE_MIN + SCALE_RANGE * float(values_hash & 0x3FF) / 1024.0
	var k := float((values_hash >> 10) & 0x3FF) / 1024.0
	var conifer_roll := float((values_hash >> 20) & 0x3FF) / 1024.0
	var chance := (
		ScatterPlanner.CONIFER_CHANCE_HIGH
		if y > ScatterPlanner.HIGH_GROUND
		else ScatterPlanner.CONIFER_CHANCE_LOW
	)
	var conifer := conifer_roll < chance
	var tree := {
		"cell": cell,
		"position": Vector3(x, y, z),
		"scale": s,
		"height_scale": s * (0.9 + k * 0.3),
		"yaw": k * 6.0,
		"conifer": conifer,
		"k": k,
	}
	tree.merge(_pick(cell, conifer))
	return tree


## Whether the map lets a tree stand at `p`: inside the area, on the mask (forest, off the
## clearing, roads and rivers) and off the parcels.
func _stands(p: Vector2) -> bool:
	if not area.has_point(p):
		return false
	return mask_allows(p.x, p.y) and (_parcels == null or not _parcels.blocks_standing(p.x, p.y))


## Species, variant and colour variation of a cell's tree (TreeSpecies.pick's format, but from the
## integer hash: the same bits on the GPU).
func _pick(cell: Vector2i, conifer: bool) -> Dictionary:
	var h := ScatterPlanner.tile_seed(_seed, cell, PICK_SALT)
	var group := TreeSpecies.CONIFERS if conifer else TreeSpecies.DECIDUOUS
	var shares := _conifer_shares if conifer else _deciduous_shares
	var roll := unit(h, PART_SPECIES)
	var species: StringName = group[group.size() - 1]
	for n in shares.size():
		if roll < shares[n]:
			species = group[n]
			break
	var variant := mini(int(unit(h, PART_VARIANT) * TreeMeshes.VARIANTS), TreeMeshes.VARIANTS - 1)
	var hue := (unit(h, PART_HUE) * 2.0 - 1.0) * TreeSpecies.HUE_SHIFT
	if not conifer and unit(h, PART_AUTUMN) < _autumn:
		hue = lerpf(
			TreeSpecies.AUTUMN_HUE_MIN, TreeSpecies.AUTUMN_HUE_MAX, unit(h, PART_AUTUMN_HUE)
		)
	var custom := Color(
		hue,
		lerpf(TreeSpecies.VALUE_MIN, TreeSpecies.VALUE_MAX, unit(h, PART_VALUE)),
		lerpf(TreeSpecies.SATURATION_MIN, TreeSpecies.SATURATION_MAX, unit(h, PART_SATURATION)),
		unit(h, PART_PHASE)
	)
	return {"species": species, "variant": variant, "custom": custom}


## A value in [0, 1) from the 32-bit hash `h` (`part` picks one of a few independent ones).
static func unit(h: int, part: int) -> float:
	var x := (h ^ ((part + 1) * UNIT_MULTIPLIER)) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * MIX_MULTIPLIER) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * MIX_MULTIPLIER) & 0xFFFFFFFF
	x ^= x >> 16
	return float(x & 0xFFFFFF) / float(0x1000000)


## Whether the mask lets a tree stand at (x, z) (MASK_PER_UNIT texels over `area`).
func mask_allows(x: float, z: float) -> bool:
	var px := floori((x - area.position.x) * MASK_PER_UNIT)
	var pz := floori((z - area.position.y) * MASK_PER_UNIT)
	if px < 0 or pz < 0 or px >= _mask_size.x or pz >= _mask_size.y:
		return false
	return _mask_bytes[pz * _mask_size.x + px] > 127


## Whether any texel of the stand mask within `rect` lets a tree stand (an impostor chunk has
## forest). Main thread or any; native byte counting.
func mask_any(rect: Rect2) -> bool:
	var lo := Vector2i(((rect.position - area.position) * MASK_PER_UNIT).floor()).max(Vector2i.ZERO)
	var hi := Vector2i(((rect.end - area.position) * MASK_PER_UNIT).ceil()).min(_mask_size)
	if hi.x <= lo.x or hi.y <= lo.y:
		return false
	var bytes := _mask.get_region(Rect2i(lo, hi - lo)).get_data()
	return bytes.count(0) < bytes.size()


## The stand mask (L8 over `area`, MASK_PER_UNIT texels per unit, 255 = a tree may stand).
func mask_image() -> Image:
	return _mask


## Merges the source's forest and keep-off masks into the stand mask.
func _build_mask(source: ForestMaskSource) -> void:
	var masks := source.build(_grid, area, MASK_PER_UNIT)
	var forest: Image = masks["forest"]
	var keep_off: PackedByteArray = (masks["keep_off"] as Image).get_data()
	_mask_size = forest.get_size()
	_mask_bytes = forest.get_data()
	for k in keep_off.size():
		if keep_off[k] > 127:
			_mask_bytes[k] = 0
	_mask = Image.create_from_data(_mask_size.x, _mask_size.y, false, Image.FORMAT_L8, _mask_bytes)


## The shader inputs of the fill (forest_impostor.gdshader): seed, spacing, clearing, species
## shares, the forest tiles, the keep-off mask, the parcels. Main thread.
func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter(&"forest_seed", _seed & 0xFFFFFFFF)
	material.set_shader_parameter(&"spacing", spacing)
	material.set_shader_parameter(&"min_ground", ScatterPlanner.MIN_TREE_GROUND)
	material.set_shader_parameter(&"high_ground", ScatterPlanner.HIGH_GROUND)
	material.set_shader_parameter(
		&"conifer_chance",
		Vector2(ScatterPlanner.CONIFER_CHANCE_HIGH, ScatterPlanner.CONIFER_CHANCE_LOW)
	)
	material.set_shader_parameter(
		&"shares",
		Vector4(
			_conifer_shares[0], _deciduous_shares[0], _deciduous_shares[1], _deciduous_shares[2]
		)
	)
	material.set_shader_parameter(&"autumn_share", _autumn)
	material.set_shader_parameter(
		&"fill_area", Vector4(area.position.x, area.position.y, area.end.x, area.end.y)
	)
	material.set_shader_parameter(&"forest_mask", ImageTexture.create_from_image(_mask))
	material.set_shader_parameter(&"mask_per_unit", MASK_PER_UNIT)
	var has_parcels := _parcels != null
	material.set_shader_parameter(&"use_parcels", has_parcels)
	if has_parcels:
		material.set_shader_parameter(&"parcels", _parcels.texture())
		material.set_shader_parameter(&"parcel_origin_m", _parcels.origin_m)
		material.set_shader_parameter(&"parcel_metres_per_pixel", _parcels.metres_per_pixel)
	material.set_shader_parameter(&"metres_per_unit", MapScale.metres_per_unit)


## The drawn lattice heights as an RF image of (cells + 1)^2 vertices (the shader's ground,
## interpolated as TerrainLattice.mesh_height_at does). Main thread; reads the cached blocks.
static func height_image(lattice: TerrainLattice) -> Image:
	var side := TerrainLattice.CELLS_PER_CHUNK + 1
	var size := lattice.cells + Vector2i.ONE
	var values := PackedFloat32Array()
	values.resize(size.x * size.y)
	var counts := lattice.chunk_counts()
	for cz in counts.y:
		for cx in counts.x:
			var block := lattice.block(Vector2i(cx, cz))
			for b in side:
				var j := cz * TerrainLattice.CELLS_PER_CHUNK + b
				if j >= size.y:
					break
				for a in side:
					var i := cx * TerrainLattice.CELLS_PER_CHUNK + a
					if i >= size.x:
						break
					values[j * size.x + i] = block[b * side + a]
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, values.to_byte_array())
