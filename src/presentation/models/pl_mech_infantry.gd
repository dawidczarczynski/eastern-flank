## Polish mechanised infantry squad (12th Mechanized Brigade dismounts, current kit): five
## soldiers in loose wz. 93 Pantera (faction uniform camo), wz. 2005 PASGT-like helmets under
## Pantera covers with ear defenders, KKZ plate carriers in the uniform pattern with olive pouches
## and hydration packs; three MSBS Grot C riflemen in the wide, crouched assault stance, a kneeling
## anti-tank gunner with the Carl Gustaf M4 (AT_LAUNCHER) and a UKM-2000 machine gunner. Squad
## contract: Soldier0..4, each with a Rig; kneelers have Kneel + Stand (Stand hidden); the AT
## gunner's posture nodes carry AtLauncher/Muzzle (parts/at_launcher.gd).
## Blueprint: docs/design/units/units/pl_mech_infantry/blueprint.md.
## The soldier (pose, anatomical body, AO, helpers) is the shared parts/soldier.gd; this
## file adds the Polish kit through `dress`. SOLDIER_SCALE exaggerates the real 1.82 m so the
## squad reads at game zoom.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
const AtLauncher := preload("res://src/presentation/models/parts/at_launcher.gd")
## Look of the squad's anti-tank launcher (parts/at_launcher.gd): the Carl Gustaf M4.
const AT_LAUNCHER_KIND := AtLauncher.CARL_GUSTAF
## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.5
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {"squad_march": {}}
## Exaggeration of the soldiers (real 1.82 m -> 3.2 m), the same on-screen size as the generic
## infantry squad (TASK-031); at true scale a soldier would be 0.24 world units on a 1.0 hex.
const SOLDIER_SCALE := 1.75
const RIFLE := 0
const AT_LAUNCHER := 1
const MG := 2
## How each kit holds its weapon (SoldierPose stances): riflemen crouched in the assault stance.
const STANCES := {
	RIFLE: Soldier.ASSAULT_STANCE,
	AT_LAUNCHER: Soldier.AT_LAUNCHER_STANCE,
	MG: Soldier.HIP_STANCE,
}
## Squad layout: [x, z, kneeling, kit, carry, yaw] (Soldier.squad); front rifleman first, aiming;
## the rear rifleman carries low and watches the right flank, the kneeling one covers the left.
const SQUAD: Array = [
	[0.12, 0.0, false, RIFLE, Soldier.AIM],
	[-0.03, 0.15, true, AT_LAUNCHER],
	[-0.04, -0.15, false, MG],
	[-0.19, 0.06, false, RIFLE, Soldier.LOW, 0.7],
	[-0.16, -0.13, true, RIFLE, Soldier.AIM, -0.5],
]
## Look of the kit (Soldier.materials): the uniform print and the nylon mixed towards the wz. 93
## Pantera tan of the reference GLB, light tan gloves and white-grey knee pads.
const LOOK := {"khaki": 0.7, "light": Color("#b3ab94")}
## High-cut combat helmet (HP-05 / HBT-02 style) under a Pantera cover: a dome of `HELMET_R`
## (radius, oval x length / z width) rising HELMET_CROWN above the rim plane; the rim follows
## `rim_height` – at the brow in front, cut up and back over the ears, low at the nape. Frame: rim
## plane at head-pivot HELMET_AT, tilted HELMET_TILT rad back. HELMET_PHI = the polar angles of
## the dome's rings as fractions of the way to the rim.
const HELMET_R := 0.157
const HELMET_OVAL := Vector2(1.03, 0.95)
const HELMET_CROWN := 0.13
const HELMET_AT := Vector3(0.008, 0.062, 0.0)
const HELMET_TILT := 0.06
const HELMET_PHI: Array[float] = [0.0, 0.22, 0.42, 0.6, 0.76, 0.9, 1.0]
const HELMET_SIDES := 16
## Rim heights (helmet frame, m): over the ears (the high cut) and at the nape.
const RIM_CUT := 0.05
const RIM_NAPE := -0.028
## Ear defender cup: centre in head pivot coordinates (z = side, mirrored) and radius, depth (m).
const EAR_CUP := Vector3(-0.006, 0.03, 0.108)
const EAR_CUP_SIZE := Vector2(0.037, 0.034)


