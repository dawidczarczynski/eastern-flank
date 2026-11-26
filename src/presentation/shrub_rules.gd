class_name ShrubRules
extends RefCounted
## Where the shrubs of the real-scale countryside grow (TASK-217a, ADR 0033; `true` VisualScale
## preset only): the GDScript reference of the GPU-placed shrub layer (ShrubField,
## assets/shaders/shrub_rules.gdshaderinc). A jittered grid of `shrub_cell_m` cells (metres,
## LookPreset.vegetation(), converted with MapScale) lies over the map; every cell holds at most
## one shrub, a pure function of (seed, cell) and the map textures (VegetationMasks, ParcelMap,
## the drawn lattice height):
##
## - nothing on KEEP_OFF texels (road / river ribbons with their clearance, bridges, built-up land,
##   open water), in water, or inside a crop parcel – but on its edge strip (within
##   PARCEL_STRIP_M of a texel that is not crop) and on the balks;
## - the habitat picks the chance and the kind mix (HABITAT_CHANCE, KIND_SHARES): forest edges and
##   clearings (the blurred forest stand between EDGE_FROM and EDGE_TO; none deeper inside),
##   hedges, river and marsh banks, heath (SCRUB / BARE land cover, noise-driven), field edges
##   (parcel strips, balks, roadsides) and sparse noise-driven scrub on the open meadow;
## - four kinds, each its own colour, silhouette (the source model of KIND_SOURCE) and height
##   range in metres (KIND_HEIGHT_M): low bush, hazel / blackthorn, juniper, willow.
##
## No random number generator, no GameState.rng: the same cell gives the same shrub in any order
## and at any MapScale (heights and the grid are metres). Cosmetic only.
## The shader does the same with the same constants (tests/unit/test_shrub_rules.gd compares
## them); the tables (chances, shares, heights, colours) are passed as uniforms by bind().

enum Kind { LOW_BUSH, HAZEL, JUNIPER, WILLOW }
enum Habitat { NONE, FOREST_EDGE, HEDGE, BANK, HEATH, FIELD_EDGE, MEADOW }

const KIND_COUNT := 4
const HABITAT_COUNT := 7
const POINT_SALT := 0x5B01
const VALUE_SALT := 0x5B02
const NOISE_SALT := 0x5B03
const VARIANT_SALT := 0x5B04
## unit() parts of the value hash.
const PART_CHANCE := 0
const PART_KIND := 1
const PART_HEIGHT := 2
const PART_WIDTH := 3
const PART_YAW := 4
const PART_HUE := 5
const PART_VALUE := 6
const PART_PHASE := 7
const JITTER := 0.8
## Blurred forest stand (0-255): from EDGE_FROM to below EDGE_TO a forest edge or clearing, from
## EDGE_TO on the forest interior (no shrubs).
const EDGE_FROM := 8
const EDGE_TO := 247
## A crop texel within this many metres of a texel that is not crop is the parcel's edge strip.
const PARCEL_STRIP_M := 3.0
## ParcelMap kinds: NONE, the meadow parcel and the balk; every other kind is a crop.
const PARCEL_NONE := 0
const PARCEL_MEADOW := 7
const PARCEL_BALK := 8
## What _crop_at finds.
const CROP_NONE := 0
const CROP_FIELD := 1
const CROP_BALK := 2
## Scrub noise wavelength (metres) and its use: heath chance x (HEATH_NOISE_MIN + HEATH_NOISE_SPAN
## x noise); meadow chance x smoothstep(MEADOW_NOISE_FROM, MEADOW_NOISE_TO, noise).
const NOISE_WAVELENGTH_M := 50.0
const HEATH_NOISE_MIN := 0.2
const HEATH_NOISE_SPAN := 1.6
const MEADOW_NOISE_FROM := 0.55
const MEADOW_NOISE_TO := 0.85
## Chance of a cell (2.5 m, 1 600 per ha) to hold a shrub, per Habitat: forest edge ~225 / ha,
## hedge ~1 per 2 m of line (the hedge band is one 4 m texel wide), bank ~140 / ha, heath ~80 / ha
## on average, field edge ~130 / ha, meadow at most ~14 / ha inside a scrub patch.
const HABITAT_CHANCE: Array[float] = [0.0, 0.14, 0.78, 0.0875, 0.05, 0.08, 0.009]
## Kind shares per Habitat (low bush, hazel / blackthorn, juniper, willow). Junipers grow on the
## heath only (ShrubField draws the juniper model only in near chunks with heath).
const KIND_SHARES: Array[Vector4] = [
	Vector4(1.0, 0.0, 0.0, 0.0),
	Vector4(0.25, 0.65, 0.0, 0.10),
	Vector4(0.2, 0.75, 0.0, 0.05),
	Vector4(0.1, 0.1, 0.0, 0.8),
	Vector4(0.25, 0.05, 0.7, 0.0),
	Vector4(0.45, 0.5, 0.0, 0.05),
	Vector4(0.6, 0.35, 0.0, 0.05),
]
## Height range (metres) per Kind.
const KIND_HEIGHT_M: Array[Vector2] = [
	Vector2(0.5, 1.0), Vector2(1.5, 3.0), Vector2(0.8, 1.5), Vector2(2.0, 3.0)
]
## Crown width over height per Kind (x 0.85-1.15 per shrub): spreading low bushes, upright
## hazels, columnar junipers, broad willows.
const KIND_WIDTH_SHARE: Array[float] = [1.3, 0.85, 0.42, 1.15]
## The model (TreeMeshes species) each Kind is drawn with, and its index in SOURCES.
const SOURCES: Array[StringName] = [&"undergrowth", &"shrub", &"spruce"]
const KIND_SOURCE: Array[int] = [0, 1, 2, 1]
## Leaf colour (sRGB) per Kind: fresh low bushes, dark hazel / blackthorn, blue-green juniper,
## silvery willow.
const KIND_COLORS: Array[Color] = [
	Color("#5f7a38"), Color("#43602b"), Color("#3a5642"), Color("#7b9163")
]
## Colour variation per shrub (as TreeSpecies).
const HUE_SHIFT := 0.03
const VALUE_MIN := 0.85
const VALUE_MAX := 1.1

