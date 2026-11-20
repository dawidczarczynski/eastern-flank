class_name InfantryFire
extends Node3D
## Playback of an infantry squad's fire (TASK-188b), reused for every infantry attack of the battle:
## muzzle flashes and impact puffs per round, glowing tracer streaks for the tracer rounds (with a
## short light pulse on HIGH) and, against a vehicle, one anti-tank rocket with a launch flash, a
## back-blast and a smoke trail. All nodes are pooled and hidden after the attack. The picture is a
## pure function of the attack's age (pose), so one tween scrubs it; the plan comes from TracerPlan.
## The rocket's hit is the caller's (the same shell-hit effect as a tank), see append_to().

const MAX_SHOTS := 16
const MUZZLE_COLOR := Color("ffd28a")
const MUZZLE_SIZE := 0.1
const MUZZLE_TIME := 0.08
const PUFF_COLOR := Color("b9a98a")
const PUFF_SIZE := 0.1
const PUFF_TIME := 0.22
## Red, thin and long: reads as a laser beam like the tracers in conflict footage.
const TRACER_COLOR := Color("ff2418")
const TRACER_LENGTH := 0.7
const TRACER_WIDTH := 0.016
const ROCKET_COLOR := Color("fff0c0")
const ROCKET_LENGTH := 0.22
const ROCKET_WIDTH := 0.05
const LAUNCH_FLASH_SIZE := 0.4
const LAUNCH_FLASH_TIME := 0.18
const LIGHT_COLOR := Color("ff3a28")
const LIGHT_ENERGY := 5.0
const LIGHT_RANGE := 2.0
const BACKBLAST_BACK := 0.1
## The rocket's explosion on the target: a big fireball flash, a light pulse and the impact
## particles of SalvoFxPool (fire, smoke, debris, dust ring).
const BLAST_COLOR := Color("ffb060")
const BLAST_SIZE := 0.9
const BLAST_TIME := 0.32
const BLAST_LIGHT_ENERGY := 8.0
const BLAST_LIGHT_RANGE := 3.0
## The off-map spot where warm_up() shows everything for a frame.
const PARK := Vector3(0.0, -50.0, 0.0)

var _muzzle_fx: Array[FlashFx] = []
var _puff_fx: Array[FlashFx] = []
var _streaks: Array[MeshInstance3D] = []
var _rocket_flash: FlashFx
var _rocket_body: MeshInstance3D
var _light: OmniLight3D
var _blast_flash: FlashFx
var _blast_light: OmniLight3D
var _pool: SalvoFxPool
var _shots: Array[Dictionary] = []
var _rocket := {}
var _trail: SalvoTrail
var _trail_carry := 0.0
var _trail_last := Vector3.ZERO
var _scale := 1.0
var _streak_mesh: BoxMesh
var _streak_material: StandardMaterial3D


## A pool added to `parent`; the light only when `quality["fx_lights"]`, the smoke and the
## back-blast only with `pool` (null on LOW).
static func create(parent: Node, quality: Dictionary, pool: SalvoFxPool) -> InfantryFire:
	var fx := InfantryFire.new()
	fx.name = "InfantryFire"
	fx.setup(quality.get("fx_lights", false), pool)
	parent.add_child(fx)
	return fx


