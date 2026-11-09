extends TestCase
## Commander's briefing of a campaign battle (TASK-094c, GDD "Player roles"): Mission (task + the
## objectives in words) and Intent (the leader's order) from BattleSetup.Mission, the one-line
## mission reminder of the battle HUD and the report wording of the end screen.

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


## Player 1 attacks the objective (3, 4), player 0 holds it; 12 turns.
static func _setup() -> BattleSetup:
	var setup := BattleSetup.new()
	setup.attacker = 1
	setup.objectives = ContactMap.objectives(1, Vector2i(3, 4), 12)
	var tasks: Array[StringName] = [&"defend", &"attack"]
	for player in 2:
		var mission := BattleSetup.Mission.new()
		mission.task = tasks[player]
		mission.intent_key = ContactRules.INTENT_MOVE if player == 1 else ContactRules.INTENT_HOLD
		mission.intent_args = [2, 5]
		mission.formation_name = "Formation %d" % player
		setup.missions.append(mission)
	return setup


func test_attacker_mission_names_the_objectives() -> void:
	var lines := BattleBriefing.mission_lines(_setup(), 1)
	assert_eq(lines[0], "Attack")
	assert_true(
		lines.has(
			"Take the objective: a company of yours on it at the end of your turn wins at once"
		),
		str(lines)
	)
	assert_true(lines.has("Or destroy every enemy company"), str(lines))
	assert_true(lines.has("The battle ends after turn 12"), str(lines))


func test_defender_mission_holds_the_objective() -> void:
	var lines := BattleBriefing.mission_lines(_setup(), 0)
	assert_eq(lines[0], "Defend")
	assert_true(lines.has("Hold the objective until the end of turn 12"), str(lines))


func test_intent_is_the_leaders_order() -> void:
	assert_true(BattleBriefing.intent(_setup(), 1).begins_with("Advance to hex "))
	assert_true(BattleBriefing.intent(_setup(), 0).begins_with("Hold hex "))


func test_reminder_is_one_line() -> void:
	assert_eq(
		BattleBriefing.reminder(_setup(), 1), "Mission · Attack · Take the objective · 12 turns"
	)
	assert_eq(
		BattleBriefing.reminder(_setup(), 0), "Mission · Defend · Hold the objective · 12 turns"
	)


func test_no_mission_in_scenario_battles() -> void:
	var setup := BattleSetup.new()
	assert_false(BattleBriefing.has_mission(setup, 0))
	assert_true(BattleBriefing.has_mission(_setup(), 0))


func test_panel_shows_mission_and_intent() -> void:
	var briefing := BattleBriefing.new()
	briefing.present(_setup(), 1)
	assert_true(briefing.visible)
	assert_eq(briefing.title_text(), "FORMATION 1")
	assert_true(briefing.mission_text().begins_with("ATTACK"), briefing.mission_text())
	assert_true(briefing.intent_text().begins_with("ADVANCE TO HEX"), briefing.intent_text())
	briefing.close()
	assert_false(briefing.visible)
	briefing.free()
