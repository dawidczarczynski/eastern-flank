# gdlint: disable=max-public-methods
class_name UnitView
extends Node3D
## Visual representation of a unit: primitive model, faction marker on the ground and a HUD
## label. Holds no game state – only unit_id and appearance.

## Durations match EventQueue.base_duration() so the burst speed estimate stays accurate
## (a move lasts MoveAnimation.duration(), i.e. EventQueue.SECONDS_PER_TILE per tile).
const HIT_DURATION := EventQueue.ATTACK_DURATION
const HIT_SHAKE := 0.12
const HIT_FLASH_ALPHA := 0.8
const DIE_DARKEN_DURATION := 0.25
const DIE_DARKEN_ALPHA := 0.6
const DIE_DURATION := EventQueue.DEATH_DURATION - DIE_DARKEN_DURATION
## Wreck death (TASK-065) uses the same total time as the plain death (EventQueue.DEATH_DURATION).
const WRECK_DURATION := EventQueue.DEATH_DURATION
## Marker design values (scene.js placeMarker / markerFill).
const RING_INNER := 0.6
const RING_OUTER := 0.72
const RING_OUTER_SELECTED := 0.8
const RING_LIFT := 0.035
const RING_ALPHA := 0.8
const RING_ALPHA_DONE := 0.45
const FILL_SCALE := 0.6
const FILL_LIFT := 0.03
const FILL_ALPHA := 0.06
const FILL_ALPHA_HOVERED := 0.2
const FILL_ALPHA_SELECTED := 0.32
const RING_SEGMENTS := 5
const FILL_SUBDIVISIONS := 4

## One unlit white material shared by every hit flash (events play one at a time).
static var _flash_material: StandardMaterial3D

## Graphics quality switches (GraphicsQuality.features), set by BattleController before use.
var quality: Dictionary = {}
## (x: float, z: float) -> Terrain.Type under a point, set by BattleController (dust colour).
var terrain_at: Callable
var unit_id: int
## The unit's definition id (e.g. &"homar_k"): the model and the salvo profile (SalvoTiming).
var definition_id: StringName

var _pivot: Node3D  # holds the model; shaken on hit
var _meshes: Array[MeshInstance3D] = []
var _death_material: StandardMaterial3D
var _label: UnitLabel
var _ring := MeshInstance3D.new()
var _fill := MeshInstance3D.new()
var _ring_material := _marker_material()
var _fill_material := _marker_material(false)
var _ground_height: Callable
var _marker_origin := Vector3.INF  # where the marker geometry was last built
var _marker_selected := false  # selected state the ring geometry was built for
var _label_height := UnitModels.DEFAULT_LABEL_HEIGHT
var _owner_color := Color.WHITE
var _selected := false
var _hovered := false
var _done := false
var _move_tween: Tween
var _move_points := PackedVector3Array()  # world points of the running move
var _move_elapsed := 0.0
var _move_duration := 0.0
var _move_start_yaw := 0.0  # heading when a steered (wheeled) move began
var _move_plan := {}  # HeavyMove.plan of a vehicle's running move
var _move_height: Callable  # (x, z) -> ground height the unit walks on
var _model: Node3D  # the "Model" node locomotion poses
var _fx: MotionFx  # dust and exhaust of a driving vehicle; null without particles
var _is_tracked := false  # pivots in place before driving (HeavyMove)
var _is_vehicle := false  # uses wheel / hull locomotion (UnitModels.is_vehicle)
var _wheel_distance := 0.0  # accumulated across moves, never reset
var _hit_tween: Tween
var _hp := 0  # the HP the label shows (events play in order: the HP before the next hit)
var _max_hp := 0
var _dying := false
var _burn_meshes: Array[MeshInstance3D] = []  # camo-shaded parts that burn black (wreck death)
var _turret: Node3D
var _turret_rest := Transform3D.IDENTITY
var _death_flash: OmniLight3D
var _launcher_pose := Vector2.ZERO  # last set_launcher_pose (traverse, elevation)


