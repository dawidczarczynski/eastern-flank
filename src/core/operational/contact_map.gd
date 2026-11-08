class_name ContactMap
extends RefCounted
## The tactical map of a contact battle (TASK-094b, GDD "Battle hand-off and auto-resolve"): cuts
## the real terrain around the contact out of the theatre's TacticalLayer, deploys both
## formations' companies facing each other and sets the objectives. Pure: it reads data and
## returns a new BattleSetup; nothing in the operation changes and no RNG is drawn.
##
## - Region: ContactSettings `width` x `height` tactical hexes centred on the tile under the
##   midpoint of the two formations' operational hexes, clamped into the layer, starting on an
##   even row (`region_around`).
## - Objective: the passable tile nearest the cut's centre; the defender holds it (initial
##   owner), the attacker must take it (TAKE_HEXES, immediate win), the defender wins when it
##   still owns it at the turn limit (HOLD_HEXES); otherwise the result is a draw, which leaves
##   the field to the defender; ELIMINATE for both.
## - Deployment (`deploy`): the cut is split into thirds along the attacker -> defender
##   direction; each side's companies, in setup order, take the passable free tile nearest the
##   middle of their third, at least `deploy_spacing` hexes from every placed company.


## `setup` (a pending contact battle of TASK-094a; `map_id` = the operational map) on the real
## terrain: the theatre ImportedMap `setup.map_id` and its tactical layer from the shipped
## ContactSettings. Null with push_error when the map or its layer is missing (see `build_with`).
static func build(
	setup: BattleSetup, attacker_hex: Vector2i, defender_hex: Vector2i
) -> BattleSetup:
	var settings := ContactSettings.shipped()
	var theatre := ImportedMap.find(setup.map_id)
	var layer := TacticalLayer.find(settings.layer_for(setup.map_id))
	if theatre == null or layer == null:
		push_error("ContactMap: no theatre map or tactical layer for '%s'" % setup.map_id)
		return null
	return build_with(setup, attacker_hex, defender_hex, theatre, layer, settings)


## A copy of `setup` with `map_id` = the layer's id, `map_region` = the cut, every company's
## `coord` (local to the cut) and the contact objectives. `attacker_hex` / `defender_hex` are
## the formations' operational hexes on `theatre` (only its geo-reference is read). Null with
## push_error when the layer is smaller than the cut, a company cannot be placed or the setup has
## no valid attacker.
static func build_with(
	setup: BattleSetup,
	attacker_hex: Vector2i,
	defender_hex: Vector2i,
	theatre: ImportedMap,
	layer: TacticalLayer,
	settings: ContactSettings
) -> BattleSetup:
	var result := BattleSetup.from_dict(setup.to_dict())
	if result == null or setup.attacker < 0 or setup.attacker > 1:
		push_error("ContactMap: the setup has no valid attacker")
		return null
	var cut := Vector2i(settings.width, settings.height)
	var centre := centre_tile(attacker_hex, defender_hex, theatre, layer)
	var region := region_around(centre, Vector2i(layer.width, layer.height), cut)
	if region.size == Vector2i.ZERO:
		push_error("ContactMap: layer '%s' is smaller than the %s cut" % [layer.id, cut])
		return null
	var grid := layer.region_grid(region)
	if grid == null:
		return null
	var objective := objective_hex(grid, cut)
	var direction := attack_direction(attacker_hex, defender_hex)
	var coords := deploy(
		grid, cut, direction, result.companies, setup.attacker, objective, settings.deploy_spacing
	)
	if coords.size() != result.companies.size():
		push_error("ContactMap: no room to deploy every company in %s" % region)
		return null
	for i in coords.size():
		result.companies[i].coord = coords[i]
	result.map_id = layer.id
	result.map_region = region
	result.objectives = objectives(setup.attacker, objective, settings.turn_limit)
	return result


## Offset tile of `layer` under the midpoint of the two operational hexes' centres.
static func centre_tile(
	attacker_hex: Vector2i, defender_hex: Vector2i, theatre: ImportedMap, layer: TacticalLayer
) -> Vector2i:
	var size := TerrainField.HEX_SIZE
	var mid := (Hex.to_world(attacker_hex, size) + Hex.to_world(defender_hex, size)) * 0.5
	return layer.projected_to_offset(theatre.easting(mid), theatre.northing(mid))


## The `cut`-sized rectangle (offset columns x rows) centred on `centre` – tile `centre` is at
## local (cut.x / 2, cut.y / 2), one row lower when the start row had to be made even – clamped
## into a layer of `layer_size`. Empty when the layer is smaller than the cut.
static func region_around(centre: Vector2i, layer_size: Vector2i, cut: Vector2i) -> Rect2i:
	if cut.x > layer_size.x or cut.y > layer_size.y or cut.x <= 0 or cut.y <= 0:
		return Rect2i()
	@warning_ignore("integer_division")
	var x := clampi(centre.x - cut.x / 2, 0, layer_size.x - cut.x)
	@warning_ignore("integer_division")
	var y := clampi(centre.y - cut.y / 2, 0, layer_size.y - cut.y)
	y -= y % 2
	return Rect2i(x, y, cut.x, cut.y)