## Grid spacing (world units).
var spacing := 1.0
var masks: VegetationMasks

var _lattice := Callable()
var _seed := 0
var _parcels: ParcelMap
var _parcel_bytes := PackedByteArray()
var _parcel_size := Vector2i.ZERO
var _parcel_stride := 1
var _noise_wavelength := 1.0
var _strip := 0.0
var _near_chunk := 1.0


## The rules over `vegetation_masks` (its area is where shrubs may stand); `lattice` is
## Callable(x, z) -> float, the drawn lattice height (MapView.mesh_height_at; the shader's height
## texture); `near_chunk` the mesh layer's chunk size (the model variant is one per near chunk).
func _init(
	vegetation_masks: VegetationMasks,
	lattice: Callable,
	seed_value: int,
	parcels: ParcelMap = null,
	v: Dictionary = {},
	near_chunk: float = 0.25
) -> void:
	masks = vegetation_masks
	_lattice = lattice
	_seed = seed_value & 0xFFFFFFFF
	_parcels = parcels
	var values := v if not v.is_empty() else LookPreset.vegetation()
	spacing = MapScale.to_units(float(values["shrub_cell_m"]))
	_noise_wavelength = MapScale.to_units(NOISE_WAVELENGTH_M)
	_strip = MapScale.to_units(PARCEL_STRIP_M)
	_near_chunk = near_chunk
	if parcels != null:
		_parcel_bytes = parcels.image.get_data()
		_parcel_size = parcels.size_px()
		_parcel_stride = maxi(1, _parcel_bytes.size() / maxi(1, _parcel_size.x * _parcel_size.y))


## The jittered point (world XZ) of a cell.
func point(cell: Vector2i) -> Vector2:
	var h := VegetationHash.cell_hash(_seed, cell, POINT_SALT)
	return VegetationHash.point(h, cell, spacing, JITTER)


## The cells whose centre lies in `rect` (a chunk's cells).
func cells_of(rect: Rect2) -> Rect2i:
	return VegetationHash.cells_of(rect, spacing)