## `faction` is the owner's faction (colours; null = neutral); `ground_height` is a Callable
## (x: float, z: float) -> float for draping the marker; `hud_root` receives the unit's label.
func setup(
	unit: Unit,
	faction: FactionDefinition,
	world_position: Vector3,
	hud_root: Control,
	ground_height: Callable
) -> void:
	unit_id = unit.id
	definition_id = unit.definition.id
	position = world_position
	_ground_height = ground_height
	_owner_color = UiPalette.color_of(faction)
	_max_hp = unit.definition.max_hp
	_hp = unit.hp

	_pivot = Node3D.new()
	_pivot.name = "Body"
	add_child(_pivot)
	var model_id := unit.definition.id
	var model := UnitModels.build(model_id, unit.owner_id, faction, unit.id)
	# Facing lives on the pivot so moves can turn the whole model (TASK-022).
	_pivot.rotation.y = model.rotation.y
	model.rotation.y = 0.0
	_pivot.add_child(model)
	_model = model.get_node("Model")
	_is_vehicle = UnitModels.is_vehicle(unit.definition)
	_is_tracked = UnitModels.is_tracked(unit.definition)
	_apply_rest_pose()
	_collect_meshes(_pivot)
	if quality.get("particles", false) and MotionEffects.emits(unit.definition.unit_class):
		_fx = MotionFx.new()
		var wind := Wind.DIRECTION.normalized() * Wind.strength()
		_fx.setup(model, _model, unit.definition.unit_class, wind)

	for marker: MeshInstance3D in [_ring, _fill]:
		marker.top_level = true  # vertices are in world space
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
	_ring.material_override = _ring_material
	_fill.material_override = _fill_material

	_label_height = UnitModels.label_height(model_id)
	_label = UnitLabel.new()
	hud_root.add_child(_label)
	hud_root.move_child(_label, 0)  # below the other HUD panels
	_label.setup(tr(unit.definition.short_name), _owner_color, _hp, _max_hp)
	_refresh_markers()
	_update_label()


func _process(_delta: float) -> void:
	if _dying:
		return
	if _ring.visible and global_position != _marker_origin:
		_rebuild_marker_geometry()  # the unit is sliding: keep the marker on the ground
	_update_label()


## Re-places the HUD label after a camera jump while _process is off (screenshot tool).
func refresh_label() -> void:
	_update_label()


func _exit_tree() -> void:
	if _label != null and is_instance_valid(_label):
		_label.queue_free()


## Walks the unit along `world_points` (tile centres, the first one being its current tile),
## MoveAnimation.SECONDS_PER_TILE per segment, turning to face each segment. `ground_height`
## is a Callable (x, z) -> float the unit's feet follow (the terrain surface). The marker is
## hidden on the way and reappears at the destination. Returns the tween (the caller may
## scale its speed and wait for `finished`), or null when nothing is animated.
func move_along(world_points: PackedVector3Array, ground_height: Callable) -> Tween:
	if _dying or world_points.is_empty():
		return null
	_finish_move()
	_move_points = world_points
	_move_height = ground_height
	_move_elapsed = 0.0
	_move_start_yaw = _pivot.rotation.y
	_set_markers_visible(false)
	if _fx != null:
		_fx.begin()
	_move_tween = create_tween()
	# The tween drives `elapsed`; its speed scale (burst speed) therefore also speeds up turning.
	_move_plan = HeavyMove.plan(world_points, _pivot.rotation.y) if _is_tracked else {}
	_move_duration = (
		_move_plan["duration"] if _is_tracked else MoveAnimation.duration(world_points)
	)
	_move_tween.tween_method(_step_move, 0.0, _move_duration, _move_duration)
	_move_tween.tween_callback(_end_move)
	return _move_tween


