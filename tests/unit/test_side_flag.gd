extends TestCase
## Side flags next to side names (TASK-127): data, SideFlag, result notice, turn bar.


func _state() -> OperationalState:
	var state := OperationalState.new()
	state.player_sides = [&"nato", &"russia"]
	state.player_factions = [&"poland", &"russia"]
	return state


func _setup() -> BattleSetup:
	var setup := BattleSetup.new()
	setup.attacker = 0
	for player in 2:
		var mission := BattleSetup.Mission.new()
		mission.formation_name = "F%d" % player
		setup.missions.append(mission)
	return setup


func _result(winner: int) -> BattleResult:
	var result := BattleResult.new()
	result.winner = winner
	result.field_holder = winner
	result.retreat = 1 - winner if winner >= 0 else -1
	for player in 2:
		var company := BattleResult.Company.new()
		company.player = player
		company.strength_start = 5
		company.strength_end = 3
		result.companies.append(company)
	return result


func test_every_side_has_a_flag() -> void:
	var dir := DirAccess.open(SideDefinition.SIDES_DIR)
	var found := 0
	for file in dir.get_files():
		var side := SideDefinition.find(StringName(file.get_basename()))
		if side == null:
			continue
		found += 1
		assert_true(side.flag != null, "side %s has a flag" % side.id)
	assert_true(found >= 2)


func test_side_flag_shows_and_hides() -> void:
	var flag := SideFlag.new()
	flag.setup(SideDefinition.find(&"nato"), Color.RED)
	assert_true(flag.visible)
	assert_true(flag.texture != null)
	assert_eq(flag.frame_colour, Color.RED)
	flag.setup(null)
	assert_false(flag.visible)
	var bare := SideDefinition.new()
	flag.setup(bare)
	assert_false(flag.visible)
	flag.free()


func test_result_notice_flags() -> void:
	var notice := StaffMapBattleResult.new()
	var palette := StaffMapPalette.new()
	var state := _state()
	notice.present(state, _setup(), _result(1), palette)
	assert_true(notice.title_flag().visible)
	assert_true(notice.title_flag().texture == SideDefinition.find(&"russia").flag)
	assert_true(notice.tab_flag(0).texture == SideDefinition.find(&"nato").flag)
	assert_true(notice.tab_flag(1).texture == SideDefinition.find(&"russia").flag)
	notice.present(state, _setup(), _result(-1), palette)
	assert_false(notice.title_flag().visible, "no flag on a draw")
	notice.free()
