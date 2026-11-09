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
## through the simulation) -> staff map `take_simulation` / `view` / `take_report`. Esc to the
## menu from a campaign battle and the main menu itself `abandon` the session (no result).

const STAFF_MAP_SCENE := "res://scenes/operational/staff_map.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## The operation of the campaign; null when there is none.
static var simulation: OperationalSimulation = null
static var operation_id: StringName = &""
## The player the human commands in the battle (the staff map's viewer when Play was pressed).
static var human_player := 0
## The staff map's view settings when Play was pressed (StaffMap.view_settings).
static var view: Dictionary = {}
## The battle being played (ContactBattle.prepare: the first pending battle, map cut); null when
## none is.
static var battle: BattleSetup = null

## The last played battle and its result until the staff map shows them (take_report).
static var _report_setup: BattleSetup = null
static var _report_result: BattleResult = null
## True from Play until the staff map takes the simulation back.
static var _away := false


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


## The end screen's Report to staff: the result of `state` (the GameState the battle started
## from `battle`) closes the pending battle through ResolveBattleCommand. False (and nothing
## changes) when no campaign battle runs, it is not over or the operation rejects the result.
static func finish_battle(state: GameState) -> bool:
	if not in_battle() or state == null or not state.is_over():
		return false
	var command := ResolveBattleCommand.new(BattleResult.from_battle(battle, state))
	if not simulation.execute(command):
		return false
	_report_setup = battle
	_report_result = command.result
	battle = null
	return true


## The simulation for a staff map of `p_operation_id` that is coming back from a battle (once:
## the session stays, but a later staff map builds a new operation); null otherwise.
static func take_simulation(p_operation_id: StringName) -> OperationalSimulation:
	if not _away or battle != null or simulation == null or operation_id != p_operation_id:
		return null
	_away = false
	return simulation


## {setup, result} of the battle just reported, once; empty when there is none.
static func take_report() -> Dictionary:
	if _report_result == null:
		return {}
	var report := {"setup": _report_setup, "result": _report_result}
	_report_setup = null
	_report_result = null
	return report


## Drops the campaign without a result (Esc to the menu from a campaign battle, the main menu).
static func abandon() -> void:
	simulation = null
	operation_id = &""
	human_player = 0
	view = {}
	battle = null
	_report_setup = null
	_report_result = null
	_away = false


## The only scene change between the staff map and the battle (ADR 0015 §5); no-op without a
## tree (headless tests).
static func change_scene(tree: SceneTree, path: String) -> void:
	if tree != null:
		tree.change_scene_to_file(path)