func _step_move(elapsed: float) -> void:
	var dt := maxf(0.0, elapsed - _move_elapsed)
	_move_elapsed = elapsed
	if _is_tracked:
		_step_heavy(elapsed, dt)
		return
	# Path time runs slower at the start and end: the unit accelerates and brakes.
	var accel := MoveAnimation.WHEELED_ACCEL_TIME if _is_vehicle else MoveAnimation.ACCEL_TIME
	var path_time := MoveAnimation.path_time(elapsed, _move_duration, accel)
	var p := _ground_point(MoveAnimation.sample(_move_points, path_time))
	var target := MoveAnimation.segment_target(_move_points, path_time)
	var heading_error := 0.0
	if _is_vehicle and _move_points.size() > 1:
		# Steered: the heading follows the path; the starting error fades while it pulls out.
		var along := MoveAnimation.steered_yaw(_move_points, path_time)
		var fade := 1.0 - smoothstep(0.0, MoveAnimation.WHEELED_STEER_IN, elapsed)
		var start_error := MoveAnimation.wrap_angle(_move_start_yaw - along)
		heading_error = start_error * fade
		_pivot.rotation.y = along + heading_error
	elif Vector2(target.x - p.x, target.z - p.z).length_squared() > 0.000001:
		var yaw := MoveAnimation.facing_yaw(p, target)
		_pivot.rotation.y = MoveAnimation.turn_towards(_pivot.rotation.y, yaw, dt)
	if _fx != null and dt > 0.0:
		var speed := Vector2(p.x - position.x, p.z - position.z).length() / dt
		var terrain: int = terrain_at.call(p.x, p.z) if terrain_at.is_valid() else 0
		_fx.update(elapsed, speed, heading_error, terrain)
	position = p
	var ramp := accel if _is_vehicle else Locomotion.ENVELOPE_RAMP
	_pose_moving(path_time, Locomotion.envelope(elapsed, _move_duration, ramp))


## A vehicle pivots in place to each new heading, then drives the straight run (HeavyMove).
func _step_heavy(elapsed: float, dt: float) -> void:
	var pose := HeavyMove.pose(_move_plan, elapsed)
	var p := _ground_point(MoveAnimation.sample(_move_points, pose["path_time"]))
	_pivot.rotation.y = pose["yaw"]
	if _fx != null and dt > 0.0:
		var speed := Vector2(p.x - position.x, p.z - position.z).length() / dt
		var terrain: int = terrain_at.call(p.x, p.z) if terrain_at.is_valid() else 0
		_fx.update(elapsed, speed, pose["turn_left"], terrain)
	position = p
	var env := 0.0
	if pose["driving"]:
		env = Locomotion.envelope(
			pose["run_t"], pose["run_duration"], MoveAnimation.HEAVY_ACCEL_TIME
		)
	_pose_moving(pose["path_time"], env)


## Dust and exhaust of a vehicle driving on the spot (the unit catalog's Drive): `speed` world units
## per second, `since_start` seconds after it pulled away; a speed of 0 switches them off. No-op
## without particles or for a class that raises none.
func drive_effects(since_start: float, speed: float) -> void:
	if _fx == null:
		return
	if speed <= 0.0:
		_fx.end()
		return
	_fx.begin()
	_fx.update(since_start, speed, 0.0, Terrain.Type.PLAINS)


func _ground_point(p: Vector3) -> Vector3:
	if _move_height.is_valid():
		p.y = _move_height.call(p.x, p.z)
	return p


## Locomotion pose for the path time reached (distance and envelope derive from the move's
## animation time only, so the burst speed scale applies automatically).
func _pose_moving(path_time: float, env: float) -> void:
	var distance := Locomotion.travelled(_move_points, path_time)
	if _is_vehicle:
		var tilt := Locomotion.slope_tilt(_ground_height, position, _pivot.rotation.y)
		UnitModels.pose_tank(_model, _wheel_distance + distance, env, tilt)
	else:
		UnitModels.pose_infantry(_model, distance, env, true)


