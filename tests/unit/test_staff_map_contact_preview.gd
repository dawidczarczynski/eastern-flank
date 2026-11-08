extends TestCase
## The staff map's debug contact-map preview (TASK-094b): the cut's outline in staff map space,
## the pick flow, the draft and the numbers on the shipped theatre; the battle scene's setup entry.

## Theatre: 1 km hexes, hex (0, 0) at E 7600 / N -5000; layer: 250 m tiles from E 0 / N 0.
const THEATRE_E := 7600.0
const THEATRE_N := -5000.0

static var _state: OperationalState
static var _theatre: ImportedMap


func before_all() -> void:
	_state = Operation.build(&"suwalki_gap", 1)
	_theatre = ImportedMap.find(_state.map_id)


func after_all() -> void:
	_state = null
	_theatre = null


static func _small_theatre() -> ImportedMap:
	var map := ImportedMap.new()
	map.hex_spacing_m = 1000.0
	map.origin_easting = THEATRE_E
	map.origin_northing = THEATRE_N
	return map


static func _small_layer() -> TacticalLayer:
	var grid := HexGrid.new()
	for row in 8:
		for col in 8:
			grid.set_terrain(MapGenerator.offset_to_axial(col, row), Terrain.Type.PLAINS)
	return TacticalLayer.from_grid(grid, 8, 8)


## Staff map point (hex units of the theatre) of a layer tile's centre.
static func _staff_point(theatre: ImportedMap, layer: TacticalLayer, tile: Vector2i) -> Vector2:
	var p := layer.offset_to_projected(tile)
	var m := theatre.hex_spacing_m / Hex.SQRT3
	return Vector2((p.x - theatre.origin_easting) / m, (theatre.origin_northing - p.y) / m)


func test_outline_is_a_closed_rectangle_padded_by_half_a_tactical_hex() -> void:
	var theatre := _small_theatre()
	var layer := _small_layer()
	var corners := StaffMapContactPreview.cut_outline(theatre, layer, Rect2i(0, 0, 4, 4))
	assert_eq(corners.size(), 5)
	assert_eq(corners[0], corners[4], "closed")
	var m := theatre.hex_spacing_m / Hex.SQRT3
	# NW corner: tile (0, 0) at E 0 / N 0, half a spacing west, one hex radius north.
	assert_true(
		corners[0].distance_to(Vector2(-125.0 - THEATRE_E, THEATRE_N - 144.3376) / m) < 1e-4
	)
	# 4 columns (the odd last row shifted half a hex east) + half a hex each side.
	assert_true(is_equal_approx((corners[1].x - corners[0].x) * m, 4.5 * 250.0))
	# 3 row steps + a hex radius north and south.
	assert_true(absf((corners[2].y - corners[1].y) * m - (3.0 * 216.5064 + 2.0 * 144.3376)) < 0.01)
	assert_eq(corners[1].y, corners[0].y)
	assert_eq(corners[3].x, corners[0].x)


func test_outline_contains_every_tile_of_the_region() -> void:
	var theatre := _small_theatre()
	var layer := _small_layer()
	var region := Rect2i(2, 2, 5, 4)
	var corners := StaffMapContactPreview.cut_outline(theatre, layer, region)
	var box := Rect2(corners[0], corners[2] - corners[0])
	for row in range(region.position.y, region.end.y):
		for col in range(region.position.x, region.end.x):
			assert_true(box.has_point(_staff_point(theatre, layer, Vector2i(col, row))))
	assert_false(box.has_point(_staff_point(theatre, layer, Vector2i(1, 2))), "west of the cut")


func test_pick_needs_an_adjacent_defender_hex() -> void:
	var preview := StaffMapContactPreview.new(_state, _theatre)
	var a := _state.formations[0].coord
	assert_true(preview.pick(a))
	assert_eq(preview.picked, 1)
	assert_false(preview.pick(a + Vector2i(3, 0)), "not adjacent")
	assert_true(preview.problem != "")
	assert_eq(preview.picked, 1, "still waiting for the defender")
	assert_false(preview.pick(Vector2i(-999, -999)), "off the map")


