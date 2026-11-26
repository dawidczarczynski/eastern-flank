class_name VegetationMasks
extends RefCounted
## The map as textures for the GPU-placed vegetation layers (TASK-217a, ADR 0033): built once per
## map, at TEXEL_M metres per texel (converted with MapScale), over one world rectangle. Two L8
## images of the same layout:
##   habitat   a code per texel (Habitat): the land the plants grow on, and KEEP_OFF (255) where
##             nothing may stand – road and river ribbons with their clearance (bridges lie on
##             them), built-up land and open water. Painted in rising code order with max(), so
##             the stronger code wins where two overlap (keep-off over everything).
##   forest    the forest stand (ForestFill's mask: forest minus its clearings and ribbons),
##             box-blurred over ~FOREST_BLUR texels: 255 deep inside a forest, 0 far outside it,
##             in between within ~10 m of a forest edge or clearing.
## The shaders read the same texels as the GDScript references (ShrubRules), nearest filtering.
## The farmland parcels stay ParcelMap's own texture (the layers read it directly).
##
## Usage: VegetationMasks.from_map(grid, area, forest_fill, land_cover, parcels), or build(area,
## inputs) with synthetic inputs (tests). Pure and deterministic: the same inputs give the same
## bytes.

enum Habitat { MEADOW = 0, FIELD_EDGE = 1, HEATH = 2, BANK = 3, HEDGE = 4, KEEP_OFF = 255 }

## Flags on a habitat code (not on KEEP_OFF) from the land-cover raster: no real parcel
## (RealParcels, the parcel texel's blue > 0) lies here (CoverLook.allows_parcel: forest, water,
## villages, marsh), and no procedural strip parcel (only the FIELD cover carries them). The
## ParcelMap image itself is not clipped by the cover (ParcelMap.kind_at_metres does that per
## query), so the shrub rules read a crop texel only where the flag allows it.
const NO_REAL_PARCEL := 128
const NO_STRIP_PARCEL := 64
const CODE_MASK := 63

## Texel size in metres (the task's limit is 4.5 m).
const TEXEL_M := 4.0
## The forest stand is averaged over blocks of this many texels (mipmapped, then bilinear): the
## edge band reaches ~1-2 blocks' half width (8-16 m) to both sides of a forest edge.
const FOREST_BLUR := 4
## Bands beyond a ribbon's clearance: the roadside scrub strip and the river bank.
const ROADSIDE_M := 6.0
const BANK_M := 15.0

var area := Rect2()
## Texels per world unit.
var per_unit := 1.0
var size := Vector2i.ONE
var _habitat := PackedByteArray()
var _forest := PackedByteArray()
var _habitat_image: Image
var _forest_image: Image
var _textures: Array[ImageTexture] = []


## The masks of a map over `rect` (world units): ribbons from `grid`'s links, the forest stand of
## `fill` (or none), land cover from `land_cover` (a raster, or the hex types), hedges from
## `parcels` (the hedged balks of the strip parcels and the real parcels' hedge lines).
static func from_map(
	grid: HexGrid, rect: Rect2, fill: ForestFill, land_cover: LandCover, parcels: ParcelMap
) -> VegetationMasks:
	var inputs := {"grid": grid, "cover": land_cover}
	if fill != null:
		inputs["forest"] = fill.mask_image()
		inputs["forest_area"] = fill.area
	if grid != null and grid.has_links():
		for kind: FeatureRibbonPlanner.Kind in [
			FeatureRibbonPlanner.Kind.ROAD, FeatureRibbonPlanner.Kind.RIVER
		]:
			var lines := FeatureRibbonPlanner.lines(grid, kind)
			var halves := FeatureRibbonPlanner.half_widths(grid, kind)
			var list: Array = []
			for n in lines.size():
				list.append([lines[n], halves[n]])
			inputs["roads" if kind == FeatureRibbonPlanner.Kind.ROAD else "rivers"] = list
	if parcels != null:
		inputs["hedges"] = hedge_lines(parcels, rect)
	return build(rect, inputs)


## The masks over `rect` from raw inputs (all optional):
##   "forest": Image (L8, 255 = forest stands) over "forest_area": Rect2;
##   "cover": LandCover (a raster; without one, "grid"'s hex types: URBAN / WATER keep-off,
##            MARSH bank);
##   "roads", "rivers": Array of [PackedVector2Array line, PackedFloat32Array half widths]
##            (world units, FeatureRibbonPlanner.lines / half_widths);
##   "hedges": Array[PackedVector2Array] (world units);
##   "clearance": world units kept off beyond a ribbon's half width (FeatureRibbonPlanner).
static func build(rect: Rect2, inputs: Dictionary) -> VegetationMasks:
	var masks := VegetationMasks.new()
	masks._build(rect, inputs)
	return masks


