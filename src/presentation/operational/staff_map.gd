class_name StaffMap
extends Node3D
## The operational staff map scene (TASK-093a, 2.5D restyle TASK-125): the theatre as a dark
## digital map over a mildly extruded relief, seen by a tilted orthographic camera (no yaw, north
## up). Opens from the main menu ("Operation") or with `tools/run.sh --scene=staff_map`.
## Presentation only: it reads the ImportedMap / HexGrid.
## Camera: drag (left or middle button), WASD / arrows, screen edge pan; wheel zoom around the
## cursor; Ctrl + wheel or Q / E pitch, V flat <-> tilted; clamped to the map. G toggles the grid,
## Esc / Back returns to the menu. Maths in StaffMapCameraMath, picking in StaffMapRelief.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const DEFAULT_MAP := &"suwalki_theatre"
const CARD_OFFSET := Vector2(18, 18)
## How fast the pitch follows its target (1 / s, exponential).
const PITCH_SMOOTHING := 14.0

## Which map to open (the Operation button uses the default).
var map_id: StringName = DEFAULT_MAP
## True once the map is built (the loading notice shows for a frame first).
var is_built := false
## Milliseconds the build took (reported by the screenshot / measure tools).
var build_ms := 0

var _grid: HexGrid
var _palette: StaffMapPalette
var _view: StaffMapView
var _camera: Camera3D
var _card: StaffMapCard
var _hint: Label
var _back: Button
var _hud: CanvasLayer
var _dragging := false
var _min_zoom := 0.1
var _max_zoom := 1.0
var _bounds := Rect2()
var _km_per_unit := 1.0
## Camera state: ground point at the screen centre (world pixels) and zoom (screen px per world
## px), as in v0; pitch in degrees.
var _position := Vector2.ZERO
var _zoom := 1.0
var _pitch := StaffMapCameraMath.PITCH_DEFAULT
var _pitch_target := StaffMapCameraMath.PITCH_DEFAULT
var _tilt := StaffMapCameraMath.PITCH_DEFAULT  # the last tilt, for V
var _last_mouse := Vector2(-1, -1)


func _ready() -> void:
	Engine.max_fps = FramePacing.max_fps(true)
	GameSettings.apply_saved()
	_palette = load(StaffMapPalette.PATH) as StaffMapPalette
	_build_environment()
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	var imported := ImportedMap.find(map_id)
	var loading := LoadingScreen.new()
	loading.set_operation(imported.display_name if imported != null else "")
	loading.set_status("BUILDING THE STAFF MAP")
	_hud.add_child(loading)
	# The notice must be presented before the heavy build blocks the loop.
	await get_tree().process_frame
	await get_tree().process_frame
	var start := Time.get_ticks_msec()
	if imported == null:
		push_error("StaffMap: no map '%s'" % map_id)
		_return_to_menu()
		return
	_grid = imported.to_grid()
	_km_per_unit = imported.hex_spacing_m / Hex.SQRT3 / 1000.0
	_view = StaffMapView.new()
	add_child(_view)
	_view.build(_grid, _palette, imported.hex_spacing_m)
	_bounds = _view.world_bounds()
	_build_camera()
	_build_hud()
	build_ms = Time.get_ticks_msec() - start
	print("Staff map built in %d ms" % build_ms)
	loading.queue_free()
	is_built = true
	refresh_texts()


func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


func _process(delta: float) -> void:
	if not is_built:
		return
	_pitch_by_keys(delta)
	_follow_pitch(delta)
	_pan_by_keys_and_edge(delta)
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if not is_built:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_ESCAPE:
				_return_to_menu()
			KEY_G:
				_view.set_grid_visible(not _view.grid_visible())
			KEY_V:
				_pitch_target = StaffMapCameraMath.toggle_pitch(_pitch_target, _tilt)
		return
	var button := event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE) == 0:
			_dragging = false  # the release went to a button
			return
		_move_camera(_position + StaffMapCameraMath.drag_delta(motion.relative, _zoom, _pitch))


## Sets every text in the current language.
func refresh_texts() -> void:
	if _back == null:
		return  # not built yet; _ready calls it again
	_back.text = "‹ " + tr("Back").to_upper()
	_hint.text = tr("STAFF_MAP_HINT")


