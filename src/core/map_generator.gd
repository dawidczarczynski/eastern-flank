class_name MapGenerator
extends RefCounted
## Procedural map generation. Deterministic for a given RNG seed.


static func generate(width: int, height: int, rng: RandomNumberGenerator) -> HexGrid:
	var grid := HexGrid.new()
	for row in height:
		for col in width:
			grid.set_terrain(offset_to_axial(col, row), _roll_terrain(rng))
	return grid


## Converts from "offset" layout (rectangular map: column, row) to axial coordinates.
static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - floori(row / 2.0), row)


static func _roll_terrain(rng: RandomNumberGenerator) -> Terrain.Type:
	var roll := rng.randf()
	if roll < 0.08:
		return Terrain.Type.WATER
	if roll < 0.25:
		return Terrain.Type.FOREST
	if roll < 0.35:
		return Terrain.Type.HILLS
	return Terrain.Type.PLAINS
