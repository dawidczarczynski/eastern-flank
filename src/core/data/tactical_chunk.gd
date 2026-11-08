class_name TacticalChunk
extends Resource
## One square of a TacticalLayer (TASK-094b, ADR 0018 "Tactical layer"): data/maps/<layer>/
## chunk_<cx>_<cy>.tres, written by tools/import_map.py --profile=layer. `data` is zlib (Godot
## COMPRESSION_DEFLATE) of five planes of `width` x `height` bytes each, row-major, row 0 north:
## terrain (Terrain.Type), road link mask, river link mask (bit i = towards Hex.DIRECTIONS[i]),
## then the DEM height as uint16 (TacticalLayer.elevation_offset_m / elevation_step_m) low bytes
## and high bytes.

## Planes in `data` (decoded).
const PLANES := 5

## First column and row of the chunk in the layer (offset layout).
@export var column: int
@export var row: int
@export var width: int
@export var height: int
@export var data: PackedByteArray


## The decoded planes (PLANES * width * height bytes); empty when `data` is malformed.
func decode() -> PackedByteArray:
	var size := PLANES * width * height
	if size <= 0 or data.is_empty():
		return PackedByteArray()
	var planes := data.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	return planes if planes.size() == size else PackedByteArray()
