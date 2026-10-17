extends RefCounted
## Pure image checks for tools/screenshot.gd (tested headless).

const SAMPLE_GRID := 16


## True when every pixel of a SAMPLE_GRID x SAMPLE_GRID grid has the same colour
## (e.g. a black frame because nothing was rendered). An empty image counts as blank.
static func is_blank(image: Image) -> bool:
	if image == null or image.is_empty():
		return true
	var width := image.get_width()
	var height := image.get_height()
	var first := image.get_pixel(_sample(0, width), _sample(0, height))
	for row in SAMPLE_GRID:
		for column in SAMPLE_GRID:
			if image.get_pixel(_sample(column, width), _sample(row, height)) != first:
				return false
	return true


## Centre of the index-th of SAMPLE_GRID equal cells along a side of `size` pixels.
static func _sample(index: int, size: int) -> int:
	return mini(int((index + 0.5) * size / SAMPLE_GRID), size - 1)