func _build(rect: Rect2, inputs: Dictionary) -> void:
	area = rect
	per_unit = MapScale.metres_per_unit / TEXEL_M
	size = ForestMaskSource.mask_size(area, per_unit)
	_habitat = _cover_codes(inputs.get("cover"), inputs.get("grid"))
	var clearance: float = inputs.get(
		"clearance", FeatureRibbonPlanner.clearance(FeatureRibbonPlanner.Kind.ROAD)
	)
	var roadside := MapScale.to_units(ROADSIDE_M)
	var bank := MapScale.to_units(BANK_M)
	var half_texel := 0.5 / per_unit
	# A hedge is one texel wide on average (texel centres within half a texel of the line); the
	# line moves by a small odd fraction of a texel so that a line on a texel border never ties.
	var tie_break := Vector2(0.0131, 0.0173) / per_unit
	for line: PackedVector2Array in inputs.get("hedges", []):
		var moved := PackedVector2Array()
		for p in line:
			moved.append(p + tie_break)
		var widths := PackedFloat32Array()
		widths.resize(line.size())
		_paint_line(moved, widths, half_texel, Habitat.HEDGE, 0.0, Habitat.MEADOW)
	for entry: Array in inputs.get("roads", []):
		_paint_line(
			entry[0],
			entry[1],
			clearance,
			Habitat.KEEP_OFF,
			clearance + roadside,
			Habitat.FIELD_EDGE
		)
	for entry: Array in inputs.get("rivers", []):
		_paint_line(entry[0], entry[1], clearance, Habitat.KEEP_OFF, clearance + bank, Habitat.BANK)
	_habitat_image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, _habitat)
	_forest_image = _forest_blur(inputs.get("forest"), inputs.get("forest_area", Rect2()))
	_forest = _forest_image.get_data()


## The land-cover codes of every texel: URBAN / WATER keep-off, MARSH bank, SCRUB / BARE heath,
## the rest meadow. A raster is resized (nearest) onto the texels; without one, the hex types.
func _cover_codes(cover: LandCover, grid: HexGrid) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y)
	if cover != null and cover.has_raster():
		var cells := cover.cells()
		var codes := PackedByteArray()
		codes.resize(cells.size())
		var table := _cover_table()
		for k in cells.size():
			codes[k] = table[cells[k]]
		var raster := Image.create_from_data(
			cover.width, cover.height, false, Image.FORMAT_L8, codes
		)
		var world := cover.world_rect()
		var target := Vector2i(
			maxi(1, roundi(world.size.x * per_unit)), maxi(1, roundi(world.size.y * per_unit))
		)
		raster.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
		var base := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, bytes)
		var at := Vector2i(((world.position - area.position) * per_unit).round())
		base.blit_rect(raster, Rect2i(Vector2i.ZERO, target), at)
		return base.get_data()
	if grid == null:
		return bytes
	var r := TerrainField.HEX_SIZE
	for c in grid.coords():
		var code := 0
		match grid.get_terrain(c):
			Terrain.Type.URBAN, Terrain.Type.WATER:
				code = Habitat.KEEP_OFF
			Terrain.Type.MARSH:
				code = Habitat.BANK
		if code != 0:
			var w := Hex.to_world(c, r)
			_fill_hex(bytes, Vector2(w.x, w.z), r, code)
	return bytes


## `code` painted over the texel byte `old`: KEEP_OFF wins, else the larger code, the flags kept.
static func paint(old: int, code: int) -> int:
	if old == Habitat.KEEP_OFF or code == Habitat.KEEP_OFF:
		return Habitat.KEEP_OFF
	return (old & ~CODE_MASK) | maxi(old & CODE_MASK, code)


## The habitat code of a texel byte (without its flags).
static func code_of(value: int) -> int:
	return value if value == Habitat.KEEP_OFF else value & CODE_MASK


## LandCover.Kind -> habitat code and parcel flags (256 entries, unknown kinds meadow).
static func _cover_table() -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(256)
	for kind in LandCover.KIND_COUNT:
		var flags := 0
		if (CoverLook.PARCEL_KINDS_MASK & (1 << kind)) == 0:
			flags |= NO_REAL_PARCEL
		if kind != LandCover.Kind.FIELD:
			flags |= NO_STRIP_PARCEL
		table[kind] = flags
	table[LandCover.Kind.URBAN] = Habitat.KEEP_OFF
	table[LandCover.Kind.WATER] = Habitat.KEEP_OFF
	table[LandCover.Kind.MARSH] |= Habitat.BANK
	table[LandCover.Kind.SCRUB] |= Habitat.HEATH
	table[LandCover.Kind.BARE] |= Habitat.HEATH
	return table