## Rest pose: no bob / sway / lean, kneelers kneel, vehicle hull follows the slope at its tile.
func _apply_rest_pose() -> void:
	if _is_vehicle:
		var tilt := Locomotion.slope_tilt(_ground_height, position, _pivot.rotation.y)
		UnitModels.pose_tank(_model, _wheel_distance, 0.0, tilt)
	else:
		UnitModels.pose_infantry(_model, 0.0, 0.0, false)


## Arrival: snap to the last point, keep the facing, show the marker there.
func _end_move() -> void:
	if _fx != null:
		_fx.end()
	if not _move_points.is_empty():
		var last := _move_points[_move_points.size() - 1]
		if _move_height.is_valid():
			last.y = _move_height.call(last.x, last.z)
		position = last
		_wheel_distance += Locomotion.travelled(_move_points, MoveAnimation.duration(_move_points))
	_move_points = PackedVector3Array()
	_apply_rest_pose()
	if not _dying:
		_set_markers_visible(true)


## Stops a running move and puts the unit at its destination.
func _finish_move() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
		_end_move()
	_move_tween = null


func _set_markers_visible(markers_visible: bool) -> void:
	_ring.visible = markers_visible
	_fill.visible = markers_visible
	if markers_visible and global_position != _marker_origin:
		_rebuild_marker_geometry()


## World positions of the launch tubes (the "Mouth" nodes under the model's "Pod"), or empty
## for units without a launcher.
func launch_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for mouth in _mouths():
		points.append(UnitModels.world_transform(mouth).origin)
	return points


## Launch direction of each tube in launch_points() order: the pod's world +X (the tube axis),
## normalised; empty without tubes.
func launch_directions() -> Array[Vector3]:
	var directions: Array[Vector3] = []
	var mouths := _mouths()
	if mouths.is_empty():
		return directions
	var axis := UnitModels.world_transform(UnitModels.launcher_pod(_model)).basis.x.normalized()
	for mouth in mouths:
		directions.append(axis)
	return directions


func _mouths() -> Array[Node3D]:
	var mouths: Array[Node3D] = []
	var pod := UnitModels.launcher_pod(_model)
	if pod != null:
		for child in pod.get_children():
			if (child as Node3D) != null and child.name.begins_with("Mouth"):
				mouths.append(child as Node3D)
	return mouths


## Yaw (pivot rotation.y) that makes the model face the world point `target`.
func yaw_towards(target: Vector3) -> float:
	return MoveAnimation.facing_yaw(global_position, target)


## Whether the launcher turns and elevates before a volley (instead of the whole vehicle turning).
func has_launcher() -> bool:
	return UnitModels.has_launcher(_model)


## How the launcher points at the world point `target` from the current facing: x = body yaw
## change (non-zero only for a limited traverse), y = turntable angle (see UnitModels.launcher_aim).
func launcher_aim_towards(target: Vector3) -> Vector2:
	return UnitModels.launcher_aim(_model, facing_yaw(), yaw_towards(target))


## Whether the launcher's traverse is limited (the vehicle may have to turn first).
func launcher_limited() -> bool:
	return UnitModels.launcher_limited(_model)


## Elevation (rad) the launcher fires at.
func launcher_elevation() -> float:
	return UnitModels.launcher_elevation(_model)


func set_launcher_pose(traverse: float, elevation: float) -> void:
	_launcher_pose = Vector2(traverse, elevation)
	if not _dying:
		UnitModels.pose_launcher(_model, traverse, elevation)


## Recoil of the pod (TASK-074): the last set_launcher_pose with `offset` (rad) added to the
## elevation; 0 restores that pose exactly.
func set_launcher_jolt(offset: float) -> void:
	if not _dying:
		UnitModels.pose_launcher(_model, _launcher_pose.x, _launcher_pose.y + offset)


## Whether the turret turns and the gun elevates before a direct-fire attack.
func has_turret() -> bool:
	return UnitModels.has_turret(_model)


