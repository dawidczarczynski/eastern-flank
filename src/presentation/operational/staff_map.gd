class_name StaffMap
extends Node2D
## The operational staff map scene (TASK-093a): the theatre as a flat paper map with a fixed
## top-down camera. Opens from the main menu ("Operation") or directly with
## `tools/run.sh --scene=staff_map`. Presentation only: it reads the ImportedMap / HexGrid.
## Camera: drag (left or middle button), WASD / arrows, screen edge pan; wheel zoom around the
## cursor; clamped to the map. G toggles the grid, Esc / Back returns to the menu.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const DEFAULT_MAP := &"suwalki_theatre"
const CARD_OFFSET := Vector2(18, 18)

## Which map to open (the Operation button uses the default).
var map_id: StringName = DEFAULT_MAP
## True once the map is built (the loading notice shows for a frame first).
var is_built := false
## Milliseconds the build took (reported by the screenshot / measure tools).
var build_ms := 0

var _grid: HexGrid
var _view: StaffMapView
var _camera: Camera2D
var _card: StaffMapCard
var _hint: Label
var _back: Button
var _hud: CanvasLayer
var _dragging := false
var _min_zoom := 0.1
var _max_zoom := 1.0
var _bounds := Rect2()


func _ready() -> void:
	Engine.max_fps = FramePacing.max_fps(true)
	GameSettings.apply_saved()
	get_viewport().msaa_2d = Viewport.MSAA_4X  # smooth line edges; restored in _exit_tree
	_build_background()
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
	var palette := load(StaffMapPalette.PATH) as StaffMapPalette
	_view = StaffMapView.new()
	add_child(_view)
	_view.build(_grid, palette)
	_bounds = _view.world_bounds()
	_build_camera()
	_build_hud()
	build_ms = Time.get_ticks_msec() - start
	print("Staff map built in %d ms" % build_ms)
	loading.queue_free()
	is_built = true
	refresh_texts()


func _exit_tree() -> void:
	get_viewport().msaa_2d = Viewport.MSAA_DISABLED


func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


func _process(delta: float) -> void:
	if not is_built:
		return
	_pan_by_keys_and_edge(delta)
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if not is_built:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			_return_to_menu()
		elif key.keycode == KEY_G:
			_view.set_grid_visible(not _view.grid_visible())
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
		_move_camera(_camera.position - motion.relative / _camera.zoom.x)


## Sets every text in the current language.
func refresh_texts() -> void:
	_back.text = "‹ " + tr("Back").to_upper()
	_hint.text = tr("STAFF_MAP_HINT")


func view() -> StaffMapView:
	return _view


func camera() -> Camera2D:
	return _camera


func card() -> StaffMapCard:
	return _card


## Zoom limits for the current window (min: the whole theatre, max: ~10 hexes).
func zoom_limits() -> Vector2:
	return Vector2(_min_zoom, _max_zoom)


## Screenshot / test aid: camera centre (hex units) and zoom (clamped).
func debug_focus(centre_hex_units: Vector2, zoom: float) -> void:
	_set_zoom(zoom)
	_move_camera(centre_hex_units * StaffMapView.UNIT)


## Screenshot / test aid: shows the hover card for a hex as if the cursor were over it.
func debug_hover(c: Vector2i) -> void:
	if not _view.has_tile(c):
		return
	_view.highlight(c)
	_card.show_info(StaffMapCard.info(_grid, c))
	# The canvas transform follows the camera only at the end of the frame: compute the position.
	var size := get_viewport_rect().size
	_place_card((_hex_world(c) - _camera.position) * _camera.zoom.x + size * 0.5)


func _hex_world(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return Vector2(w.x, w.z) * StaffMapView.UNIT


func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Desk"
	layer.layer = -100
	var desk := ColorRect.new()
	desk.color = (load(StaffMapPalette.PATH) as StaffMapPalette).desk
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(desk)
	add_child(layer)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.make_current()
	_update_limits()
	_set_zoom(_min_zoom)
	_camera.position = _bounds.get_center()
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
	var size := get_viewport_rect().size
	_min_zoom = StaffMapCameraMath.min_zoom(_bounds, size)
	_max_zoom = StaffMapCameraMath.max_zoom(size, StaffMapView.UNIT, _min_zoom)


func _on_viewport_resized() -> void:
	_update_limits()
	_set_zoom(_camera.zoom.x)


func _set_zoom(zoom: float) -> void:
	var z := clampf(zoom, _min_zoom, _max_zoom)
	_camera.zoom = Vector2(z, z)
	_move_camera(_camera.position)


func _move_camera(position: Vector2) -> void:
	_camera.position = StaffMapCameraMath.clamp_position(
		position, _camera.zoom.x, _bounds, get_viewport_rect().size
	)


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
			_zoom_at(notches, event.position)


func _zoom_at(notches: float, cursor: Vector2) -> void:
	var old_zoom := _camera.zoom.x
	var new_zoom := StaffMapCameraMath.zoom_by(old_zoom, notches, _min_zoom, _max_zoom)
	var size := get_viewport_rect().size
	var moved := StaffMapCameraMath.zoom_about(_camera.position, old_zoom, new_zoom, cursor, size)
	_camera.zoom = Vector2(new_zoom, new_zoom)
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
		_move_camera(_camera.position + step / _camera.zoom.x)


## Pan direction from the cursor touching the window edge (focused window only).
func _edge_direction() -> Vector2:
	if not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var size := get_viewport_rect().size
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
	if not get_viewport_rect().has_point(mouse):
		_clear_hover()
		return
	var c := _view.hex_at_world(get_global_mouse_position())
	if not _view.has_tile(c):
		_clear_hover()
		return
	_view.highlight(c)
	_card.show_info(StaffMapCard.info(_grid, c))
	_place_card(mouse)


func _clear_hover() -> void:
	_view.highlight(Vector2i(-100000, -100000))
	_card.hide()


## Puts the card next to `screen`, kept inside the window.
func _place_card(screen: Vector2) -> void:
	var size := get_viewport_rect().size
	var at := screen + CARD_OFFSET
	if at.x + _card.size.x > size.x:
		at.x = screen.x - CARD_OFFSET.x - _card.size.x
	if at.y + _card.size.y > size.y:
		at.y = screen.y - CARD_OFFSET.y - _card.size.y
	_card.position = at


func _return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
