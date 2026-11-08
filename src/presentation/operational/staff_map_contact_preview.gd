class_name StaffMapContactPreview
extends RefCounted
## Pure model of the staff map's debug "Contact map" panel (TASK-094b, F9, only with --debug):
## two clicked adjacent operational hexes (attacker, defender) -> a drafted contact battle on the
## real terrain (ContactMap.build_with), its cut as an outline on the staff map and the numbers
## the panel lists. Nothing in the operation changes: the draft is a copy built here (like
## ContactRules._build_setup, but without drawing from the operation's RNG) and the battle state
## is only built to check it opens.
##
## The formations: the one standing on the clicked hex when its companies can be fielded, else a
## stand-in (the first fieldable formation of that player), so any pair of hexes can be tried.

## Seed of the drafted battle (the operation's RNG is not touched).
const DRAFT_SEED := 11

var attacker_hex := Vector2i.ZERO
var defender_hex := Vector2i.ZERO
## 0 = waiting for the attacker hex, 1 = for the defender hex, 2 = both picked.
var picked := 0
## The drafted and built contact battle; null before a build or when it failed.
var setup: BattleSetup
var attacker: Formation
var defender: Formation
var attacker_stand_in := false
var defender_stand_in := false
## Microseconds of ContactMap.build_with and of Scenario.from_setup on its result.
var build_us := 0
var state_us := 0
## Chunks of the tactical layer decoded after the build, and how many this build added.
var chunks_loaded := 0
var chunks_added := 0
## Why the last pick or build failed ("" = it did not).
var problem := ""

var _state: OperationalState
var _theatre: ImportedMap
var _layer: TacticalLayer
var _settings: ContactSettings


## `layer` / `settings` default to the theatre's shipped tactical layer and ContactSettings.
func _init(
	state: OperationalState,
	theatre: ImportedMap,
	layer: TacticalLayer = null,
	settings: ContactSettings = null
) -> void:
	_state = state
	_theatre = theatre
	_settings = settings if settings != null else ContactSettings.shipped()
	_layer = layer
	if _layer == null and _settings != null and _state != null:
		_layer = TacticalLayer.find(_settings.layer_for(_state.map_id))


func layer() -> TacticalLayer:
	return _layer


func settings() -> ContactSettings:
	return _settings


## A click on operational hex `c`: the first click picks the attacker, the second an adjacent
## defender and builds; a click after a build starts over. False (and `problem`) when the hex is
## not on the map or not adjacent to the attacker.
func pick(c: Vector2i) -> bool:
	problem = ""
	if _state == null or not _state.grid.has_tile(c):
		problem = "Not a hex of the theatre"
		return false
	if picked != 1:
		attacker_hex = c
		picked = 1
		setup = null
		return true
	if Hex.distance(attacker_hex, c) != 1:
		problem = "The defender hex must be adjacent to the attacker hex"
		return false
	defender_hex = c
	picked = 2
	return build()


## Picks both hexes at once and builds (screenshot tool, tests).
func pick_pair(attacker_c: Vector2i, defender_c: Vector2i) -> bool:
	picked = 0
	return pick(attacker_c) and pick(defender_c)


## Drafts the battle of the two picked hexes, cuts its map and checks the battle state builds.
func build() -> bool:
	setup = null
	if _theatre == null or _layer == null:
		problem = "No theatre map or tactical layer"
		return false
	attacker = _formation_at(attacker_hex, -1)
	attacker_stand_in = attacker == null or attacker.coord != attacker_hex
	if attacker == null:
		problem = "No formation can stand in for the attacker"
		return false
	defender = _formation_at(defender_hex, 1 - attacker.owner_id)
	defender_stand_in = defender == null or defender.coord != defender_hex
	if defender == null:
		problem = "No formation can stand in for the defender"
		return false
	var before := _layer.loaded_chunks()
	var start := Time.get_ticks_usec()
	var built := ContactMap.build_with(
		draft(_state, attacker, defender), attacker_hex, defender_hex, _theatre, _layer, _settings
	)
	build_us = Time.get_ticks_usec() - start
	chunks_loaded = _layer.loaded_chunks()
	chunks_added = chunks_loaded - before
	if built == null:
		problem = "ContactMap could not build the cut"
		return false
	start = Time.get_ticks_usec()
	var battle := Scenario.from_setup(built)
	state_us = Time.get_ticks_usec() - start
	if battle == null:
		problem = "Scenario.from_setup failed on the cut"
		return false
	setup = built
	return true


## Companies of each player (index = player) in the built setup.
func company_counts() -> Array[int]:
	var counts: Array[int] = [0, 0]
	if setup != null:
		for company in setup.companies:
			if company.player >= 0 and company.player < counts.size():
				counts[company.player] += 1
	return counts


## The cut's outline on the staff map (hex units, x east / y = z south), closed (first corner
## repeated); empty without a built setup.
func outline() -> PackedVector2Array:
	if setup == null:
		return PackedVector2Array()
	return cut_outline(_theatre, _layer, setup.map_region)


