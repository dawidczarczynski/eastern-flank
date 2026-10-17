class_name UnitView
extends Node3D
## Visual representation of a unit: primitive model, faction marker on the ground and a HUD
## label. Holds no game state – only unit_id and appearance.

## Durations match EventQueue.base_duration() so the burst speed estimate stays accurate.
const MOVE_DURATION := EventQueue.MOVE_DURATION
const HIT_DURATION := EventQueue.ATTACK_DURATION
const HIT_SHAKE := 0.12
const HIT_FLASH_ALPHA := 0.8
const DIE_DARKEN_DURATION := 0.1
const DIE_DARKEN_ALPHA := 0.6
const DIE_DURATION := EventQueue.DEATH_DURATION - DIE_DARKEN_DURATION
## Label anchor height above the unit's feet per definition id.
const LABEL_HEIGHTS := {&"infantry": 0.5, &"cavalry": 0.62}
const DEFAULT_LABEL_HEIGHT := 0.5
## Marker design values (scene.js placeMarker / markerFill).
const RING_INNER := 0.6
const RING_OUTER := 0.72
const RING_OUTER_SELECTED := 0.8
const RING_LIFT := 0.035
const RING_ALPHA := 0.95
const RING_ALPHA_DONE := 0.45
const FILL_SCALE := 0.6
const FILL_LIFT := 0.03
const FILL_ALPHA := 0.1
const FILL_ALPHA_HOVERED := 0.2
const FILL_ALPHA_SELECTED := 0.32
const RING_SEGMENTS := 5
const FILL_SUBDIVISIONS := 4

## One unlit white material shared by every hit flash (events play one at a time).
static var _flash_material: StandardMaterial3D

var unit_id: int

var _pivot: Node3D  # holds the model; shaken on hit
var _meshes: Array[MeshInstance3D] = []
var _death_material: StandardMaterial3D
var _label: UnitLabel
var _ring := MeshInstance3D.new()
var _fill := MeshInstance3D.new()
var _ring_material := _marker_material()
var _fill_material := _marker_material()
var _ground_height: Callable
var _marker_origin := Vector3.INF  # where the marker geometry was last built
var _marker_selected := false  # selected state the ring geometry was built for
var _label_height := DEFAULT_LABEL_HEIGHT
var _owner_color := Color.WHITE
var _selected := false
var _hovered := false
var _done := false
var _move_tween: Tween
var _move_target: Vector3
var _hit_tween: Tween
var _hp := 0
var _max_hp := 0
var _dying := false


## `ground_height` is a Callable (x: float, z: float) -> float for draping the marker;
## `hud_root` receives the unit's label.
func setup(unit: Unit, world_position: Vector3, hud_root: Control, ground_height: Callable) -> void:
	unit_id = unit.id
	position = world_position
	_ground_height = ground_height
	_owner_color = UiPalette.FACTION[clampi(unit.owner_id, 0, UiPalette.FACTION.size() - 1)]
	_max_hp = unit.definition.max_hp
	_hp = unit.hp

	_pivot = Node3D.new()
	_pivot.name = "Body"
	add_child(_pivot)
	_pivot.add_child(UnitModels.build(unit.definition.id, unit.owner_id))
	_collect_meshes(_pivot)

	for marker: MeshInstance3D in [_ring, _fill]:
		marker.top_level = true  # vertices are in world space
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
	_ring.material_override = _ring_material
	_fill.material_override = _fill_material

	_label_height = LABEL_HEIGHTS.get(unit.definition.id, DEFAULT_LABEL_HEIGHT)
	_label = UnitLabel.new()
	hud_root.add_child(_label)
	hud_root.move_child(_label, 0)  # below the other HUD panels
	_label.setup(tr(unit.definition.short_name), unit.owner_id, _hp, _max_hp)
	_refresh_markers()
	_update_label()


func _process(_delta: float) -> void:
	if _dying:
		return
	if global_position != _marker_origin:
		_rebuild_marker_geometry()  # the unit is sliding: keep the marker on the ground
	_update_label()


func _exit_tree() -> void:
	if _label != null and is_instance_valid(_label):
		_label.queue_free()


## Slides the unit to `world_position`. Returns the tween (the caller may scale its speed and
## wait for `finished`), or null when nothing is animated.
func move_to(world_position: Vector3) -> Tween:
	if _dying:
		return null
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_target = world_position
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", world_position, MOVE_DURATION).set_trans(
		Tween.TRANS_SINE
	)
	return _move_tween