## The shrubs whose point lies in `rect` (end exclusive), in cell order.
func plan_rect(rect: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first := Vector2i((rect.position / spacing).floor()) - Vector2i.ONE
	var last := Vector2i((rect.end / spacing).ceil())
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			var p := point(Vector2i(i, j))
			if not rect.has_point(p):
				continue
			var shrub := cell_shrub(Vector2i(i, j))
			if not shrub.is_empty():
				result.append(shrub)
	return result


## The habitat at world point `p` (Habitat.NONE where nothing may stand).
func habitat_at(p: Vector2) -> Habitat:
	var code := masks.habitat_at(p.x, p.y)
	if code == VegetationMasks.Habitat.KEEP_OFF:
		return Habitat.NONE
	var field_edge := _field_edge(p)
	if field_edge < 0:
		return Habitat.NONE
	var forest := masks.forest_at(p.x, p.y)
	if forest >= EDGE_TO:
		return Habitat.NONE
	if forest >= EDGE_FROM:
		return Habitat.FOREST_EDGE
	return _open_habitat(code, field_edge > 0)


## 1 on a balk or a crop parcel's edge strip (within PARCEL_STRIP_M of a point that is not
## crop), -1 inside a crop parcel, 0 off the parcels.
func _field_edge(p: Vector2) -> int:
	var parcel := _crop_at(p)
	if parcel == CROP_NONE:
		return 0
	if parcel == CROP_BALK:
		return 1
	var offsets: Array[Vector2] = [
		Vector2(_strip, 0.0), Vector2(-_strip, 0.0), Vector2(0.0, _strip), Vector2(0.0, -_strip)
	]
	for offset in offsets:
		if _crop_at(p + offset) != CROP_FIELD:
			return 1
	return -1


## What the parcels hold at `p`: a crop (CROP_FIELD), a balk, or nothing – unpainted, a meadow
## parcel, or a parcel texel where the land cover carries no parcel (VegetationMasks' flags: the
## raw ParcelMap image is not clipped by the cover).
func _crop_at(p: Vector2) -> int:
	if _parcels == null:
		return CROP_NONE
	var m := p * MapScale.metres_per_unit - _parcels.origin_m
	var q := Vector2i((m / _parcels.metres_per_pixel).floor())
	if q.x < 0 or q.y < 0 or q.x >= _parcel_size.x or q.y >= _parcel_size.y:
		return CROP_NONE
	var at := (q.y * _parcel_size.x + q.x) * _parcel_stride
	var kind := _parcel_bytes[at]
	if kind == PARCEL_NONE or kind == PARCEL_MEADOW:
		return CROP_NONE
	var real := _parcel_stride >= 3 and _parcel_bytes[at + 2] > 0
	var flag := VegetationMasks.NO_REAL_PARCEL if real else VegetationMasks.NO_STRIP_PARCEL
	if (masks.texel_byte(p.x, p.y) & flag) != 0:
		return CROP_NONE
	return CROP_BALK if kind == PARCEL_BALK else CROP_FIELD


## The habitat of open land (no forest edge) with mask `code`, `field_edge` on a parcel edge.
static func _open_habitat(code: int, field_edge: bool) -> Habitat:
	match code:
		VegetationMasks.Habitat.HEDGE:
			return Habitat.HEDGE
		VegetationMasks.Habitat.BANK:
			return Habitat.BANK
		VegetationMasks.Habitat.HEATH:
			return Habitat.HEATH
	var edge := field_edge or code == VegetationMasks.Habitat.FIELD_EDGE
	return Habitat.FIELD_EDGE if edge else Habitat.MEADOW


## The chance of a cell at `p` in `habitat` (the noise-driven ones vary over the map).
func chance(habitat: Habitat, p: Vector2) -> float:
	var base: float = HABITAT_CHANCE[habitat]
	if habitat == Habitat.HEATH or habitat == Habitat.MEADOW:
		var n := VegetationHash.value_noise(_seed, p.x, p.y, _noise_wavelength, NOISE_SALT)
		if habitat == Habitat.HEATH:
			return base * (HEATH_NOISE_MIN + HEATH_NOISE_SPAN * n)
		return base * smoothstep(MEADOW_NOISE_FROM, MEADOW_NOISE_TO, n)
	return base


## The shrub of a grid cell, {} when it holds none: {cell, position (world, y: lattice height),
## habitat, kind, height_m, width_m, height, width (world units), yaw, source (TreeMeshes
## species), variant, hue, value, phase}. Thread-safe.
func cell_shrub(cell: Vector2i) -> Dictionary:
	var p := point(cell)
	if not masks.area.has_point(p):
		return {}
	var habitat := habitat_at(p)
	if habitat == Habitat.NONE:
		return {}
	var h := VegetationHash.cell_hash(_seed, cell, VALUE_SALT)
	if VegetationHash.unit(h, PART_CHANCE) >= chance(habitat, p):
		return {}
	var y: float = _lattice.call(p.x, p.y)
	if y < ScatterPlanner.MIN_TREE_GROUND:
		return {}
	var kind := pick_kind(habitat, VegetationHash.unit(h, PART_KIND))
	var range_m: Vector2 = KIND_HEIGHT_M[kind]
	var height_m := lerpf(range_m.x, range_m.y, VegetationHash.unit(h, PART_HEIGHT))
	var width_m := (
		height_m * KIND_WIDTH_SHARE[kind] * (0.85 + 0.3 * VegetationHash.unit(h, PART_WIDTH))
	)
	return {
		"cell": cell,
		"position": Vector3(p.x, y, p.y),
		"habitat": habitat,
		"kind": kind,
		"height_m": height_m,
		"width_m": width_m,
		"height": MapScale.to_units(height_m),
		"width": MapScale.to_units(width_m),
		"yaw": VegetationHash.unit(h, PART_YAW) * TAU,
		"source": SOURCES[KIND_SOURCE[kind]],
		"variant": variant_of(cell),
		"hue": (VegetationHash.unit(h, PART_HUE) * 2.0 - 1.0) * HUE_SHIFT,
		"value": lerpf(VALUE_MIN, VALUE_MAX, VegetationHash.unit(h, PART_VALUE)),
		"phase": VegetationHash.unit(h, PART_PHASE),
	}


## The Kind a roll in [0, 1) picks in `habitat`.
static func pick_kind(habitat: Habitat, roll: float) -> Kind:
	var shares: Vector4 = KIND_SHARES[habitat]
	var acc := 0.0
	for k in KIND_COUNT - 1:
		acc += shares[k]
		if roll < acc:
			return k as Kind
	return Kind.WILLOW


## The model variant of a cell: one per near-layer chunk (one mesh per near chunk; the impostors
## pick the same atlas row).
func variant_of(cell: Vector2i) -> int:
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * spacing
	return chunk_variant(Vector2i((centre / _near_chunk).floor()))


## The model variant of a near-layer chunk.
func chunk_variant(chunk: Vector2i) -> int:
	var h := VegetationHash.cell_hash(_seed, chunk, VARIANT_SALT)
	return mini(int(VegetationHash.unit(h, 0) * TreeMeshes.VARIANTS), TreeMeshes.VARIANTS - 1)


## The shader inputs of the rules (shrub_rules.gdshaderinc): seed, grid, tables, masks, parcels.
func bind(material: ShaderMaterial) -> void:
	masks.bind(material)
	material.set_shader_parameter(&"shrub_seed", _seed)
	material.set_shader_parameter(&"spacing", spacing)
	material.set_shader_parameter(&"noise_wavelength", _noise_wavelength)
	material.set_shader_parameter(&"parcel_strip", _strip)
	material.set_shader_parameter(&"near_chunk", _near_chunk)
	material.set_shader_parameter(&"min_ground", ScatterPlanner.MIN_TREE_GROUND)
	material.set_shader_parameter(&"metres_per_unit", MapScale.metres_per_unit)
	var chances := PackedFloat32Array(HABITAT_CHANCE)
	material.set_shader_parameter(&"habitat_chance", chances)
	var shares := PackedVector4Array()
	for s in KIND_SHARES:
		shares.append(s)
	material.set_shader_parameter(&"kind_shares", shares)
	var heights := PackedVector2Array()
	for r in KIND_HEIGHT_M:
		heights.append(Vector2(MapScale.to_units(r.x), MapScale.to_units(r.y)))
	material.set_shader_parameter(&"kind_heights", heights)
	material.set_shader_parameter(&"kind_width_share", PackedFloat32Array(KIND_WIDTH_SHARE))
	var colors := PackedVector3Array()
	for c in KIND_COLORS:
		var linear := c.srgb_to_linear()
		colors.append(Vector3(linear.r, linear.g, linear.b))
	material.set_shader_parameter(&"kind_colors", colors)
	var has_parcels := _parcels != null
	material.set_shader_parameter(&"use_parcels", has_parcels)
	if has_parcels:
		material.set_shader_parameter(&"parcels", _parcels.texture())
		material.set_shader_parameter(&"parcel_origin_m", _parcels.origin_m)
		material.set_shader_parameter(&"parcel_metres_per_pixel", _parcels.metres_per_pixel)