static func build(faction: FactionDefinition) -> Node3D:
	var g := Soldier.squad(
		"pl_mech_infantry", SQUAD, SOLDIER_SCALE, Soldier.materials(faction, LOOK), dress, STANCES
	)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## The Polish kit on one soldier: helmet with ear defenders, plate carrier, hydration pack and the
## weapon of `pose.kit`; returns the grips (see Soldier.squad).
static func dress(k: MeshKits, pose: SoldierPose) -> Array[Vector3]:
	_helmet(k, pose)
	_ear_defenders(k, pose)
	_carrier(k, pose)
	_hydration(k, pose)
	match pose.kit:
		AT_LAUNCHER:
			return AtLauncher.build(k, pose, AT_LAUNCHER_KIND)
		MG:
			return _mg(k, pose)
	return _rifle(k, pose.shouldered(Soldier.carry_angle(pose.carry, pose.kneel, -0.45, -0.25)))


## High-cut helmet under the Pantera cover (uniform camo): the dome down to the cut rim, a lip
## and short inner wall marked as a cavity; the cover's elastic band (khaki nylon); side rails, the
## NVG shroud and its mount (black); the chin strap; goggles over the eyes; AO cap under the rim.
static func _helmet(k: MeshKits, pose: SoldierPose) -> void:
	var h := (
		pose.head
		* Transform3D(Basis(Vector3.BACK, HELMET_TILT), SoldierPose.HEAD_PIVOT + HELMET_AT)
	)
	pose.helmet = h
	var shell := k.k(&"uniform")
	var rings := []
	for f: float in HELMET_PHI:
		rings.append(_helmet_ring(h, f, 1.0, 0.0))
	shell.loft_rings(rings, false)
	shell.openness = Soldier.HELMET_INSIDE
	shell.loft_rings(
		[
			_helmet_ring(h, 1.0, 1.0, 0.0),
			_helmet_ring(h, 1.0, 0.93, -0.008),
			_helmet_ring(h, 0.93, 0.9, 0.0)
		],
		false,
		false
	)
	shell.openness = 1.0
	# Cover band around the dome (2 rings, khaki nylon).
	k.k(&"vest").loft_rings(
		[_helmet_ring(h, 0.62, 1.025, 0.0), _helmet_ring(h, 0.74, 1.025, 0.0)], false
	)
	var dark := k.k(&"dark")
	# Side rails along the cut, the NVG shroud plate and the mount under it.
	for side: float in [-1.0, 1.0]:
		var at := _helmet_point(h, side * 1.45, 0.95, 1.02)
		var along := (
			_helmet_point(h, side * 1.15, 0.95, 1.02) - _helmet_point(h, side * 1.75, 0.95, 1.02)
		)
		var out := (at - h.origin).normalized()
		var rail := Basis(along.normalized(), out.cross(along).normalized(), out)
		dark.cbox(at, Vector3(0.12, 0.024, 0.014), 0.0, rail.orthonormalized())
	var front := h.basis.rotated(h.basis.z, -0.5)
	dark.cbox(_helmet_point(h, 0.0, 0.8, 1.02), Vector3(0.014, 0.05, 0.075), 0.0, front)
	dark.cbox(_helmet_point(h, 0.0, 0.93, 1.06), Vector3(0.022, 0.03, 0.03), 0.0, h.basis)
	# Chin strap from the rim behind the ears to under the chin.
	var face := pose.head * Transform3D(Basis.IDENTITY, SoldierPose.HEAD_PIVOT)
	for side: float in [-1.0, 1.0]:
		(
			dark
			. tube(
				[
					_helmet_point(h, side * 2.0, 1.0, 0.97),
					face * Vector3(0.03, -0.03, side * 0.064),
					face * Vector3(0.05, -0.052, side * 0.03),
					face * Vector3(0.052, -0.056, 0.0),
				],
				0.005,
				4
			)
		)
	# Goggles: a curved band of three lenses in front of the eyes.
	dark.cbox(face * Vector3(0.1, 0.07, 0.0), Vector3(0.016, 0.04, 0.07), 0.0, face.basis)
	for side: float in [-1.0, 1.0]:
		var yaw := Basis(Vector3.UP, -side * 0.75)
		dark.cbox(
			face * Vector3(0.082, 0.07, side * 0.058),
			Vector3(0.014, 0.038, 0.05),
			0.0,
			face.basis * yaw
		)
	pose.occluders.cap(h * Vector3(0.0, 0.03, 0.0), h.basis.y, 0.15, 1.3)


