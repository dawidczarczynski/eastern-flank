class_name VegetationHash
extends RefCounted
## The shared cell hash of the GPU-placed vegetation layers (TASK-217a, ADR 0033; generalised
## from the forest of TASK-189 / ADR 0027): a layer lays a jittered grid over the world, and
## everything about the plant of a cell – whether it stands, its kind, size, yaw, colour – is a
## pure function of (seed, cell) and the map textures. The vertex shader evaluates the same
## function per instance (assets/shaders/vegetation_hash.gdshaderinc, which includes
## forest_hash.gdshaderinc's uint32 hash), so no plant is planned on the CPU.
##
## This is the GDScript reference (headless tests, the layers' own reference planners): 32-bit
## unsigned arithmetic only – masked to 32 bits after every multiply – so both sides give the same
## bits. tests/unit/test_vegetation_hash.gd fixes the values of five (seed, cell) pairs and
## checks that the include carries the same constants. Change both together.
##
## Cosmetic only: no GameState.rng, nothing in the game state reads it.

## ScatterPlanner._mix's multiplier and ForestFill.unit's per-part offset (shared with the forest).
const MIX_MULTIPLIER := ForestFill.MIX_MULTIPLIER
const UNIT_MULTIPLIER := ForestFill.UNIT_MULTIPLIER
## Salt step of the value noise's lattice hash (a different stream from the cell hashes).
const NOISE_SALT := 0x6E01


## The 32-bit hash of a grid cell (ScatterPlanner.tile_seed: seed and salt, then x, then z).
static func cell_hash(seed_value: int, cell: Vector2i, salt: int) -> int:
	return ScatterPlanner.tile_seed(seed_value, cell, salt)


## A value in [0, 1) from the 32-bit hash `h`; `part` picks one of several independent ones
## (ForestFill.unit).
static func unit(h: int, part: int) -> float:
	return ForestFill.unit(h, part)


## The jittered point (world XZ) of `cell` on a grid of `spacing` (world units) from its point
## hash `h`: the cell centre moved by up to +-jitter / 2 of a cell on each axis (ForestFill.point).
static func point(h: int, cell: Vector2i, spacing: float, jitter: float) -> Vector2:
	return Vector2(
		(cell.x + 0.5 + jitter * (float(h & 0xFFFF) / 65536.0 - 0.5)) * spacing,
		(cell.y + 0.5 + jitter * (float((h >> 16) & 0xFFFF) / 65536.0 - 0.5)) * spacing
	)


## Smooth value noise in [0, 1) at (x, z) on a lattice `wavelength` apart (same units as x, z):
## the lattice values are unit(cell_hash(seed, corner, salt), 0), blended with a smoothstep.
static func value_noise(seed_value: int, x: float, z: float, wavelength: float, salt: int) -> float:
	var fx := x / wavelength
	var fz := z / wavelength
	var i := floori(fx)
	var j := floori(fz)
	var u := fx - float(i)
	var v := fz - float(j)
	u = u * u * (3.0 - 2.0 * u)
	v = v * v * (3.0 - 2.0 * v)
	var a := _lattice(seed_value, i, j, salt)
	var b := _lattice(seed_value, i + 1, j, salt)
	var c := _lattice(seed_value, i, j + 1, salt)
	var d := _lattice(seed_value, i + 1, j + 1, salt)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


static func _lattice(seed_value: int, i: int, j: int, salt: int) -> float:
	return unit(cell_hash(seed_value, Vector2i(i, j), salt ^ NOISE_SALT), 0)


## The cells whose centre lies in `rect` on a grid of `spacing`: Rect2i(first cell, counts).
## Adjacent rectangles share no cell (a GPU layer's chunks own their cells by centre).
static func cells_of(rect: Rect2, spacing: float) -> Rect2i:
	var first := Vector2i(
		ceili(rect.position.x / spacing - 0.5), ceili(rect.position.y / spacing - 0.5)
	)
	var end := Vector2i(ceili(rect.end.x / spacing - 0.5), ceili(rect.end.y / spacing - 0.5))
	return Rect2i(first, end - first)


## The largest cell count of any `size` x `size` chunk on a grid of `spacing` (the shared
## MultiMesh's instance count).
static func max_cells(size: float, spacing: float) -> int:
	var side := ceili(size / spacing) + 1
	return side * side