## How the turret points at the world point `target` from the current facing: x = body yaw change
## (non-zero only for a limited traverse), y = turret angle (see UnitModels.turret_aim).
func turret_aim_towards(target: Vector3) -> Vector2:
	return UnitModels.turret_aim(_model, facing_yaw(), yaw_towards(target))


## Whether the turret's traverse is limited (the vehicle may have to turn first).
func turret_limited() -> bool:
	return UnitModels.turret_limited(_model)


## Gun elevation (rad) towards the world point `target` from the gun hinge, within the limits.
func gun_elevation_towards(target: Vector3) -> float:
	var gun := _model.get_node_or_null("Turret/Gun") as Node3D
	if gun == null:
		return 0.0
	return UnitModels.gun_elevation(_model, gun.global_position, target)


## Poses the turret (about Y) and the gun (elevation) relative to their built pose.
func set_turret_pose(traverse: float, elevation: float) -> void:
	if not _dying:
		UnitModels.pose_turret(_model, traverse, elevation)


## Whether the vehicle lowers jacks / closes shields before a volley.
func has_deployables() -> bool:
	return UnitModels.has_deployables(_model)


## Deploy step pose: 0 = stowed, 1 = jacks down and shields closed.
func set_deploy_pose(t: float) -> void:
	if not _dying:
		UnitModels.pose_deployables(_model, t)


func facing_yaw() -> float:
	return _pivot.rotation.y


## The "Model" node that locomotion and the mechanisms pose (the catalog poses it directly).
func model() -> Node3D:
	return _model


func set_facing_yaw(yaw: float) -> void:
	if not _dying:
		_pivot.rotation.y = yaw
		_apply_rest_pose()  # slope tilt depends on the heading


## The HP the label shows right now.
func shown_hp() -> int:
	return _hp


## Shows `hp` on the label without the hit reaction (a rocket salvo's HP steps, TASK-074).
func set_shown_hp(hp: int) -> void:
	if _dying:
		return
	_hp = hp
	_label.set_hp(hp, _max_hp)


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
## A vehicle with a valid `on_wreck` Callable (UnitView -> void) instead flashes, burns black and
## twists its turret over the same time, then calls `on_wreck` (which takes the body, see
## take_body) before the node is freed. Returns null if the unit is already dying.
func play_death(on_wreck := Callable()) -> Tween:
	if _dying:
		return null
	_begin_death()
	if on_wreck.is_valid() and _is_vehicle:
		return _play_wreck_death(on_wreck)
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


func _begin_death() -> void:
	_dying = true
	# Defensive: a unit may die while its move tween is still running – snap to its target.
	_finish_move()
	_reset_hit()
	_ring.queue_free()
	_fill.queue_free()
	_label.queue_free()


## Prepares the wreck death: the burn targets, the turret pose to start from, the flash and the
## fire burst. `set_wreck_time` then plays it.
func _play_wreck_death(on_wreck: Callable) -> Tween:
	_prepare_wreck_death()
	var tween := create_tween()
	tween.tween_method(set_wreck_time, 0.0, WRECK_DURATION, WRECK_DURATION)
	tween.tween_callback(
		func() -> void:
			on_wreck.call(self)
			queue_free()
	)
	return tween


func _prepare_wreck_death() -> void:
	_burn_meshes.clear()
	_collect_camo_meshes(_pivot)
	_turret = _model.get_node_or_null("Turret") as Node3D
	if _turret != null:
		_turret_rest = _turret.transform
	_death_flash = OmniLight3D.new()
	_death_flash.light_color = WreckPlan.FLASH_COLOR
	_death_flash.omni_range = WreckPlan.FLASH_RANGE
	_death_flash.light_energy = WreckPlan.FLASH_ENERGY
	_death_flash.shadow_enabled = false
	_death_flash.position = Vector3(0.0, 0.3, 0.0)
	add_child(_death_flash)
	if quality.get("particles", false):
		_add_death_burst()


