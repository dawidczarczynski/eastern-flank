class_name ParcelMap
extends RefCounted
## The baked farmland parcels of a map (TASK-108f, FieldParcels.bake): an RG8 image with the
## parcel kind (FieldParcels.Kind) in red and the row orientation / parcel id in green, covering
## a world rectangle at `metres_per_pixel`. The terrain shader samples it as a texture; the grass
## planner reads the kind per position. With a land-cover raster (TASK-108g, `look`) a parcel only
## shows inside the noisy outline of the FIELD cover: kind_at reads NONE elsewhere, and the shader
## cuts the crops along the same outline (TerrainGround.set_parcels, terrain.gdshader).
## With real parcels (TASK-215b, RealParcels.paint) the image is RGB8: blue > 0 marks a pixel of a
## real parcel or its balk (FieldParcels.angle_code: the row direction); such a pixel is masked by
## the land cover where it can carry no field (CoverLook.allows_parcel: forest, water, villages,
## marsh) instead of by the FIELD outline. Blue 0 (or RG8) is a procedural strip as before.

## Crop mask bits: nothing tall may stand (every parcel but balk / none), no tall grass (crops,
## not the meadow), and the block size in pixels.
const MASK_STANDING := 1
const MASK_GRASS := 2
const MASK_BLOCK := 64

var image: Image
## World position (x, z) in metres of the image's top-left corner.
var origin_m := Vector2.ZERO
var metres_per_pixel := 5.0
## The land-cover look whose FIELD cover clips the parcels, or null (the image is final).
var look: CoverLook
## The real parcels painted into the image (RealParcels), their crops and neighbour lists, or
## null / empty.
var real: RealParcels
var real_crops := PackedInt32Array()
var real_neighbours: Array[PackedInt32Array] = []
## The exact real parcel edges (RealParcels.edge_image, same size as `image`), or null.
var edges: Image
## The crop keep-off mask (TASK-217c; the `true` preset): when on, blocks_standing and
## blocks_tall_grass read per-pixel bytes built once per block of MASK_BLOCK pixels (from
## kind_at_metres at the pixel centres, so the cover clipping is baked in) instead of resolving the
## kind of every single plant. Off (`balanced`): the old per-point kind lookups.
var crop_mask_on := false
var _edges_texture: ImageTexture
var _texture: ImageTexture
var _mask_blocks: Dictionary = {}
var _mask_mutex := Mutex.new()


func size_px() -> Vector2i:
	return Vector2i(image.get_width(), image.get_height())


## Kind (FieldParcels.Kind, 0 = none) at world position (x, z) in metres; NONE outside the image.
func kind_at_metres(x_m: float, z_m: float) -> int:
	var px := floori((x_m - origin_m.x) / metres_per_pixel)
	var py := floori((z_m - origin_m.y) / metres_per_pixel)
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return 0  # FieldParcels.NONE
	var pixel := label_at_metres(x_m, z_m)
	var kind := roundi(pixel.r * 255.0)
	if kind != 0 and look != null:
		var m := MapScale.metres_per_unit
		if pixel.b > 0.0:
			if not look.allows_parcel(x_m / m, z_m / m):
				return 0
		elif not look.has_kind(LandCover.Kind.FIELD, x_m / m, z_m / m):
			return 0
	return kind


## Whether (x_m, z_m) metres lies on a real parcel or its balk (RealParcels).
func is_real_at_metres(x_m: float, z_m: float) -> bool:
	var px := floori((x_m - origin_m.x) / metres_per_pixel)
	var py := floori((z_m - origin_m.y) / metres_per_pixel)
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return false
	return label_at_metres(x_m, z_m).b > 0.0


