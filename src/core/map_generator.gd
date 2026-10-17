class_name MapGenerator
extends RefCounted
## Procedural map generation from elevation and moisture noise (TerrainField).
## Deterministic for a given RNG seed.

const DEFAULT_SETTINGS := preload("res://data/map/terrain_generation.tres")


static func generate(
	width: int,
	height: int,
	rng: RandomNumberGenerator,
	settings: TerrainGenerationSettings = DEFAULT_SETTINGS
) -> HexGrid:
	var offset := Vector2(rng.randf_range(-1000.0, 1000.0), rng.randf_range(-1000.0, 1000.0))
	var grid := HexGrid.new()
	grid.field = TerrainField.new(settings, offset)
	for row in height:
		for col in width:
			var c := offset_to_axial(col, row)
			var center := Hex.to_world(c, TerrainField.HEX_SIZE)
			var elevation := grid.field.height(center.x, center.z)
			var moisture := grid.field.moisture(center.x, center.z)
			grid.set_terrain(c, classify(elevation, moisture, settings))
			grid.set_elevation(c, elevation)
	return grid


## Terrain type for an elevation and moisture: low → water, high → hills (or forest
## when very wet), wet lowland → forest, the rest plains.
static func classify(
	h: float, moisture: float, settings: TerrainGenerationSettings
) -> Terrain.Type:
	if h < settings.water_level:
		return Terrain.Type.WATER
	if h > settings.hills_level:
		if moisture > settings.highland_forest_moisture:
			return Terrain.Type.FOREST
		return Terrain.Type.HILLS
	if moisture > settings.forest_moisture:
		return Terrain.Type.FOREST
	return Terrain.Type.PLAINS


## Sets the tile's terrain and clamps its elevation into the type's band, so the 3D
## surface never shows water under a land tile (e.g. spawn tiles forced to plains).
static func force_terrain(
	grid: HexGrid,
	c: Vector2i,
	t: Terrain.Type,
	settings: TerrainGenerationSettings = DEFAULT_SETTINGS
) -> void:
	var e := grid.elevation(c)
	grid.set_terrain(c, t)
	match t:
		Terrain.Type.HILLS:
			e = clampf(e, settings.hills_min, settings.hills_max)
		Terrain.Type.WATER:
			e = clampf(e, settings.water_min, settings.water_max)
		_:
			e = clampf(e, settings.land_min, settings.land_max)
	grid.set_elevation(c, e)


## Converts from "offset" layout (rectangular map: column, row) to axial coordinates.
static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - floori(row / 2.0), row)


## Inverse of `offset_to_axial`: axial coordinates to (column, row) offset.
static func axial_to_offset(c: Vector2i) -> Vector2i:
	return Vector2i(c.x + floori(c.y / 2.0), c.y)
