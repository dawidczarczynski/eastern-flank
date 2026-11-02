class_name ScenarioPreview
extends Control
## Flat top-down preview of a scenario's terrain for the scenario screen (TASK-124): terrain
## colours, roads, rivers and unit start markers drawn as 2D polygons from the scenario's grid,
## without a MapView. The per-scenario geometry is built once and cached.

const COLORS := {
	Terrain.Type.PLAINS: Color("#7d8a4f"),
	Terrain.Type.FOREST: Color("#3f5a34"),
	Terrain.Type.HILLS: Color("#8b7a52"),
	Terrain.Type.WATER: Color("#2f5d7c"),
	Terrain.Type.FIELDS: Color("#a59a58"),
	Terrain.Type.URBAN: Color("#7b766d"),
	Terrain.Type.MARSH: Color("#56705a"),
}
const ROAD_COLOR := Color("#d8c9a0")
const RIVER_COLOR := Color("#5a93b8")
const PLAYER_COLORS: Array[Color] = [Color("#e8b04a"), Color("#e07c5e")]
const PREVIEW_SEED := 12345
const MARGIN := 8.0

## Scenario name -> {"hexes": Array of [Vector2i, Color], "roads": Array of [Vector2, Vector2],
## "rivers": same, "units": Array of [Vector2, int owner], "bounds": Rect2} in unit hex size.
static var _cache: Dictionary = {}

var _scenario := ""


## Shows the terrain of `scenario_name` (one of Scenario.NAMES).
func show_scenario(scenario_name: String) -> void:
	_scenario = scenario_name
	queue_redraw()


func scenario() -> String:
	return _scenario


## Geometry of a scenario in hex-size-1 world units (X right, Z down); cached.
static func geometry(scenario_name: String) -> Dictionary:
	if _cache.has(scenario_name):
		return _cache[scenario_name]
	var state := Scenario.build(scenario_name, PREVIEW_SEED, FactionRegistry.DEFAULT_IDS)
	var result := {"hexes": [], "roads": [], "rivers": [], "units": [], "bounds": Rect2()}
	if state == null:
		return result
	var grid := state.grid
	var bounds := Rect2()
	var first := true
	for c in grid.coords():
		var centre := _centre(c)
		var colour: Color = COLORS.get(grid.get_terrain(c), COLORS[Terrain.Type.PLAINS])
		result["hexes"].append([c, colour])
		var tile := Rect2(centre - Vector2(Hex.SQRT3 / 2.0, 1.0), Vector2(Hex.SQRT3, 2.0))
		bounds = tile if first else bounds.merge(tile)
		first = false
		for i in Hex.DIRECTIONS.size():
			var n := c + Hex.DIRECTIONS[i]
			if not grid.has_tile(n):
				continue
			if (grid.road_links(c) & (1 << i)) != 0:
				result["roads"].append([centre, _centre(n)])
			if (grid.river_links(c) & (1 << i)) != 0:
				result["rivers"].append([centre, _centre(n)])
	for unit: Unit in state.units.values():
		result["units"].append([_centre(unit.coord), unit.owner_id])
	result["bounds"] = bounds
	_cache[scenario_name] = result
	return result


static func _centre(c: Vector2i) -> Vector2:
	var p := Hex.to_world(c, 1.0)
	return Vector2(p.x, p.z)


func _draw() -> void:
	var data := geometry(_scenario)
	var bounds: Rect2 = data["bounds"]
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var avail := size - Vector2(MARGIN, MARGIN) * 2.0
	var scale_factor := minf(avail.x / bounds.size.x, avail.y / bounds.size.y)
	var offset := (size - bounds.size * scale_factor) / 2.0 - bounds.position * scale_factor
	for entry: Array in data["hexes"]:
		var corners := PackedVector2Array()
		var centre := _centre(entry[0])
		for i in 6:
			var angle := deg_to_rad(60.0 * i - 30.0)
			corners.append((centre + Vector2(cos(angle), sin(angle))) * scale_factor + offset)
		draw_colored_polygon(corners, entry[1])
	var width := maxf(1.0, scale_factor * 0.25)
	for seg: Array in data["rivers"]:
		draw_line(
			seg[0] * scale_factor + offset, seg[1] * scale_factor + offset, RIVER_COLOR, width
		)
	for seg: Array in data["roads"]:
		draw_line(seg[0] * scale_factor + offset, seg[1] * scale_factor + offset, ROAD_COLOR, width)
	for marker: Array in data["units"]:
		var colour: Color = PLAYER_COLORS[clampi(marker[1], 0, PLAYER_COLORS.size() - 1)]
		draw_circle(marker[0] * scale_factor + offset, maxf(2.0, scale_factor * 0.3), colour)
