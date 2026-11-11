class_name StaffMapInstallations
extends Control
## The installation markers of the staff map (TASK-097a) in screen space, one
## StaffMapInstallationMarker per installation of both sides (no fog yet), placed up-left of the
## hex centre so a formation counter on the same hex stays readable. StaffMap calls layout() when
## the camera moved and refresh() after every event; picking is a 2D hit test (marker_at).
## Reads the OperationalState only.

## Offset of a marker from its hex centre on screen.
const OFFSET := Vector2(-26, -22)
## What an installation gives (translation keys, English text), per class.
const GIVES := {
	&"airfield": "Fire support in nearby battles",
	&"depot": "Supply for nearby formations",
	&"c2": "Command and control of the front",
	&"air_defence": "Intercepts incoming strikes",
}
const CLASS_NAMES := {
	&"airfield": "Airfield",
	&"depot": "Depot",
	&"c2": "Command post",
	&"air_defence": "Air defence",
}

var _state: OperationalState
var _markers := {}  # StringName -> StaffMapInstallationMarker
var _points := {}  # StringName -> Vector2 (screen, hex centre)
var _hovered: StringName = &""
var _depth := 1.0


func _init() -> void:
	name = "Installations"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Facts for the hover card (pure): name, class name, country name, integrity %, what it gives.
## Texts are translated.
static func info(state: OperationalState, installation: Installation) -> Dictionary:
	var definition := CountryDefinition.find(state.country_at(installation.coord))
	var country := ""
	if definition != null:
		country = String(TranslationServer.translate(definition.display_name))
	return {
		"name": String(TranslationServer.translate(installation.display_name)),
		"class": String(TranslationServer.translate(CLASS_NAMES.get(installation.class_id, ""))),
		"country": country,
		"integrity": installation.integrity,
		"destroyed": installation.destroyed(),
		"gives": String(TranslationServer.translate(GIVES.get(installation.class_id, ""))),
		"owner": installation.owner,
	}


func build(state: OperationalState, palette: StaffMapPalette) -> void:
	_state = state
	for installation in state.installations:
		var marker := StaffMapInstallationMarker.new()
		marker.setup(installation, palette)
		marker.depth = _depth
		add_child(marker)
		_markers[installation.id] = marker


## Slab depth of every marker (0 = flat map, 1 = tilted; StaffMapCounter.depth_for_pitch).
func set_depth(value: float) -> void:
	_depth = value
	for id: StringName in _markers:
		marker(id).depth = value


func marker(installation_id: StringName) -> StaffMapInstallationMarker:
	return _markers.get(installation_id) as StaffMapInstallationMarker


func marker_count() -> int:
	return _markers.size()


## Re-reads the integrities (after an event).
func refresh() -> void:
	for installation in _state.installations:
		var m := marker(installation.id)
		if m != null and m.integrity != installation.integrity:
			m.set_integrity(installation.integrity)


## `points`: installation id -> screen position of its hex centre.
func layout(points: Dictionary) -> void:
	_points = points
	var view_rect := Rect2(-1e5, -1e5, 2e5, 2e5)
	if is_inside_tree():
		view_rect = get_viewport_rect().grow(
			StaffMapInstallationMarker.RADIUS * StaffMapCounter.TILE_SCALE * 2.0
		)
	for id: StringName in _markers:
		var m := marker(id)
		var at: Vector2 = _points.get(id, Vector2(-1e6, -1e6)) + OFFSET
		m.visible = view_rect.has_point(at)
		m.position = at.round()


## The id of the marker under a screen point, or &"".
func marker_at(screen: Vector2) -> StringName:
	var children := get_children()
	for i in range(children.size() - 1, -1, -1):  # topmost first
		var m := children[i] as StaffMapInstallationMarker
		if m != null and m.visible and m.hits(screen - m.position):
			return m.installation_id
	return &""


func set_hovered(installation_id: StringName) -> void:
	if installation_id == _hovered:
		return
	if _markers.has(_hovered):
		marker(_hovered).hovered = false
	_hovered = installation_id
	if _markers.has(installation_id):
		marker(installation_id).hovered = true
		move_child(marker(installation_id), -1)  # the pointed-at marker is never covered


func hovered() -> StringName:
	return _hovered
