extends RefCounted
## Anti-tank launcher (granatnik przeciwpancerny) of an infantry squad's AT gunner – visual kind
## per country, shared behaviour: the model file picks the look with its AT_LAUNCHER_KIND
## (CARL_GUSTAF: Carl Gustaf M4, Poland; RPG7: RPG-7V, Russia), everything else is common. Every
## kind is held in the same SoldierPose.AT_LAUNCHER stance on the frame `pose.launcher()` (origin =
## the tube's middle on the right shoulder, x along the tube): its grips sit under the tube ahead
## of the shoulder, and it records the same node contract as SoldierPose.markers – `AtLauncher`
## (the launcher frame) with its child `Muzzle` at the front of the tube, x along the bore (the
## direction the round leaves). TASK-188b fires from `Muzzle` whatever the kind.
## Built in metres into the soldier's MeshKits (gun paint; the PG-7 warhead in the vest colour);
## the tube, grips and sight are shared pieces, only their table differs per kind.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
const CARL_GUSTAF := &"carl_gustaf"
const RPG7 := &"rpg7"
## Per kind: "tube" = turned profile (Vector2(radius, x) from the muzzle back, Soldier.bore_lathe),
## "muzzle" = x of the tube's front, "grips" = [front x, rear x] of the pistol grips (their tops
## on the tube's underside at "grip_y"), "rest" = shoulder rest [x, length] or [] , "sight" =
## [centre, size] of the sight block on the left.
const KINDS := {
	CARL_GUSTAF:
	{
		"tube":
		[
			Vector2(0.0, 0.47),
			Vector2(0.05, 0.47),
			Vector2(0.052, 0.45),
			Vector2(0.046, 0.42),
			Vector2(0.045, -0.25),
			Vector2(0.05, -0.27),
			Vector2(0.05, -0.31),
			Vector2(0.04, -0.34),
			Vector2(0.066, -0.47),
			Vector2(0.062, -0.48),
			Vector2(0.0, -0.48),
		],
		"muzzle": 0.47,
		"grips": [0.17, -0.04],
		"grip_y": -0.08,
		"rest": [-0.2, 0.13],
		"sight": [Vector3(0.05, 0.068, -0.058), Vector3(0.11, 0.04, 0.034)],
	},
	RPG7:
	{
		"tube":
		[
			Vector2(0.0, 0.46),
			Vector2(0.02, 0.46),
			Vector2(0.02, 0.14),
			Vector2(0.033, 0.13),
			Vector2(0.034, 0.12),
			Vector2(0.034, -0.12),
			Vector2(0.033, -0.13),
			Vector2(0.02, -0.14),
			Vector2(0.02, -0.4),
			Vector2(0.046, -0.54),
			Vector2(0.04, -0.545),
			Vector2(0.0, -0.545),
		],
		"muzzle": 0.46,
		"grips": [0.2, 0.0],
		"grip_y": -0.07,
		"rest": [],
		"sight": [Vector3(0.1, 0.04, -0.045), Vector3(0.09, 0.04, 0.03)],
	},
}
## Marker names (SoldierPose.markers paths; Soldier.soldier makes them nodes).
const NODE := &"AtLauncher"
const MUZZLE := &"AtLauncher/Muzzle"


## The launcher of `kind` on the gunner's shoulder; records the AtLauncher / Muzzle markers.
## Returns the [left, right] grips (front, rear) and the fingers' curl directions.
static func build(k: MeshKits, pose: SoldierPose, kind: StringName) -> Array[Vector3]:
	var spec: Dictionary = KINDS.get(kind, KINDS[RPG7])
	var t := pose.launcher()
	var gun := k.k(&"gun")
	Soldier.bore_lathe(gun, t, Vector3.ZERO, spec["tube"], 12)
	var grips: Array = spec["grips"]
	var grip_y: float = spec["grip_y"]
	for x: float in grips:
		Soldier.part(gun, t, Vector3(x, grip_y, 0.0), Vector3(0.034, 0.1, 0.028), -0.22, 0.0)
	var rest: Array = spec["rest"]
	if not rest.is_empty():
		Soldier.part(gun, t, Vector3(rest[0], -0.06, 0.0), Vector3(rest[1], 0.024, 0.05))
	var sight: Array = spec["sight"]
	Soldier.part(gun, t, sight[0], sight[1])
	if kind == RPG7:
		pg7(k.k(&"vest"), t.origin, t.basis * Basis(Vector3.BACK, -PI / 2.0))
	pose.markers[NODE] = t
	pose.markers[MUZZLE] = Transform3D(t.basis, t * Vector3(spec["muzzle"], 0.0, 0.0))
	var curl := -t.basis.z
	var hold := grip_y - 0.04
	return [t * Vector3(grips[0], hold, 0.0), t * Vector3(grips[1], hold, 0.0), curl, curl]


## PG-7 round on the lathe axis (+Y of `rot`) at `c`: the bulbous warhead with its conical nose
## from 0.45 to 0.82 m, the tail end at 0.45 sits in the launcher's muzzle.
static func pg7(kit: MeshKit, c: Vector3, rot: Basis) -> void:
	(
		kit
		. lathe(
			c,
			rot,
			[
				Vector2(0.0, 0.82),
				Vector2(0.012, 0.78),
				Vector2(0.0425, 0.62),
				Vector2(0.0425, 0.53),
				Vector2(0.022, 0.48),
				Vector2(0.022, 0.45),
				Vector2(0.0, 0.45),
			],
			12
		)
	)