func _add_death_burst() -> void:
	var burst := (
		ParticleFx
		. emitter(
			{
				"lifetime": 0.8,
				"max_particles": WreckPlan.BURST_PARTICLES,
				"direction": Vector3.UP,
				"spread": 70.0,
				"velocity_min": 0.4,
				"velocity_max": 1.4,
				"gravity": Vector3(0.0, 0.3, 0.0),
				"damping": 1.0,
				"size_start": 0.15,
				"size_end": 0.6,
				"alpha": 0.9,
				"tint": Color("e0803a"),
			}
		)
	)
	burst.name = "DeathBurst"
	burst.position = Vector3(0.0, 0.3, 0.0)
	burst.one_shot = true
	burst.explosiveness = 1.0
	add_child(burst)
	burst.amount_ratio = 1.0
	burst.emitting = true


## Poses the wreck death `t` seconds in (0..WRECK_DURATION): flash, burnt hull, turret knocked
## askew. Public so tests can jump to any moment.
func set_wreck_time(t: float) -> void:
	var burnt := WreckPlan.burnt_at(t)
	for mesh in _burn_meshes:
		mesh.set_instance_shader_parameter(&"burnt", burnt)
	if _death_flash != null:
		_death_flash.light_energy = WreckPlan.flash_energy(t)
	if _turret != null:
		var p := WreckPlan.turret_progress(t)
		var twist := Basis(Vector3.UP, WreckPlan.turret_yaw(unit_id) * p)
		var tilt := Basis(Vector3.BACK, WreckPlan.turret_tilt(unit_id) * p)
		_turret.transform = Transform3D(
			twist * tilt * _turret_rest.basis,
			_turret_rest.origin + Vector3.UP * WreckPlan.TURRET_LIFT * p
		)
	if t >= WreckPlan.TURRET_END:
		UnitModels.pose_launcher(_model, 0.0, 0.0)  # launcher pods drop to their stowed pose
		UnitModels.pose_deployables(_model, 0.0)


## Starts a wreck death without a tween (tests): everything `play_death` sets up before the clock.
func begin_wreck_death() -> void:
	_begin_death()
	_prepare_wreck_death()


## The model pivot, detached from this view with its local transform kept: a WreckView adopts it
## when the unit's death animation ends. Null if already taken.
func take_body() -> Node3D:
	if _pivot == null or _pivot.get_parent() != self:
		return null
	var body := _pivot
	remove_child(body)
	_meshes.clear()
	return body


func _collect_camo_meshes(node: Node) -> void:
	for child in node.get_children():
		var instance := child as MeshInstance3D
		if instance != null:
			var shader := instance.material_override as ShaderMaterial
			if shader != null and shader.shader == ModelParts.CAMO_SHADER:
				_burn_meshes.append(instance)
		_collect_camo_meshes(child)


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
	_label.place(camera, _world_position() + Vector3.UP * _label_height)


## global_position errors outside the tree (headless tests); the local position is the same there.
func _world_position() -> Vector3:
	return global_position if is_inside_tree() else position


## Alphas and ring width follow the selected / hovered / done state.
func _refresh_markers() -> void:
	var ring_alpha := RING_ALPHA_DONE if _done else RING_ALPHA
	GroundOverlay.set_color(_ring_material, Color(_owner_color, ring_alpha))
	var fill_alpha := FILL_ALPHA
	if _selected:
		fill_alpha = FILL_ALPHA_SELECTED
	elif _hovered:
		fill_alpha = FILL_ALPHA_HOVERED
	GroundOverlay.set_color(_fill_material, Color(_owner_color, fill_alpha))
	if _selected != _marker_selected or _marker_origin == Vector3.INF:
		_rebuild_marker_geometry()


func _rebuild_marker_geometry() -> void:
	var center := _world_position()
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
		flat.append(Vector3(p.x, _marker_origin.y + lift, p.y))
	return flat


static func _triangles_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _marker_material(pulled := true) -> ShaderMaterial:
	return GroundOverlay.material(Color(1, 1, 1, 0), pulled)