## The parcel map's texel at (x_m, z_m) metres (inside the image) as the shader reads it
## (terrain.gdshader parcel_label, its twin): next to a real parcel edge (`edges`, the exact lines
## of RealParcels.edge_image) the label of the texel 1.5 texels beyond the edge line on the point's
## side, and BALK (blue at least 1) within the balk half width of a track / hedge edge; elsewhere
## the nearest texel.
func label_at_metres(x_m: float, z_m: float) -> Color:
	var p := Vector2(x_m, z_m) - origin_m
	var size := size_px()
	var texel := Vector2i((p / metres_per_pixel).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var pixel := image.get_pixel(texel.x, texel.y)
	if edges == null:
		return pixel
	var edge_mpp := metres_per_pixel * RealParcels.EDGE_TEXEL
	var e_size := Vector2i(edges.get_width(), edges.get_height())
	var et := Vector2i((p / edge_mpp).floor()).clamp(Vector2i.ZERO, e_size - Vector2i.ONE)
	var e := edges.get_pixel(et.x, et.y)
	var code := roundi(e.r * 255.0)
	if code == 0:
		return pixel
	var theta := FieldParcels.code_angle(code)
	var normal := Vector2(-sin(theta), cos(theta))
	var centre := (Vector2(et) + Vector2(0.5, 0.5)) * edge_mpp
	var d := (p - centre).dot(normal) + (e.g * 2.0 - 1.0) * RealParcels.EDGE_RANGE_M
	var side := 1.0 if d >= 0.0 else -1.0
	var q_m := p - normal * d + normal * side * 1.5 * metres_per_pixel
	var q := Vector2i((q_m / metres_per_pixel).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var label := image.get_pixel(q.x, q.y)
	if absf(d) < RealParcels.balk_half_m(roundi(e.b * 255.0)):
		label = Color(FieldParcels.Kind.BALK / 255.0, label.g, maxf(label.b, 1.0 / 255.0))
	return label


## The edges image as a texture (nearest, no mipmaps), or null.
func edges_texture() -> ImageTexture:
	if edges == null:
		return null
	if _edges_texture == null:
		_edges_texture = ImageTexture.create_from_image(edges)
	return _edges_texture


## Polylines (metres) along the real parcels' hedge edges, painted as BALK_M wide balks: the
## line TASK-199's hedges can follow. Empty without real parcels.
func hedge_lines() -> Array[PackedVector2Array]:
	if real == null:
		return []
	return real.hedge_lines


## Whether trees, bushes, rocks and thickets are kept off world position (x, z) (world units):
## on every parcel kind except the balk (hedgerow strip) and unpainted ground.
func blocks_standing(x: float, z: float) -> bool:
	if crop_mask_on:
		return (mask_at(x, z) & MASK_STANDING) != 0
	var kind := kind_at(x, z)
	return kind != 0 and kind != 8  # FieldParcels.Kind.NONE / BALK


## blocks_standing by the exact per-point kind, never the crop mask: for planners that ask about
## a few thousand items, where baking 64x64-pixel mask blocks (under one lock) costs far more than
## the lookups (TASK-222). Same answer as the mask away from pixel edges.
func blocks_standing_exact(x: float, z: float) -> bool:
	var kind := kind_at(x, z)
	return kind != 0 and kind != 8  # FieldParcels.Kind.NONE / BALK


## Whether tall grass is kept off (x, z): crop parcels, not meadows, balks or unpainted ground.
func blocks_tall_grass(x: float, z: float) -> bool:
	if crop_mask_on:
		return (mask_at(x, z) & MASK_GRASS) != 0
	var kind := kind_at(x, z)
	return kind != 0 and kind != 8 and kind != 7  # NONE / BALK / MEADOW


## The keep-off bits (MASK_STANDING, MASK_GRASS) of the crop mask at world position (x, z) in
## world units; 0 outside the image. Pure and thread-safe (blocks are built on first use).
func mask_at(x: float, z: float) -> int:
	var m := MapScale.metres_per_unit
	var px := floori((x * m - origin_m.x) / metres_per_pixel)
	var py := floori((z * m - origin_m.y) / metres_per_pixel)
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return 0
	var bx := px / MASK_BLOCK
	var by := py / MASK_BLOCK
	var key := by * 65536 + bx
	_mask_mutex.lock()
	var block: PackedByteArray = _mask_blocks.get(key, PackedByteArray())
	if block.is_empty():
		block = _build_mask_block(bx, by)
		_mask_blocks[key] = block
	_mask_mutex.unlock()
	return block[(py - by * MASK_BLOCK) * MASK_BLOCK + (px - bx * MASK_BLOCK)]


func _build_mask_block(bx: int, by: int) -> PackedByteArray:
	var block := PackedByteArray()
	block.resize(MASK_BLOCK * MASK_BLOCK)
	for j in MASK_BLOCK:
		for i in MASK_BLOCK:
			var x_m := origin_m.x + ((bx * MASK_BLOCK + i) + 0.5) * metres_per_pixel
			var z_m := origin_m.y + ((by * MASK_BLOCK + j) + 0.5) * metres_per_pixel
			var kind := kind_at_metres(x_m, z_m)
			var bits := 0
			if kind != 0 and kind != 8:  # FieldParcels.Kind.NONE / BALK
				bits = MASK_STANDING if kind == 7 else MASK_STANDING | MASK_GRASS
			block[j * MASK_BLOCK + i] = bits
	return block


## Kind at world position (x, z) in world units.
func kind_at(x: float, z: float) -> int:
	return kind_at_metres(x * MapScale.metres_per_unit, z * MapScale.metres_per_unit)


## The world rectangle (x, z, in world units) the image covers.
func rect_units() -> Rect2:
	var size_m := Vector2(size_px()) * metres_per_pixel
	return Rect2(origin_m / MapScale.metres_per_unit, size_m / MapScale.metres_per_unit)


func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	return _texture
