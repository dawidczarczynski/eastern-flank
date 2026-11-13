class_name Session
extends RefCounted
## The campaign across scene changes (TASK-094c, ADR 0015 §5): while a contact battle is played
## the staff map scene is freed, so the Session keeps the OperationalSimulation, the operation
## id, the human's side and the staff map's view settings, plus the battle being played and – after
## "Report to staff" – its result for the staff map's short result notice. Static state (like
## BattleOptions) instead of an autoload node: it survives `change_scene_to_file` the same way and
## works in headless tests and `--script` tools without a project autoload.
##
## Flow: staff map Play battle -> `play_battle` (ContactBattle.prepare cuts the map; the staff map
## hands over its simulation and view) -> battle scene reads `battle` / `human_player` -> end
## screen Report to staff -> `finish_battle` (BattleResult.from_battle -> ResolveBattleCommand
## through the simulation) -> staff map `take_simulation` / `view` / `take_report`. Leaving a
## battle from its menu (`leave_battle`) auto-resolves the rest from the state reached; the main
## menu itself `abandon`s the session (no result).
## Saving (TASK-094d): a staff map that builds a new operation calls `start_campaign`; the
## session keeps the seed and every played battle (`finish_battle`), so `record` gives the whole
## CampaignRecord (the operational commands are the simulation's history). Continue: `resume`
## with a loaded record and its replayed simulation, then the staff map takes it.

const STAFF_MAP_SCENE := "res://scenes/operational/staff_map.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## The operation of the campaign; null when there is none.
static var simulation: OperationalSimulation = null
static var operation_id: StringName = &""
## The side picked on the side selection screen (SideDefinition id) for the operation the staff map
## is about to build; empty = none (command line / tools). The staff map takes it once.
static var chosen_side: StringName = &""
## The player the human commands in the battle (the staff map's viewer when Play was pressed).
static var human_player := 0
## The staff map's view settings when Play was pressed (StaffMap.view_settings).
static var view: Dictionary = {}
## The battle being played (ContactBattle.prepare: the first pending battle, map cut); null when
## none is.
static var battle: BattleSetup = null
## The campaign seed (Operation.build) and the battles played so far, in resolve order.
static var seed_value := 0
static var battles: Array[CampaignRecord.Battle] = []

## The last played battle and its result until the staff map shows them (take_report).
static var _report_setup: BattleSetup = null
static var _report_result: BattleResult = null
static var _report_events: Array[Dictionary] = []
## True from Play until the staff map takes the simulation back.
static var _away := false


## The side picked in the menu, cleared on read; empty when none was picked.
static func take_chosen_side() -> StringName:
	var side := chosen_side
	chosen_side = &""
	return side


## A staff map built a new operation: it becomes the session's campaign (no battles yet).
static func start_campaign(
	p_simulation: OperationalSimulation, p_operation_id: StringName, p_seed: int
) -> void:
	abandon()
	simulation = p_simulation
	operation_id = p_operation_id
	seed_value = p_seed


## The campaign as a CampaignRecord with the human on `viewer`'s side; null without a campaign or
## while a battle is being played (a battle in progress cannot be saved).
static func record(viewer: int) -> CampaignRecord:
	if simulation == null or battle != null:
		return null
	var sides := simulation.state.player_sides
	var side := sides[viewer] if viewer >= 0 and viewer < sides.size() else &""
	return CampaignRecord.from_simulation(simulation, seed_value, side, battles)


## Continue: `p_simulation` (the replay of `p_record`) waits for the staff map (take_simulation),
## viewed by the record's side.
static func resume(p_record: CampaignRecord, p_simulation: OperationalSimulation) -> void:
	abandon()
	simulation = p_simulation
	operation_id = p_record.operation_id
	seed_value = p_record.seed
	battles = p_record.battles.duplicate()
	human_player = maxi(p_record.human_player(p_simulation.state), 0)
	view = {"viewer": human_player}
	_away = true


## True while a simulation waits for the staff map (after a battle or Continue).
static func resuming() -> bool:
	return _away and battle == null and simulation != null


## Hands the campaign over for playing its first pending battle. "" on success; otherwise why
## not (ContactBattle.problem, or `map_failed` when the battle map cannot be cut) and nothing
## changes.
static func play_battle(
	p_simulation: OperationalSimulation, p_operation_id: StringName, viewer: int, p_view: Dictionary
) -> String:
	if p_simulation == null:
		return "no_campaign"
	var problem := ContactBattle.problem(p_simulation.state)
	if problem != "":
		return problem
	var prepared := ContactBattle.prepare(p_simulation.state)
	if prepared == null:
		return "map_failed"
	if p_simulation != simulation:
		battles.clear()
	simulation = p_simulation
	operation_id = p_operation_id
	human_player = viewer
	view = p_view.duplicate(true)
	battle = prepared
	_report_setup = null
	_report_result = null
	_away = true
	return ""


