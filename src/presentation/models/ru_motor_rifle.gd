## Russian motor rifle squad (BMP dismounts in Ratnik kit): five soldiers in EMR (faction uniform
## camo), rounded 6B47 helmets and bulky 6B45 armour with a high collar and front pouches; a
## leader and a kneeling rifleman with AK-74M + GP-30, a standing RPG-7V gunner, a kneeling
## RPK-74M gunner and the assistant grenadier with a rocket carrier. Squad contract: Soldier0..4,
## each with a Rig; kneelers have Kneel + Stand (Stand hidden). The soldier (pose, anatomical
## body, AO, RPG-7, helpers) is the shared parts/soldier.gd; this file adds the Ratnik kit through
## `dress`.
## Blueprint: docs/design/units/units/ru_motor_rifle/blueprint.md.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.5
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {"squad_march": {}}
## Exaggeration of the soldiers (real 1.80 m -> 3.15 m), the same as the other squads.
const SOLDIER_SCALE := 1.75
const RIFLE := 0
const GP30 := 1
const RPG := 2
const MG := 3
const ASSIST := 4
## How each kit holds its weapon (SoldierPose stances; the rest shoulder their rifles).
const STANCES := {RPG: Soldier.LAUNCHER_STANCE}
## Squad layout: [x, z, kneeling, kit, carry, yaw] (Soldier.squad); the leader first, aiming. 5 of
## the 6 dismounts (see blueprint); the assistant carries low and watches the right flank, the
## kneeling rifleman covers the left.
const SQUAD: Array = [
	[0.13, 0.0, false, GP30, Soldier.AIM],
	[-0.03, 0.16, false, RPG],
	[-0.03, -0.15, true, MG],
	[-0.19, 0.06, false, ASSIST, Soldier.LOW, 0.6],
	[-0.16, -0.13, true, GP30, Soldier.AIM, -0.5],
]
## 6B47 (outer ~0.31 × 0.285 m): rounded full-cut shell, no flared brim, deep over the ears and
## neck, then the inner wall (Vector2(radius, y) from the rim plane, metres); `oval` stretches it to
## the real length / width; rim plane in head pivot coordinates and its back tilt.
const HELMET: Array[Vector2] = [
	Vector2(0.0, 0.133),
	Vector2(0.07, 0.127),
	Vector2(0.112, 0.107),
	Vector2(0.138, 0.08),
	Vector2(0.15, 0.045),
	Vector2(0.153, 0.01),
	Vector2(0.151, -0.02),
	Vector2(0.145, -0.036),
	Vector2(0.139, -0.031),
	Vector2(0.133, 0.0),
	Vector2(0.12, 0.05),
	Vector2(0.0, 0.05),
]
const HELMET_OVAL := Vector2(1.01, 0.93)
const HELMET_AT := Vector3(0.0, 0.07, 0.0)
const HELMET_TILT := 0.14


static func build(faction: FactionDefinition) -> Node3D:
	var g := Soldier.squad(
		"ru_motor_rifle", SQUAD, SOLDIER_SCALE, Soldier.materials(faction), dress, STANCES
	)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## The Ratnik kit on one soldier: 6B47 helmet, 6B45 armour and the weapon of `pose.kit`; returns
## the grips (see Soldier.squad).
static func dress(k: MeshKits, pose: SoldierPose) -> Array[Vector3]:
	_helmet(k, pose)
	_armour(k, pose)
	match pose.kit:
		RPG:
			return Soldier.rpg7(k, pose.launcher())
		MG:
			return _ak(k, pose.shouldered(-0.08 if pose.kneel else -0.35), false, true, pose.kneel)
		ASSIST:
			_rocket_carrier(k, pose)
	var angle := Soldier.carry_angle(pose.carry, pose.kneel, -0.4, -0.2)
	return _ak(k, pose.shouldered(angle), pose.kit == GP30, false, false)