func setup(with_light: bool, pool: SalvoFxPool) -> void:
	_pool = pool
	_scale = VisualScale.unit_model_scale()
	_streak_mesh = BoxMesh.new()
	_streak_material = StandardMaterial3D.new()
	_streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_streak_material.albedo_color = TRACER_COLOR
	for i in MAX_SHOTS:
		_muzzle_fx.append(_flash(MUZZLE_COLOR, MUZZLE_SIZE, MUZZLE_TIME))
		_puff_fx.append(_flash(PUFF_COLOR, PUFF_SIZE, PUFF_TIME))
		_streaks.append(_streak())
	_rocket_flash = _flash(MUZZLE_COLOR, LAUNCH_FLASH_SIZE, LAUNCH_FLASH_TIME)
	_rocket_body = _streak()
	var body_material := _streak_material.duplicate() as StandardMaterial3D
	body_material.albedo_color = ROCKET_COLOR
	_rocket_body.material_override = body_material
	_blast_flash = _flash(BLAST_COLOR, BLAST_SIZE, BLAST_TIME)
	if with_light:
		_blast_light = OmniLight3D.new()
		_blast_light.name = "BlastLight"
		_blast_light.light_color = BLAST_COLOR
		_blast_light.omni_range = BLAST_LIGHT_RANGE
		_blast_light.shadow_enabled = false
		_blast_light.visible = false
		add_child(_blast_light)
		_light = OmniLight3D.new()
		_light.name = "Light"
		_light.light_color = LIGHT_COLOR
		_light.omni_range = LIGHT_RANGE
		_light.shadow_enabled = false
		_light.visible = false
		add_child(_light)


func _flash(color: Color, size: float, life: float) -> FlashFx:
	var fx := FlashFx.new().setup(color, size * _scale, life)
	add_child(fx)
	return fx


func _streak() -> MeshInstance3D:
	var streak := MeshInstance3D.new()
	streak.mesh = _streak_mesh
	streak.material_override = _streak_material
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak.visible = false
	add_child(streak)
	return streak


## Rocket description for append_to(): {from (muzzle), to, t0, flight}.
static func rocket_plan(from: Vector3, to: Vector3) -> Dictionary:
	return {
		"from": from,
		"to": to,
		"t0": TracerPlan.ROCKET_DELAY,
		"flight": TracerPlan.rocket_flight(from.distance_to(to)),
	}


## Appends the whole attack to `tween`: the rounds of `shots` (TracerPlan.rifle_shots) and, when
## `rocket` is not empty, the rocket; `on_hit` is called when the target should react (the rocket's
## arrival, else the first round's) and the tween lasts TracerPlan.duration.
func append_to(
	tween: Tween, shots: Array[Dictionary], rocket: Dictionary, on_hit: Callable
) -> void:
	var rocket_distance := -1.0
	var hit_t := TracerPlan.first_landing(shots)
	if not rocket.is_empty():
		rocket_distance = (rocket["from"] as Vector3).distance_to(rocket["to"])
		hit_t = float(rocket["t0"]) + float(rocket["flight"])
	var total := TracerPlan.duration(shots, rocket_distance)
	tween.tween_callback(_begin.bind(shots, rocket))
	var now := 0.0
	var marks: Array = []
	if not rocket.is_empty():
		marks.append([float(rocket["t0"]), _launch_rocket])
	var landed := on_hit
	if not rocket.is_empty():
		landed = func() -> void:
			_explode()
			on_hit.call()
	marks.append([hit_t, landed])
	for mark: Array in marks:
		now = _append_segment(tween, now, mark[0])
		tween.tween_callback(mark[1])
	_append_segment(tween, now, total)
	tween.tween_callback(_end)


func _append_segment(tween: Tween, from: float, to: float) -> float:
	if to - from > 0.0001:
		tween.tween_method(pose, from, to, to - from)
		return to
	return from


## Places the nodes of the attack and hides the rest.
func _begin(shots: Array[Dictionary], rocket: Dictionary) -> void:
	_shots = shots.slice(0, MAX_SHOTS)
	_rocket = rocket
	for i in _shots.size():
		var shot := _shots[i]
		_muzzle_fx[i].position = shot["from"]
		_puff_fx[i].position = shot["to"]
	if not rocket.is_empty():
		_rocket_flash.position = rocket["from"]
		_blast_flash.position = (rocket["to"] as Vector3) + Vector3(0.0, 0.05, 0.0)
	pose(-1.0)


func _launch_rocket() -> void:
	if _rocket.is_empty() or _pool == null:
		return
	var from: Vector3 = _rocket["from"]
	var dir := _direction(from, _rocket["to"])
	_trail = _pool.acquire_trail()
	_trail.start(from)
	_trail_carry = 0.0
	_trail_last = from
	_pool.emit_backblast(from - dir * BACKBLAST_BACK * _scale, dir, from.y, Color(0, 0, 0, 0))


