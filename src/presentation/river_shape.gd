class_name RiverShape
extends RefCounted
## The shape of a river ribbon (TASK-108c), split from FeatureRibbonPlanner: the cross-section
## per sample (water width noise, independent irregular banks on each side, source taper), the
## sideways meander, the end fade where a tributary merges or a source starts. Pure and static;
## every distance is metres converted with MapScale, every noise a function of world position.


## The channel the rivers of `grid` are dug into (RiverChannel) over the undug ground of `surface`;
## null on a grid without rivers.
static func channel(grid: HexGrid, surface: TerrainSurface) -> RiverChannel:
	if not grid.has_links():
		return null
	return RiverChannel.build(
		FeatureRibbonPlanner.lines(grid, FeatureRibbonPlanner.Kind.RIVER),
		FeatureRibbonPlanner.water_widths(grid),
		surface.base_height_at
	)


## `water_m` is the chain's base water width in metres (TASK-216, constant along the chain).
## Per-sample cross-section of a chain: {half: widest side's half width (the ribbon's reach, used
## for clearance), outer: Vector2(left, right) half width of the whole ribbon, edge: Vector2(left,
## right) `across` where the water ends, water: whole water width}. Roads are constant; rivers
## vary with world-position noise (the water width, each side's water edge and bank band
## independently at two scales) and narrow towards a dead-end source (the banks keep theirs).
static func sides(
	line: PackedVector2Array,
	chain: Array,
	pieces: Array,
	kind: FeatureRibbonPlanner.Kind,
	water_m: float = FeatureRibbonPlanner.RIVER_WATER_M
) -> Dictionary:
	var count := line.size()
	var half := PackedFloat32Array()
	var outer := PackedVector2Array()
	var edge := PackedVector2Array()
	var water := PackedFloat32Array()
	half.resize(count)
	outer.resize(count)
	edge.resize(count)
	water.resize(count)
	if kind == FeatureRibbonPlanner.Kind.ROAD:
		half.fill(FeatureRibbonPlanner.width(kind) / 2.0)
		outer.fill(Vector2.ONE * FeatureRibbonPlanner.width(kind) / 2.0)
		edge.fill(Vector2.ONE * FeatureRibbonPlanner.carriageway_across())
		return {"half": half, "outer": outer, "edge": edge, "water": water}
	var base := FeatureRibbonPlanner.water_width(water_m) / 2.0
	var bank := FeatureRibbonPlanner.bank_width(water_m)
	var start_source: bool = pieces[chain[0]["piece"]]["kind"] == &"dead"
	var end_source: bool = chain.size() > 1 and pieces[chain[-1]["piece"]]["kind"] == &"dead"
	var along := PackedFloat32Array()
	along.resize(count)
	for i in range(1, count):
		along[i] = along[i - 1] + line[i].distance_to(line[i - 1])
	var total := along[count - 1] if count > 0 else 0.0
	for i in count:
		var p := line[i]
		var noise := TerrainNoise.value_noise(
			p.x / MapScale.to_units(FeatureRibbonPlanner.WIDTH_WAVELENGTH_M),
			p.y / MapScale.to_units(FeatureRibbonPlanner.WIDTH_WAVELENGTH_M),
			FeatureRibbonPlanner.WIDTH_SEED
		)
		var w := base * (1.0 + FeatureRibbonPlanner.RIVER_WIDTH_VARIATION * (2.0 * noise - 1.0))
		var taper := 1.0
		if start_source:
			taper = minf(taper, taper(along[i]))
		if end_source:
			taper = minf(taper, taper(total - along[i]))
		var water_l := (
			w * taper * (1.0 + FeatureRibbonPlanner.WATER_EDGE_VARIATION * edge_noise(p, 0))
		)
		var water_r := (
			w * taper * (1.0 + FeatureRibbonPlanner.WATER_EDGE_VARIATION * edge_noise(p, 1))
		)
		var bank_l := bank * (1.0 + FeatureRibbonPlanner.BANK_VARIATION * edge_noise(p, 2))
		var bank_r := bank * (1.0 + FeatureRibbonPlanner.BANK_VARIATION * edge_noise(p, 3))
		outer[i] = Vector2(water_l + bank_l, water_r + bank_r)
		edge[i] = Vector2(water_l / outer[i].x, water_r / outer[i].y)
		half[i] = maxf(outer[i].x, outer[i].y)
		water[i] = water_l + water_r
	return {"half": half, "outer": outer, "edge": edge, "water": water}


## Deterministic irregularity in [-1, 1] of one side's edge (`channel` 0..3: water edge left /
## right, bank band left / right) at world position `p`: a slow swing plus a faster wobble.
static func edge_noise(p: Vector2, channel: int) -> float:
	var seed_value: float = FeatureRibbonPlanner.EDGE_SEEDS[channel]
	var slow := TerrainNoise.value_noise(
		p.x / MapScale.to_units(FeatureRibbonPlanner.EDGE_WAVELENGTH_M),
		p.y / MapScale.to_units(FeatureRibbonPlanner.EDGE_WAVELENGTH_M),
		seed_value
	)
	var fine := TerrainNoise.value_noise(
		p.x / MapScale.to_units(FeatureRibbonPlanner.EDGE_FINE_WAVELENGTH_M),
		p.y / MapScale.to_units(FeatureRibbonPlanner.EDGE_FINE_WAVELENGTH_M),
		seed_value + 7.0
	)
	return 0.65 * (2.0 * slow - 1.0) + 0.35 * (2.0 * fine - 1.0)


