class_name ColourRaster
extends RefCounted
## A decoded satellite colour image (TASK-192a, ADR 0031 "Satellite colour layer"): sRGB pixels
## (8 bit, Sentinel-2 L2A corrected by tools/import_map.py) of `cell_m` metres in a frame of metres
## (x east, z south); `origin` is the centre of pixel (0, 0), the north-west one. Pure data: the
## view samples it; no rule reads it.

var image: Image
var cell_m: float
var origin: Vector2


## The raster of a JPEG of `width` x `height` pixels; null when the bytes do not decode to
## that size.
static func from_jpg(
	jpg: PackedByteArray, width: int, height: int, cell: float, pixel_origin: Vector2
) -> ColourRaster:
	if jpg.is_empty() or width <= 0 or height <= 0 or cell <= 0.0:
		return null
	var decoded := Image.new()
	if decoded.load_jpg_from_buffer(jpg) != OK:
		return null
	if decoded.get_width() != width or decoded.get_height() != height:
		return null
	return from_image(decoded, cell, pixel_origin)


static func from_image(source: Image, cell: float, pixel_origin: Vector2) -> ColourRaster:
	var raster := ColourRaster.new()
	raster.image = source
	if source.get_format() != Image.FORMAT_RGB8:
		raster.image = source.duplicate() as Image
		raster.image.convert(Image.FORMAT_RGB8)
	raster.cell_m = cell
	raster.origin = pixel_origin
	return raster


func size() -> Vector2i:
	return image.get_size()


## The colour at (x_m, z_m), bilinear between the four nearest pixel centres; a point beyond the
## outer pixel centres takes the edge colour.
func sample(x_m: float, z_m: float) -> Color:
	var w := image.get_width()
	var h := image.get_height()
	var fx := clampf((x_m - origin.x) / cell_m, 0.0, float(w - 1))
	var fy := clampf((z_m - origin.y) / cell_m, 0.0, float(h - 1))
	var i := mini(floori(fx), maxi(w - 2, 0))
	var j := mini(floori(fy), maxi(h - 2, 0))
	var u := fx - i
	var v := fy - j
	var i1 := mini(i + 1, w - 1)
	var j1 := mini(j + 1, h - 1)
	var top := image.get_pixel(i, j).lerp(image.get_pixel(i1, j), u)
	var bottom := image.get_pixel(i, j1).lerp(image.get_pixel(i1, j1), u)
	return top.lerp(bottom, v)
