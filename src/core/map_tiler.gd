class_name MapTiler
extends RefCounted
## Tiles a map grid into a larger one for the large-map benchmark (TASK-072a): every second tile
## is mirrored, so heights and terrain stay continuous at the seams. Pure and deterministic.
## Only terrain, elevation and real height are copied; road and river links are not (a mirrored
## row shifts the hex parity, so the link masks would need remapping).


## Tiles per side for a map `scale` times the source's area (1, 4, 16 → 1, 2, 4).
static func tiles_for_scale(scale: int) -> int:
	return roundi(sqrt(float(scale)))


## `tiles_x` x `tiles_y` copies of `source` (an imported map of `width` x `height` offset tiles);
## copies with an odd index along an axis are mirrored along it.
static func tile(source: HexGrid, width: int, height: int, tiles_x: int, tiles_y: int) -> HexGrid:
	var grid := HexGrid.new()
	grid.authored_elevation = source.authored_elevation
	for tile_y in tiles_y:
		for tile_x in tiles_x:
			for row in height:
				var src_row := height - 1 - row if tile_y % 2 == 1 else row
				for col in width:
					var src_col := width - 1 - col if tile_x % 2 == 1 else col
					var from := MapGenerator.offset_to_axial(src_col, src_row)
					var to := MapGenerator.offset_to_axial(
						tile_x * width + col, tile_y * height + row
					)
					grid.set_terrain(to, source.get_terrain(from))
					grid.set_elevation(to, source.elevation(from))
					if source.has_elevation_m(from):
						grid.set_elevation_m(to, source.elevation_m(from))
	return grid