## Unit vector (world x, z) from the attacker's operational hex towards the defender's.
static func attack_direction(attacker_hex: Vector2i, defender_hex: Vector2i) -> Vector2:
	var a := Hex.to_world(attacker_hex, TerrainField.HEX_SIZE)
	var b := Hex.to_world(defender_hex, TerrainField.HEX_SIZE)
	var d := Vector2(b.x - a.x, b.z - a.z)
	return Vector2.RIGHT if d.is_zero_approx() else d.normalized()


## The local axial tile of the cut's objective: the passable tile nearest (hex distance, then
## row, then column) the centre tile (cut.x / 2, cut.y / 2).
static func objective_hex(grid: HexGrid, cut: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	var centre := MapGenerator.offset_to_axial(cut.x / 2, cut.y / 2)
	var best := centre
	var best_key: Array = []
	for r in cut.y:
		for c in cut.x:
			var tile := MapGenerator.offset_to_axial(c, r)
			if not _passable(grid, tile):
				continue
			var key := [Hex.distance(tile, centre), r, c]
			if best_key.is_empty() or key < best_key:
				best_key = key
				best = tile
	return best


## Contact objectives: `hex` held by the defender (1 - attacker), taken by the attacker.
static func objectives(attacker: int, hex: Vector2i, turn_limit: int) -> BattleObjectives:
	var defender := 1 - attacker
	var hexes: Array[Vector2i] = [hex]
	var result := BattleObjectives.new()
	result.turn_limit = turn_limit
	result.hexes = hexes.duplicate()
	result.initial_owners = [defender]
	result.conditions = [
		VictoryCondition.make(VictoryCondition.Kind.TAKE_HEXES, attacker, hexes),
		VictoryCondition.make(VictoryCondition.Kind.HOLD_HEXES, defender, hexes),
		VictoryCondition.make(VictoryCondition.Kind.ELIMINATE, -1),
	]
	return result


## Local axial tile of each company (same order); shorter than `companies` when one cannot be
## placed. The attacker's companies go to the third of the cut nearest the attacker (along
## `direction`, attacker -> defender), the others to the opposite third; each takes the free
## passable tile (not `objective`) nearest the middle of its third that is at least `spacing`
## hexes from every placed company – then any free tile of the third, then of the whole cut.
## Ties: row, then column. Deterministic.
static func deploy(
	grid: HexGrid,
	cut: Vector2i,
	direction: Vector2,
	companies: Array[BattleSetup.Company],
	attacker: int,
	objective: Vector2i,
	spacing: int
) -> Array[Vector2i]:
	@warning_ignore("integer_division")
	var centre := _xz(MapGenerator.offset_to_axial(cut.x / 2, cut.y / 2))
	var low := INF
	var high := -INF
	for r in cut.y:
		for c in cut.x:
			var p := (_xz(MapGenerator.offset_to_axial(c, r)) - centre).dot(direction)
			low = minf(low, p)
			high = maxf(high, p)
	var third := (high - low) / 3.0
	var sides := {}
	for attacking: bool in [true, false]:
		var anchor := centre + direction * (low + third * 0.5 if attacking else high - third * 0.5)
		sides[attacking] = _candidates(
			grid, cut, centre, direction, anchor, objective, low + third, high - third, attacking
		)
	var taken: Array[Vector2i] = []
	var result: Array[Vector2i] = []
	for company in companies:
		var lists: Array = sides[company.player == attacker]
		var tile: Variant = _pick(lists[0], taken, spacing)
		if tile == null:
			tile = _pick(lists[0], taken, 1)
		if tile == null:
			tile = _pick(lists[1], taken, 1)
		if tile == null:
			return result
		taken.append(tile)
		result.append(tile)
	return result


## [tiles of the side's third, all tiles of the cut], each passable, not the objective, nearest
## `anchor` first (world distance, then row, then column).
static func _candidates(
	grid: HexGrid,
	cut: Vector2i,
	centre: Vector2,
	direction: Vector2,
	anchor: Vector2,
	objective: Vector2i,
	attacker_limit: float,
	defender_limit: float,
	attacking: bool
) -> Array:
	var in_third: Array = []
	var anywhere: Array = []
	for r in cut.y:
		for c in cut.x:
			var tile := MapGenerator.offset_to_axial(c, r)
			if tile == objective or not _passable(grid, tile):
				continue
			var world := _xz(tile)
			var entry := [world.distance_squared_to(anchor), r, c, tile]
			anywhere.append(entry)
			var p := (world - centre).dot(direction)
			if (attacking and p <= attacker_limit) or (not attacking and p >= defender_limit):
				in_third.append(entry)
	in_third.sort()
	anywhere.sort()
	return [_tiles(in_third), _tiles(anywhere)]


static func _tiles(entries: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for entry: Array in entries:
		result.append(entry[3])
	return result


## The first tile of `tiles` at least `spacing` hexes from every tile in `taken`; null if none.
static func _pick(tiles: Array[Vector2i], taken: Array[Vector2i], spacing: int) -> Variant:
	for tile in tiles:
		var free := true
		for other in taken:
			if Hex.distance(tile, other) < spacing:
				free = false
				break
		if free:
			return tile
	return null


static func _passable(grid: HexGrid, tile: Vector2i) -> bool:
	var t := grid.get_terrain(tile)
	return t != Terrain.Type.WATER and Terrain.move_cost(t) != Terrain.IMPASSABLE


static func _xz(tile: Vector2i) -> Vector2:
	var w := Hex.to_world(tile, TerrainField.HEX_SIZE)
	return Vector2(w.x, w.z)
