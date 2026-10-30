class_name CatalogStage
extends Node3D
## The 3D side of the in-game unit catalog (TASK-084): lighting like the battle, a ground disc, one
## stand-alone UnitView built through UnitModels.build (the battle's path) and the animations the
## model offers (CatalogAnimations). The launcher steps and the salvo effects are the battle's own
## (VolleyPlayback, SalvoFxPool); Drive raises the battle's dust and exhaust.
## Holds no GameState and no rules; the camera and the UI live in unit_catalog.gd.
## Lasting animations (Drive, March) are toggles advanced in _process; pose animations (Deploy,
## Raise, Traverse, Fire) run one at a time on `_pose_tween`.

signal state_changed

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const BATTLE_ENVIRONMENT := "res://assets/environments/battle_environment.tres"
const BACKGROUND := Color("#171a15")
const GROUND_COLOR := Color("#34372f")
const GROUND_RADIUS := 1.9
const GROUND_HEIGHT := 0.04
## The Fire animation shoots at a point this far from the unit, in the direction the launcher is
## traversed to: far beyond the ground disc, so the rockets climb out of the picture (their
## impacts are not shown).
const TARGET_DISTANCE := 30.0
## Radius of the salvo's landing disc around that point.
const LANDING_RADIUS := 1.0
## Culling box (XZ) of the salvo effects: the stage and the rockets' whole flight.
const FX_BOUNDS := Rect2(-35.0, -35.0, 70.0, 70.0)
## Gun elevation (rad) of the tank Traverse demo.
const TURRET_DEMO_ELEVATION := 0.1
## Travel speed of Drive and March (world units per second), like a move in the battle.
const TRAVEL_SPEED := 1.0 / MoveAnimation.SECONDS_PER_TILE
## Hit reaction hit points shown (the label is hidden; the call needs a value).
const HIT_HP := 1

## Graphics quality features (GraphicsQuality.features) for the views; set before show_unit.
var quality: Dictionary = {}

var _view: UnitView
var _definition: UnitDefinition
var _faction: FactionDefinition
var _hud_holder := Control.new()
var _wreck: WreckView
var _bounds := AABB()
var _animations: Array[StringName] = []
var _fx_rng := RandomNumberGenerator.new()
var _sun: DirectionalLight3D
var _world_environment := WorldEnvironment.new()
var _driving := false
var _marching := false
var _standing := false
var _env := 0.0
var _distance := 0.0
var _deploy_on := false
var _raise_on := false
var _traverse_on := false
var _firing := false
var _dead := false
var _traverse_angle := 0.0
var _pose_tween: Tween
var _volley: RocketVolley
var _salvo_fx: SalvoFxPool  # created at the first Fire; null without particles
var _muzzle_flash: MuzzleFlash  # created at the first tank Fire; its light follows `quality` then
var _drive_time := 0.0


func _init() -> void:
	name = "CatalogStage"
	_fx_rng.randomize()
	_hud_holder.visible = false  # the unit label has nothing to show here
	add_child(_hud_holder)
	_build_environment()
	_build_ground()


# --- Queries ----------------------------------------------------------------------------------


func definition() -> UnitDefinition:
	return _definition


func faction() -> FactionDefinition:
	return _faction


## The unit's view; null before show_unit or once its death animation has freed it.
func view() -> UnitView:
	return _view if is_instance_valid(_view) else null


## The sun, to apply the graphics quality to.
func sun() -> DirectionalLight3D:
	return _sun


func world_environment() -> WorldEnvironment:
	return _world_environment


## Box of the model as built (stage space), for the camera framing.
func bounds() -> AABB:
	return _bounds


## Box the camera frames: the model (the Fire target is far off-screen).
func framing_bounds() -> AABB:
	return _bounds


## The salvo effects pool; null before the first launcher is shown or without particles.
func salvo_fx() -> SalvoFxPool:
	return _salvo_fx


## Length, height and width of the model in real metres (without the game's model scale).
func model_size_m() -> Vector3:
	return _bounds.size / VisualScale.unit_model_scale() * UnitModels.METERS_PER_UNIT


## The animations this model offers (CatalogAnimations.for_model), in button order.
func animations() -> Array[StringName]:
	return _animations


func is_dead() -> bool:
	return _dead


## The running pose tween (Deploy, Raise, Traverse, Fire); null when idle. Tests step it.
func pose_tween() -> Tween:
	return _pose_tween if _pose_tween != null and _pose_tween.is_valid() else null


## Whether a pose animation is running (the pose buttons are disabled meanwhile).
func is_busy() -> bool:
	return pose_tween() != null