## Writes `code` into the texels whose centre lies in the pointy-top hex at `centre` (size r).
func _fill_hex(bytes: PackedByteArray, centre: Vector2, r: float, code: int) -> void:
	var z0 := maxi(0, ceili((centre.y - r - area.position.y) * per_unit - 0.5))
	var z1 := mini(size.y - 1, floori((centre.y + r - area.position.y) * per_unit - 0.5))
	for pz in range(z0, z1 + 1):
		var dz := absf(area.position.y + (pz + 0.5) / per_unit - centre.y)
		var half := Hex.SQRT3 * 0.5 * r if dz <= r * 0.5 else Hex.SQRT3 * (r - dz)
		var x0 := maxi(0, ceili((centre.x - half - area.position.x) * per_unit - 0.5))
		var x1 := mini(size.x - 1, floori((centre.x + half - area.position.x) * per_unit - 0.5))
		for px in range(x0, x1 + 1):
			bytes[pz * size.x + px] = paint(bytes[pz * size.x + px], code)


## Paints a polyline with per-point half widths: texels whose centre lies within half width +
## `inner` of it get `inner_code`, within half width + `outer` (if larger) `outer_code` (max()).
func _paint_line(
	line: PackedVector2Array,
	halves: PackedFloat32Array,
	inner: float,
	inner_code: int,
	outer: float,
	outer_code: int
) -> void:
	for k in line.size() - 1:
		var half := maxf(halves[k], halves[k + 1]) if halves.size() > k + 1 else 0.0
		var near := half + inner
		var far := maxf(near, half + outer)
		_paint_segment(line[k], line[k + 1], near, inner_code, far, outer_code)


func _paint_segment(
	a: Vector2, b: Vector2, near: float, near_code: int, far: float, far_code: int
) -> void:
	var lo := ((a.min(b) - Vector2.ONE * far - area.position) * per_unit).floor()
	var hi := ((a.max(b) + Vector2.ONE * far - area.position) * per_unit).ceil()
	var x0 := maxi(int(lo.x), 0)
	var z0 := maxi(int(lo.y), 0)
	var x1 := mini(int(hi.x), size.x - 1)
	var z1 := mini(int(hi.y), size.y - 1)
	var ab := b - a
	var length_squared := ab.length_squared()
	var near_squared := near * near
	var far_squared := far * far
	for pz in range(z0, z1 + 1):
		var cz := area.position.y + (pz + 0.5) / per_unit
		var row := pz * size.x
		for px in range(x0, x1 + 1):
			var c := Vector2(area.position.x + (px + 0.5) / per_unit, cz)
			var t := 0.0
			if length_squared > 0.0:
				t = clampf((c - a).dot(ab) / length_squared, 0.0, 1.0)
			var d := c.distance_squared_to(a + ab * t)
			if d < near_squared:
				_habitat[row + px] = paint(_habitat[row + px], near_code)
			elif d < far_squared:
				_habitat[row + px] = paint(_habitat[row + px], far_code)


## The forest stand on the texels (nearest), averaged over FOREST_BLUR-texel blocks and
## stretched back bilinearly; all 0 without a forest image.
func _forest_blur(forest: Image, forest_area: Rect2) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	if forest == null or not forest_area.has_area():
		return image
	var target := Vector2i(
		maxi(1, roundi(forest_area.size.x * per_unit)),
		maxi(1, roundi(forest_area.size.y * per_unit))
	)
	var stand := forest.duplicate() as Image
	if stand.get_format() != Image.FORMAT_L8:
		stand.convert(Image.FORMAT_L8)
	stand.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	var at := Vector2i(((forest_area.position - area.position) * per_unit).round())
	image.blit_rect(stand, Rect2i(Vector2i.ZERO, target), at)
	var coarse := Vector2i(maxi(1, size.x / FOREST_BLUR), maxi(1, size.y / FOREST_BLUR))
	image.resize(coarse.x, coarse.y, Image.INTERPOLATE_TRILINEAR)
	image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return image