func view() -> StaffMapView:
	return _view


func camera() -> Camera3D:
	return _camera


func card() -> StaffMapCard:
	return _card


func pitch() -> float:
	return _pitch


func zoom() -> float:
	return _zoom


## Zoom limits for the current window and pitch (min: the whole theatre, max: ~10 hex rows).
func zoom_limits() -> Vector2:
	return Vector2(_min_zoom, _max_zoom)


## Screenshot / test aid: camera centre (hex units) and zoom (clamped); fades jump to the level.
func debug_focus(centre_hex_units: Vector2, zoom_value: float) -> void:
	_position = centre_hex_units * StaffMapView.UNIT
	_set_zoom(zoom_value)
	_view.set_zoom_level(_view.zoom_level(), true)


## Screenshot / test aid: sets the pitch at once (no smoothing).
func debug_pitch(degrees: float) -> void:
	_pitch = StaffMapCameraMath.clamp_pitch(degrees)
	_pitch_target = _pitch
	if _pitch > 0.5:
		_tilt = _pitch
	_on_pitch_changed()


## Screenshot / test aid: shows the hover card for a hex as if the cursor were over it.
func debug_hover(c: Vector2i) -> void:
	if not _view.has_tile(c):
		return
	_view.highlight(c)
	_card.show_info(StaffMapCard.info(_grid, c))
	_place_card(_screen_of_hex(c))


## The hex under a screen point (picking against the relief); check has_tile.
func hex_at_screen(screen: Vector2) -> Vector2i:
	var ray := StaffMapCameraMath.screen_ray(screen, _viewport_size(), _target(), _scale(), _pitch)
	return StaffMapLayers.hex_at(_view.relief().raycast(ray["origin"], ray["direction"]))


## Screen position of a hex centre on the relief.
func _screen_of_hex(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	var point := _view.relief().surface_point(Vector2(w.x, w.z))
	return StaffMapCameraMath.project(point, _viewport_size(), _target(), _scale(), _pitch)


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _target() -> Vector3:
	return Vector3(_position.x, 0.0, _position.y) / StaffMapView.UNIT


## Screen pixels per hex unit.
func _scale() -> float:
	return _zoom * StaffMapView.UNIT


func _ground_viewport() -> Vector2:
	return StaffMapCameraMath.ground_viewport(_viewport_size(), _pitch)


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _palette.map_void
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	add_child(world)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 1.0
	_camera.far = StaffMapCameraMath.CAMERA_DISTANCE * 2.0
	add_child(_camera)
	_camera.make_current()
	_position = _bounds.get_center()
	_update_limits()
	_set_zoom(_min_zoom)
	_view.set_zoom_level(_view.zoom_level(), true)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_hud() -> void:
	_card = StaffMapCard.new()
	_hud.add_child(_card)
	_back = MenuStyle.button("")
	_back.position = Vector2(16, 16)
	_back.pressed.connect(_return_to_menu)
	_back.focus_mode = Control.FOCUS_NONE
	_hud.add_child(_back)
	_hint = MenuStyle.label("", HudTheme.mono(500, 1), 11, UiPalette.HUD_DESC)
	var plate := MenuStyle.box(UiPalette.PANEL, UiPalette.LINE)
	plate.set_content_margin_all(7)
	_hint.add_theme_stylebox_override(&"normal", plate)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(16, -40)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hint)


func _update_limits() -> void:
	_min_zoom = StaffMapCameraMath.min_zoom(_bounds, _ground_viewport())
	_max_zoom = StaffMapCameraMath.max_zoom(_viewport_size(), StaffMapView.UNIT, _min_zoom)


func _on_viewport_resized() -> void:
	_update_limits()
	_set_zoom(_zoom)


func _set_zoom(zoom_value: float) -> void:
	_zoom = clampf(zoom_value, _min_zoom, _max_zoom)
	_move_camera(_position)


func _move_camera(position: Vector2) -> void:
	_position = StaffMapCameraMath.clamp_position(position, _zoom, _bounds, _ground_viewport())
	_apply_camera()


