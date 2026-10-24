class_name SoldierPose
extends RefCounted
## Static pose of one soldier (TASK-085, soldier v4 stage A): the skeleton's joints in metres
## (x forward, y up, z right, boot soles on y = 0) for a posture (standing / kneeling), a stance
## (how the weapon is held) and a carry, solved at build time as pure geometry – the body, the kit
## and the weapon are then built around it (parts/soldier.gd, parts/soldier_body.gd).
##
## Proportions: ANSUR II male means (US Army anthropometric survey) scaled to a 1.75 m body in
## 3 cm boots; segment lengths are joint to joint and fixed – the limbs are placed with two-bone
## IK (`two_bone`), so they never stretch. Neutral coordinates = the figure standing upright, feet
## together; `pelvis`, `chest` and `head` map neutral points to the posed ones (`torso(y)` blends
## between pelvis and chest along the spine).

const OcclusionBake := preload("res://src/presentation/models/parts/occlusion_bake.gd")

## Joint-to-joint segment lengths (m).
const UPPER_ARM := 0.3
const FOREARM := 0.26
## Wrist to the middle of a gripped handle (the hand closes around it).
const HAND_GRIP := 0.075
const THIGH := 0.42
const SHIN := 0.41
## Neutral skeleton: hip joint height and half spacing, shoulder joint (z = side * z), lumbar pivot
## of the spine twist / lean, neck base and head pivot (top of the neck), ankle joint above the
## soles.
const HIP_Y := 0.94
const HIP_HALF := 0.088
const SHOULDER := Vector3(-0.005, 1.435, 0.172)
const LUMBAR := Vector3(0.0, 1.05, 0.0)
const NECK_BASE := Vector3(-0.012, 1.5, 0.0)
const HEAD_PIVOT := Vector3(0.0, 1.6, 0.0)
const ANKLE_H := 0.11
## Chin (bottom of the jaw) and right eye, neutral.
const CHIN := Vector3(0.085, 1.562, 0.0)
const EYE := Vector3(0.08, 1.668, 0.032)
## Shoulder pocket (neutral): the butt of a shouldered weapon sits between the deltoid and the
## chest, on the carrier's shoulder strap; aiming lifts the shoulder and the butt with it.
const POCKET := Vector3(0.105, 1.44, 0.09)
const POCKET_AIM := Vector3(0.11, 1.48, 0.072)
## Bore above the butt's centre, sight line above the bore (shouldered rifles).
const BORE := 0.035
const SIGHT := 0.075
## RPG-7 tube's middle (neutral; the tube rests on the right shoulder behind its grips, which are
## ahead of the shoulder) and its sight's eyepiece in the tube frame.
const LAUNCHER_REST := Vector3(0.21, 1.522, 0.128)
const LAUNCHER_SIGHT := Vector3(0.0, 0.055, -0.06)
## Kneeling: height of the knee joint on the ground (the knee pad touches y = 0).
const KNEEL_KNEE_Y := 0.105
## Largest head pitch and roll (rad) of a cheek weld: the head bends onto the stock, not further.
const MAX_WELD := Vector2(0.45, 0.3)
## Standing legs keep this fraction of their full reach (soft knees).
const REACH := 0.99

## Stances (how the weapon is held): shouldered rifle / carbine / LMG, RPG on the shoulder, GPMG
## at the hip.
const RIFLE := 0
const LAUNCHER := 1
const HIP := 2
## Carries (Soldier.READY / AIM / LOW).
const READY := 0
const AIM := 1
const LOW := 2

