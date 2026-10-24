## Polish mechanised infantry squad (12th Mechanized Brigade dismounts, current kit): five
## soldiers in wz. 93 Pantera (faction uniform camo), wz. 2005 PASGT-like helmets, KKZ plate
## carriers with front pouches and assault packs; three MSBS Grot C riflemen, a kneeling RPG-7
## gunner and a UKM-2000 machine gunner. Squad contract: Soldier0..4, each with a Rig; kneelers
## have Kneel + Stand (Stand hidden).
## Blueprint: docs/design/units/units/pl_mech_infantry/blueprint.md.
## The soldier (pose, anatomical body, AO, RPG-7, helpers) is the shared parts/soldier.gd; this
## file adds the Polish kit through `dress`. SOLDIER_SCALE exaggerates the real 1.82 m so the
## squad reads at game zoom.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.5
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {"squad_march": {}}
## Exaggeration of the soldiers (real 1.82 m -> 3.2 m), the same on-screen size as the generic
## infantry squad (TASK-031); at true scale a soldier would be 0.24 world units on a 1.0 hex.
const SOLDIER_SCALE := 1.75
const RIFLE := 0
const RPG := 1
const MG := 2
## How each kit holds its weapon (SoldierPose stances).
const STANCES := {
	RIFLE: Soldier.RIFLE_STANCE,
	RPG: Soldier.LAUNCHER_STANCE,
	MG: Soldier.HIP_STANCE,
}
## Squad layout: [x, z, kneeling, kit, carry, yaw] (Soldier.squad); front rifleman first, aiming;
## the rear rifleman carries low and watches the right flank, the kneeling one covers the left.
const SQUAD: Array = [
	[0.12, 0.0, false, RIFLE, Soldier.AIM],
	[-0.03, 0.15, true, RPG],
	[-0.04, -0.15, false, MG],
	[-0.19, 0.06, false, RIFLE, Soldier.LOW, 0.7],
	[-0.16, -0.13, true, RIFLE, Soldier.AIM, -0.5],
]
## wz. 2005 helmet (PASGT-like, outer 0.32 × 0.29 m): dome flaring into a short brim, then the
## inner wall of the shell (Vector2(radius, y) from the rim plane, metres); `oval` stretches it to
## the real length / width; rim plane in head pivot coordinates and its back tilt.
const HELMET: Array[Vector2] = [
	Vector2(0.0, 0.128),
	Vector2(0.055, 0.123),
	Vector2(0.095, 0.108),
	Vector2(0.123, 0.083),
	Vector2(0.14, 0.052),
	Vector2(0.148, 0.022),
	Vector2(0.152, 0.004),
	Vector2(0.157, -0.01),
	Vector2(0.153, -0.016),
	Vector2(0.143, -0.006),
	Vector2(0.128, 0.05),
	Vector2(0.0, 0.05),
]
const HELMET_OVAL := Vector2(1.03, 0.93)
const HELMET_AT := Vector3(0.004, 0.07, 0.0)
const HELMET_TILT := 0.24


static func build(faction: FactionDefinition) -> Node3D:
	var g := Soldier.squad(
		"pl_mech_infantry", SQUAD, SOLDIER_SCALE, Soldier.materials(faction), dress, STANCES
	)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## The Polish kit on one soldier: helmet, plate carrier, pack and the weapon of `pose.kit`; returns
## the grips (see Soldier.squad).
static func dress(k: MeshKits, pose: SoldierPose) -> Array[Vector3]:
	_helmet(k, pose)
	_carrier(k, pose)
	_pack(k, pose)
	match pose.kit:
		RPG:
			return Soldier.rpg7(k, pose.launcher())
		MG:
			return _mg(k, pose)
	return _rifle(k, pose.shouldered(Soldier.carry_angle(pose.carry, pose.kneel, -0.45, -0.25)))


## wz. 2005 helmet with the Pantera cover (uniform camo), elastic band, NVG shroud and chin strap.
static func _helmet(k: MeshKits, pose: SoldierPose) -> void:
	var h := Soldier.helmet(k, pose, HELMET, HELMET_AT, HELMET_TILT, HELMET_OVAL)
	var dark := k.k(&"dark")
	dark.loft_rings(
		Soldier.oval_rings(
			h,
			[
				Vector2(0.138, 0.062),
				Vector2(0.144, 0.06),
				Vector2(0.146, 0.05),
				Vector2(0.141, 0.048)
			],
			HELMET_OVAL,
			16
		)
	)
	dark.cbox(
		h * Vector3(0.132, 0.085, 0.0),
		Vector3(0.022, 0.035, 0.045),
		0.008,
		h.basis.rotated(h.basis.z, -0.55)
	)