## Pushes the 2D state to the Camera3D and the view (zoom level, hatch scale).
func _apply_camera() -> void:
	_camera.transform = StaffMapCameraMath.camera_transform(_target(), _pitch)
	_camera.size = _viewport_size().y / _scale()
	_view.set_view_scale(_scale(), _pitch)
	var px_per_km := _scale() / _km_per_unit
	_view.set_zoom_level(
		StaffMapCameraMath.zoom_level(
			px_per_km,
			maxi(_view.zoom_level(), 0),
			_palette.zoom_level_px_per_km,
			_palette.zoom_hysteresis
		)
	)


func _on_pitch_changed() -> void:
	_update_limits()
	_set_zoom(_zoom)


func _pitch_by_keys(delta: float) -> void:
	var direction := (
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	)
	if direction != 0.0:
		_set_pitch_target(_pitch_target + direction * StaffMapCameraMath.PITCH_KEY_SPEED * delta)
		_pitch = _pitch_target  # held keys drive the pitch directly (already smooth)
		_on_pitch_changed()


func _set_pitch_target(degrees: float) -> void:
	_pitch_target = StaffMapCameraMath.clamp_pitch(degrees)
	if _pitch_target > 0.5:
		_tilt = _pitch_target


func _follow_pitch(delta: float) -> void:
	if is_equal_approx(_pitch, _pitch_target):
		return
	var t := 1.0 - exp(-PITCH_SMOOTHING * delta)
	_pitch = lerpf(_pitch, _pitch_target, t)
	if absf(_pitch - _pitch_target) < 0.05:
		_pitch = _pitch_target
	_on_pitch_changed()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var notches := event.factor if event.factor > 0.0 else 1.0
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				notches = -notches
			if event.ctrl_pressed:
				_set_pitch_target(_pitch_target + notches * StaffMapCameraMath.PITCH_WHEEL_STEP)
			else:
				_zoom_at(notches, event.position)


func _zoom_at(notches: float, cursor: Vector2) -> void:
	var new_zoom := StaffMapCameraMath.zoom_by(_zoom, notches, _min_zoom, _max_zoom)
	var size := _viewport_size()
	var moved := StaffMapCameraMath.zoom_about(
		_position,
		_zoom,
		new_zoom,
		StaffMapCameraMath.ground_cursor(cursor, size, _pitch),
		_ground_viewport()
	)
	_zoom = new_zoom
	_move_camera(moved)


func _pan_by_keys_and_edge(delta: float) -> void:
	var direction := Vector2(
		(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		),
		(
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		)
	)
	if direction == Vector2.ZERO and not _dragging:
		direction = _edge_direction()
	if direction != Vector2.ZERO:
		var step := direction.normalized() * StaffMapCameraMath.KEY_PAN_SPEED * delta
		_move_camera(_position - StaffMapCameraMath.drag_delta(step, _zoom, _pitch))


## Pan direction from the cursor touching the window edge (focused window only).
func _edge_direction() -> Vector2:
	if not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var size := _viewport_size()
	var mouse := get_viewport().get_mouse_position()
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > size.x or mouse.y > size.y:
		return Vector2.ZERO
	var margin := StaffMapCameraMath.EDGE_MARGIN
	return Vector2(
		float(mouse.x >= size.x - margin) - float(mouse.x <= margin),
		float(mouse.y >= size.y - margin) - float(mouse.y <= margin)
	)


func _update_hover() -> void:
	if _dragging or not DisplayServer.window_is_focused():
		return
	var mouse := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mouse):
		_clear_hover()
		return
	var c := hex_at_screen(mouse)
	if not _view.has_tile(c):
		_clear_hover()
		return
	if c != _view.hovered() or not _card.visible:
		_view.highlight(c)
		_card.show_info(StaffMapCard.info(_grid, c))
	if mouse != _last_mouse:
		_place_card(mouse)
		_last_mouse = mouse


func _clear_hover() -> void:
	_view.highlight(StaffMapView.NO_HEX)
	_card.hide()


## Puts the card next to `screen`, kept inside the window.
func _place_card(screen: Vector2) -> void:
	var size := _viewport_size()
	var at := screen + CARD_OFFSET
	if at.x + _card.size.x > size.x:
		at.x = screen.x - CARD_OFFSET.x - _card.size.x
	if at.y + _card.size.y > size.y:
		at.y = screen.y - CARD_OFFSET.y - _card.size.y
	_card.position = at


func _return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