## Whether the toggle is switched on (button pressed): Drive / March running, Kneel / stand
## standing, Deploy / Raise / Traverse at their far pose, Fire running.
func is_on(id: StringName) -> bool:
	var flags := {
		CatalogAnimations.DRIVE: _driving,
		CatalogAnimations.MARCH: _marching,
		CatalogAnimations.KNEEL: _standing,
		CatalogAnimations.DEPLOY: _deploy_on,
		CatalogAnimations.RAISE: _raise_on,
		CatalogAnimations.TRAVERSE: _traverse_on,
		CatalogAnimations.FIRE: _firing,
	}
	return flags.get(id, false)


## Whether pressing the button does something now.
func can_play(id: StringName) -> bool:
	if view() == null or _dead:
		return false
	match id:
		CatalogAnimations.HIT, CatalogAnimations.DEATH:
			return true
		CatalogAnimations.FIRE:
			return (
				id in _animations
				and not is_busy()
				and not (_deploy_on or _raise_on or _traverse_on)
			)
		CatalogAnimations.DEPLOY, CatalogAnimations.RAISE, CatalogAnimations.TRAVERSE:
			return id in _animations and not is_busy()
	return id in _animations


# --- Showing a unit ---------------------------------------------------------------------------


## Replaces the shown unit by a fresh model of `unit_definition` in `unit_faction`'s colours (null
## = neutral grey); this is also the Reset after Hit and Death.
func show_unit(unit_definition: UnitDefinition, unit_faction: FactionDefinition) -> void:
	clear()
	_definition = unit_definition
	_faction = unit_faction
	var unit := Unit.new(0, 0, unit_definition, Vector2i.ZERO)
	_view = UnitView.new()
	_view.quality = quality
	add_child(_view)
	_view.setup(unit, unit_faction, Vector3.ZERO, _hud_holder, Callable())
	for child in _view.get_children():
		if child is MeshInstance3D:
			child.visible = false  # faction ring and fill on the battle map's ground
	var model := _view.model()
	_bounds = OrbitMath.visible_bounds(model, model.transform)
	_animations = CatalogAnimations.for_model(model)
	if CatalogAnimations.FIRE in _animations or CatalogAnimations.TRAVERSE in _animations:
		_traverse_angle = CatalogAnimations.traverse_angle(model)
	if CatalogAnimations.FIRE in _animations:
		_salvo_pool()  # built (and its shaders compiled) now, not at the first launch
	state_changed.emit()


## Removes the unit (and its wreck) and resets every animation state.
func clear() -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = null
	_free_volley()
	_hide_muzzle_flash()
	if _view != null and is_instance_valid(_view):
		remove_child(_view)
		_view.queue_free()
	_view = null
	if _wreck != null and is_instance_valid(_wreck):
		remove_child(_wreck)
		_wreck.queue_free()
	_wreck = null
	_driving = false
	_marching = false
	_standing = false
	_env = 0.0
	_distance = 0.0
	_drive_time = 0.0
	_deploy_on = false
	_raise_on = false
	_traverse_on = false
	_firing = false
	_dead = false


# --- Animations -------------------------------------------------------------------------------


## Starts (or toggles) an animation; does nothing when `can_play` says no.
func play(id: StringName) -> void:
	if not can_play(id):
		return
	match id:
		CatalogAnimations.DRIVE:
			_driving = not _driving
		CatalogAnimations.MARCH:
			_marching = not _marching
		CatalogAnimations.KNEEL:
			_standing = not _standing
			_rest_infantry()
		CatalogAnimations.DEPLOY:
			_deploy()
		CatalogAnimations.RAISE:
			_raise()
		CatalogAnimations.TRAVERSE:
			_traverse()
		CatalogAnimations.FIRE:
			_fire()
		CatalogAnimations.HIT:
			_view.play_hit(HIT_HP)
		CatalogAnimations.DEATH:
			_die()
	state_changed.emit()


## Advances Drive and March: the pose follows a travelled distance, ramped in and out like a move.
func _process(delta: float) -> void:
	var unit_view := view()
	if unit_view == null or _dead:
		return
	var moving := _driving or _marching
	if not moving and _env <= 0.0:
		return
	_env = move_toward(_env, 1.0 if moving else 0.0, delta / Locomotion.ENVELOPE_RAMP)
	_distance += delta * TRAVEL_SPEED * _env
	_drive_time = _drive_time + delta if _env > 0.0 else 0.0
	unit_view.drive_effects(_drive_time, TRAVEL_SPEED * _env)
	var model := unit_view.model()
	if UnitModels.is_vehicle(_definition):
		UnitModels.pose_tank(model, _distance, _env, Vector2.ZERO)
	elif _env > 0.0:
		UnitModels.pose_infantry(model, _distance, _env, true)
	else:
		_rest_infantry()


