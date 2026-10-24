extends Node3D
## In-game unit catalog (TASK-084): browse every unit, orbit and zoom around its model and play
## the animations it has. The 3D scene lives in CatalogStage, the camera maths in OrbitMath, the
## button table in CatalogAnimations; this script is the UI and the input. No GameState, no rules.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LEFT_WIDTH := 260.0
const RIGHT_WIDTH := 300.0
const MARGIN := 16.0
const AUTO_ROTATE_SPEED := 0.45  # rad/s
const CAMERA_SMOOTHING := 14.0
const FAR := 60.0

var quality: Dictionary = {}

var _stage := CatalogStage.new()
var _camera := Camera3D.new()
var _yaw := OrbitMath.DEFAULT_YAW
var _pitch := OrbitMath.DEFAULT_PITCH
var _distance := 1.0
var _target := Vector3.ZERO
var _radius := 1.0
var _dragging := false
var _auto_rotate := false
var _faction_index := 0
var _definition: UnitDefinition
var _unit_buttons := {}  # unit id -> Button
var _anim_buttons := {}  # animation id -> Button
var _info: VBoxContainer
var _anim_box: HFlowContainer
var _faction_box: HBoxContainer
var _title_label: Label
var _hint: Label


func _ready() -> void:
	Engine.max_fps = FramePacing.max_fps(true)
	_setup_quality()
	_stage.quality = quality
	add_child(_stage)
	_camera.fov = OrbitMath.FOV_DEGREES
	_camera.near = 0.02
	_camera.far = FAR
	_camera.current = true
	add_child(_camera)
	_stage.state_changed.connect(_refresh_animation_buttons)
	_build_ui()
	var groups := CatalogUnits.grouped()
	if not groups.is_empty():
		select_unit((groups[0]["units"] as Array)[0])


func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


func stage() -> CatalogStage:
	return _stage


## The unit shown, null before the first selection.
func selected_unit() -> UnitDefinition:
	return _definition


## Camera state (yaw, pitch, distance), for tests and the screenshot tool.
func orbit_state() -> Dictionary:
	return {"yaw": _yaw, "pitch": _pitch, "distance": _distance}


## Sets the orbit camera; the values are clamped like input.
func set_orbit(yaw: float, pitch: float, distance: float) -> void:
	_yaw = OrbitMath.wrap_yaw(yaw)
	_pitch = OrbitMath.clamp_pitch(pitch)
	_distance = OrbitMath.clamp_distance(distance, _radius)
	_place_camera()


## Shows a unit (faction index 0 = the first faction that fields it), resets the camera.
func select_unit(definition: UnitDefinition, faction_index := 0) -> void:
	_definition = definition
	_faction_index = faction_index
	for id: StringName in _unit_buttons:
		(_unit_buttons[id] as Button).set_pressed_no_signal(id == definition.id)
	_show_model()
	_rebuild_side_panel()


## Rebuilds the model in a fresh state (also the Reset button after Hit and Death).
func reset_model() -> void:
	_show_model(false)
	_refresh_animation_buttons()


func reset_camera() -> void:
	var state := OrbitMath.default_state(_radius)
	_yaw = state["yaw"]
	_pitch = state["pitch"]
	_distance = state["distance"]
	_place_camera()


func _setup_quality() -> void:
	if quality.is_empty():
		var override := GraphicsQuality.parse_override(OS.get_cmdline_user_args())
		var level: GraphicsQuality.Level
		if override >= 0:
			level = override as GraphicsQuality.Level
		else:
			level = GraphicsQuality.detect(
				RenderingServer.get_current_rendering_method(),
				RenderingServer.get_video_adapter_name()
			)
		quality = GraphicsQuality.features(level)
	var environment := _stage.world_environment().environment
	GraphicsQuality.apply_environment(environment, quality)
	environment.ssao_enabled = false  # a single model on a disc needs no ambient occlusion pass
	environment.ssil_enabled = false
	GraphicsQuality.apply_sun(_stage.sun(), quality)
	GraphicsQuality.apply_viewport(get_viewport(), quality)


func _faction_for(definition: UnitDefinition, index: int) -> FactionDefinition:
	var factions := CatalogUnits.factions_for(definition)
	if factions.is_empty():
		return null
	return factions[clampi(index, 0, factions.size() - 1)]