## The rocket arrives: the impact particles (none on LOW) and the camera shake; the flash and the
## light follow the age in pose().
func _explode() -> void:
	if _rocket.is_empty() or _pool == null:
		return
	var to: Vector3 = _rocket["to"]
	_pool.emit_impact(to, MotionEffects.dust_color(Terrain.Type.PLAINS))
	_pool.shake_at(to)


## Everything for the attack's age `age` seconds after it began (hidden before 0 and when over).
func pose(age: float) -> void:
	var pulse := -1
	var pulse_age := 1.0
	for i in _shots.size():
		var shot := _shots[i]
		var local := age - float(shot["t0"])
		var flight: float = shot["flight"]
		_muzzle_fx[i].pose(local)
		_puff_fx[i].pose(local - flight)
		var live: bool = shot["tracer"] and local >= 0.0 and local < flight
		_streaks[i].visible = live
		if live:
			_place_streak(
				_streaks[i], shot["from"], shot["to"], local / flight, TRACER_LENGTH, TRACER_WIDTH
			)
		if shot["tracer"] and local >= 0.0 and local < MUZZLE_TIME and local < pulse_age:
			pulse = i
			pulse_age = local
	if _light != null:
		_light.visible = pulse >= 0
		if pulse >= 0:
			_light.position = _shots[pulse]["from"]
			_light.light_energy = LIGHT_ENERGY * (1.0 - pulse_age / MUZZLE_TIME)
	if not _rocket.is_empty():
		_pose_rocket(age)


func _pose_rocket(age: float) -> void:
	var local := age - float(_rocket["t0"])
	var flight: float = _rocket["flight"]
	var blast_age := local - flight
	_blast_flash.pose(blast_age)
	if _blast_light != null:
		var live := blast_age >= 0.0 and blast_age < BLAST_TIME
		_blast_light.visible = live
		if live:
			_blast_light.position = _blast_flash.position + Vector3(0.0, 0.2, 0.0)
			_blast_light.light_energy = BLAST_LIGHT_ENERGY * (1.0 - blast_age / BLAST_TIME)
	_rocket_flash.pose(local)
	var flying := local >= 0.0 and local < flight
	_rocket_body.visible = flying
	if not flying:
		return
	var from: Vector3 = _rocket["from"]
	var to: Vector3 = _rocket["to"]
	var f := local / flight
	_place_streak(_rocket_body, from, to, f, ROCKET_LENGTH, ROCKET_WIDTH)
	if _trail != null:
		var head := from.lerp(to, f)
		var laid := SalvoFxPool.trail_points(
			_trail_last, head, SalvoFxPool.TRAIL_SPACING, _trail_carry
		)
		_trail_carry = laid["carry"]
		_trail_last = head
		_trail.extend(laid["points"], head)


## Hides everything and lets the smoke trail fade by itself.
func _end() -> void:
	pose(-1.0)
	_rocket_body.visible = false
	_blast_flash.pose(-1.0)
	if _blast_light != null:
		_blast_light.visible = false
	if _trail != null:
		_trail.stop()
		_trail = null
	_shots = []
	_rocket = {}
	if _light != null:
		_light.visible = false


## A streak of `length` x `width` (times the model scale) whose head is at fraction `f` of
## from -> to; the tail is clipped to the start while it has not travelled `length` yet.
func _place_streak(
	streak: MeshInstance3D, from: Vector3, to: Vector3, f: float, length: float, width: float
) -> void:
	var path := to - from
	var head := from + path * f
	var shown := minf(length * _scale, path.length() * f)
	var dir := _direction(from, to)
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	basis = basis * Basis.from_scale(Vector3(width * _scale, width * _scale, maxf(shown, 0.001)))
	streak.transform = Transform3D(basis, head - dir * shown * 0.5)


static func _direction(from: Vector3, to: Vector3) -> Vector3:
	var dir := to - from
	return dir.normalized() if dir.length() > 0.00001 else Vector3.FORWARD