## True while a campaign battle is being played (the battle scene is a campaign battle).
static func in_battle() -> bool:
	return battle != null and simulation != null


## The end screen's Report to staff: the result of `played` (the GameSimulation the battle
## started from `battle`) closes the pending battle through ResolveBattleCommand and the battle
## (setup, tactical commands, result) joins the record. False (and nothing changes) when no
## campaign battle runs, it is not over or the operation rejects the result.
static func finish_battle(played: GameSimulation) -> bool:
	if not in_battle() or played == null or not played.state.is_over():
		return false
	return _close_battle(played, BattleResult.from_battle(battle, played.state), false)


## Leaving a campaign battle that is not over: the rest is auto-resolved from the state the player
## reached (AutoResolve.resolve_from) and closes the pending battle like a played one; the
## commands played so far join the record. False (and nothing changes) when no campaign battle
## runs, it is already over (use `finish_battle`) or the operation rejects the result.
static func leave_battle(played: GameSimulation) -> bool:
	if not in_battle() or played == null or played.state.is_over():
		return false
	var result := AutoResolve.resolve_from(battle, played.state)
	return result != null and _close_battle(played, result, true)


## Closes the pending battle with `result` and records it with the commands of `played`.
static func _close_battle(played: GameSimulation, result: BattleResult, left: bool) -> bool:
	var command := ResolveBattleCommand.new(result)
	if not _execute_collecting(command):
		return false
	var commands := BattleReplay.command_dicts(played.history)
	battles.append(
		(
			CampaignRecord.Battle.concluded(battle, commands, command.result)
			if left
			else CampaignRecord.Battle.played(battle, commands, command.result)
		)
	)
	_report_setup = battle
	_report_result = command.result
	battle = null
	return true


## Auto-resolve (TASK-120): the first pending battle is resolved at once, without a battle scene –
## `AutoResolve.resolve` of the pending setup closes it through ResolveBattleCommand and the
## battle (pending setup, no tactical commands, result) joins the record. "" on success and the
## result waits in `take_report`; otherwise why not (ContactBattle.problem codes, or
## `auto_failed` / `rejected`) and nothing changes.
static func auto_resolve(p_simulation: OperationalSimulation, p_operation_id: StringName) -> String:
	if p_simulation == null:
		return "no_campaign"
	var problem := ContactBattle.problem(p_simulation.state)
	if problem != "":
		return problem
	var setup := p_simulation.state.pending_battles[0]
	var result := AutoResolve.resolve(setup)
	if result == null:
		return "auto_failed"
	if p_simulation != simulation:
		battles.clear()
	simulation = p_simulation
	operation_id = p_operation_id
	if not _execute_collecting(ResolveBattleCommand.new(result)):
		return "rejected"
	battles.append(CampaignRecord.Battle.auto(setup, result))
	_report_setup = setup
	_report_result = result
	return ""


## The simulation for a staff map of `p_operation_id` that is coming back from a battle (once:
## the session stays, but a later staff map builds a new operation); null otherwise.
static func take_simulation(p_operation_id: StringName) -> OperationalSimulation:
	if not _away or battle != null or simulation == null or operation_id != p_operation_id:
		return null
	_away = false
	return simulation


## {setup, result, events} of the battle just reported, once; empty when there is none. `events`
## are the operational events of the resolution (retreat, destruction, battle_consequences) for
## the after-action report (TASK-095).
static func take_report() -> Dictionary:
	if _report_result == null:
		return {}
	var report := {"setup": _report_setup, "result": _report_result, "events": _report_events}
	_report_setup = null
	_report_result = null
	_report_events = []
	return report


## Executes `command` on the session's simulation and keeps its events for `take_report`.
static func _execute_collecting(command: OperationalCommand) -> bool:
	var collected: Array[Dictionary] = []
	var collect := func(event: Dictionary) -> void: collected.append(event)
	simulation.event_emitted.connect(collect)
	var accepted := simulation.execute(command)
	simulation.event_emitted.disconnect(collect)
	if accepted:
		_report_events = collected
	return accepted


## Drops the campaign without a result (Esc to the menu from a campaign battle, the main menu).
static func abandon() -> void:
	chosen_side = &""
	simulation = null
	operation_id = &""
	human_player = 0
	view = {}
	battle = null
	seed_value = 0
	battles = []
	_report_setup = null
	_report_result = null
	_report_events = []
	_away = false


## The only scene change between the staff map and the battle (ADR 0015 §5); no-op without a
## tree (headless tests). The battle scene loads behind the loading screen (SceneLoader).
static func change_scene(tree: SceneTree, path: String) -> void:
	if tree == null:
		return
	if path == BATTLE_SCENE:
		SceneLoader.open(tree, path, battle.operation_name if battle != null else "")
	else:
		tree.change_scene_to_file(path)
