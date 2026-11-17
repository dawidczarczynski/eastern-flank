extends TestCase
## Defender cluster around the objective of a contact battle (TASK-163): ContactMap.deploy.

const CUT := Vector2i(40, 30)


## A CUT-sized grid of plains (local offset tiles); `overrides` maps offset (col, row) -> terrain.
static func _cut_grid(overrides: Dictionary = {}) -> HexGrid:
	var grid := HexGrid.new()
	for row in CUT.y:
		for col in CUT.x:
			var c := MapGenerator.offset_to_axial(col, row)
			grid.set_terrain(c, overrides.get(Vector2i(col, row), Terrain.Type.PLAINS))
	return grid


static func _objective() -> Vector2i:
	return ContactMap.objective_hex(_cut_grid(), CUT)


## Companies of player 0 (attacking) then `defenders` of player 1; deploys west -> east.
static func _deploy(
	grid: HexGrid, attackers: int, defenders: int, spacing := 2, radius := 3
) -> Array[Vector2i]:
	var companies: Array[BattleSetup.Company] = []
	for i in attackers + defenders:
		var company := BattleSetup.Company.new()
		company.player = 0 if i < attackers else 1
		companies.append(company)
	var objective := ContactMap.objective_hex(grid, CUT)
	return ContactMap.deploy(grid, CUT, Vector2.RIGHT, companies, 0, objective, spacing, radius)


func test_defender_radius_is_shipped_and_validated() -> void:
	var settings := ContactSettings.shipped()
	assert_eq(settings.defender_radius, 3)
	assert_eq(settings.problem(), "")
	settings = ContactSettings.new()
	settings.defender_radius = 0
	assert_true(settings.problem() != "")
	settings.defender_radius = -1
	assert_true(settings.problem() != "")
	settings.defender_radius = 1
	assert_eq(settings.problem(), "")


func test_defenders_cluster_within_the_radius_spaced() -> void:
	var objective := _objective()
	var coords := _deploy(_cut_grid(), 6, 6)
	assert_eq(coords.size(), 12)
	for i in range(6, 12):
		var d := Hex.distance(coords[i], objective)
		assert_true(d >= 1 and d <= 3, "distance %d" % d)
		for j in range(6, 12):
			if i != j:
				assert_true(Hex.distance(coords[i], coords[j]) >= 2, "spacing")
	for i in 6:
		for j in range(6, 12):
			assert_true(coords[i] != coords[j], "no shared tile")


func test_defenders_prefer_defence_bonus_over_distance() -> void:
	var objective := _objective()
	var oo := MapGenerator.axial_to_offset(objective)
	var hills := Vector2i(oo.x + 3, oo.y)
	var forest := Vector2i(oo.x - 2, oo.y)
	var grid := _cut_grid({hills: Terrain.Type.HILLS, forest: Terrain.Type.FOREST})
	var coords := _deploy(grid, 0, 2)
	assert_eq(Hex.distance(objective, MapGenerator.offset_to_axial(hills.x, hills.y)), 3)
	assert_eq(coords[0], MapGenerator.offset_to_axial(hills.x, hills.y), "hills first")
	assert_eq(coords[1], MapGenerator.offset_to_axial(forest.x, forest.y), "then forest")


func test_defender_spacing_relaxes_inside_the_radius() -> void:
	var objective := _objective()
	var oo := MapGenerator.axial_to_offset(objective)
	var overrides := {}
	for row in CUT.y:
		for col in CUT.x:
			var t := Vector2i(col, row)
			var d := Hex.distance(MapGenerator.offset_to_axial(col, row), objective)
			if d >= 1 and d <= 3 and not (row == oo.y and col >= oo.x + 1 and col <= oo.x + 3):
				overrides[t] = Terrain.Type.WATER
	var coords := _deploy(_cut_grid(overrides), 0, 3)
	assert_eq(coords.size(), 3)
	for tile in coords:
		assert_true(Hex.distance(tile, objective) <= 3, "stays inside the radius")


func test_defender_radius_widens_when_the_zone_is_full() -> void:
	var objective := _objective()
	var open: Array[Vector2i] = []
	var overrides := {}
	for row in CUT.y:
		for col in CUT.x:
			var d := Hex.distance(MapGenerator.offset_to_axial(col, row), objective)
			if d >= 1 and d <= 3:
				if open.size() < 2 and d == 3:
					open.append(MapGenerator.offset_to_axial(col, row))
				else:
					overrides[Vector2i(col, row)] = Terrain.Type.WATER
	var coords := _deploy(_cut_grid(overrides), 0, 4)
	assert_eq(coords.size(), 4)
	var outside := 0
	for tile in coords:
		if Hex.distance(tile, objective) == 4:
			outside += 1
	assert_eq(outside, 2, "two widened to distance 4")


func test_a_cut_without_room_places_fewer_defenders() -> void:
	var overrides := {}
	for row in CUT.y:
		for col in CUT.x:
			overrides[Vector2i(col, row)] = Terrain.Type.WATER
	var coords := _deploy(_cut_grid(overrides), 0, 2)
	assert_true(coords.size() < 2)


func test_defender_deployment_is_deterministic() -> void:
	assert_eq(_deploy(_cut_grid(), 5, 5), _deploy(_cut_grid(), 5, 5))
