class_name UnitView
extends Node3D
## Visual representation of a unit. Holds no game state – only unit_id and appearance.

const PLAYER_COLORS: Array[Color] = [Color(0.2, 0.4, 0.9), Color(0.85, 0.2, 0.2)]
## Durations match EventQueue.base_duration() so the burst speed estimate stays accurate.
const MOVE_DURATION := EventQueue.MOVE_DURATION
const HIT_DURATION := EventQueue.ATTACK_DURATION
const HIT_SHAKE := 0.12
const HIT_FLASH_COLOR := Color(1.0, 1.0, 1.0)
const DIE_DARKEN_DURATION := 0.1
const DIE_DURATION := EventQueue.DEATH_DURATION - DIE_DARKEN_DURATION
const HP_LABEL_HEIGHT := 1.25

var unit_id: int

var _body: MeshInstance3D
var _material: StandardMaterial3D
var _base_color: Color
var _hp_label: Label3D
var _move_tween: Tween
var _move_target: Vector3
var _hit_tween: Tween
var _max_hp := 0
var _dying := false


func setup(unit: Unit, world_position: Vector3) -> void:
	unit_id = unit.id
	position = world_position

	var mesh := CapsuleMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.9
	_base_color = PLAYER_COLORS[unit.owner_id % PLAYER_COLORS.size()]
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	mesh.material = _material

	_body = MeshInstance3D.new()
	_body.mesh = mesh
	_body.position.y = mesh.height / 2.0
	add_child(_body)

	_hp_label = Label3D.new()
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.fixed_size = false
	_hp_label.pixel_size = 0.005
	_hp_label.font_size = 48
	_hp_label.outline_size = 12
	_hp_label.modulate = Color(1.0, 1.0, 1.0)
	_hp_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_hp_label.position.y = HP_LABEL_HEIGHT
	add_child(_hp_label)
	_max_hp = unit.definition.max_hp
	set_hp(unit.hp)


func set_hp(hp: int) -> void:
	_hp_label.text = "%d/%d" % [hp, _max_hp]


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


## Short "got hit" reaction: sideways shake of the body plus a white flash, then the new HP.
## Returns the tween, or null when nothing is animated.
func play_hit(hp: int) -> Tween:
	if _dying:
		return null
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_body.position.x = 0.0
	_material.albedo_color = _base_color
	var step := HIT_DURATION / 4.0
	set_hp(hp)
	_hit_tween = create_tween()
	_hit_tween.tween_property(_body, "position:x", HIT_SHAKE, step)
	_hit_tween.parallel().tween_property(_material, "albedo_color", HIT_FLASH_COLOR, step)
	_hit_tween.tween_property(_body, "position:x", -HIT_SHAKE, step * 2.0)
	_hit_tween.parallel().tween_property(_material, "albedo_color", _base_color, step * 3.0)
	_hit_tween.tween_property(_body, "position:x", 0.0, step)
	return _hit_tween


## Death animation: darkens and shrinks the unit, then frees the node (queue_free is deferred,
## so the returned tween still emits `finished`). Returns null if the unit is already dying.
func play_death() -> Tween:
	if _dying:
		return null
	_dying = true
	if _move_tween != null and _move_tween.is_valid():
		# Defensive: a unit may die while its move tween is still running – snap to its target.
		_move_tween.kill()
		position = _move_target
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
		_body.position.x = 0.0
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", _base_color.darkened(0.6), DIE_DARKEN_DURATION)
	var shrink := tween.tween_property(self, "scale", Vector3.ONE * 0.01, DIE_DURATION)
	shrink.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
	return tween


func set_selected(selected: bool) -> void:
	if _dying:
		return
	scale = Vector3.ONE * (1.25 if selected else 1.0)
