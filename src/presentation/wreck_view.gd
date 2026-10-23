class_name WreckView
extends Node3D
## The burnt-out hulk a destroyed vehicle leaves behind (TASK-065): the unit's body (already
## charred, turret askew) plus a smoke column and, during the first turn, a flickering fire.
## Pure scenery: no collision, never picked, not in the units dictionary. WreckLife decides when
## the smoke thins / stops and when the wreck is hidden; this node only shows it.

const SMOKE_LIFETIME := 4.0
const SMOKE_MAX := 24
const SMOKE_SIZE_START := 0.25
const SMOKE_SIZE_END := 0.8
const SMOKE_ALPHA := 0.55
const SMOKE_DARK := Color("2b2a28")
const SMOKE_LIGHT := Color("6b6965")
## Smoke rises this fast (units/s) and drifts with the wind.
const SMOKE_RISE_MIN := 0.55
const SMOKE_RISE_MAX := 0.7
const SMOKE_WIND_PUSH := 0.25
const FIRE_DURATION := 6.0
const FIRE_ENERGY := 0.8
const FIRE_FLICKER := 0.4
const FIRE_RANGE := 2.0
const FIRE_COLOR := Color("ff8a3a")
const FADE_DURATION := 0.5

var unit_id := -1
var life: WreckLife
var _body: Node3D
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _fire_time := 0.0
var _fade_tween: Tween


## `body` is the unit's model pivot with its local transform kept (the wreck stands at the
## unit's position); `quality` is GraphicsQuality.features (smoke and fire need `particles`).
func setup(id: int, coord: Vector2i, body: Node3D, quality: Dictionary) -> void:
	unit_id = id
	life = WreckLife.new(coord)
	_body = body
	add_child(body)
	if quality.get("particles", false):
		_build_smoke()
		_build_fire()
	set_process(_light != null)


func coord() -> Vector2i:
	return life.coord


func is_hidden() -> bool:
	return life.hidden


func smoke_emitter() -> GPUParticles3D:
	return _smoke


func fire_light() -> OmniLight3D:
	return _light


func body() -> Node3D:
	return _body


## A turn started: the smoke thins after the first, stops after the third.
func on_turn_started() -> void:
	life.on_turn_started()
	_apply_smoke()
	if not life.fire_active():
		_stop_fire()


## A living unit finished a move on `to`: if that is this wreck's tile, hide it.
func on_unit_moved(to: Vector2i) -> void:
	if life.on_unit_moved(to):
		_apply_smoke()
		_stop_fire()
		_fade_out()


func _process(delta: float) -> void:
	if _light == null or not _light.visible:
		return
	_fire_time += delta
	if _fire_time >= FIRE_DURATION or not life.fire_active():
		_stop_fire()
		return
	var flicker := sin(_fire_time * 23.0) * sin(_fire_time * 7.3)
	_light.light_energy = FIRE_ENERGY + FIRE_FLICKER * flicker


func _build_smoke() -> void:
	var drift := Wind.DIRECTION.normalized() * Wind.strength() * SMOKE_WIND_PUSH
	_smoke = (
		ParticleFx
		. emitter(
			{
				"lifetime": SMOKE_LIFETIME,
				"max_particles": SMOKE_MAX,
				"direction": Vector3.UP,
				"spread": 8.0,
				"velocity_min": SMOKE_RISE_MIN,
				"velocity_max": SMOKE_RISE_MAX,
				"gravity": Vector3(drift.x, 0.0, drift.y),
				"damping": 0.0,
				"size_start": SMOKE_SIZE_START,
				"size_end": SMOKE_SIZE_END,
				"alpha": SMOKE_ALPHA,
				"tint": Color.WHITE,
			}
		)
	)
	_smoke.name = "Smoke"
	(_smoke.process_material as ParticleProcessMaterial).color_ramp = _smoke_ramp()
	_smoke.position = _hull_top()
	add_child(_smoke)
	_smoke.amount_ratio = 1.0
	_smoke.emitting = true


func _build_fire() -> void:
	_light = OmniLight3D.new()
	_light.name = "Fire"
	_light.light_color = FIRE_COLOR
	_light.light_energy = FIRE_ENERGY
	_light.omni_range = FIRE_RANGE
	_light.shadow_enabled = false
	_light.position = _hull_top()
	add_child(_light)


## Centre of the hull in the wreck's space, at three quarters of its height.
func _hull_top() -> Vector3:
	var box := MotionFx.model_bounds(_body)
	return _body.transform * (box.get_center() + Vector3.UP * box.size.y * 0.25)


## Dark soot fading in, turning light grey as it rises, fading out.
static func _smoke_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	gradient.colors = PackedColorArray(
		[Color(SMOKE_DARK, 0.0), Color(SMOKE_DARK, SMOKE_ALPHA), Color(SMOKE_LIGHT, 0.0)]
	)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _apply_smoke() -> void:
	if _smoke == null:
		return
	var factor := life.smoke_factor()
	_smoke.amount_ratio = maxf(factor, 0.01)
	_smoke.emitting = factor > 0.0


func _stop_fire() -> void:
	if _light != null:
		_light.visible = false
		_light.light_energy = 0.0


func _fade_out() -> void:
	if not is_inside_tree():
		visible = false
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_body, meshes)
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(
		func(f: float) -> void:
			for mesh in meshes:
				mesh.transparency = f,
		0.0,
		1.0,
		FADE_DURATION
	)
	_fade_tween.tween_callback(func() -> void: visible = false)


static func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		into.append(mesh)
	for child in node.get_children():
		_collect_meshes(child, into)
