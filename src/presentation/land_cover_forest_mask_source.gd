class_name LandCoverForestMaskSource
extends HexForestMaskSource
## The ForestMaskSource of a map with a land-cover raster (TASK-108g, ADR 0028; replaces the
## transitional HexForestMaskSource there): forest where the raster's forest cover lies, with
## CoverLook's noisy soft outline, so forest edges follow the real ones and never a hex edge.
## The forest mask is evaluated on a coarse lattice of about one raster cell (CoverLook's soft
## value, short-cut inside and outside the forest) and resized bilinearly to the requested
## resolution, so its 0.5 level – the one ForestFill and forest_impostor.gdshader cut at – is a
## smooth curve, at a fraction of the cost of a per-texel test. The keep-off mask is the parent's:
## a clearing at every tile centre on forest, and roads and rivers near forest. No hex type read.

var _look: CoverLook


func _init(look: CoverLook, clearing_units: float = 0.0) -> void:
	super(clearing_units)
	_look = look


func build(grid: HexGrid, area: Rect2, per_unit: float) -> Dictionary:
	var size := ForestMaskSource.mask_size(area, per_unit)
	var forest := _forest_cover(area, size)
	var keep_off := PackedByteArray()
	keep_off.resize(size.x * size.y)
	if clearing > 0.0:
		for c in grid.coords():
			var w := Hex.to_world(c, TerrainField.HEX_SIZE)
			if _look.forest_weight(w.x, w.z) > 0.0:
				HexForestMaskSource._disc(
					keep_off, size, Vector2(w.x, w.z), clearing, area, per_unit
				)
	if grid.has_links():
		for kind: FeatureRibbonPlanner.Kind in [
			FeatureRibbonPlanner.Kind.ROAD, FeatureRibbonPlanner.Kind.RIVER
		]:
			var lines := FeatureRibbonPlanner.lines(grid, kind)
			var halves := FeatureRibbonPlanner.half_widths(grid, kind)
			var reach_extra := FeatureRibbonPlanner.clearance(kind)
			for n in lines.size():
				var line: PackedVector2Array = lines[n]
				var widths: PackedFloat32Array = halves[n]
				for k in line.size() - 1:
					if not _near_forest_cover(line[k], line[k + 1]):
						continue
					var reach := maxf(widths[k], widths[k + 1]) + reach_extra
					HexForestMaskSource._segment(
						keep_off, size, line[k], line[k + 1], reach, area, per_unit
					)
	return {
		"forest": forest,
		"keep_off": Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, keep_off),
	}


## The forest mask (L8, `size` texels over `area`): CoverLook.forest_value on a lattice of about
## one raster cell, resized bilinearly.
func _forest_cover(area: Rect2, size: Vector2i) -> Image:
	var cell := _look.cover.cell_size
	var coarse := Vector2i(
		clampi(ceili(area.size.x / cell), 1, size.x), clampi(ceili(area.size.y / cell), 1, size.y)
	)
	var step := area.size / Vector2(coarse)
	var bytes := PackedByteArray()
	bytes.resize(coarse.x * coarse.y)
	for j in coarse.y:
		var z := area.position.y + (j + 0.5) * step.y
		for i in coarse.x:
			var x := area.position.x + (i + 0.5) * step.x
			bytes[j * coarse.x + i] = clampi(roundi(_look.forest_value(x, z) * 255.0), 0, 255)
	var image := Image.create_from_data(coarse.x, coarse.y, false, Image.FORMAT_L8, bytes)
	if coarse != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return image


## Whether the segment a-b runs through or next to forest (only there the ribbons matter).
func _near_forest_cover(a: Vector2, b: Vector2) -> bool:
	for t: float in [0.0, 0.5, 1.0]:
		var p := a.lerp(b, t)
		for offset: Vector2 in [Vector2.ZERO, Vector2(0.5, 0.0), Vector2(-0.5, 0.0)]:
			if _look.forest_weight(p.x + offset.x, p.y + offset.y) > 0.0:
				return true
			if _look.forest_weight(p.x + offset.y, p.y + offset.x) > 0.0:
				return true
	return false