## Short "got hit" reaction: sideways shake of the model plus a white flash, then the new HP.
## Returns the tween, or null when nothing is animated.
func play_hit(hp: int) -> Tween:
	if _dying:
		return null
	_reset_hit()
	_hp = hp
	_label.set_hp(hp, _max_hp)
	var flash := _get_flash_material()
	_set_overlay(flash)
	_set_alpha(flash, 0.0)
	var step := HIT_DURATION / 4.0
	_hit_tween = create_tween()
	_hit_tween.tween_property(_pivot, "position:x", HIT_SHAKE, step)
	_hit_tween.parallel().tween_method(_set_flash_alpha, 0.0, HIT_FLASH_ALPHA, step)
	_hit_tween.tween_property(_pivot, "position:x", -HIT_SHAKE, step * 2.0)
	_hit_tween.parallel().tween_method(_set_flash_alpha, HIT_FLASH_ALPHA, 0.0, step * 3.0)
	_hit_tween.tween_property(_pivot, "position:x", 0.0, step)
	_hit_tween.tween_callback(_set_overlay.bind(null))
	return _hit_tween


## Death animation: darkens and shrinks the unit, then frees the node (queue_free is deferred,
## so the returned tween still emits `finished`). Marker and label go away at once.
## Returns null if the unit is already dying.
func play_death() -> Tween:
	if _dying:
		return null
	_dying = true
	if _move_tween != null and _move_tween.is_valid():
		# Defensive: a unit may die while its move tween is still running – snap to its target.
		_move_tween.kill()
		position = _move_target
	_reset_hit()
	_ring.queue_free()
	_fill.queue_free()
	_label.queue_free()
	_death_material = StandardMaterial3D.new()
	_death_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_death_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_death_material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_set_overlay(_death_material)
	var tween := create_tween()
	tween.tween_method(_set_death_alpha, 0.0, DIE_DARKEN_ALPHA, DIE_DARKEN_DURATION)
	var shrink := tween.tween_property(self, "scale", Vector3.ONE * 0.01, DIE_DURATION)
	shrink.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
	return tween


## Stops a running hit reaction and leaves no flash behind (the flash material is shared).
func _reset_hit() -> void:
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_pivot.position.x = 0.0
	_set_flash_alpha(0.0)
	_set_overlay(null)


func set_selected(selected: bool) -> void:
	if _dying or selected == _selected:
		return
	_selected = selected
	_refresh_markers()


func set_hovered(hovered: bool) -> void:
	if _dying or hovered == _hovered:
		return
	_hovered = hovered
	_refresh_markers()


## `done`: the unit has nothing left to do on its owner's turn (dims ring and label).
func set_done(done: bool) -> void:
	if _dying or done == _done:
		return
	_done = done
	_refresh_markers()
	_label.set_done(done)


func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		var instance := child as MeshInstance3D
		if instance != null:
			_meshes.append(instance)
		_collect_meshes(child)


func _set_overlay(material: Material) -> void:
	for instance in _meshes:
		instance.material_overlay = material


static func _get_flash_material() -> StandardMaterial3D:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	return _flash_material


static func _set_alpha(material: StandardMaterial3D, alpha: float) -> void:
	material.albedo_color.a = alpha


func _set_flash_alpha(alpha: float) -> void:
	_set_alpha(_get_flash_material(), alpha)


func _set_death_alpha(alpha: float) -> void:
	_set_alpha(_death_material, alpha)


func _update_label() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	_label.place(camera, global_position + Vector3.UP * _label_height)


## Alphas and ring width follow the selected / hovered / done state.
func _refresh_markers() -> void:
	var ring_alpha := RING_ALPHA_DONE if _done else RING_ALPHA
	_ring_material.albedo_color = Color(_owner_color, ring_alpha)
	var fill_alpha := FILL_ALPHA
	if _selected:
		fill_alpha = FILL_ALPHA_SELECTED
	elif _hovered:
		fill_alpha = FILL_ALPHA_HOVERED
	_fill_material.albedo_color = Color(_owner_color, fill_alpha)
	if _selected != _marker_selected or _marker_origin == Vector3.INF:
		_rebuild_marker_geometry()


func _rebuild_marker_geometry() -> void:
	var center := global_position
	_marker_origin = center
	_marker_selected = _selected
	var c2 := Vector2(center.x, center.z)
	var outer := RING_OUTER_SELECTED if _selected else RING_OUTER
	_ring.mesh = _triangles_mesh(
		_drape(OverlayGeometry.hex_ring(c2, RING_INNER, outer, RING_SEGMENTS), RING_LIFT)
	)
	_fill.mesh = _triangles_mesh(
		_drape(OverlayGeometry.hex_patch(c2, FILL_SCALE, FILL_SUBDIVISIONS), FILL_LIFT)
	)


func _drape(points: PackedVector2Array, lift: float) -> PackedVector3Array:
	if _ground_height.is_valid():
		return OverlayGeometry.drape_with(points, _ground_height, lift)
	var flat := PackedVector3Array()
	for p in points:
		flat.append(Vector3(p.x, global_position.y + lift, p.y))
	return flat


static func _triangles_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _marker_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