func _rest_infantry() -> void:
	UnitModels.pose_infantry(_view.model(), 0.0, 0.0, _standing)


func _deploy() -> void:
	var from := 1.0 if _deploy_on else 0.0
	_deploy_on = not _deploy_on
	_pose_tween = create_tween()
	VolleyPlayback.tween_deploy(_pose_tween, _view, from, 1.0 - from)
	_pose_tween.finished.connect(_on_pose_finished)


func _raise() -> void:
	var elevation := UnitModels.launcher_elevation(_view.model())
	var traverse := _traverse_angle if _traverse_on else 0.0
	var from := elevation if _raise_on else 0.0
	_raise_on = not _raise_on
	var to := elevation if _raise_on else 0.0
	_pose_tween = create_tween()
	VolleyPlayback.tween_launcher(
		_pose_tween,
		_view,
		Vector2(traverse, from),
		Vector2(traverse, to),
		VolleyPlayback.LAUNCHER_RAISE_DURATION
	)
	_pose_tween.finished.connect(_on_pose_finished)


func _traverse() -> void:
	if UnitModels.has_turret(_view.model()):
		_traverse_turret()
		return
	var elevation := UnitModels.launcher_elevation(_view.model()) if _raise_on else 0.0
	var from := _traverse_angle if _traverse_on else 0.0
	_traverse_on = not _traverse_on
	var to := _traverse_angle if _traverse_on else 0.0
	_pose_tween = create_tween()
	VolleyPlayback.tween_launcher(
		_pose_tween,
		_view,
		Vector2(from, elevation),
		Vector2(to, elevation),
		VolleyPlayback.LAUNCHER_TRAVERSE_DURATION
	)
	_pose_tween.finished.connect(_on_pose_finished)


## Tank turret: turns to the demo angle with the gun slightly raised, and back.
func _traverse_turret() -> void:
	var raise := TURRET_DEMO_ELEVATION if not _traverse_on else 0.0
	var from := _traverse_angle if _traverse_on else 0.0
	var from_elevation := TURRET_DEMO_ELEVATION if _traverse_on else 0.0
	_traverse_on = not _traverse_on
	var to := _traverse_angle if _traverse_on else 0.0
	_pose_tween = create_tween()
	VolleyPlayback.tween_turret(
		_pose_tween,
		_view,
		Vector2(from, from_elevation),
		Vector2(to, raise),
		VolleyPlayback.TURRET_AIM_DURATION
	)
	_pose_tween.finished.connect(_on_pose_finished)


## The battle's volley sequence (deploy, raise, traverse, salvo, back) at a point far away in the
## direction the launcher is traversed to, so the body never has to turn. Launch fire, smoke,
## trails and lights are the battle's (SalvoFxPool on particle quality); impacts are not shown.
func _fire() -> void:
	if UnitModels.has_turret(_view.model()):
		_fire_turret()
		return
	var elevation := UnitModels.launcher_elevation(_view.model())
	var aim_point := fire_point()
	_firing = true
	_pose_tween = create_tween()
	VolleyPlayback.append_aim(_pose_tween, _view, _traverse_angle, elevation)
	_volley = VolleyPlayback.append_salvo(
		_pose_tween, self, _view, aim_point, _fx_rng, LANDING_RADIUS
	)
	var pool := _salvo_pool()
	if pool != null:
		_volley.effects = pool.effects_for_volley(quality.get("fx_lights", false), false)
	VolleyPlayback.append_stow(_pose_tween, _view, _traverse_angle, elevation)
	_pose_tween.finished.connect(_on_pose_finished)


## Tank shot: the turret turns to the demo angle with the gun slightly raised, one shot (recoil
## and muzzle flash, light per the viewer's quality), back to the front.
func _fire_turret() -> void:
	if _muzzle_flash == null:
		_muzzle_flash = MuzzleFlash.create(self, quality)
	var pose := Vector2(_traverse_angle, TURRET_DEMO_ELEVATION)
	_firing = true
	_pose_tween = create_tween()
	VolleyPlayback.tween_turret(
		_pose_tween, _view, Vector2.ZERO, pose, VolleyPlayback.TURRET_AIM_DURATION
	)
	VolleyPlayback.append_shot(_pose_tween, _view, _muzzle_flash, EventQueue.ATTACK_DURATION)
	VolleyPlayback.tween_turret(
		_pose_tween, _view, pose, Vector2.ZERO, VolleyPlayback.TURRET_AIM_DURATION
	)
	_pose_tween.finished.connect(_on_pose_finished)