## 6B47 helmet with the EMR cover (uniform camo), the side rails' mounting band and chin strap.
static func _helmet(k: MeshKits, pose: SoldierPose) -> void:
	var h := Soldier.helmet(k, pose, HELMET, HELMET_AT, HELMET_TILT, HELMET_OVAL)
	k.k(&"dark").loft_rings(
		Soldier.oval_rings(
			h,
			[
				Vector2(0.149, 0.04),
				Vector2(0.155, 0.037),
				Vector2(0.156, 0.004),
				Vector2(0.151, 0.001)
			],
			HELMET_OVAL,
			16
		)
	)


## 6B45 body armour following the torso: thick front and back sections with the cummerbund,
## padded shoulder straps, high collar, groin flap, three MOLLE magazine pouches and a side
## pouch; belt.
static func _armour(k: MeshKits, pose: SoldierPose) -> void:
	var vest := k.k(&"vest")
	var dark := k.k(&"dark")
	Soldier.torso_shell(vest, pose, 0.99, 1.43, Vector3(0.05, 0.03, 0.045), 0.1, 6)
	Soldier.shoulder_pads(vest, pose, Vector3(0.15, 0.018, 0.06))
	# High collar: a ring around the neck, higher at the back.
	(
		vest
		. lathe(
			pose.chest * Vector3(-0.012, 1.42, 0.0),
			pose.chest.basis * Basis(Vector3.BACK, 0.15),
			[
				Vector2(0.088, 0.12),
				Vector2(0.11, 0.115),
				Vector2(0.135, 0.02),
				Vector2(0.13, 0.0),
				Vector2(0.1, 0.0),
				Vector2(0.088, 0.12),
			],
			16
		)
	)
	# Groin flap below the belt.
	var flap := Soldier.on_torso(pose, 0.9, PI / 2.0, 0.03)
	vest.pillow(
		flap.origin, Vector3(0.04, 0.16, 0.19), flap.basis.rotated(flap.basis.z, -0.1), 0.35, 4, 8
	)
	var pouches := []
	for d: float in [-0.48, 0.0, 0.48]:
		var f := Soldier.on_torso(pose, 1.15, PI / 2.0 + d, 0.05)
		vest.cbox(f * Vector3(0.033, 0.0, 0.0), Vector3(0.065, 0.15, 0.09), 0.013, f.basis)
		vest.cbox(f * Vector3(0.036, 0.07, 0.0), Vector3(0.07, 0.03, 0.095), 0.008, f.basis)
		pouches.append(f * Vector3(0.033, 0.0, 0.0))
	pose.occluders.capsule(pouches[0], pouches[2], 0.04, 0.8)
	var side_pouch := Soldier.on_torso(pose, 1.12, 0.1, 0.03)
	vest.pillow(
		side_pouch * Vector3(0.03, 0.0, 0.0),
		Vector3(0.06, 0.13, 0.09),
		side_pouch.basis,
		0.45,
		4,
		8
	)
	Soldier.torso_shell(dark, pose, 0.955, 0.995, Vector3(0.012, 0.012, 0.012), 0.0, 3)


