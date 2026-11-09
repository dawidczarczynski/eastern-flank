class_name StaffMapCounters
extends Control
## The formation counters of the staff map (TASK-092b) in screen space: one StaffMapCounter per
## formation (named after its id), placed at the screen projection of its hex centre on the
## relief. StaffMap calls layout() only when the camera moved, so idle frames cost nothing.
## Declutter (stacks with a count badge) follows StaffMapFormations.stack_leaders; picking is a
## 2D hit test (counter_at). Reads the OperationalState only.

var _state: OperationalState
var _palette: StaffMapPalette
var _viewer := 0
var _counters := {}  # StringName -> StaffMapCounter
var _order: Array[StringName] = []  # placement order
var _points := {}  # StringName -> Vector2 (screen)
var _shown: Array[StringName] = []  # visible counters, top last
var _hovered: StringName = &""
var _selected: StringName = &""


func _init() -> void:
	name = "Counters"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func build(state: OperationalState, palette: StaffMapPalette, viewer_player: int) -> void:
	_state = state
	_palette = palette
	_viewer = viewer_player
	for formation in state.formations:
		_add(formation)


## Adds counters for formations that joined after build() (TASK-118): they pulse and, when a
## country of origin is known, carry its ISO tag. Returns the new ids in order.
func sync_new(origins: Dictionary) -> Array[StringName]:
	var added: Array[StringName] = []
	for formation in _state.formations:
		if _counters.has(formation.id):
			continue
		var c := _add(formation)
		var definition := CountryDefinition.find(StringName(origins.get(formation.id, &"")))
		if definition != null:
			c.country_tag = definition.iso_code
		c.start_pulse()
		added.append(formation.id)
	return added


func _add(formation: Formation) -> StaffMapCounter:
	var counter := StaffMapCounter.new()
	counter.setup(formation, _viewer, _palette)
	add_child(counter)
	_counters[formation.id] = counter
	_order.append(formation.id)
	return counter


## Formation ids in placement order.
func formation_ids() -> Array[StringName]:
	return _order


func counter(formation_id: StringName) -> StaffMapCounter:
	return _counters.get(formation_id) as StaffMapCounter


func counter_count() -> int:
	return _counters.size()


func viewer() -> int:
	return _viewer


func set_viewer(viewer_player: int) -> void:
	_viewer = viewer_player
	for formation in _state.formations:
		counter(formation.id).set_viewer(formation.owner_id, viewer_player)
	_apply_layout()


## Re-reads strengths (after an event; positions come with layout()).
func refresh() -> void:
	_drop_removed()
	for formation in _state.formations:
		counter(formation.id).set_strength(formation.strength(), formation.max_strength())
		counter(formation.id).has_order = formation.order != null


## Moved / in-contact marks (TASK-092e) from the turn view-model.
func apply_marks(marks: StaffMapTurnMarks) -> void:
	for formation in _state.formations:
		var c := counter(formation.id)
		c.moved = marks.is_moved(formation.id)
		c.in_contact = marks.in_contact(formation.id)


## Own formation ids in placement order (Tab cycles them).
func own_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for formation in _state.formations:
		if formation.owner_id == _viewer:
			ids.append(formation.id)
	return ids


## Places the counters: `points` maps every formation id to its screen position.
func layout(points: Dictionary) -> void:
	_points = points
	_apply_layout()


func set_hovered(formation_id: StringName) -> void:
	if formation_id == _hovered:
		return
	if _counters.has(_hovered):
		counter(_hovered).hovered = false
	_hovered = formation_id
	if _counters.has(formation_id):
		counter(formation_id).hovered = true


func hovered() -> StringName:
	return _hovered


func set_selected(formation_id: StringName) -> void:
	if formation_id == _selected:
		return
	if _counters.has(_selected):
		counter(_selected).selected = false
	_selected = formation_id if _counters.has(formation_id) else &""
	if _selected != &"":
		counter(_selected).selected = true
	_apply_layout()


func selected() -> StringName:
	return _selected


## The topmost visible counter under a screen point, or &"".
func counter_at(screen: Vector2) -> StringName:
	for i in range(_shown.size() - 1, -1, -1):
		var c := counter(_shown[i])
		if c.hits(screen - c.position):
			return _shown[i]
	return &""


## Ids of the counters drawn now (stack members and off-screen ones excluded).
func shown_ids() -> Array[StringName]:
	return _shown


func _apply_layout() -> void:
	if _points.is_empty():
		return
	var points: Array[Vector2] = []
	var owners: Array[int] = []
	for formation in _state.formations:
		points.append(_points.get(formation.id, Vector2(-1e6, -1e6)))
		owners.append(formation.owner_id)
	var leaders := StaffMapFormations.stack_leaders(points, owners)
	var counts := {}
	var shown_of := {}  # leader index -> index of the member shown
	for i in leaders.size():
		counts[leaders[i]] = int(counts.get(leaders[i], 0)) + 1
		if not shown_of.has(leaders[i]) or _order[i] == _selected:
			shown_of[leaders[i]] = i
	var view_rect := Rect2(-1e5, -1e5, 2e5, 2e5)  # no culling outside the tree (tests)
	if is_inside_tree():
		view_rect = get_viewport_rect().grow(StaffMapCounter.OWN_SIZE.x * 2.0)
	_shown.clear()
	for i in leaders.size():
		var c := counter(_order[i])
		var visible_now: bool = shown_of[leaders[i]] == i and view_rect.has_point(points[i])
		c.visible = visible_now
		if not visible_now:
			continue
		c.position = points[i].round()
		c.stack_count = counts[leaders[i]]
		_shown.append(_order[i])
	# Own counters above enemy ones, the selected one on top.
	var ordered: Array[StringName] = []
	for id in _shown:
		if not counter(id).is_own() and id != _selected:
			ordered.append(id)
	for id in _shown:
		if counter(id).is_own() and id != _selected:
			ordered.append(id)
	if _shown.has(_selected):
		ordered.append(_selected)
	_shown = ordered
	for id in _shown:
		move_child(counter(id), -1)


## Removes the counters of formations that left the state (destroyed by a strike, TASK-097a).
func _drop_removed() -> void:
	if _counters.size() == _state.formations.size():
		return
	var alive := {}
	for formation in _state.formations:
		alive[formation.id] = true
	for id in _order.duplicate():
		if alive.has(id):
			continue
		_counters[id].queue_free()
		_counters.erase(id)
		_order.erase(id)
		_points.erase(id)
		_shown.erase(id)
		if _hovered == id:
			_hovered = &""
		if _selected == id:
			_selected = &""
