class_name ForestMaskSource
extends RefCounted
## Where the real-scale forest may stand (TASK-189, ADR 0027): the one interface between the map
## data and the forest fill. A source turns a map into two L8 masks over a rectangle at a
## resolution the caller picks (texels per world unit, independent of the hex size):
##   "forest"    255 where the land cover is forest;
##   "keep_off"  255 where nothing may stand on forest ground (roads, rivers, the tile-centre
##               clearing).
## ForestFill merges them into the mask its GDScript reference and forest_impostor.gdshader both
## read, so replacing the source changes neither the shader nor the chunk layers.
##
## Today's source is HexForestMaskSource (the hex tile types – hex-edged forests, transitional);
## TASK-108g's sub-hex land-cover raster (~16 m) replaces it with real forest shapes.


## {"forest": Image, "keep_off": Image}, both FORMAT_L8 of ceil(area.size * per_unit) texels;
## texel (i, j) covers area.position + (i, j) / per_unit.
func build(_grid: HexGrid, _area: Rect2, _per_unit: float) -> Dictionary:
	push_error("ForestMaskSource.build is abstract")
	return {}


## Texel counts of a mask over `area` at `per_unit`.
static func mask_size(area: Rect2, per_unit: float) -> Vector2i:
	return Vector2i(
		maxi(1, ceili(area.size.x * per_unit - 1.0e-6)),
		maxi(1, ceili(area.size.y * per_unit - 1.0e-6))
	)
