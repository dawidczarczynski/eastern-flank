class_name GrassRules
extends RefCounted
## Where the near grass of the real-scale countryside grows (TASK-217b, ADR 0033; `true`
## VisualScale preset only): the GDScript reference of the GPU-placed grass layer (GpuGrassField,
## assets/shaders/grass_rules.gdshaderinc). A jittered grid of `grass_cell_m` cells (metres,
## LookPreset.vegetation(), converted with MapScale) lies over the map; every cell holds at most
## one clump, a pure function of (seed, cell) and the map textures:
##
## - where a clump may stand is the shrubs' ground question (ShrubRules.habitat_at): nothing on
##   keep-off texels (road / river ribbons with clearance, bridges, built-up land, open water),
##   nothing inside a crop parcel (its edge strip and the balks do carry grass), nothing in the
##   forest interior; none in water or on the shore band, none on slopes above
##   GrassPlanner.MAX_SLOPE (the lattice triangle's slope);
## - the density is the cell's chance per habitat (HABITAT_CHANCE), thinned by the bare dirt
##   patches of the meadow look (bare_thinning x a patch noise);
## - the kind and height follow the old GrassPlanner ranges (LookPreset.meadow(): tall patches by
##   a noise, dry stalks by the dry noise, nettle on forest edges, reeds on banks, flower clusters
##   on open meadow); a flower takes the place of a clump with the old planner's flower share.
##
## No random number generator, no GameState.rng: the same cell gives the same clump in any order
## and at any MapScale (the noise wavelengths are metres). Cosmetic only. The colour is the
## shader's (tint, dry share and kind are here, the ground colour is the terrain's).
## The shader does the same with the same constants (tests/unit/test_grass_rules.gd compares them);
## the tables are passed as uniforms by bind().

## GrassPlanner.Kind (SHORT .. REED) and the flower.
enum Kind { SHORT, TALL, DRY_STALK, NETTLE, REED, FLOWER }

const KIND_COUNT := 6
const POINT_SALT := 0x6A01
const VALUE_SALT := 0x6A02
const GROUP_SALT := 0x6A03
## Salts of the value noises (VegetationHash.value_noise, one octave pair each).
const PATCH_SALT := 0x6A11
const DRY_SALT := 0x6A12
const BARE_SALT := 0x6A13
const FLOWER_SALT := 0x6A14
## unit() parts of the value hash.
const PART_CHANCE := 0
const PART_KIND := 1
const PART_TALL := 2
const PART_SCALE := 3
const PART_YAW := 4
const PART_TINT := 5
const PART_REED := 6
const PART_FLOWER := 7
const PART_FLOWER_HEIGHT := 8
const PART_FLOWER_ROLL := 9
const PART_FADE := 10
const PART_PHASE := 11
const JITTER := 0.9
## Second octave of the two-octave noises: frequency factor and amplitude (TerrainNoise.fbm).
const OCTAVE_FREQUENCY := 2.03
const OCTAVE_AMPLITUDE := 0.5
## Dry macro noise frequency per world unit at the default MapScale (GroundNoise.macro_k) and the
## bare-patch noise's (GroundNoise.MOISTURE_FREQUENCY).
const DRY_FREQUENCY := 0.12
const BARE_FREQUENCY := GroundNoise.MOISTURE_FREQUENCY
## Most flower species groups of a meadow look (the shader's arrays).
const MAX_GROUPS := 8
## Chance of a cell to hold a clump, per ShrubRules.Habitat (NONE, forest edge, hedge, bank, heath,
## field edge, meadow): 156 cells per 100 m² at 0.8 m, so 110-156 clumps per 100 m² before the
## bare patches.
const HABITAT_CHANCE: Array[float] = [0.0, 0.7, 0.8, 1.0, 0.7, 0.9, 1.0]

