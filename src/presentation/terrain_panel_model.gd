class_name TerrainPanelModel
extends RefCounted
## Pure model of the bottom-left terrain panel. Returns untranslated English strings;
## the view translates them. No nodes, no tr().

const DASH := "—"
const _ELEVATION_BASE_M := 12.0
const _ELEVATION_SCALE_M := 420.0


## Keys: name, hex, move, defense, elevation, tags (PackedStringArray), path
## ("2 / 3 MP" or ""), city ("" unless the tile is a named city),
## plus the raw ints path_cost and moves_left for the view.
## `path_cost` is -1 when the tile is not a valid move target.
static func build(
	grid: HexGrid, coord: Vector2i, path_cost: int, moves_left: int, city_name := ""
) -> Dictionary:
	var offset := MapGenerator.axial_to_offset(coord)
	var terrain := grid.get_terrain(coord)
	var impassable := grid.move_cost(coord) == Terrain.IMPASSABLE
	var tags := PackedStringArray()
	if impassable:
		tags.append("Impassable")
	var metres := roundi(maxf(grid.elevation(coord), 0.0) * _ELEVATION_SCALE_M + _ELEVATION_BASE_M)
	return {
		"name": Terrain.definition(terrain).display_name,
		"hex": "%02d·%02d" % [offset.x + 1, offset.y + 1],
		"move": DASH if impassable else str(grid.move_cost(coord)),
		"defense": DASH if impassable else "+%d" % grid.defense_bonus(coord),
		"elevation": "%d m" % metres,
		"tags": tags,
		"path": "%d / %d MP" % [path_cost, moves_left] if path_cost >= 0 else "",
		"city": city_name,
		"path_cost": path_cost,
		"moves_left": moves_left,
	}