## Standing stance parameters: pelvis offset (x, z) and yaw / roll (rad, yaw + = left, roll + =
## right side down), spine (chest relative to the pelvis) yaw and forward lean, ankles [x, z] and
## foot yaws [left, right]. Rifles and the RPG: bladed (left foot forward, hips turned right, the
## shoulders less – the twist towards the weapon); the GPMG gunner squarer, leaning into the gun.
const STANDS := {
	RIFLE:
	{
		"pelvis": Vector2(-0.02, 0.0),
		"yaw": -0.4,
		"roll": 0.03,
		"spine_yaw": 0.2,
		"lean": 0.06,
		"ankles": [Vector2(0.12, -0.12), Vector2(-0.14, 0.15)],
		"feet": Vector2(-0.2, -0.8),
	},
	LAUNCHER:
	{
		"pelvis": Vector2(-0.02, 0.0),
		"yaw": -0.42,
		"roll": 0.03,
		"spine_yaw": 0.16,
		"lean": 0.1,
		"ankles": [Vector2(0.16, -0.12), Vector2(-0.16, 0.15)],
		"feet": Vector2(-0.2, -0.85),
	},
	HIP:
	{
		"pelvis": Vector2(-0.01, 0.0),
		"yaw": -0.22,
		"roll": 0.02,
		"spine_yaw": 0.08,
		"lean": 0.04,
		"ankles": [Vector2(0.11, -0.14), Vector2(-0.1, 0.15)],
		"feet": Vector2(0.05, -0.5),
	},
}
## Elbow pole directions in the chest frame [left, right] per stance: elbows hang down and back;
## the firing elbow of a shouldered rifle goes out when aiming.
const ELBOW_POLES := {
	RIFLE: [Vector3(-0.15, -1.0, -0.2), Vector3(-0.35, -1.0, 0.35)],
	LAUNCHER: [Vector3(-0.1, -1.0, -0.35), Vector3(-0.3, -0.9, 0.4)],
	HIP: [Vector3(-0.2, -1.0, -0.35), Vector3(-0.55, -0.7, 0.45)],
}
const ELBOW_AIM := Vector3(-0.3, -0.75, 0.6)

var kneel := false
var kit := 0
var carry := READY
var stance := RIFLE
## Squad slot: varies the relaxed stances (weight shift, head turn).
var slot := 0
## Neutral -> posed: pelvis (legs, belt), chest (shoulders, vest, pack), head (face, helmet).
var pelvis := Transform3D.IDENTITY
var chest := Transform3D.IDENTITY
var head := Transform3D.IDENTITY
## Chest rotation relative to the pelvis, about LUMBAR.
var spine := Basis.IDENTITY
## Ankle frames [left, right]: origin = ankle joint, basis = the foot's yaw (and pitch).
var feet: Array[Transform3D] = []
## Elbow poles [left, right], posed directions.
var elbow_poles: Array[Vector3] = []
## Posed shoulder pocket (butt centre of a shouldered weapon).
var pocket := Vector3.ZERO
## Joints (m): &"hip_l", &"knee_l", &"ankle_l", &"shoulder_l", &"elbow_l", &"wrist_l", &"hand_l"
## (and _r), &"chin"; the arms' entries are filled when the arms are built.
var joints := {}
## Helmet frame (rim plane centre, Y up into the shell), set when the helmet is built.
var helmet := Transform3D.IDENTITY
## AO proxies of the body and kit (parts/occlusion_bake.gd), baked into the variant's meshes.
var occluders := OcclusionBake.new()


## The pose of a soldier: posture, kit, carry and stance; varies the relaxed stances (weight
## shift, head turn) by the squad slot `slot_id` deterministically (TerrainNoise.hash, no RNG).
static func make(
	kneeling: bool, kit_id: int, carry_id: int, stance_id: int, slot_id := 0
) -> SoldierPose:
	var p := SoldierPose.new()
	p._setup(kneeling, kit_id, carry_id, stance_id, slot_id)
	return p


func _setup(kneeling: bool, kit_id: int, carry_id: int, stance_id: int, slot_id: int) -> void:
	kneel = kneeling
	kit = kit_id
	carry = carry_id
	stance = stance_id
	slot = slot_id
	var aims := aiming()
	var vary := TerrainNoise.hash(slot_id, 7.0, 11.0) - 0.5
	var turn := TerrainNoise.hash(slot_id, 13.0, 5.0) - 0.5
	var s: Dictionary = STANDS[stance]
	var lean: float = s["lean"] + (0.05 if aims else 0.0) + (0.04 if kneel else 0.0)
	var spine_roll := 0.0 if aims else -vary * 0.07
	spine = Basis(Vector3.UP, s["spine_yaw"]) * Basis(Vector3.BACK, -lean)
	spine = spine * Basis(Vector3.RIGHT, spine_roll)
	if kneel:
		_kneel_legs(s)
	else:
		_stand_legs(s, 0.0 if aims else vary)
	chest = torso(10.0)
	pocket = chest * (POCKET_AIM if carry == AIM else POCKET)
	var poles: Array = ELBOW_POLES[stance]
	elbow_poles = [chest.basis * (poles[0] as Vector3), chest.basis * (poles[1] as Vector3)]
	if stance == RIFLE and carry == AIM:
		elbow_poles[1] = chest.basis * ELBOW_AIM
	# The face turns to the front (+x) against the body's twist, plus a look of its own.
	var front := chest.basis.x
	var forward := -atan2(-front.z, front.x)
	var sight := _sight_line()
	if sight.is_empty():
		var look := turn * 0.7 if carry != AIM else 0.0
		head = head_frame(chest, forward + look, 0.05 + vary * 0.1, vary * 0.12)
	else:
		head = _cheek_weld(forward, sight[0], sight[1])
	joints[&"chin"] = head * CHIN