## Grid spacing (world units).
var spacing := 1.0
var masks: VegetationMasks
## The ground question (habitat, crop interiors, keep-off): the shrubs' rules over the same masks.
var ground: ShrubRules

var _lattice := Callable()
var _lattice_origin := Vector2.ZERO
var _seed := 0
var _meadow: Dictionary = {}
var _patch_wavelength := 1.0
var _flower_wavelength := 1.0
var _dry_wavelength := 1.0
var _bare_wavelength := 1.0
var _flower_cell := 1.0
var _flower_share := 0.0
var _groups: Array = []


## The rules over `vegetation_masks`; `lattice` is Callable(x, z) -> float, the drawn lattice
## height (the shader's height texture) and `lattice_origin` its first vertex; `meadow` is
## LookPreset.meadow() (empty: the active one).
func _init(
	vegetation_masks: VegetationMasks,
	lattice: Callable,
	lattice_origin: Vector2,
	seed_value: int,
	parcels: ParcelMap = null,
	v: Dictionary = {},
	meadow: Dictionary = {}
) -> void:
	masks = vegetation_masks
	_lattice = lattice
	_lattice_origin = lattice_origin
	_seed = seed_value & 0xFFFFFFFF
	var values := v if not v.is_empty() else LookPreset.vegetation()
	_meadow = meadow if not meadow.is_empty() else LookPreset.meadow()
	spacing = MapScale.to_units(float(values["grass_cell_m"]))
	ground = ShrubRules.new(masks, lattice, seed_value, parcels, values)
	_patch_wavelength = _wavelength(float(_meadow["patch_frequency"]))
	_flower_wavelength = _wavelength(float(_meadow["flower_frequency"]))
	_dry_wavelength = _wavelength(DRY_FREQUENCY)
	_bare_wavelength = _wavelength(BARE_FREQUENCY)
	_flower_cell = MapScale.to_units(
		float(_meadow["flower_cell"]) * MapScale.DEFAULT_METRES_PER_UNIT
	)
	_groups = _meadow["flowers"]
	# The old planner drew FLOWER_CANDIDATES_PER_DENSITY x flower_density flower candidates against
	# CHUNK candidates of PLAINS_DENSITY clumps: a flower per clump candidate at this share.
	_flower_share = (
		0.0
		if _groups.is_empty()
		else float(_meadow["flower_density"]) / GrassPlanner.PLAINS_DENSITY
	)


## A noise wavelength in world units from a per-world-unit frequency of the default MapScale: the
## physical size stays when the scale changes.
static func _wavelength(frequency: float) -> float:
	return MapScale.to_units(MapScale.DEFAULT_METRES_PER_UNIT / frequency)


## Two-octave value noise in [0, 1] (the shape of TerrainNoise.fbm(…, 2)).
func fbm(p: Vector2, wavelength: float, salt: int) -> float:
	var a := VegetationHash.value_noise(_seed, p.x, p.y, wavelength, salt)
	var b := VegetationHash.value_noise(_seed, p.x, p.y, wavelength / OCTAVE_FREQUENCY, salt + 1)
	return (a + OCTAVE_AMPLITUDE * b) / (1.0 + OCTAVE_AMPLITUDE)


## The jittered point (world XZ) of a cell.
func point(cell: Vector2i) -> Vector2:
	var h := VegetationHash.cell_hash(_seed, cell, POINT_SALT)
	# Two unit values, not VegetationHash.point's 16-bit halves: the halves' GPU twin
	# (veg_point) placed every clump far off its cell on the D3D12 target (TASK-217b).
	return (
		(
			Vector2(cell)
			+ Vector2(0.5, 0.5)
			+ JITTER * Vector2(VegetationHash.unit(h, 0) - 0.5, VegetationHash.unit(h, 1) - 0.5)
		)
		* spacing
	)


## The cells whose centre lies in `rect` (a chunk's cells).
func cells_of(rect: Rect2) -> Rect2i:
	return VegetationHash.cells_of(rect, spacing)