func test_a_pair_builds_the_cut_around_the_contact() -> void:
	var preview := StaffMapContactPreview.new(_state, _theatre)
	var formation := _first_fieldable()
	var a := formation.coord
	var d := _land_neighbour(a)
	assert_true(preview.pick_pair(a, d), preview.problem)
	assert_eq(preview.attacker, formation)
	assert_false(preview.attacker_stand_in)
	var setup := preview.setup
	assert_eq(setup.map_id, preview.settings().layer_for(_state.map_id))
	assert_eq(setup.map_region.size, Vector2i(preview.settings().width, preview.settings().height))
	assert_eq(setup.attacker, formation.owner_id)
	var counts := preview.company_counts()
	assert_eq(counts[0] + counts[1], setup.companies.size())
	assert_eq(counts[formation.owner_id], formation.companies.size())
	assert_true(preview.build_us > 0 and preview.state_us > 0)
	assert_true(preview.chunks_loaded > 0)
	# The outline surrounds the midpoint of the two operational hexes.
	var corners := preview.outline()
	var box := Rect2(corners[0], corners[2] - corners[0])
	var wa := Hex.to_world(a, 1.0)
	var wd := Hex.to_world(d, 1.0)
	assert_true(box.has_point(Vector2(wa.x + wd.x, wa.z + wd.z) * 0.5))
	assert_true(box.size.x > 1.0 and box.size.x < 4.0, "about 10 km on 5 km hexes")
	var text := "\n".join(preview.lines())
	assert_true(text.contains("40 × 30"), text)
	assert_true(text.contains("Build"), text)
	assert_true(text.contains("Chunks loaded"), text)
	# A click after the build starts over with a new attacker.
	assert_true(preview.pick(d))
	assert_eq(preview.picked, 1)
	assert_true(preview.setup == null)


func test_empty_hexes_use_stand_in_formations() -> void:
	var preview := StaffMapContactPreview.new(_state, _theatre)
	var a := _empty_land_hex()
	assert_true(preview.pick_pair(a, _land_neighbour(a)), preview.problem)
	assert_true(preview.attacker_stand_in)
	assert_true(preview.defender_stand_in)
	assert_true(preview.attacker.owner_id != preview.defender.owner_id)
	assert_true("\n".join(preview.lines()).contains("stand-in"))


func test_the_draft_leaves_the_operation_rng_alone() -> void:
	var before := _state.rng.state
	var formation := _first_fieldable()
	var setup := StaffMapContactPreview.draft(_state, formation, formation)
	assert_eq(_state.rng.state, before)
	assert_eq(setup.map_id, _state.map_id)
	assert_eq(setup.companies.size(), 2 * formation.companies.size())


func test_the_pending_setup_is_taken_once() -> void:
	var setup := BattleSetup.new()
	BattleOptions.pending_setup = setup
	assert_eq(BattleOptions.take_pending_setup(), setup)
	assert_true(BattleOptions.pending_setup == null)
	assert_true(BattleOptions.take_pending_setup() == null)


static func _first_fieldable() -> Formation:
	for formation in _state.formations:
		if StaffMapContactPreview.fieldable(_state, formation):
			return formation
	return null


static func _land_neighbour(c: Vector2i) -> Vector2i:
	for n in Hex.neighbors(c):
		if _state.grid.has_tile(n) and _state.grid.get_terrain(n) != Terrain.Type.WATER:
			return n
	return c


## A land hex near the theatre's centre with no formation on it.
static func _empty_land_hex() -> Vector2i:
	for row in range(30, 60):
		var c := MapGenerator.offset_to_axial(20, row)
		if (
			_state.grid.has_tile(c)
			and _state.grid.get_terrain(c) != Terrain.Type.WATER
			and _state.formation_at(c) == null
			and _land_neighbour(c) != c
		):
			return c
	return Vector2i.ZERO
