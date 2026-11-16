class_name StaffMapRightDockView
extends Control
## The view of the right-hand tabbed dock (TASK-174a, docs/design/operational_map/
## slide_in_panels.html variant B): a full-viewport, click-through holder for the section panels
## (StaffMapWindow with `Dock.TABBED`, 420 px, flush right between the turn bar and the bottom
## bar) and the vertical tab strip on the dock's inner edge. `set_progress` slides everything in
## (0 = off screen, 1 = open); the owner (StaffMap) animates it together with the camera inset.
## Holds no state of the dock itself (StaffMapRightDock does).

signal tab_pressed(tab: StaffMapRightDock.Tab)

const FADE_SECONDS := 0.12
const TAB_SIZE := Vector2(30, 96)
const TAB_GAP := 4.0
const TAB_TOP := 16.0  # below the dock's top edge

var _panels := {}  # StaffMapRightDock.Tab -> StaffMapWindow
var _tabs := {}  # StaffMapRightDock.Tab -> DockTab
var _strip: Control
var _progress := 0.0
var _fade: Tween


## One vertical tab: 30 x 96, the label reads bottom to top; the active one is amber.
class DockTab:
	extends Control

	signal pressed

	var label := ""
	var active := false
	var _hover := false

	func _init(text: String) -> void:
		label = text
		custom_minimum_size = TAB_SIZE
		size = TAB_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func set_active(value: bool) -> void:
		active = value
		queue_redraw()

	func _set_hover(value: bool) -> void:
		_hover = value
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var fill := Color(UiPalette.AMBER, 0.12) if active else UiPalette.PANEL_STRONG
		var edge := UiPalette.AMBER if active else UiPalette.LINE
		var ink := (
			UiPalette.AMBER if active else (UiPalette.HUD_TEXT if _hover else UiPalette.HUD_MUTED)
		)
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, UiPalette.PANEL_STRONG)
		draw_rect(rect, fill)
		# border on the top, left and bottom (the right edge touches the dock)
		var outline := PackedVector2Array(
			[
				Vector2(size.x, 0.5),
				Vector2(0.5, 0.5),
				Vector2(0.5, size.y - 0.5),
				Vector2(size.x, size.y - 0.5)
			]
		)
		draw_polyline(outline, edge, 1.0)
		var font := HudTheme.display(700, 2)
		var text := label.to_upper()
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_set_transform(Vector2(size.x * 0.5 + 4.0, (size.y + width) * 0.5), -PI / 2.0)
		draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		draw_set_transform(Vector2.ZERO)


func _init() -> void:
	name = "RightDock"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_strip = Control.new()
	_strip.name = "Tabs"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	hide()


## Registers the panel of `tab` (reparented into the dock) and gives it a tab on the strip.
func add_section(tab: StaffMapRightDock.Tab, title: String, panel: StaffMapWindow) -> void:
	if panel.get_parent() != null:
		panel.reparent(self, false)
	else:
		add_child(panel)
	panel.dock_side = StaffMapWindow.Dock.TABBED
	_panels[tab] = panel
	var button := DockTab.new(title)
	button.name = "Tab%d" % int(tab)
	button.pressed.connect(func() -> void: tab_pressed.emit(tab))
	_strip.add_child(button)
	_tabs[tab] = button
	_place_tabs()


func panel(tab: StaffMapRightDock.Tab) -> StaffMapWindow:
	return _panels[tab]


func tab_button(tab: StaffMapRightDock.Tab) -> Control:
	return _tabs[tab]


## The tab strip is shown while a section is open.
func show_tabs(shown: bool) -> void:
	_strip.visible = shown


## Lights the tab of the open section (-1 = none).
func set_active_tab(tab: int) -> void:
	for id: StaffMapRightDock.Tab in _tabs:
		(_tabs[id] as DockTab).set_active(int(id) == tab)


## Sizes the holder to the viewport and puts the panels and tabs on the dock.
func layout(viewport: Vector2) -> void:
	size = viewport
	var height := viewport.y - StaffMapCameraMath.TOP_INSET - float(ActionBar.HEIGHT)
	for tab: StaffMapRightDock.Tab in _panels:
		var window: StaffMapWindow = _panels[tab]
		window.custom_minimum_size = Vector2(StaffMapRightDock.WIDTH, height)
		window.reset_size()
		window.position = StaffMapWindow.dock_position(
			StaffMapWindow.Dock.TABBED, viewport.x, window.size.x
		)
	_place_tabs()


## 0 = off screen on the right, 1 = open. The holder is hidden at 0.
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	position.x = StaffMapRightDock.WIDTH * (1.0 - _progress)
	visible = _progress > 0.0


func progress() -> float:
	return _progress


## The height of the dock (the panels are this tall).
func dock_height() -> float:
	return size.y - StaffMapCameraMath.TOP_INSET - float(ActionBar.HEIGHT)


## Fades `panel` in over 120 ms (a tab swap); the dock itself does not move.
func fade_in(window: Control) -> void:
	if _fade != null:
		_fade.kill()
	window.modulate.a = 1.0
	if not is_inside_tree():
		return
	window.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(window, "modulate:a", 1.0, FADE_SECONDS)


func _place_tabs() -> void:
	var x := size.x - StaffMapRightDock.WIDTH - TAB_SIZE.x
	var y := StaffMapCameraMath.TOP_INSET + TAB_TOP
	var index := 0
	for tab: StaffMapRightDock.Tab in _tabs:
		(_tabs[tab] as Control).position = Vector2(x, y + index * (TAB_SIZE.y + TAB_GAP))
		index += 1