## The sides of a line walked the other way: samples reversed, left and right swapped.
static func reversed_sides(sides: Dictionary) -> Dictionary:
	var outer: PackedVector2Array = sides["outer"]
	var edge: PackedVector2Array = sides["edge"]
	var result_outer := PackedVector2Array()
	var result_edge := PackedVector2Array()
	for i in range(outer.size() - 1, -1, -1):
		result_outer.append(Vector2(outer[i].y, outer[i].x))
		result_edge.append(Vector2(edge[i].y, edge[i].x))
	return {
		"half": FeatureRibbonPlanner.reversed_floats(sides["half"]),
		"outer": result_outer,
		"edge": result_edge,
		"water": FeatureRibbonPlanner.reversed_floats(sides["water"]),
	}


## Metres over which the end of `step` fades: a confluence end (a spoke ending on a through
## piece) or a source; 0 for none.
static func end_fade_m(
	step: Dictionary, pieces: Array, junctions: Dictionary, source: bool
) -> float:
	var piece: Dictionary = pieces[step["piece"]]
	if piece["kind"] == &"spoke" and junctions.has(piece["tile"]):
		return FeatureRibbonPlanner.JUNCTION_FADE_M
	return FeatureRibbonPlanner.SOURCE_FADE_M if source else 0.0


## Per-sample opacity factor in [0, 1]: 0 at an end that fades, rising linearly to 1 over
## `start_m` / `end_m` metres.
static func fade(line: PackedVector2Array, start_m: float, end_m: float) -> PackedFloat32Array:
	var along := FeatureRibbonPlanner.arc_length_m(line)
	var result := PackedFloat32Array()
	result.resize(line.size())
	var total := along[line.size() - 1] if line.size() > 0 else 0.0
	for i in line.size():
		var f := 1.0
		if start_m > 0.0:
			f = minf(f, along[i] / start_m)
		if end_m > 0.0:
			f = minf(f, (total - along[i]) / end_m)
		result[i] = clampf(f, 0.0, 1.0)
	return result


static func taper(distance_from_source: float) -> float:
	return lerpf(
		FeatureRibbonPlanner.RIVER_SOURCE_WIDTH,
		1.0,
		TerrainNoise.smooth(
			0.0, MapScale.to_units(FeatureRibbonPlanner.SOURCE_TAPER_M), distance_from_source
		)
	)


## The river's sideways meander: every sample moves along its normal by low-frequency noise of
## its world position, limited so it keeps WALL_MARGIN from the walls of its hex that the piece
## does not cross (the crossing sides may slide a little along the side).
static func meander(
	line: PackedVector2Array, tiles: PackedVector2Array, junctions: Dictionary
) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(line.size())
	var count := line.size()
	var closed := count > 2 and line[0].is_equal_approx(line[count - 1])
	# Within reach of the neighbouring tiles' junctions only (about one hex).
	var calm := minf(MapScale.to_units(FeatureRibbonPlanner.JUNCTION_CALM_M), 1.5)
	for i in count:
		var p := line[i]
		var dir := FeatureRibbonPlanner.direction(line, i, closed)
		var normal := Vector2(-dir.y, dir.x)
		var main := TerrainNoise.value_noise(
			p.x / MapScale.to_units(FeatureRibbonPlanner.MEANDER_WAVELENGTH_M),
			p.y / MapScale.to_units(FeatureRibbonPlanner.MEANDER_WAVELENGTH_M),
			FeatureRibbonPlanner.MEANDER_SEED
		)
		var fine := TerrainNoise.value_noise(
			p.x / MapScale.to_units(FeatureRibbonPlanner.MEANDER_FINE_WAVELENGTH_M),
			p.y / MapScale.to_units(FeatureRibbonPlanner.MEANDER_FINE_WAVELENGTH_M),
			FeatureRibbonPlanner.MEANDER_FINE_SEED
		)
		var offset := (
			MapScale.to_units(FeatureRibbonPlanner.MEANDER_MAIN_M) * (2.0 * main - 1.0)
			+ MapScale.to_units(FeatureRibbonPlanner.MEANDER_FINE_M) * (2.0 * fine - 1.0)
		)
		var tile := Vector2i(tiles[i])
		# Calm at confluences, so a tributary still ends on the main river's centreline (a
		# junction within the calm distance lies in the sample's tile or a neighbour).
		if not junctions.is_empty():
			for t: Vector2i in [tile] + Hex.neighbors(tile):
				if junctions.has(t):
					var d := p.distance_to(junctions[t])
					if d < calm:
						offset *= TerrainNoise.smooth(0.05, calm, d)
		# Pull the offset back while the moved point comes closer to a wall than WALL_MARGIN
		# (or than the unmoved point already is).
		var keep := minf(
			FeatureRibbonPlanner.hex_margin_loose(p, tile), FeatureRibbonPlanner.WALL_MARGIN
		)
		for _k in 6:
			if FeatureRibbonPlanner.hex_margin_loose(p + normal * offset, tile) >= keep - 1e-6:
				break
			offset *= 0.5
		if FeatureRibbonPlanner.hex_margin_loose(p + normal * offset, tile) < keep - 1e-6:
			offset = 0.0
		result[i] = p + normal * offset
	if closed:
		result[count - 1] = result[0]
	return result