## Whether the soldier aims (rifle at AIM, or the RPG): an aiming pose does not vary by slot.
func aiming() -> bool:
	return carry == AIM or stance == LAUNCHER


## Neutral -> posed transform at the spine height `y` (neutral): the pelvis below the waist, the
## chest above the sternum, blended between.
func torso(y: float) -> Transform3D:
	var r := Basis.IDENTITY.slerp(spine, smoothstep(0.98, 1.32, y))
	return pelvis * Transform3D(r, LUMBAR - r * LUMBAR)


## Frame of a shouldered weapon whose muzzle points `angle` rad up: origin on the bore at the butt
## (the butt's centre in the shoulder pocket), x along the bore, y up.
func shouldered(angle: float) -> Transform3D:
	var b := Basis(Vector3.BACK, angle)
	return Transform3D(b, pocket + b * Vector3(0.0, BORE, 0.0))


## Frame of an RPG on the right shoulder: origin = the tube's middle, x along the tube (0.04 rad
## up).
func launcher() -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, 0.04), chest * LAUNCHER_REST)


## Shoulder joint (posed) of `side` (-1 left, 1 right); aiming lifts the firing shoulder.
func shoulder(side: float) -> Vector3:
	var lift := 0.015 if side > 0.0 and aiming() else 0.0
	return chest * Vector3(SHOULDER.x, SHOULDER.y + lift, SHOULDER.z * side)


## Head frame: the neck bends about its base and the head about its pivot, half the turn each;
## `yaw`, `pitch` (+ = looking down) and `roll` (+ = right ear down) in rad, relative to `chest_xf`.
static func head_frame(chest_xf: Transform3D, yaw: float, pitch: float, roll: float) -> Transform3D:
	var half := Basis(Vector3.UP, yaw * 0.5) * Basis(Vector3.BACK, -pitch * 0.5)
	half = half * Basis(Vector3.RIGHT, roll * 0.5)
	var neck := Transform3D(half, NECK_BASE - half * NECK_BASE)
	var top := Transform3D(half, HEAD_PIVOT - half * HEAD_PIVOT)
	return chest_xf * neck * top