func _show_model(frame_camera := true) -> void:
	_stage.show_unit(_definition, _faction_for(_definition, _faction_index))
	var bounds := _stage.framing_bounds()
	_target = bounds.get_center()
	_radius = OrbitMath.radius(bounds)
	if frame_camera:
		reset_camera()
	else:
		set_orbit(_yaw, _pitch, _distance)


# --- Input and camera -------------------------------------------------------------------------


func _process(delta: float) -> void:
	if _auto_rotate and not _dragging:
		_yaw = OrbitMath.wrap_yaw(_yaw + AUTO_ROTATE_SPEED * delta)
	_place_camera()


func _place_camera() -> void:
	if not is_inside_tree():
		return
	_camera.position = OrbitMath.eye(_target, _yaw, _pitch, _distance)
	_camera.look_at(_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		var state := OrbitMath.dragged(_yaw, _pitch, motion.relative)
		_yaw = state["yaw"]
		_pitch = state["pitch"]
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			go_back()
		elif key.keycode == KEY_HOME:
			reset_camera()


func _on_mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if button.pressed and button.double_click:
				reset_camera()
		MOUSE_BUTTON_WHEEL_UP:
			_distance = OrbitMath.zoomed(_distance, button.factor, _radius)
		MOUSE_BUTTON_WHEEL_DOWN:
			_distance = OrbitMath.zoomed(_distance, -button.factor, _radius)


func go_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# --- UI ---------------------------------------------------------------------------------------


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.add_child(ScreenDecor.new())
	_build_left_panel(root)
	_build_right_panel(root)
	_hint = MenuStyle.label("", HudTheme.mono(500, 1), 11, UiPalette.HUD_MUTED)
	_hint.text = (
		"%s · %s      %s · %s      %s · %s"
		% [
			tr("LMB DRAG"),
			tr("ROTATE"),
			tr("WHEEL"),
			tr("ZOOM"),
			tr("HOME / DOUBLE CLICK"),
			tr("RESET VIEW"),
		]
	)
	var hint_panel := PanelContainer.new()
	hint_panel.add_theme_stylebox_override(
		&"panel", MenuStyle.box(UiPalette.PANEL_HINT, Color(0, 0, 0, 0))
	)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.offset_bottom = -MARGIN
	hint_panel.add_child(_hint)
	root.add_child(hint_panel)


func _build_left_panel(root: Control) -> void:
	var panel := MenuStyle.panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = MARGIN
	panel.offset_right = MARGIN + LEFT_WIDTH
	panel.offset_top = MARGIN
	panel.offset_bottom = -MARGIN
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(column)
	var back := MenuStyle.button("‹ " + tr("Back"))
	back.pressed.connect(go_back)
	column.add_child(back)
	column.add_child(MenuStyle.caption(tr("Unit catalog")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(list)
	var group := ButtonGroup.new()
	for entry in CatalogUnits.grouped():
		var header := MenuStyle.label(
			tr(entry["label"]).to_upper(), HudTheme.mono(600, 2), 11, UiPalette.HUD_MUTED
		)
		list.add_child(header)
		for definition: UnitDefinition in entry["units"]:
			var b := MenuStyle.button(tr(definition.display_name), true)
			b.button_group = group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.tooltip_text = tr(definition.display_name)
			if not UnitModels.has_model(definition.id):
				b.text += " (!)"
				b.tooltip_text = tr("No model yet (placeholder)")
			b.pressed.connect(select_unit.bind(definition, 0))
			list.add_child(b)
			_unit_buttons[definition.id] = b


func _build_right_panel(root: Control) -> void:
	var panel := MenuStyle.panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -MARGIN - RIGHT_WIDTH
	panel.offset_right = -MARGIN
	panel.offset_top = MARGIN
	panel.offset_bottom = -MARGIN
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	panel.add_child(column)
	_title_label = MenuStyle.label("", HudTheme.display(700, 2), 24, UiPalette.HUD_TEXT)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title_label)
	_faction_box = HBoxContainer.new()
	_faction_box.add_theme_constant_override(&"separation", 6)
	column.add_child(_faction_box)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override(&"separation", 4)
	column.add_child(_info)
	column.add_child(MenuStyle.caption(tr("Animations")))
	_anim_box = HFlowContainer.new()
	_anim_box.add_theme_constant_override(&"h_separation", 6)
	_anim_box.add_theme_constant_override(&"v_separation", 6)
	column.add_child(_anim_box)


func _rebuild_side_panel() -> void:
	var definition := _definition
	_title_label.text = tr(definition.display_name).to_upper()
	_rebuild_factions()
	_rebuild_info()
	_rebuild_animation_buttons()


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _rebuild_factions() -> void:
	_clear(_faction_box)
	var factions := CatalogUnits.factions_for(_definition)
	if factions.size() < 2:
		var only := tr(factions[0].display_name) if factions.size() == 1 else ""
		if only != "":
			_faction_box.add_child(
				MenuStyle.label(only.to_upper(), HudTheme.mono(600, 2), 12, UiPalette.HUD_DESC)
			)
		return
	var group := ButtonGroup.new()
	for i in factions.size():
		var b := MenuStyle.button(tr(factions[i].display_name), true)
		b.custom_minimum_size.y = 30.0
		b.add_theme_font_size_override(&"font_size", 12)
		b.button_group = group
		b.set_pressed_no_signal(i == _faction_index)
		b.pressed.connect(select_unit.bind(_definition, i))
		_faction_box.add_child(b)


func _rebuild_info() -> void:
	_clear(_info)
	var d := _definition
	_add_fact("CLASS_%s" % String(d.unit_class).to_upper(), "")
	_add_fact(String(d.mobility).capitalize(), "")
	_add_fact("Hit points", str(d.max_hp))
	_add_fact("Attack", str(d.attack))
	_add_fact("Defense", str(d.defense))
	_add_fact("Moves", str(d.move_points))
	_add_fact("Range", str(d.attack_range))
	var size := _stage.model_size_m()
	_add_fact("Model size", "%.1f × %.1f × %.1f m" % [size.x, size.z, size.y])


## One line "LABEL ........ value"; with an empty value just the label (class, mobility).
func _add_fact(key: String, value: String) -> void:
	var row := HBoxContainer.new()
	var name_label := MenuStyle.label(
		tr(key).to_upper(),
		HudTheme.mono(500, 1),
		11,
		UiPalette.HUD_TEXT if value == "" else UiPalette.HUD_MUTED
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if value != "":
		row.add_child(MenuStyle.label(value, HudTheme.mono(600, 0), 12, UiPalette.HUD_TEXT))
	_info.add_child(row)


func _rebuild_animation_buttons() -> void:
	_clear(_anim_box)
	_anim_buttons.clear()
	var ids: Array[StringName] = []
	ids.append_array(_stage.animations())
	ids.append_array(CatalogAnimations.COMMON)
	for id in ids:
		var toggle := id not in CatalogAnimations.COMMON
		var b := MenuStyle.button(tr(CatalogAnimations.label(id)), toggle)
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override(&"font_size", 12)
		b.pressed.connect(_stage.play.bind(id))
		_anim_box.add_child(b)
		_anim_buttons[id] = b
	var reset := MenuStyle.button(tr("Reset"))
	reset.custom_minimum_size = Vector2(0, 34)
	reset.add_theme_font_size_override(&"font_size", 12)
	reset.pressed.connect(reset_model)
	_anim_box.add_child(reset)
	var rotate := MenuStyle.button(tr("Auto-rotate"), true)
	rotate.custom_minimum_size = Vector2(0, 34)
	rotate.add_theme_font_size_override(&"font_size", 12)
	rotate.set_pressed_no_signal(_auto_rotate)
	rotate.toggled.connect(func(on: bool) -> void: _auto_rotate = on)
	_anim_box.add_child(rotate)
	_refresh_animation_buttons()


## Pressed / disabled state of the animation buttons after the stage changed.
func _refresh_animation_buttons() -> void:
	for id: StringName in _anim_buttons:
		var b := _anim_buttons[id] as Button
		b.disabled = not _stage.can_play(id) and not _stage.is_on(id)
		if b.toggle_mode:
			b.set_pressed_no_signal(_stage.is_on(id))
