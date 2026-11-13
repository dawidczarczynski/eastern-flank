class_name StaffMapSupportGhosts
extends Control
## Ghost counters of outside support on its way (TASK-121): a dashed hexagon in the side colour at
## the entry hex with the formation count and a caption under it ("in 3 turns", "waiting – Belarus
## closed"). Screen-space like the counters; StaffMap calls layout() when the camera moved and
## refresh() after every event. When the package arrives the real counters appear and the ghost
## goes. Reads only (StaffMapSupportModel.ghosts).

const RADIUS := StaffMapCounter.RADIUS * StaffMapCounter.TILE_SCALE * 0.8
const CAPTION_GAP := 6.0
const CAPTION_SIZE := 11
const DASH_STEPS := 6

var _ghosts: Array[Dictionary] = []
var _nodes: Array[Ghost] = []
var _colour := Color.WHITE


## One ghost marker.
class Ghost:
	extends Control

	var colour := Color.WHITE
	var count := 1
	var caption := ""
	var waiting := false
	var _font: Font = HudTheme.mono(700, 0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	func _draw() -> void:
		var points := PackedVector2Array()
		for i in 7:
			var angle := deg_to_rad(60.0 * i)
			points.append(Vector2(cos(angle), sin(angle)) * StaffMapSupportGhosts.RADIUS)
		draw_colored_polygon(points.slice(0, 6), Color(colour, 0.12))
		for i in 6:
			var from := points[i]
			var to := points[i + 1]
			for step in StaffMapSupportGhosts.DASH_STEPS:
				if step % 2 == 0:
					var a := from.lerp(to, float(step) / StaffMapSupportGhosts.DASH_STEPS)
					var b := from.lerp(to, float(step + 1) / StaffMapSupportGhosts.DASH_STEPS)
					draw_line(a, b, Color(colour, 0.9), 1.5)
		var number := "+%d" % count
		var size := _font.get_string_size(number, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(
			_font, Vector2(-size.x / 2.0, 5.0), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, colour
		)
		var tint := UiPalette.AMBER if waiting else UiPalette.HUD_TEXT
		var text := caption.to_upper()
		var text_size := _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, -1, StaffMapSupportGhosts.CAPTION_SIZE
		)
		var at := Vector2(-text_size.x / 2.0, StaffMapSupportGhosts.RADIUS + 14.0)
		draw_rect(Rect2(at + Vector2(-5, -12), text_size + Vector2(10, 6)), Color(0, 0, 0, 0.65))
		draw_string(
			_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, StaffMapSupportGhosts.CAPTION_SIZE, tint
		)


func _init() -> void:
	name = "SupportGhosts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_colour(colour: Color) -> void:
	_colour = colour


## The ghosts shown (see StaffMapSupportModel.ghosts), rebuilt on every call.
func show_ghosts(ghosts: Array[Dictionary]) -> void:
	_ghosts = ghosts
	for node in _nodes:
		remove_child(node)
		node.queue_free()
	_nodes.clear()
	for ghost in _ghosts:
		var node := Ghost.new()
		node.name = "Ghost_" + String(ghost["package"])
		node.colour = _colour
		node.count = ghost["count"]
		node.caption = ghost["text"]
		node.waiting = ghost["waiting"]
		add_child(node)
		_nodes.append(node)


func ghosts() -> Array[Dictionary]:
	return _ghosts


func count() -> int:
	return _nodes.size()


## Puts every ghost on its entry hex; `project` maps a hex to a screen position.
func layout(project: Callable) -> void:
	var view_rect := Rect2(-1e5, -1e5, 2e5, 2e5)
	if is_inside_tree():
		view_rect = get_viewport_rect().grow(RADIUS * 3.0)
	for i in _nodes.size():
		var at: Vector2 = project.call(_ghosts[i]["coord"])
		_nodes[i].visible = view_rect.has_point(at)
		_nodes[i].position = at.round()
