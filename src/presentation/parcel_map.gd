class_name ParcelMap
extends RefCounted
## The baked farmland parcels of a map (TASK-108f, FieldParcels.bake): an RG8 image with the
## parcel kind (FieldParcels.Kind) in red and the row orientation / parcel id in green, covering
## a world rectangle at `metres_per_pixel`. The terrain shader samples it as a texture; the grass
## planner reads the kind per position.

var image: Image
## World position (x, z) in metres of the image's top-left corner.
var origin_m := Vector2.ZERO
var metres_per_pixel := 5.0
var _texture: ImageTexture


func size_px() -> Vector2i:
	return Vector2i(image.get_width(), image.get_height())


## Kind (FieldParcels.Kind, 0 = none) at world position (x, z) in metres; NONE outside the image.
func kind_at_metres(x_m: float, z_m: float) -> int:
	var px := floori((x_m - origin_m.x) / metres_per_pixel)
	var py := floori((z_m - origin_m.y) / metres_per_pixel)
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return 0  # FieldParcels.NONE
	return roundi(image.get_pixel(px, py).r * 255.0)


## Whether trees, bushes, rocks and thickets are kept off world position (x, z) (world units):
## on every parcel kind except the balk (hedgerow strip) and unpainted ground.
func blocks_standing(x: float, z: float) -> bool:
	var kind := kind_at(x, z)
	return kind != 0 and kind != 8  # FieldParcels.Kind.NONE / BALK


## Whether tall grass is kept off (x, z): crop parcels, not meadows, balks or unpainted ground.
func blocks_tall_grass(x: float, z: float) -> bool:
	var kind := kind_at(x, z)
	return kind != 0 and kind != 8 and kind != 7  # NONE / BALK / MEADOW


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