## Ends the running pose animation at once (the poses snap to their final values).
func finish_pose() -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_on_pose_finished()


## The battle's salvo effects pool, created for the first launcher shown; null when `quality` has
## no particles.
func _salvo_pool() -> SalvoFxPool:
	if _salvo_fx == null and quality.get("particles", false):
		_salvo_fx = SalvoFxPool.new(FX_BOUNDS)
		add_child(_salvo_fx)
		_salvo_fx.set_sun(_sun.transform.basis.z, _sun.light_color)
		_salvo_fx.warm_up(Vector2.ZERO, quality.get("fx_lights", false))
	return _salvo_fx


## Where the Fire animation shoots: TARGET_DISTANCE from the unit in the direction the launcher
## traverses to, so the body never has to turn.
func fire_point() -> Vector3:
	var stowed := 0.0 if UnitModels.launcher_params(_view.model())["stowed"] == "front" else PI
	var yaw := _view.facing_yaw() + stowed + _traverse_angle
	return _view.position + Vector3(cos(yaw), 0.0, -sin(yaw)) * TARGET_DISTANCE


## Snaps every pose to its flags, so the end of a tween is exact and a Fire ends in the built pose.
func _on_pose_finished() -> void:
	_pose_tween = null
	_free_volley()
	_firing = false
	var unit_view := view()
	if unit_view != null:
		unit_view.set_deploy_pose(1.0 if _deploy_on else 0.0)
		unit_view.set_turret_pose(
			_traverse_angle if _traverse_on else 0.0, TURRET_DEMO_ELEVATION if _traverse_on else 0.0
		)
		unit_view.set_gun_recoil(0.0)
		_hide_muzzle_flash()
		unit_view.set_launcher_pose(
			_traverse_angle if _traverse_on else 0.0,
			UnitModels.launcher_elevation(unit_view.model()) if _raise_on else 0.0
		)
	state_changed.emit()


## A shot cut off mid-flash (Reset, Death, another unit) must not leave the flash or its light on.
func _hide_muzzle_flash() -> void:
	if _muzzle_flash != null:
		_muzzle_flash.pose(-1.0)


func _free_volley() -> void:
	if _volley != null and is_instance_valid(_volley):
		_volley.queue_free()
	_volley = null


func _die() -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = null
	_free_volley()
	_hide_muzzle_flash()
	_firing = false
	_driving = false
	_marching = false
	_dead = true
	_view.drive_effects(0.0, 0.0)
	var tween := _view.play_death(_adopt_wreck)
	if tween != null:
		tween.finished.connect(func() -> void: state_changed.emit())


## A vehicle's death leaves its burnt body standing, like a wreck on the battle map.
func _adopt_wreck(dying: UnitView) -> void:
	var body := dying.take_body()
	if body == null:
		return
	_wreck = WreckView.new()
	_wreck.position = dying.position
	add_child(_wreck)
	_wreck.setup(dying.unit_id, Vector2i.ZERO, body, quality)


# --- Scenery ----------------------------------------------------------------------------------


func _build_environment() -> void:
	var environment := (load(BATTLE_ENVIRONMENT) as Environment).duplicate() as Environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.background_energy_multiplier = 1.0
	environment.fog_enabled = false
	_world_environment.environment = environment
	add_child(_world_environment)
	_sun = _battle_sun()
	add_child(_sun)


## DirectionalLight3D with the properties of the battle scene's "Sun" node (read from the packed
## scene, so the two never drift apart; the same trick as tools/render_unit.gd).
func _battle_sun() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	var state := (load(BATTLE_SCENE) as PackedScene).get_state()
	for node_index in state.get_node_count():
		if state.get_node_name(node_index) != &"Sun":
			continue
		for property_index in state.get_node_property_count(node_index):
			light.set(
				state.get_node_property_name(node_index, property_index),
				state.get_node_property_value(node_index, property_index)
			)
	return light


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var disc := CylinderMesh.new()
	disc.top_radius = GROUND_RADIUS
	disc.bottom_radius = GROUND_RADIUS
	disc.height = GROUND_HEIGHT
	disc.radial_segments = 64
	disc.rings = 1
	ground.mesh = disc
	ground.position = Vector3(0.0, -GROUND_HEIGHT * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)
