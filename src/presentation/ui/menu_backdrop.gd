class_name MenuBackdrop
extends Control
## Main menu background (docs/design/operational_map/main_menu.html, variant A "Fracture"): the
## staff map,
## dimmed, with a jagged shard torn open in its lower left that shows the tactical battle, bright
## and graded; a hex marker on the map and two dashed zoom lines lead into the shard – the two
## layers of the game in one picture. Both stills are rendered by tools/menu_backdrop.sh
## (assets/menu/), so they follow the graphics work; a missing file leaves that layer out.
## Presentation only.

const MAP_PATH := "res://assets/menu/staff_map.png"
const BATTLE_PATH := "res://assets/menu/battle.png"
const GRADE := preload("res://assets/shaders/menu_grade.gdshader")
## The shard in the 1440x900 design frame of the proposal, as fractions of the screen.
const DESIGN := Vector2(1440.0, 900.0)
const SHARD := [
	Vector2(0, 380),
	Vector2(170, 340),
	Vector2(240, 410),
	Vector2(430, 370),
	Vector2(500, 470),
	Vector2(690, 440),
	Vector2(740, 560),
	Vector2(930, 600),
	Vector2(960, 740),
	Vector2(820, 800),
	Vector2(870, 900),
	Vector2(0, 900),
]
const MARKER := Vector2(327, 195)  # the zoomed hex on the staff map (design frame)
const MARKER_RADIUS := 22.0
const FUNNEL_TO := [1, 3]  # shard vertices the dashed zoom lines end in
## The battle still is shifted (fractions of the screen) so that the Homar-K of
## tools/menu_backdrop.sh sits in the middle of the shard, whole, backblast beside it.
const BATTLE_SHIFT := Vector2(-0.15, 0.09)
const FADE_TIME := 0.5

var _map: TextureRect
var _shard: Polygon2D
var _edge: Line2D
var _glow: Line2D
var _overlay: Control  # hex marker and zoom lines
var _captions: Array[Label] = []


## Screen-covering rectangle for an image of `image` size in a `view` (centred, aspect kept).
static func cover(image: Vector2, view: Vector2) -> Rect2:
	var factor := maxf(view.x / image.x, view.y / image.y)
	var size := image * factor
	return Rect2((view - size) * 0.5, size)


## The shard outline in screen pixels: the design frame stretched over `view`.
static func shard_points(view: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p: Vector2 in SHARD:
		points.append(p / DESIGN * view)
	return points


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map = TextureRect.new()
	_map.texture = _load(MAP_PATH)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.material = _grade(0.5, 0.65, 1.0, Vector3(1, 1, 1))
	add_child(_map)
	_shard = Polygon2D.new()
	_shard.texture = _load(BATTLE_PATH)
	_shard.antialiased = true
	_shard.material = _grade(0.98, 1.3, 1.14, Vector3(1.05, 1.0, 0.93))
	add_child(_shard)
	_glow = _line(Color(0, 0, 0, 0.5), 10.0)
	_edge = _line(Color(UiPalette.AMBER, 0.7), 2.0)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_captions = [_caption("Operational · Staff map"), _caption("Tactical · Suwałki Gap")]
	resized.connect(_layout)
	_layout()
	if is_inside_tree():
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, FADE_TIME)


## Re-places the layers for the current size (also after a window resize).
func _layout() -> void:
	var view := size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var points := shard_points(view)
	_shard.polygon = points
	var uv := PackedVector2Array()
	if _shard.texture != null:
		var image := _shard.texture.get_size()
		var frame := cover(image, view)
		frame.position += BATTLE_SHIFT * view
		for p in points:
			uv.append((p - frame.position) / frame.size * image)
	_shard.uv = uv
	for line in [_glow, _edge]:
		(line as Line2D).points = points
	_glow.position = Vector2(0, -4)
	_captions[0].position = Vector2(44, 56)
	_captions[1].position = Vector2(44, view.y - 44.0 - _captions[1].size.y)
	_overlay.queue_redraw()


## Sets the captions in the current language (also after a language switch).
func refresh_texts() -> void:
	if _captions.is_empty():
		return  # not built yet (_ready runs when the menu enters the tree)
	_captions[0].text = tr("Operational · Staff map").to_upper()
	_captions[1].text = tr("Tactical · Suwałki Gap").to_upper()
	_layout()


func _draw_overlay() -> void:
	var view := size
	var centre := MARKER / DESIGN * view
	var radius := MARKER_RADIUS * view.y / DESIGN.y
	var hex := PackedVector2Array()
	for i in 6:
		hex.append(centre + Vector2.from_angle(deg_to_rad(60.0 * i + 30.0)) * radius)
	_overlay.draw_colored_polygon(hex, Color(UiPalette.AMBER, 0.14))
	hex.append(hex[0])
	_overlay.draw_polyline(hex, UiPalette.AMBER, 2.0, true)
	var points := shard_points(view)
	for i: int in FUNNEL_TO:
		_overlay.draw_dashed_line(centre, points[i], Color(UiPalette.AMBER, 0.5), 1.5, 6.0, true)


func _grade(brightness: float, saturation: float, contrast: float, tint: Vector3) -> Material:
	var material := ShaderMaterial.new()
	material.shader = GRADE
	material.set_shader_parameter(&"brightness", brightness)
	material.set_shader_parameter(&"saturation", saturation)
	material.set_shader_parameter(&"contrast", contrast)
	material.set_shader_parameter(&"tint", tint)
	return material


func _line(color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.closed = true
	line.default_color = color
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	line.antialiased = true
	add_child(line)
	return line


func _caption(text: String) -> Label:
	var label := MenuStyle.label(tr(text).to_upper(), HudTheme.mono(500, 2), 11, UiPalette.AMBER)
	label.add_theme_stylebox_override(
		&"normal", MenuStyle.box(UiPalette.PANEL, Color(UiPalette.AMBER, 0.34))
	)
	add_child(label)
	return label


func _load(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
