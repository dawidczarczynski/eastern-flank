class_name TerrainViewController
extends BattleController
## Devtools terrain viewer (docs/TOOLS.md, not part of the game): the battle scene's terrain on
## its own – the cut of the tactical layer a contact battle at the picked operational hex would
## fight on (TerrainViewSetup), with no units, no battle HUD and no rules to play. Only the camera
## and the grid key (G) work. Esc returns to the staff map's terrain picker.
## The setup comes from BattleOptions.pending_setup, set by the picker (StaffMap --terrain-viewer).

const STAFF_MAP_SCENE := "res://scenes/operational/staff_map.tscn"
const HINT := "TERRAIN VIEWER  ·  %s  ·  G grid  ·  Esc back to the map"


func _initial_state() -> GameState:
	if setup == null:
		push_error("TerrainViewController: no setup – open it from the staff map's terrain viewer")
		return null
	scenario_name = ""
	return Scenario.from_setup(setup)


func _ready() -> void:
	await super._ready()
	if not is_built:
		return
	_hud_root.hide()
	var label := Label.new()
	label.name = "Hint"
	label.text = HINT % setup.operation_name
	label.position = Vector2(16, 12)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	$HUD.add_child(label)
	$HUD.add_child(FpsOverlay.new())  # shown when the DEVTOOLS FPS OVERLAY switch is on


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file(STAFF_MAP_SCENE)
		return
	super(event)


## No side plays: nothing to do on a click or an Enter.
func _on_camera_clicked(_screen_position: Vector2, _button: MouseButton) -> void:
	pass


func _end_human_turn() -> void:
	pass


func _run_ai_turns() -> void:
	pass