## KKZ plate carrier following the torso: plates front and back with the cummerbund lower at the
## sides, padded shoulder straps, three magazine pouches (8 × 13 × 4.5 cm) with flaps, radio
## (left) and IFAK (right) on the sides, belt with buckle.
static func _carrier(k: MeshKits, pose: SoldierPose) -> void:
	var vest := k.k(&"vest")
	var dark := k.k(&"dark")
	Soldier.torso_shell(vest, pose, 1.04, 1.42, Vector3(0.036, 0.016, 0.034), 0.15, 6)
	Soldier.shoulder_pads(vest, pose, Vector3(0.13, 0.012, 0.05))
	var pouches := []
	for d: float in [-0.42, 0.0, 0.42]:
		var f := Soldier.on_torso(pose, 1.18, PI / 2.0 + d, 0.036)
		vest.cbox(f * Vector3(0.022, 0.0, 0.0), Vector3(0.045, 0.13, 0.08), 0.01, f.basis)
		vest.cbox(f * Vector3(0.025, 0.06, 0.0), Vector3(0.05, 0.024, 0.084), 0.007, f.basis)
		pouches.append(f * Vector3(0.022, 0.0, 0.0))
	pose.occluders.capsule(pouches[0], pouches[2], 0.03, 0.8)
	var radio := Soldier.on_torso(pose, 1.2, PI, 0.016)
	vest.pillow(
		radio * Vector3(0.025, 0.0, 0.0), Vector3(0.05, 0.16, 0.085), radio.basis, 0.45, 4, 8
	)
	var ifak := Soldier.on_torso(pose, 1.17, 0.15, 0.016)
	vest.pillow(ifak * Vector3(0.025, 0.0, 0.0), Vector3(0.05, 0.12, 0.08), ifak.basis, 0.45, 4, 8)
	Soldier.torso_shell(dark, pose, 0.975, 1.02, Vector3(0.012, 0.012, 0.012), 0.0, 3)
	var buckle := Soldier.on_torso(pose, 0.998, PI / 2.0, 0.014)
	dark.cbox(buckle.origin, Vector3(0.012, 0.042, 0.055), 0.004, buckle.basis)


## Assault pack on the back plate: body, lid, compression straps and a side bottle.
static func _pack(k: MeshKits, pose: SoldierPose) -> void:
	var vest := k.k(&"vest")
	var dark := k.k(&"dark")
	var f := Soldier.on_torso(pose, 1.25, -PI / 2.0, 0.034)
	vest.pillow(f * Vector3(0.072, -0.01, 0.0), Vector3(0.14, 0.32, 0.27), f.basis, 0.35, 6, 12)
	vest.pillow(f * Vector3(0.07, 0.15, 0.0), Vector3(0.16, 0.07, 0.28), f.basis, 0.4, 4, 8)
	for z: float in [-0.08, 0.08]:
		dark.tube(
			[
				f * Vector3(0.14, 0.13, z),
				f * Vector3(0.147, -0.03, z),
				f * Vector3(0.135, -0.13, z)
			],
			0.008,
			4
		)
	(
		dark
		. lathe(
			f * Vector3(0.07, -0.08, 0.155),
			f.basis,
			[
				Vector2(0.0, 0.09),
				Vector2(0.02, 0.09),
				Vector2(0.035, 0.07),
				Vector2(0.035, -0.07),
				Vector2(0.0, -0.07),
			],
			8
		)
	)
	pose.occluders.capsule(f * Vector3(0.07, -0.12, 0.0), f * Vector3(0.07, 0.12, 0.0), 0.075)