## Two-bone IK (pure geometry): the middle joint for segments `l1` (root – mid) and `l2` (mid –
## end) from `root` towards `target`, bent towards `pole` (a direction). Out of reach the chain
## points straight at the target and stops short. Returns [mid, end]; the lengths are exact.
static func two_bone(
	root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3
) -> Array[Vector3]:
	var to := target - root
	var dir := to.normalized() if to.length_squared() > 1e-12 else Vector3.DOWN
	var d := clampf(to.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 1e-10:
		bend = dir.cross(Vector3.BACK if absf(dir.z) < 0.9 else Vector3.UP)
	var mid := root + dir * a + bend.normalized() * h
	return [mid, root + dir * d]


# --- Legs -----------------------------------------------------------------------------------------


## Standing: feet planted per stance, the pelvis shifted onto the weight leg (`vary`) and lowered
## until both legs reach with soft knees; knees bend over the toes.
func _stand_legs(s: Dictionary, vary: float) -> void:
	var offset: Vector2 = s["pelvis"]
	var rot := Basis(Vector3.UP, s["yaw"]) * Basis(Vector3.RIGHT, s["roll"] + vary * 0.1)
	var centre := Vector3(offset.x, HIP_Y, offset.y - vary * 0.05)
	var ankles: Array = s["ankles"]
	var yaws: Vector2 = s["feet"]
	var targets: Array[Vector3] = []
	for i in 2:
		var at: Vector2 = ankles[i]
		targets.append(Vector3(at.x, ANKLE_H, at.y))
	for step in 60:
		pelvis = Transform3D(rot, centre) * Transform3D(Basis.IDENTITY, -Vector3(0.0, HIP_Y, 0.0))
		var worst := 0.0
		for i in 2:
			worst = maxf(worst, _hip(i).distance_to(targets[i]))
		if worst <= REACH * (THIGH + SHIN):
			break
		centre.y -= 0.004
	feet = []
	for i in 2:
		var foot := Basis(Vector3.UP, yaws[i])
		feet.append(Transform3D(foot, targets[i]))
		_leg_joints(i, targets[i], foot.x + Vector3(0.0, 0.15, 0.0))


## Kneeling: right knee on the ground with the thigh nearly upright, right foot behind on its
## toes, left foot planted forward with the knee up.
func _kneel_legs(s: Dictionary) -> void:
	var rot := Basis(Vector3.UP, s["yaw"] - 0.05)
	var knee_r := Vector3(-0.02, KNEEL_KNEE_Y, 0.12)
	var hip_r := knee_r + Vector3(-0.1, 1.0, -0.03).normalized() * THIGH
	var centre := hip_r - rot * Vector3(0.0, 0.0, HIP_HALF)
	pelvis = Transform3D(rot, centre) * Transform3D(Basis.IDENTITY, -Vector3(0.0, HIP_Y, 0.0))
	var ankle_l := Vector3(0.31, ANKLE_H, -0.17)
	var ankle_r := knee_r + Vector3(-0.95, 0.3, 0.02).normalized() * SHIN
	feet = [Transform3D(Basis(Vector3.UP, -0.15), ankle_l), _toes_down(ankle_r, -0.25)]
	_leg_joints(0, ankle_l, Vector3(0.35, 1.0, -0.1))
	joints[&"hip_r"] = _hip(1)
	joints[&"knee_r"] = knee_r
	joints[&"ankle_r"] = ankle_r


## Hip joint (posed) of leg `i` (0 left, 1 right).
func _hip(i: int) -> Vector3:
	return pelvis * Vector3(0.0, HIP_Y, HIP_HALF * (-1.0 if i == 0 else 1.0))


## Knee by IK from the hip to `ankle`, bent towards `pole`; records the leg's joints.
func _leg_joints(i: int, ankle: Vector3, pole: Vector3) -> void:
	var tag := "l" if i == 0 else "r"
	var hip := _hip(i)
	var chain := two_bone(hip, ankle, THIGH, SHIN, pole)
	joints[StringName("hip_" + tag)] = hip
	joints[StringName("knee_" + tag)] = chain[0]
	joints[StringName("ankle_" + tag)] = chain[1]


## Ankle frame of a foot standing on its toes behind a kneeler: pitched toes-down until the toe tip
## touches the ground.
static func _toes_down(ankle: Vector3, yaw: float) -> Transform3D:
	var frame := Transform3D(Basis(Vector3.UP, yaw), ankle)
	for step in 80:
		var phi := step * 0.02
		frame = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -phi), ankle)
		if (frame * Vector3(0.228, -ANKLE_H + 0.004, 0.0)).y <= 0.0:
			break
	return frame


# --- Head -----------------------------------------------------------------------------------------


## The aiming sight line [origin, direction] the eye looks along, or [] when not aiming.
func _sight_line() -> Array:
	if stance == LAUNCHER:
		var t := launcher()
		return [t * LAUNCHER_SIGHT, t.basis.x]
	if stance == RIFLE and carry == AIM:
		var g := shouldered(-0.03)
		return [g * Vector3(0.0, SIGHT, 0.0), g.basis.x]
	return []


## Head bent onto the stock (cheek weld): the pitch and roll that bring the right eye closest to
## the sight line (coarse grid, then a fine one), the face turned to the front.
func _cheek_weld(yaw: float, origin: Vector3, dir: Vector3) -> Transform3D:
	var best := Vector2(0.1, 0.0)
	var span := Vector2(0.4, 0.4)
	var centre := Vector2(0.35, 0.25)
	for pass_index in 2:
		var best_cost := INF
		for i in 9:
			for j in 9:
				var a := centre + Vector2(span.x * (i / 4.0 - 1.0), span.y * (j / 4.0 - 1.0))
				var pitch := clampf(a.x, 0.0, MAX_WELD.x)
				var roll := clampf(a.y, -0.1, MAX_WELD.y)
				var eye := head_frame(chest, yaw, pitch, roll) * EYE
				var rel := eye - origin
				var miss := (rel - dir * rel.dot(dir)).length()
				var cost := miss + 0.02 * (pitch + absf(roll))
				if cost < best_cost:
					best_cost = cost
					best = Vector2(pitch, roll)
		centre = best
		span *= 0.25
	return head_frame(chest, yaw, best.x, best.y)
