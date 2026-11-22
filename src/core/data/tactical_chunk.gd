class_name TacticalChunk
extends Resource
## One square of a TacticalLayer (TASK-094b, ADR 0018 "Tactical layer"): data/maps/<layer>/
## chunk_<cx>_<cy>.tres, written by tools/import_map.py --profile=layer. `data` is zlib (Godot
## COMPRESSION_DEFLATE) of five planes of `width` x `height` bytes each, row-major, row 0 north:
## terrain (Terrain.Type), road link mask, river link mask (bit i = towards Hex.DIRECTIONS[i]),
## then the DEM height as uint16 (TacticalLayer.elevation_offset_m / elevation_step_m) low bytes
## and high bytes.
## `cover` (TASK-108g, ADR 0028) is zlib of this chunk's window of the layer's land-cover raster:
## cells `cover_column` .. + `cover_width` - 1 x north rows `cover_row` .. + `cover_height` - 1
## of the whole raster, one LandCover.Kind byte each, row-major, row 0 north. The windows of all
## chunks tile the raster without overlap. Empty in layers imported before the raster.
## `colour_jpg` (TASK-192a, ADR 0031) is a baseline JPEG of this chunk's window of the layer's
## satellite colour raster: pixels `colour_column` .. + `colour_width` - 1 x rows `colour_row` ..
## + `colour_height` - 1 of the whole raster (TacticalLayer.colour_*). Each window also holds the
## first pixel column / row of its east / south neighbour, so a bilinear sample needs one window.
## Empty in layers imported without colour.

## Planes in `data` (decoded).
const PLANES := 5

## First column and row of the chunk in the layer (offset layout).
@export var column: int
@export var row: int
@export var width: int
@export var height: int
@export var data: PackedByteArray
@export var cover_column: int
@export var cover_row: int
@export var cover_width: int
@export var cover_height: int
@export var cover: PackedByteArray
@export var colour_column: int
@export var colour_row: int
@export var colour_width: int
@export var colour_height: int
@export var colour_jpg: PackedByteArray


## The decoded planes (PLANES * width * height bytes); empty when `data` is malformed.
func decode() -> PackedByteArray:
	var size := PLANES * width * height
	if size <= 0 or data.is_empty():
		return PackedByteArray()
	var planes := data.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	return planes if planes.size() == size else PackedByteArray()


## Raster cells of this chunk's cover window (cover_width x cover_height, global cells).
func cover_rect() -> Rect2i:
	return Rect2i(cover_column, cover_row, cover_width, cover_height)


## The decoded cover window (cover_width * cover_height bytes); empty when there is none or it is
## malformed.
func decode_cover() -> PackedByteArray:
	var size := cover_width * cover_height
	if size <= 0 or cover.is_empty():
		return PackedByteArray()
	var cells := cover.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	return cells if cells.size() == size else PackedByteArray()


## Pixels of the whole colour raster in this chunk's window.
func colour_rect() -> Rect2i:
	return Rect2i(colour_column, colour_row, colour_width, colour_height)
