class_name RiverChannel
extends RefCounted
## The river bed in the terrain height (follow-up of TASK-216): the ground along every river
## centre line is dug into a channel, so a river lies in a valley with banks instead of a texture
## on flat ground. Pure and immutable once built (queried from worker threads).
##
## The water surface of a river only ever falls downstream (`levels`): the undug ground along the
## line is smoothed, the downstream end is the lower one, and the level is the running minimum
## from the source, never below the water plane. A rise of the ground over that level is dug
## through instead of lifting the water, so a river never runs uphill.
##
## Profile across a river of water half width `w` (distance `d` from the centre line, `base` the
## undug ground at the point, `level` the water surface there): a flat bed `depth - freeboard`
## below the level for the middle third of the water, rising to the level exactly at `d = w`,
## then a bank slope that climbs from the level to `base` over `slope` more.
## Where channels overlap (a confluence) the deeper one wins, so a tributary opens into the river.

## Visual exaggeration of the depth against the metres, like the relief of the tactical maps.
const VERTICAL := 2.0
## Largest bed depth below the banks, metres.
const MAX_DEPTH_M := 4.0
## Freeboard (waterline below the bank top) as a share of the depth.
const FREEBOARD := 0.4
## The ground along a line is averaged over this many vertices each side before its level is taken.
const SMOOTH_VERTICES := 5
## Index cell size, world units.
const CELL := 1.0
## How far past the water edge a point still counts as "in the water" for `water_level`: the bank
## band of the ribbon (world units, generous: the ribbon never reaches past the bank).
const _EDGE_REACH := 0.12

## Per segment: ax, az, bx, bz, wa, wb (water half widths), la, lb (water level at the ends),
## da, db (bed depth below the bank at the ends), sa, sb (bank slope width at the ends), reach.
const STRIDE := 13

var _data := PackedFloat32Array()
var _cells: Dictionary = {}  # Vector2i -> PackedInt32Array of segment numbers


## Bed depth in world units of a river `water_m` wide.
static func depth_units(water_m: float) -> float:
	return MapScale.to_units(minf(1.0 + 0.06 * water_m, MAX_DEPTH_M)) * VERTICAL


## Bank slope width in world units of a river `water_m` wide.
static func slope_units(water_m: float) -> float:
	var depth_m := minf(1.0 + 0.06 * water_m, MAX_DEPTH_M)
	return MapScale.to_units(3.0 * depth_m + 0.4 * water_m + 2.0)


## Channel of the river `lines` (world XZ points) with the whole water width in world units at
## every point (`waters`, parallel) over the undug ground height `base_height` (Callable(x, z) ->
## float). Rivers narrower than `min_water_m` are skipped (too narrow to show in the mesh).
static func build(
	lines: Array[PackedVector2Array],
	waters: Array[PackedFloat32Array],
	base_height: Callable,
	min_water_m := 6.0
) -> RiverChannel:
	var channel := RiverChannel.new()
	for li in lines.size():
		var line := lines[li]
		var water := waters[li]
		var heights := PackedFloat32Array()
		var frees := PackedFloat32Array()
		for i in line.size():
			heights.append(base_height.call(line[i].x, line[i].y))
			frees.append(depth_units(water[i] * MapScale.metres_per_unit) * FREEBOARD)
		var level := levels(heights, frees)
		for i in line.size() - 1:
			var wa := water[i] * 0.5
			var wb := water[i + 1] * 0.5
			if maxf(wa, wb) * 2.0 * MapScale.metres_per_unit < min_water_m:
				continue
			channel._add(line[i], line[i + 1], wa, wb, level[i], level[i + 1])
	return channel


## Water surface per vertex of a line whose undug ground is `heights` and whose waterline lies
## `frees` below the bank top: falls (never rises) towards the lower end of the smoothed ground,
## stays at or below the ground and at or above the water plane.
static func levels(heights: PackedFloat32Array, frees: PackedFloat32Array) -> PackedFloat32Array:
	var count := heights.size()
	var result := PackedFloat32Array()
	result.resize(count)
	if count == 0:
		return result
	var smooth := PackedFloat32Array()
	smooth.resize(count)
	for i in count:
		var lo := maxi(i - SMOOTH_VERTICES, 0)
		var hi := mini(i + SMOOTH_VERTICES, count - 1)
		var total := 0.0
		for k in range(lo, hi + 1):
			total += heights[k]
		smooth[i] = total / float(hi - lo + 1)
	var downstream_is_last := smooth[count - 1] <= smooth[0]
	var running := INF
	for step in count:
		var i := step if downstream_is_last else count - 1 - step
		running = minf(running, minf(smooth[i], heights[i]) - frees[i])
		result[i] = maxf(running, TerrainSurface.WATER_SURFACE)
	return result