## Rim height of the high-cut shell at the angle `a` (rad, 0 = front, + = left) in the frame.
static func rim_height(a: float) -> float:
	var s := absf(wrapf(a, -PI, PI))
	return RIM_CUT * smoothstep(0.55, 1.05, s) - (RIM_CUT - RIM_NAPE) * smoothstep(1.9, 2.6, s)


## Point of the helmet dome at the angle `a` (0 = front, + = left) and the fraction `f` of the
## way from the crown to the cut rim, the radius scaled by `grow`.
static func _helmet_point(h: Transform3D, a: float, f: float, grow: float) -> Vector3:
	var phi := f * acos(clampf(rim_height(a) / HELMET_CROWN, -1.0, 1.0))
	var r := HELMET_R * sin(phi) * grow
	var y := HELMET_CROWN * cos(phi) * (grow if f < 1.0 else 1.0)
	return h * Vector3(cos(a) * r * HELMET_OVAL.x, y, -sin(a) * r * HELMET_OVAL.y)


## One ring of the dome (HELMET_SIDES points) at the fraction `f`, scaled by `grow`, `dy` lower.
static func _helmet_ring(h: Transform3D, f: float, grow: float, dy: float) -> Array:
	var ring := []
	for j in HELMET_SIDES:
		var a := -TAU * j / HELMET_SIDES  # the shared shells' winding (+z first)
		ring.append(_helmet_point(h, a, f, grow) + h.basis.y * dy)
	return ring


## Electronic ear defenders (headset cups under the helmet's rim): a turned cup over each ear
## (EAR_CUP in head pivot coordinates, z mirrored; EAR_CUP_SIZE = radius, depth), the outer face
## flat with a rounded rim.
static func _ear_defenders(k: MeshKits, pose: SoldierPose) -> void:
	var dark := k.k(&"dark")
	var r := EAR_CUP_SIZE.x
	var d := EAR_CUP_SIZE.y * 0.5
	for side: float in [-1.0, 1.0]:
		var c := (
			pose.head * (SoldierPose.HEAD_PIVOT + Vector3(EAR_CUP.x, EAR_CUP.y, side * EAR_CUP.z))
		)
		(
			dark
			. lathe(
				c,
				pose.head.basis * Basis(Vector3.RIGHT, side * PI / 2.0),
				[
					Vector2(0.0, d),
					Vector2(r * 0.75, d),
					Vector2(r, d * 0.3),
					Vector2(r, -d),
					Vector2(0.0, -d),
				],
				8
			)
		)


