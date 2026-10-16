class_name UnitView
extends Node3D
## Visual representation of a unit. Holds no game state – only unit_id and appearance.

const PLAYER_COLORS: Array[Color] = [Color(0.2, 0.4, 0.9), Color(0.85, 0.2, 0.2)]
const MOVE_DURATION := 0.25
const HIT_DURATION := 0.25
const HIT_SHAKE := 0.12
const HIT_FLASH_COLOR := Color(1.0, 1.0, 1.0)
const DIE_DURATION := 0.3
const HP_LABEL_HEIGHT := 1.25

var unit_id: int

var _body: MeshInstance3D
var _material: StandardMaterial3D
var _base_color: Color
var _hp_label: Label3D
var _move_tween: Tween
var _move_target: Vector3
var _hit_tween: Tween
var _hit_delay := 0.0
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
	set_hp(unit.hp, unit.definition.max_hp)


func set_hp(hp: int, max_hp: int) -> void:
	_hp_label.text = "%d/%d" % [hp, max_hp]


func move_to(world_position: Vector3) -> void:
	if _dying:
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_target = world_position
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", world_position, MOVE_DURATION).set_trans(
		Tween.TRANS_SINE
	)


## Seconds until the current move animation finishes (0 when not moving).
func remaining_move_time() -> float:
	if _move_tween == null or not _move_tween.is_running():
		return 0.0
	return maxf(0.0, MOVE_DURATION - _move_tween.get_total_elapsed_time())


## Short "got hit" reaction: sideways shake of the body plus a white flash, then the new HP.
## `delay` lets the attacker finish its move first (AI turns emit all events in one frame).
func play_hit(hp: int, max_hp: int, delay := 0.0) -> void:
	if _dying:
		return
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_body.position.x = 0.0
	_material.albedo_color = _base_color
	_hit_delay = delay
	var step := HIT_DURATION / 4.0
	_hit_tween = create_tween()
	_hit_tween.tween_interval(delay)
	_hit_tween.tween_callback(set_hp.bind(hp, max_hp))
	_hit_tween.tween_property(_body, "position:x", HIT_SHAKE, step)
	_hit_tween.parallel().tween_property(_material, "albedo_color", HIT_FLASH_COLOR, step)
	_hit_tween.tween_property(_body, "position:x", -HIT_SHAKE, step * 2.0)
	_hit_tween.parallel().tween_property(_material, "albedo_color", _base_color, step * 3.0)
	_hit_tween.tween_property(_body, "position:x", 0.0, step)


## Death animation: lets the hit reaction finish, then shrinks the unit and frees the node.
## Safe to call while other tweens are pending – they are bound to this node and die with it.
func play_death() -> void:
	if _dying:
		return
	_dying = true
	if _move_tween != null and _move_tween.is_valid():
		# Defensive: a unit may die while its move tween is still running – snap to its target.
		_move_tween.kill()
		position = _move_target
	var tween := create_tween()
	tween.tween_interval(_hit_delay + HIT_DURATION)
	tween.tween_property(_material, "albedo_color", _base_color.darkened(0.6), 0.1)
	var shrink := tween.tween_property(self, "scale", Vector3.ONE * 0.01, DIE_DURATION)
	shrink.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func set_selected(selected: bool) -> void:
	if _dying:
		return
	scale = Vector3.ONE * (1.25 if selected else 1.0)