## Outline of `region` (offset tiles of `tactical`) in the staff map space of `theatre`: the
## corner tiles' projected centres, padded by half a tactical hex (half the spacing east / west,
## the hex radius north / south), as a closed rectangle NW, NE, SE, SW, NW.
static func cut_outline(
	theatre: ImportedMap, tactical: TacticalLayer, region: Rect2i
) -> PackedVector2Array:
	var north_west := tactical.offset_to_projected(region.position)
	var south_east := tactical.offset_to_projected(region.end - Vector2i.ONE)
	var pad := Vector2(tactical.hex_spacing_m * 0.5, tactical.metres_per_world_unit())
	var west := north_west.x - pad.x
	var east := south_east.x + pad.x
	var north := north_west.y + pad.y
	var south := south_east.y - pad.y
	var m := theatre.hex_spacing_m / Hex.SQRT3
	var to_map := func(e: float, n: float) -> Vector2:
		return Vector2((e - theatre.origin_easting) / m, (theatre.origin_northing - n) / m)
	return PackedVector2Array(
		[
			to_map.call(west, north),
			to_map.call(east, north),
			to_map.call(east, south),
			to_map.call(west, south),
			to_map.call(west, north),
		]
	)


## The panel's text lines.
func lines() -> PackedStringArray:
	var result := PackedStringArray()
	match picked:
		0:
			result.append("Click the attacker hex")
		1:
			result.append("Attacker %s – click an adjacent defender hex" % _offset(attacker_hex))
	if picked == 2 or setup != null:
		result.append("Attacker %s → defender %s" % [_offset(attacker_hex), _offset(defender_hex)])
	if attacker != null and picked == 2:
		result.append("ATT  " + _formation_text(attacker, attacker_stand_in))
	if defender != null and picked == 2:
		result.append("DEF  " + _formation_text(defender, defender_stand_in))
	if setup != null:
		var region := setup.map_region
		var km := Vector2(region.size) * _layer.hex_spacing_m / 1000.0
		result.append(
			(
				"Cut %d × %d hexes (%.1f × %.1f km) at %d, %d"
				% [region.size.x, region.size.y, km.x, km.y, region.position.x, region.position.y]
			)
		)
		var counts := company_counts()
		result.append(
			"Companies  P0 %d · P1 %d (attacker P%d)" % [counts[0], counts[1], setup.attacker]
		)
		result.append(
			"Build %.1f ms · battle state %.1f ms" % [build_us / 1000.0, state_us / 1000.0]
		)
		result.append("Chunks loaded %d (+%d)" % [chunks_loaded, chunks_added])
	if problem != "":
		result.append(problem)
	return result


## A pending contact battle as ContactRules drafts it (TASK-094a), without the operation's RNG:
## `attacker_formation`'s companies, then `defender_formation`'s.
static func draft(
	state: OperationalState, attacker_formation: Formation, defender_formation: Formation
) -> BattleSetup:
	var result := BattleSetup.new()
	result.seed = DRAFT_SEED
	result.map_id = state.map_id
	result.operation_name = state.operation_name
	result.factions = state.player_factions.duplicate()
	result.attacker = attacker_formation.owner_id
	result.terrain = Terrain.definition(state.grid.get_terrain(defender_formation.coord)).id
	result.conditions = [BattleSetup.Conditions.new(), BattleSetup.Conditions.new()]
	for formation in [attacker_formation, defender_formation]:
		for company: Formation.Company in formation.companies:
			var planned := BattleSetup.Company.new()
			planned.player = formation.owner_id
			planned.unit_type = company.unit_type
			planned.strength = company.strength
			planned.ref = company.ref
			result.companies.append(planned)
	return result


## Whether every company of `formation` is in its player's battle faction roster.
static func fieldable(state: OperationalState, formation: Formation) -> bool:
	var faction := FactionRegistry.get_faction(state.player_factions[formation.owner_id])
	if faction == null:
		return false
	for company in formation.companies:
		if faction.find_unit(company.unit_type) == null:
			return false
	return not formation.companies.is_empty()


## The fieldable formation on `c` (of `player` unless -1), else the first fieldable one of that
## player (of player 0 for -1); null when there is none.
func _formation_at(c: Vector2i, player: int) -> Formation:
	var here := _state.formation_at(c)
	if here != null and (player < 0 or here.owner_id == player) and fieldable(_state, here):
		return here
	var wanted := 0 if player < 0 else player
	for formation in _state.formations:
		if formation.owner_id == wanted and fieldable(_state, formation):
			return formation
	return null


func _formation_text(formation: Formation, stand_in: bool) -> String:
	return (
		"%s · P%d · %d coy%s"
		% [
			formation.display_name if formation.display_name != "" else String(formation.id),
			formation.owner_id,
			formation.companies.size(),
			" (stand-in)" if stand_in else "",
		]
	)


static func _offset(c: Vector2i) -> String:
	var o := MapGenerator.axial_to_offset(c)
	return "%d:%d" % [o.x, o.y]