## KKZ plate carrier in khaki nylon (LOOK), following the torso: plates front and back, the
## cummerbund lower at the sides, padded shoulder straps; a pouch grid on the front plate – three
## double magazine pouches (15 × 8.5 × 6 cm) with flaps, three smaller pouches above –, radio
## (left) and IFAK (right) on the cummerbund, utility pouches on both hips and a dump pouch at the
## back of the belt; the belt with its buckle.
static func _carrier(k: MeshKits, pose: SoldierPose) -> void:
	var vest := k.k(&"vest")
	var dark := k.k(&"dark")
	Soldier.torso_shell(vest, pose, 1.02, 1.42, Vector3(0.05, 0.026, 0.046), 0.16, 6)
	Soldier.shoulder_pads(vest, pose, Vector3(0.14, 0.016, 0.06))
	# Webbing rows across the cummerbund and plates (the pouch grid's straps).
	for y: float in [1.07, 1.24]:
		Soldier.torso_shell(dark, pose, y, y + 0.016, Vector3(0.055, 0.031, 0.051), 0.0, 2)
	var pouches := []
	for d: float in [-0.42, 0.0, 0.42]:
		var f := Soldier.on_torso(pose, 1.16, PI / 2.0 + d, 0.05)
		vest.cbox(f * Vector3(0.03, 0.0, 0.0), Vector3(0.06, 0.15, 0.085), 0.012, f.basis)
		vest.cbox(f * Vector3(0.034, 0.07, 0.0), Vector3(0.066, 0.026, 0.09), 0.008, f.basis)
		pouches.append(f * Vector3(0.03, 0.0, 0.0))
	pose.occluders.capsule(pouches[0], pouches[2], 0.04, 0.8)
	for d: float in [-0.36, 0.0, 0.36]:
		var f := Soldier.on_torso(pose, 1.3, PI / 2.0 + d, 0.05)
		vest.cbox(f * Vector3(0.022, 0.0, 0.0), Vector3(0.044, 0.1, 0.075), 0.01, f.basis)
	var radio := Soldier.on_torso(pose, 1.2, PI, 0.026)
	vest.pillow(radio * Vector3(0.03, 0.0, 0.0), Vector3(0.06, 0.17, 0.09), radio.basis, 0.45, 4, 8)
	var ifak := Soldier.on_torso(pose, 1.17, 0.15, 0.026)
	vest.pillow(ifak * Vector3(0.03, 0.0, 0.0), Vector3(0.06, 0.13, 0.09), ifak.basis, 0.45, 4, 8)
	for th: float in [PI - 0.55, 0.55]:
		var hip := Soldier.on_torso(pose, 0.97, th, 0.016)
		vest.pillow(hip * Vector3(0.035, 0.0, 0.0), Vector3(0.07, 0.13, 0.11), hip.basis, 0.5, 4, 8)
	var dump := Soldier.on_torso(pose, 0.98, -PI / 2.0, 0.016)
	vest.pillow(dump * Vector3(0.03, 0.0, 0.0), Vector3(0.06, 0.12, 0.2), dump.basis, 0.5, 4, 8)
	pose.occluders.capsule(dump * Vector3(0.03, 0.0, -0.06), dump * Vector3(0.03, 0.0, 0.06), 0.04)
	Soldier.torso_shell(dark, pose, 0.95, 1.0, Vector3(0.014, 0.014, 0.014), 0.0, 3)
	var buckle := Soldier.on_torso(pose, 0.975, PI / 2.0, 0.016)
	dark.cbox(buckle.origin, Vector3(0.012, 0.042, 0.055), 0.004, buckle.basis)


## Low hydration pack on the back plate (the riflemen carry no assault pack in contact).
static func _hydration(k: MeshKits, pose: SoldierPose) -> void:
	var f := Soldier.on_torso(pose, 1.24, -PI / 2.0, 0.046)
	k.k(&"vest").pillow(f * Vector3(0.03, 0.0, 0.0), Vector3(0.06, 0.3, 0.2), f.basis, 0.4, 4, 8)
	pose.occluders.capsule(f * Vector3(0.03, -0.1, 0.0), f * Vector3(0.03, 0.1, 0.0), 0.04)