## The procedural strip parcels' hedges over `rect` (world units) as 40 m pieces at the balk
## centre line, where ScatterPlanner.plan_hedges planted its hedge items (same parcel and gap
## hashes: a hedge stands where the CPU hedge stood), plus the real parcels' hedge lines.
static func hedge_lines(parcels: ParcelMap, rect: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var scale_m := MapScale.metres_per_unit
	for line: PackedVector2Array in parcels.hedge_lines():
		var units := PackedVector2Array()
		for p in line:
			units.append(p / scale_m)
		result.append(units)
	var size_m := Vector2(parcels.size_px()) * parcels.metres_per_pixel
	var bounds := Rect2(parcels.origin_m, size_m)
	var within := Rect2(rect.position * scale_m, rect.size * scale_m)
	if not bounds.intersects(within):
		return result
	bounds = bounds.intersection(within)
	var step := ScatterPlanner.HEDGE_STEP_M
	var first := Vector2i((bounds.position / FieldParcels.BLOCK_M).floor())
	var last := Vector2i((bounds.end / FieldParcels.BLOCK_M).floor())
	for bx in range(first.x, last.x + 1):
		for bz in range(first.y, last.y + 1):
			for parcel: Dictionary in FieldParcels.parcels_of_block(bx, bz):
				var key: int = parcel["key"]
				var box: Rect2 = parcel["rect"]
				if (
					not box.intersects(bounds)
					or FieldParcels.unit_hash(key, 11, 0, 0) >= ScatterPlanner.HEDGE_CHANCE
				):
					continue
				var along_x: bool = parcel["along_x"]
				var v0 := box.position.x if along_x else box.position.y
				var v1 := box.end.x if along_x else box.end.y
				var across := (
					(box.position.y if along_x else box.position.x) + 0.5 * FieldParcels.BALK_M
				)
				for i in floori((v1 - v0) / step):
					if FieldParcels.unit_hash(key, 12, i, 3) < ScatterPlanner.HEDGE_GAP_CHANCE:
						continue
					var mid := v0 + (i + 0.5) * step
					var mx := mid if along_x else across
					var mz := across if along_x else mid
					if (
						parcels.kind_at_metres(mx, mz) != FieldParcels.Kind.BALK
						or parcels.is_real_at_metres(mx, mz)
					):
						continue
					var a := v0 + i * step
					var b := a + step
					var piece := PackedVector2Array()
					if along_x:
						piece.append(Vector2(a, across) / scale_m)
						piece.append(Vector2(b, across) / scale_m)
					else:
						piece.append(Vector2(across, a) / scale_m)
						piece.append(Vector2(across, b) / scale_m)
					result.append(piece)
	return result


## Habitat code at world (x, z) (KEEP_OFF outside the area), without the parcel flags.
func habitat_at(x: float, z: float) -> int:
	return code_of(texel_byte(x, z))


## The texel byte at world (x, z): habitat code and parcel flags (KEEP_OFF outside the area).
func texel_byte(x: float, z: float) -> int:
	var t := texel(x, z)
	if t.x < 0:
		return Habitat.KEEP_OFF
	return _habitat[t.y * size.x + t.x]


## Blurred forest stand (0-255) at world (x, z) (0 outside the area).
func forest_at(x: float, z: float) -> int:
	var t := texel(x, z)
	if t.x < 0:
		return 0
	return _forest[t.y * size.x + t.x]


## The texel of world (x, z), or (-1, -1) outside the area (as the shaders floor it).
func texel(x: float, z: float) -> Vector2i:
	var px := floori((x - area.position.x) * per_unit)
	var pz := floori((z - area.position.y) * per_unit)
	if px < 0 or pz < 0 or px >= size.x or pz >= size.y:
		return Vector2i(-1, -1)
	return Vector2i(px, pz)


## Whether any texel over `rect` (world units) carries habitat `code`.
func has_code(rect: Rect2, code: int) -> bool:
	var lo := Vector2i(((rect.position - area.position) * per_unit).floor()).max(Vector2i.ZERO)
	var hi := Vector2i(((rect.end - area.position) * per_unit).ceil()).min(size)
	if hi.x <= lo.x or hi.y <= lo.y:
		return false
	var bytes := _habitat_image.get_region(Rect2i(lo, hi - lo)).get_data()
	for flags: int in [0, NO_STRIP_PARCEL, NO_REAL_PARCEL, NO_STRIP_PARCEL | NO_REAL_PARCEL]:
		if bytes.has(code | flags):
			return true
	return false


## Metres per texel at the current MapScale.
func texel_m() -> float:
	return MapScale.metres_per_unit / per_unit


func habitat_image() -> Image:
	return _habitat_image


func forest_image() -> Image:
	return _forest_image


## The shader inputs: both textures, the area and the texel scale (main thread).
func bind(material: ShaderMaterial) -> void:
	if _textures.is_empty():
		_textures = [
			ImageTexture.create_from_image(_habitat_image),
			ImageTexture.create_from_image(_forest_image)
		]
	material.set_shader_parameter(&"habitat", _textures[0])
	material.set_shader_parameter(&"forest_edge", _textures[1])
	material.set_shader_parameter(
		&"mask_area", Vector4(area.position.x, area.position.y, area.end.x, area.end.y)
	)
	material.set_shader_parameter(&"mask_per_unit", per_unit)