## The clumps whose point lies in `rect` (end exclusive), in cell order.
func plan_rect(rect: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first := Vector2i((rect.position / spacing).floor()) - Vector2i.ONE
	var last := Vector2i((rect.end / spacing).ceil())
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			if not rect.has_point(point(Vector2i(i, j))):
				continue
			var clump := cell_clump(Vector2i(i, j))
			if not clump.is_empty():
				result.append(clump)
	return result


## Bare dirt patch share [0, 1] at `p` (the ground texture's dirt patches, GrassPlanner.bare_k).
func bare_k(p: Vector2) -> float:
	return TerrainNoise.smooth(
		TerrainSplat.DIRT_PATCH_FROM,
		TerrainSplat.DIRT_PATCH_TO,
		fbm(p, _bare_wavelength, BARE_SALT)
	)


## Dry-grass share [0, 1] at `p` (GrassPlanner.dry_k).
func dry_k(p: Vector2) -> float:
	return TerrainNoise.smooth(
		TerrainSplat.DRY_FROM, TerrainSplat.DRY_TO, fbm(p, _dry_wavelength, DRY_SALT)
	)


## Tall-grass share [0, 1] at `p` (GrassPlanner.tall_k without the hills factor: no hill tiles).
func tall_k(p: Vector2, in_edge: bool) -> float:
	var k := TerrainNoise.smooth(
		float(_meadow["tall_from"]),
		float(_meadow["tall_to"]),
		fbm(p, _patch_wavelength, PATCH_SALT)
	)
	if in_edge:
		k += float(_meadow["edge_tall_bonus"])
	return clampf(k, 0.0, 1.0)


## Flower cluster share [0, 1] at `p`: a flower takes a cell with this x the flower share.
func flower_k(p: Vector2) -> float:
	return TerrainNoise.smooth(
		float(_meadow["flower_from"]),
		float(_meadow["flower_to"]),
		fbm(p, _flower_wavelength, FLOWER_SALT)
	)


## The flower share of a clump candidate in a cluster of strength 1.
func flower_share() -> float:
	return _flower_share


## Steepness (rise per world unit) of the lattice triangle under `p`.
func lattice_slope(p: Vector2) -> float:
	var f := (p - _lattice_origin) / TerrainLattice.STEP
	var i := floori(f.x)
	var j := floori(f.y)
	var u := f.x - i
	var v := f.y - j
	var step := TerrainLattice.STEP
	var ha := _vertex(i, j)
	var hb := _vertex(i + 1, j)
	var hc := _vertex(i, j + 1)
	var gradient: Vector2
	if u + v <= 1.0:
		gradient = Vector2(hb - ha, hc - ha)
	else:
		var hd := _vertex(i + 1, j + 1)
		gradient = Vector2(hd - hc, hd - hb)
	return gradient.length() / step


func _vertex(i: int, j: int) -> float:
	var step := TerrainLattice.STEP
	return _lattice.call(_lattice_origin.x + i * step, _lattice_origin.y + j * step)


## The flower species group a flower at `p` has (a roll in [0, 1) from its hash): the cluster
## cell's own group, the 1 - flower_dominance rest picks freely (GrassPlanner.plan_flowers).
func flower_group(p: Vector2, roll: float) -> int:
	var cell := Vector2i((p / _flower_cell).floor())
	var own := VegetationHash.unit(VegetationHash.cell_hash(_seed, cell, GROUP_SALT), 0)
	var dominance := float(_meadow["flower_dominance"])
	if roll >= dominance:
		return pick_group((roll - dominance) / (1.0 - dominance))
	return pick_group(own)


## Index of the species group whose cumulative share contains `roll` in [0, 1).
func pick_group(roll: float) -> int:
	var acc := 0.0
	for i in _groups.size():
		acc += float((_groups[i] as Dictionary)["share"])
		if roll < acc:
			return i
	return _groups.size() - 1


## The clump of a grid cell, {} when it holds none: {cell, position (world, y: lattice height),
## habitat, kind (Kind), height (vertical multiplier), scale, yaw, tint, dry, phase, group,
## flower_color (sRGB, flowers only)}. Thread-safe.
func cell_clump(cell: Vector2i) -> Dictionary:
	var p := point(cell)
	if not masks.area.has_point(p):
		return {}
	var habitat := ground.habitat_at(p)
	if habitat == ShrubRules.Habitat.NONE:
		return {}
	var h := VegetationHash.cell_hash(_seed, cell, VALUE_SALT)
	var bare := bare_k(p)
	var keep: float = HABITAT_CHANCE[habitat]
	keep *= 1.0 - float(_meadow["bare_thinning"]) * bare
	if VegetationHash.unit(h, PART_CHANCE) >= keep:
		return {}
	var y: float = _lattice.call(p.x, p.y)
	if y <= TerrainSurface.WATER_SURFACE + GrassPlanner.SHORE_BAND:
		return {}
	if lattice_slope(p) > GrassPlanner.MAX_SLOPE:
		return {}
	var dry := dry_k(p)
	var kind := pick_kind(habitat, p, h, dry, bare)
	var group := -1
	var height := kind_height(kind, h)
	var flower_color := Color.WHITE
	if kind == Kind.FLOWER:
		group = flower_group(p, VegetationHash.unit(h, PART_FLOWER_ROLL))
		flower_color = (_groups[group] as Dictionary)["color"]
	return {
		"cell": cell,
		"position": Vector3(p.x, y, p.y),
		"habitat": habitat,
		"kind": kind,
		"height": height,
		"scale":
		GrassPlanner.SCALE_MIN + GrassPlanner.SCALE_RANGE * VegetationHash.unit(h, PART_SCALE),
		"yaw": VegetationHash.unit(h, PART_YAW) * TAU,
		"tint": VegetationHash.unit(h, PART_TINT),
		"dry": dry,
		"phase": VegetationHash.unit(h, PART_PHASE),
		"group": group,
		"flower_color": flower_color,
	}


## The kind of the clump of a cell with value hash `h` (GrassPlanner.pick_kind's order): reeds on
## banks, flowers in clusters on open meadow, dry stalks, nettle on forest edges, tall patches,
## otherwise short.
func pick_kind(habitat: int, p: Vector2, h: int, dry: float, bare: float) -> Kind:
	var in_edge := habitat == ShrubRules.Habitat.FOREST_EDGE
	if habitat == ShrubRules.Habitat.BANK:
		if VegetationHash.unit(h, PART_REED) < float(_meadow["bank_reeds"]):
			return Kind.REED
	elif habitat == ShrubRules.Habitat.MEADOW and bare < 0.5 and _flower_share > 0.0:
		if VegetationHash.unit(h, PART_FLOWER) < _flower_share * flower_k(p):
			return Kind.FLOWER
	var roll := VegetationHash.unit(h, PART_KIND)
	if roll < dry * float(_meadow["dry_stalk_share"]):
		return Kind.DRY_STALK
	if in_edge and roll >= 1.0 - float(_meadow["nettle_share"]):
		return Kind.NETTLE
	if VegetationHash.unit(h, PART_TALL) < tall_k(p, in_edge):
		return Kind.TALL
	return Kind.SHORT


## Vertical multiplier of a clump kind (GrassPlanner.kind_height; a flower's from its own roll).
func kind_height(kind: int, h: int) -> float:
	if kind == Kind.FLOWER:
		var range_k: Vector2 = _meadow["flower_height"]
		return lerpf(range_k.x, range_k.y, VegetationHash.unit(h, PART_FLOWER_HEIGHT))
	return GrassPlanner.kind_height(kind, _meadow)


## The shader inputs of the rules (grass_rules.gdshaderinc): the shrub ground rules, then the
## grass seed, grid, noises, and the kind / flower tables.
func bind(material: ShaderMaterial) -> void:
	ground.bind(material)
	material.set_shader_parameter(&"grass_seed", _seed)
	material.set_shader_parameter(&"grass_spacing", spacing)
	material.set_shader_parameter(&"patch_wavelength", _patch_wavelength)
	material.set_shader_parameter(&"flower_wavelength", _flower_wavelength)
	material.set_shader_parameter(&"dry_wavelength", _dry_wavelength)
	material.set_shader_parameter(&"bare_wavelength", _bare_wavelength)
	material.set_shader_parameter(&"flower_cell", _flower_cell)
	material.set_shader_parameter(&"flower_share", _flower_share)
	material.set_shader_parameter(&"max_slope", GrassPlanner.MAX_SLOPE)
	material.set_shader_parameter(
		&"shore_height", TerrainSurface.WATER_SURFACE + GrassPlanner.SHORE_BAND
	)
	material.set_shader_parameter(&"grass_chance", PackedFloat32Array(HABITAT_CHANCE))
	var meadow := _meadow
	material.set_shader_parameter(&"bare_thinning", float(meadow["bare_thinning"]))
	material.set_shader_parameter(&"dry_stalk_share", float(meadow["dry_stalk_share"]))
	material.set_shader_parameter(&"nettle_share", float(meadow["nettle_share"]))
	material.set_shader_parameter(
		&"tall_range", Vector2(float(meadow["tall_from"]), float(meadow["tall_to"]))
	)
	material.set_shader_parameter(&"edge_tall_bonus", float(meadow["edge_tall_bonus"]))
	material.set_shader_parameter(&"bank_reeds", float(meadow["bank_reeds"]))
	material.set_shader_parameter(
		&"flower_range", Vector2(float(meadow["flower_from"]), float(meadow["flower_to"]))
	)
	material.set_shader_parameter(&"flower_dominance", float(meadow["flower_dominance"]))
	var heights := PackedFloat32Array()
	for kind in KIND_COUNT:
		heights.append(GrassPlanner.kind_height(kind, meadow))
	material.set_shader_parameter(&"kind_height", heights)
	material.set_shader_parameter(&"flower_height", meadow["flower_height"])
	var cumulative := PackedFloat32Array()
	var colours := PackedVector3Array()
	var acc := 0.0
	for g: Dictionary in _groups:
		acc += float(g["share"])
		cumulative.append(acc)
		var c := (g["color"] as Color).srgb_to_linear()
		colours.append(Vector3(c.r, c.g, c.b))
	var count := _groups.size()
	while cumulative.size() < MAX_GROUPS:
		cumulative.append(2.0)
		colours.append(Vector3.ONE)
	material.set_shader_parameter(&"flower_cumulative", cumulative)
	material.set_shader_parameter(&"flower_colors", colours)
	material.set_shader_parameter(&"flower_count", count)
	# Kind colours (linear): the colour a kind's mix pulls the ground colour towards.
	var targets := PackedVector3Array()
	var mixes := PackedFloat32Array()
	for kind in KIND_COUNT:
		var key := ["", "tall", "dry_stalk", "nettle", "reed", ""][kind] as String
		var target := Color.WHITE
		var mix_k := 0.0
		if key != "":
			target = (meadow[key + "_color"] as Color).srgb_to_linear()
			mix_k = float(meadow[key + "_mix"])
		targets.append(Vector3(target.r, target.g, target.b))
		mixes.append(mix_k)
	material.set_shader_parameter(&"kind_target", targets)
	material.set_shader_parameter(&"kind_mix", mixes)
	var reed_dry := (meadow["reed_dry_color"] as Color).srgb_to_linear()
	material.set_shader_parameter(&"reed_dry", Vector3(reed_dry.r, reed_dry.g, reed_dry.b))