## MSBS Grot C in the shoulder (frame `t`: origin on the bore at the butt, see
## SoldierPose.shouldered), 0.84 m to the muzzle: telescoping skeleton stock (butt plate, top bar,
## angled lower strut), modular polymer receiver (upper with the ejection port, lower with the
## magazine well), long top rail with a small red dot, handguard with a bottom rail and the front
## sight post, pistol grip raked back, curved polymer magazine with its base plate, exposed barrel
## and short muzzle brake, a sling. Returns the grips (support hand under the handguard, firing
## hand on the pistol grip) and the fingers' curl.
static func _rifle(k: MeshKits, t: Transform3D) -> Array[Vector3]:
	var gun := k.k(&"gun")
	# Folding skeleton stock: butt plate, top bar, the strut from the butt's toe to the receiver.
	Soldier.part(gun, t, Vector3(0.015, -0.035, 0.0), Vector3(0.026, 0.12, 0.034), 0.0, 0.004)
	Soldier.part(gun, t, Vector3(0.125, 0.0, 0.0), Vector3(0.21, 0.024, 0.028), 0.0, 0.0)
	Soldier.part(gun, t, Vector3(0.125, -0.052, 0.0), Vector3(0.22, 0.018, 0.024), 0.27, 0.0)
	# Receiver: upper (to the rail) with the ejection port, lower with the magazine well.
	Soldier.part(gun, t, Vector3(0.34, 0.004, 0.0), Vector3(0.22, 0.046, 0.046))
	Soldier.part(gun, t, Vector3(0.37, -0.034, 0.0), Vector3(0.14, 0.032, 0.04), 0.0, 0.0)
	k.k(&"dark").cbox(t * Vector3(0.36, 0.008, 0.024), Vector3(0.06, 0.016, 0.004), 0.0, t.basis)
	# Top rail over receiver and handguard, the small red dot on it.
	Soldier.part(gun, t, Vector3(0.41, 0.034, 0.0), Vector3(0.38, 0.013, 0.024), 0.0, 0.0)
	Soldier.part(gun, t, Vector3(0.33, 0.046, 0.0), Vector3(0.03, 0.012, 0.022), 0.0, 0.0)
	Soldier.bore_lathe(
		gun,
		t,
		Vector3(0.33, 0.06, 0.0),
		[Vector2(0.0, 0.022), Vector2(0.011, 0.022), Vector2(0.011, -0.022), Vector2(0.0, -0.022)],
		6
	)
	# Handguard with its bottom rail, the front sight post at its end.
	Soldier.part(gun, t, Vector3(0.53, 0.0, 0.0), Vector3(0.18, 0.046, 0.044))
	Soldier.part(gun, t, Vector3(0.53, -0.027, 0.0), Vector3(0.16, 0.01, 0.022), 0.0, 0.0)
	Soldier.part(gun, t, Vector3(0.615, 0.04, 0.0), Vector3(0.016, 0.05, 0.012), 0.0, 0.0)
	# Pistol grip raked back; curved polymer magazine (three segments) and its base plate.
	Soldier.part(gun, t, Vector3(0.26, -0.075, 0.0), Vector3(0.034, 0.1, 0.03), -0.32, 0.0)
	Soldier.part(gun, t, Vector3(0.4, -0.08, 0.0), Vector3(0.062, 0.07, 0.024), 0.08, 0.0)
	Soldier.part(gun, t, Vector3(0.412, -0.14, 0.0), Vector3(0.06, 0.06, 0.024), 0.22, 0.0)
	Soldier.part(gun, t, Vector3(0.43, -0.192, 0.0), Vector3(0.058, 0.056, 0.024), 0.38, 0.0)
	Soldier.part(gun, t, Vector3(0.445, -0.222, 0.0), Vector3(0.066, 0.012, 0.03), 0.45, 0.0)
	# Exposed barrel and the short muzzle brake.
	(
		Soldier
		. bore_lathe(
			gun,
			t,
			Vector3(0.84, 0.0, 0.0),
			[
				Vector2(0.0, 0.0),
				Vector2(0.016, 0.0),
				Vector2(0.016, -0.06),
				Vector2(0.01, -0.065),
				Vector2(0.01, -0.23),
			]
		)
	)
	Soldier.sling(
		k,
		[
			t * Vector3(0.02, -0.07, -0.03),
			t * Vector3(0.32, -0.1, -0.045),
			t * Vector3(0.6, -0.035, -0.03)
		]
	)
	return [t * Vector3(0.5, -0.05, 0.0), t * Vector3(0.265, -0.098, 0.0), t.basis.y, -t.basis.z]


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