## MSBS Grot C in the shoulder (frame `t`: origin on the bore at the butt, see
## SoldierPose.shouldered): polymer stock, receiver, long top rail, handguard, magazine, pistol
## grip, round barrel with the muzzle device, red-dot tube and a sling. Returns the grips (support
## hand under the handguard, firing hand on the pistol grip) and the fingers' curl.
static func _rifle(k: MeshKits, t: Transform3D) -> Array[Vector3]:
	var gun := k.k(&"gun")
	Soldier.part(gun, t, Vector3(0.12, -0.03, 0.0), Vector3(0.24, 0.09, 0.04))
	Soldier.part(gun, t, Vector3(0.37, 0.0, 0.0), Vector3(0.3, 0.07, 0.05))
	Soldier.part(gun, t, Vector3(0.48, 0.045, 0.0), Vector3(0.54, 0.022, 0.032), 0.0, 0.004)
	Soldier.part(gun, t, Vector3(0.65, -0.005, 0.0), Vector3(0.26, 0.06, 0.05))
	Soldier.part(gun, t, Vector3(0.44, -0.11, 0.0), Vector3(0.06, 0.17, 0.028), 0.2)
	Soldier.part(gun, t, Vector3(0.3, -0.08, 0.0), Vector3(0.04, 0.11, 0.03), -0.3)
	(
		Soldier
		. bore_lathe(
			gun,
			t,
			Vector3(0.86, 0.0, 0.0),
			[
				Vector2(0.0, 0.07),
				Vector2(0.017, 0.07),
				Vector2(0.017, 0.02),
				Vector2(0.011, 0.01),
				Vector2(0.011, -0.09),
			]
		)
	)
	Soldier.bore_lathe(
		gun,
		t,
		Vector3(0.38, 0.09, 0.0),
		[Vector2(0.0, 0.05), Vector2(0.02, 0.05), Vector2(0.02, -0.05), Vector2(0.0, -0.05)]
	)
	Soldier.sling(
		k,
		[
			t * Vector3(0.02, -0.06, -0.025),
			t * Vector3(0.3, -0.2, -0.06),
			t * Vector3(0.7, -0.03, -0.03)
		]
	)
	return [t * Vector3(0.53, -0.055, 0.0), t * Vector3(0.305, -0.1, 0.0), t.basis.y, -t.basis.z]


## UKM-2000 carried at the hip (the stock under the right forearm): stock, receiver, feed cover,
## carrying handle, long barrel with the flash hider and gas block, folded bipod, olive ammunition
## box on the left, sling over the left shoulder.
static func _mg(k: MeshKits, pose: SoldierPose) -> Array[Vector3]:
	var gun := k.k(&"gun")
	var t := Transform3D(Basis(Vector3.BACK, 0.06), pose.torso(1.1) * Vector3(-0.1, 1.07, 0.17))
	Soldier.part(gun, t, Vector3(0.13, -0.03, 0.0), Vector3(0.26, 0.11, 0.045))
	Soldier.part(gun, t, Vector3(0.44, 0.0, 0.0), Vector3(0.36, 0.1, 0.07))
	Soldier.part(gun, t, Vector3(0.42, 0.06, 0.0), Vector3(0.22, 0.025, 0.045), 0.0, 0.004)
	Soldier.part(gun, t, Vector3(0.3, -0.09, 0.0), Vector3(0.04, 0.11, 0.035), -0.3)
	Soldier.part(gun, t, Vector3(0.68, 0.065, 0.0), Vector3(0.14, 0.025, 0.025), 0.0, 0.004)
	(
		Soldier
		. bore_lathe(
			gun,
			t,
			Vector3(0.9, 0.0, 0.0),
			[
				Vector2(0.0, 0.3),
				Vector2(0.02, 0.3),
				Vector2(0.02, 0.24),
				Vector2(0.014, 0.23),
				Vector2(0.014, -0.28),
			]
		)
	)
	Soldier.bore_lathe(
		gun,
		t,
		Vector3(0.76, 0.025, 0.0),
		[Vector2(0.0, 0.03), Vector2(0.028, 0.03), Vector2(0.028, -0.06), Vector2(0.0, -0.06)]
	)
	for s: float in [-1.0, 1.0]:
		gun.tube([t * Vector3(0.95, -0.02, s * 0.012), t * Vector3(0.6, -0.04, s * 0.02)], 0.007, 4)
	Soldier.part(k.k(&"vest"), t, Vector3(0.47, -0.1, -0.075), Vector3(0.12, 0.14, 0.09), 0.0, 0.02)
	(
		Soldier
		. sling(
			k,
			[
				t * Vector3(0.05, 0.0, -0.03),
				Soldier.on_torso(pose, 1.3, PI / 2.0 - 0.3, 0.05).origin,
				pose.chest * Vector3(-0.01, 1.51, -0.11),
				Soldier.on_torso(pose, 1.25, -PI / 2.0 - 0.6, 0.05).origin,
			]
		)
	)
	return [t * Vector3(0.52, -0.06, -0.01), t * Vector3(0.3, -0.105, 0.0), t.basis.y, -t.basis.z]