## AK-74M (or with `rpk` the RPK-74M: longer barrel and magazine, bipod down when `bipod`) in
## frame `t` (origin on the bore at the butt, see SoldierPose.shouldered): stock with the AK drop,
## receiver, lower handguard, gas tube over the barrel, front sight, muzzle brake, curved magazine,
## pistol grip; `gp30` adds the underbarrel grenade launcher. Returns the grips and the fingers'
## curl.
static func _ak(k: MeshKits, t: Transform3D, gp30: bool, rpk: bool, bipod: bool) -> Array[Vector3]:
	var gun := k.k(&"gun")
	var extra := 0.2 if rpk else 0.0
	var u := t.basis.x
	var v := t.basis.y
	var w := t.basis.z
	gun.plate(
		[Vector2(0.0, 0.0), Vector2(0.24, 0.03), Vector2(0.24, -0.02), Vector2(0.0, -0.11)],
		t.origin,
		u,
		v,
		w,
		-0.0175,
		0.0175,
		0.006
	)
	Soldier.part(gun, t, Vector3(0.39, 0.0, 0.0), Vector3(0.3, 0.07, 0.045))
	Soldier.part(gun, t, Vector3(0.63, -0.008, 0.0), Vector3(0.18, 0.055, 0.05))
	Soldier.part(gun, t, Vector3(0.84 + extra, 0.025, 0.0), Vector3(0.03, 0.05, 0.02), 0.0, 0.004)
	Soldier.part(gun, t, Vector3(0.3, -0.08, 0.0), Vector3(0.04, 0.11, 0.03), -0.3)
	gun.rod(t * Vector3(0.66, 0.038, 0.0), u, 0.013, 0.24, 8)
	(
		Soldier
		. bore_lathe(
			gun,
			t,
			Vector3(0.95 + extra, 0.0, 0.0),
			[
				Vector2(0.0, 0.0),
				Vector2(0.016, 0.0),
				Vector2(0.016, -0.07),
				Vector2(0.011, -0.075),
				Vector2(0.011, -0.41 - extra),
			]
		)
	)
	var magazine := _magazine(1.35 if rpk else 1.0)
	gun.plate(magazine, t.origin, u, v, w, -0.015, 0.015, 0.004)
	if gp30:
		gun.rod(t * Vector3(0.69, -0.065, 0.0), u, 0.024, 0.26, 10, 0.004)
		Soldier.part(gun, t, Vector3(0.56, -0.08, 0.0), Vector3(0.09, 0.07, 0.04))
	if rpk:
		# Bipod at the muzzle: legs splayed down, or folded back under the barrel.
		var leg_end := Vector3(1.0, -0.3, 0.07) if bipod else Vector3(0.68, -0.025, 0.012)
		for side: float in [-1.0, 1.0]:
			(
				gun
				. tube(
					[
						t * Vector3(0.95 + extra, -0.015, 0.0),
						t * Vector3(leg_end.x + extra, leg_end.y, leg_end.z * side),
					],
					0.008,
					4
				)
			)
	Soldier.sling(
		k,
		[
			t * Vector3(0.05, -0.06, -0.02),
			t * Vector3(0.3, -0.18, -0.06),
			t * Vector3(0.6, -0.04, -0.03)
		]
	)
	return [t * Vector3(0.56, -0.05, 0.0), t * Vector3(0.305, -0.1, 0.0), t.basis.y, -t.basis.z]


## Curved (banana) magazine outline in the frame's XY plane, metres; `length` stretches it
## (1.35 = the RPK's 45-round magazine).
static func _magazine(length: float) -> Array:
	var outline := []
	for point: Vector2 in [
		Vector2(0.395, -0.035),
		Vector2(0.465, -0.035),
		Vector2(0.475, -0.09),
		Vector2(0.5, -0.15),
		Vector2(0.535, -0.205),
		Vector2(0.475, -0.235),
		Vector2(0.445, -0.17),
		Vector2(0.415, -0.11),
	]:
		var below := -0.035 - point.y
		var curl := (point.x - 0.395) * (length - 1.0)
		outline.append(Vector2(point.x + curl, -0.035 - below * length))
	return outline


## The assistant grenadier's rocket carrier (EMR bag) on the back plate with three PG-7 warheads
## standing out of it, shoulder straps.
static func _rocket_carrier(k: MeshKits, pose: SoldierPose) -> void:
	var f := Soldier.on_torso(pose, 1.22, -PI / 2.0, 0.045)
	k.k(&"uniform").pillow(
		f * Vector3(0.08, 0.0, 0.0), Vector3(0.16, 0.34, 0.3), f.basis, 0.35, 6, 12
	)
	for z: float in [-0.09, 0.0, 0.09]:
		var origin := f * Vector3(0.08 - absf(z) * 0.2, -0.36 - absf(z) * 0.3, z)
		Soldier.pg7(k.k(&"vest"), origin, f.basis * Basis(Vector3.BACK, 0.12))
	pose.occluders.capsule(f * Vector3(0.08, -0.12, 0.0), f * Vector3(0.08, 0.12, 0.0), 0.085)