func is_empty() -> bool:
	return _data.is_empty()


## Ground height at (x, z) with the channels dug in: `base` (the undug height) lowered to the
## deepest channel profile around the point; `base` itself away from every river.
func carved_height(x: float, z: float, base: float) -> float:
	var best := base
	var list: PackedInt32Array = _cells.get(
		Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array()
	)
	for s in list:
		best = minf(best, _profile(s, x, z, base))
	return best


## Share 0..1 of sand on the ground at (x, z): 1 on the bed and along the waterline, fading out up
## the bank slope to 0 at its top. 0 away from every river.
func shore(x: float, z: float) -> float:
	var best := 0.0
	var list: PackedInt32Array = _cells.get(
		Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array()
	)
	for s in list:
		var o := s * STRIDE
		var p := Vector2(x, z)
		var t := _closest(Vector2(_data[o], _data[o + 1]), Vector2(_data[o + 2], _data[o + 3]), p)
		var d := (
			(Vector2(_data[o], _data[o + 1]).lerp(Vector2(_data[o + 2], _data[o + 3]), t))
			. distance_to(p)
		)
		var w := lerpf(_data[o + 4], _data[o + 5], t)
		var slope := lerpf(_data[o + 10], _data[o + 11], t)
		var share := 1.0 - TerrainNoise.smooth(0.1, 1.0, (d - w) / maxf(slope, 1e-6))
		best = maxf(best, share)
	return best


## Water surface height at (x, z) when it lies within the water of a channel, else NAN.
func water_level(x: float, z: float) -> float:
	var best := NAN
	var best_d := INF
	var list: PackedInt32Array = _cells.get(
		Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array()
	)
	for s in list:
		var o := s * STRIDE
		var a := Vector2(_data[o], _data[o + 1])
		var b := Vector2(_data[o + 2], _data[o + 3])
		var t := _closest(a, b, Vector2(x, z))
		var d := (a + (b - a) * t).distance_to(Vector2(x, z))
		var w := lerpf(_data[o + 4], _data[o + 5], t)
		var margin := d - w
		if margin <= _EDGE_REACH and margin < best_d:
			best_d = margin
			best = lerpf(_data[o + 6], _data[o + 7], t)
	return best


func _add(a: Vector2, b: Vector2, wa: float, wb: float, level_a: float, level_b: float) -> void:
	var water_a_m := wa * 2.0 * MapScale.metres_per_unit
	var water_b_m := wb * 2.0 * MapScale.metres_per_unit
	var da := depth_units(water_a_m)
	var db := depth_units(water_b_m)
	var sa := slope_units(water_a_m)
	var sb := slope_units(water_b_m)
	var number := _data.size() / STRIDE
	var reach := maxf(wa + sa, wb + sb)
	_data.append_array(
		PackedFloat32Array([a.x, a.y, b.x, b.y, wa, wb, level_a, level_b, da, db, sa, sb, reach])
	)
	var lo := Vector2(minf(a.x, b.x) - reach, minf(a.y, b.y) - reach)
	var hi := Vector2(maxf(a.x, b.x) + reach, maxf(a.y, b.y) + reach)
	for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			var key := Vector2i(cx, cz)
			var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
			list.append(number)
			_cells[key] = list


## Height the ground is dug to at (x, z) by segment `s` (`base` when it does not reach).
func _profile(s: int, x: float, z: float, base: float) -> float:
	var o := s * STRIDE
	var p := Vector2(x, z)
	var a := Vector2(_data[o], _data[o + 1])
	var b := Vector2(_data[o + 2], _data[o + 3])
	var t := _closest(a, b, p)
	var d := (a + (b - a) * t).distance_to(p)
	if d >= _data[o + 12]:
		return base
	var w := lerpf(_data[o + 4], _data[o + 5], t)
	var level := lerpf(_data[o + 6], _data[o + 7], t)
	var depth := lerpf(_data[o + 8], _data[o + 9], t)
	var slope := lerpf(_data[o + 10], _data[o + 11], t)
	if d <= w:
		var bed := level - depth * (1.0 - FREEBOARD)
		return minf(base, lerpf(bed, level, TerrainNoise.smooth(0.33, 1.0, d / maxf(w, 1e-6))))
	var rise := TerrainNoise.smooth(0.0, 1.0, (d - w) / maxf(slope, 1e-6))
	return minf(base, lerpf(level, maxf(base, level), rise))


static func _closest(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-12:
		return 0.0
	return clampf((p - a).dot(ab) / len2, 0.0, 1.0)
