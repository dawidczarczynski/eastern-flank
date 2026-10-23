## Shared soldier for the infantry squad models (pl_mech_infantry, ru_motor_rifle): the squad
## pivots (SoldierN / Rig, kneelers Kneel + hidden Stand, see UnitModels.pose_infantry) and a smooth
## procedural body built with MeshKit (TASK-067): swept torso, legs and arms with knee, elbow and
## calf shaping, deltoids, neck and head (jaw, nose, ears), gloves, boots with soles, knee pads,
## thigh pockets and the faction sleeve patch; plus the helmet, RPG-7 and weapon helpers both kits
## use. The kit-specific pieces (helmet, armour, pack, weapons) come from the model's `dress` hook.
## Each soldier is built in metres (x forward, y up, z right, feet on y = 0) into one MeshKit per
## material role (base scale M -> model units); the geometry of a soldier variant does not depend
## on the faction and is cached by "<key>:<kit>:<carry>:<kneel>" (ModelParts.cached_meshes).

## Model units per metre (1 unit = 10 m).
const M := 0.1
## Hip height standing / kneeling (m): the upper body drops by the difference when kneeling.
const HIP := 0.92
const HIP_KNEEL := 0.55
## Rifle butt in the right shoulder (m, before the kneeling `up` offset).
const RIFLE_BUTT := Vector3(0.12, 1.34, 0.11)
## Shoulder joint (m, z = side * SHOULDER.z).
const SHOULDER := Vector3(0.0, 1.41, 0.21)
## Head centre (m).
const HEAD := Vector3(0.035, 1.625, 0.0)
## Weapon carry (optional 5th value of a layout entry, default READY): the model's `dress` hook
## turns it into the weapon angle (`carry_angle`). Mixed carries keep a squad from looking like
## five copies of one figure (TASK-068).
const READY := 0
const AIM := 1
const LOW := 2
## Muzzle angle (rad, + = up) of an aimed and of a low-carried weapon.
const AIM_ANGLE := -0.03
const LOW_ANGLE := -0.85
## Material roles, in build order (the uniform camo first).
const ROLES: Array[StringName] = [&"uniform", &"vest", &"skin", &"dark", &"gun", &"accent"]
## Roles of the body itself (the rest is kit and weapons).
const BODY_ROLES: Array[StringName] = [&"uniform", &"skin", &"dark"]
## Boots, gloves, knee pads, belts and straps: weathered dark paint with mud up to the ankles and
## on a kneeling knee (heights in model units of the unscaled soldier, 0.012 = 12 cm).
const GEAR_PAINT := {
	"color": Color("#2a2b25"),
	"base_roughness": 0.85,
	"metallic": 0.05,
	"wear_amount": 0.25,
	"tint_amount": 0.2,
	"dust_amount": 0.3,
	"mud_height": 0.012,
	"mud_amount": 0.7,
	"streak_amount": 0.0,
	"fade": 0.05,
}


## Materials for the ROLES: faction uniform camo, vest colour and accent, PBR skin / gun, the
## weathered gear paint.
static func materials(faction: FactionDefinition) -> Dictionary:
	return {
		&"uniform": ModelParts.faction_material(faction, &"uniform"),
		&"vest": ModelParts.vest(faction),
		&"accent": ModelParts.accent(faction),
		&"skin": ModelParts.pbr(ModelParts.SKIN),
		&"dark": ModelParts.weathered_paint("soldier:gear", GEAR_PAINT),
		&"gun": ModelParts.pbr(ModelParts.GUN),
	}


## The squad: one "SoldierN" pivot per `layout` entry [x, z, kneeling, kit, carry, yaw] (model
## units; carry and yaw optional), scaled by `soldier_scale` and yawed by `yaw` rad, or by
## ±0.3 rad (TerrainNoise.hash) without one. `dress` is
## func(k: MeshKits, up: Vector3, kit: int, kneel: bool, carry: int) -> Array[Vector3]: it adds
## the kit's helmet, armour and weapon (metres, upper body offset by `up`) and returns the
## [left, right] hand positions the arms reach for.
static func squad(
	key: String, layout: Array, soldier_scale: float, mats: Dictionary, dress: Callable
) -> Node3D:
	var g := Node3D.new()
	for i in layout.size():
		var entry: Array = layout[i]
		var kneel: bool = entry[2]
		var kit: int = entry[3]
		var carry: int = entry[4] if entry.size() > 4 else READY
		var s := Node3D.new()
		s.name = "Soldier%d" % i
		s.position = Vector3(entry[0], 0.0, entry[1])
		s.scale = Vector3.ONE * soldier_scale
		s.rotation.y = (
			float(entry[5]) if entry.size() > 5 else (TerrainNoise.hash(i, 3, 1) - 0.5) * 0.6
		)
		g.add_child(s)
		var rig := Node3D.new()
		rig.name = "Rig"
		s.add_child(rig)
		if kneel:
			var kneeling := Node3D.new()
			kneeling.name = "Kneel"
			rig.add_child(kneeling)
			soldier(kneeling, key, mats, true, kit, carry, dress)
			var stand := Node3D.new()
			stand.name = "Stand"
			stand.visible = false
			rig.add_child(stand)
			soldier(stand, key, mats, false, kit, carry, dress)
		else:
			soldier(rig, key, mats, false, kit, carry, dress)
	return g


## One soldier under `into`: one mesh instance per material role, the geometry cached per variant.
static func soldier(
	into: Node3D, key: String, mats: Dictionary, kneel: bool, kit: int, carry: int, dress: Callable
) -> void:
	var meshes := ModelParts.cached_meshes(
		"%s:%d:%d:%s" % [key, kit, carry, kneel],
		func() -> Dictionary: return soldier_kits(kneel, kit, carry, dress).commit_all()
	)
	MeshKits.add_meshes(into, meshes, mats)


## The kits of one soldier: legs, body, the kit from `dress` and the arms reaching its grips.
static func soldier_kits(kneel: bool, kit: int, carry: int, dress: Callable) -> MeshKits:
	var k := MeshKits.new(null, Transform3D(Basis.from_scale(Vector3.ONE * M), Vector3.ZERO))
	for role in ROLES:
		k.k(role)
	var up := Vector3(0.04, HIP_KNEEL - HIP, 0.0) if kneel else Vector3.ZERO
	legs(k, kneel)
	torso(k, up)
	head(k, up)
	var hands: Array[Vector3] = dress.call(k, up, kit, kneel, carry)
	arms(k, up, hands)
	return k


## Weapon angle (rad, + = up) for a `carry`: READY uses the kit's own angle for the posture
## (`ready_stand` / `ready_kneel`), AIM and LOW are shared.
static func carry_angle(carry: int, kneel: bool, ready_stand: float, ready_kneel: float) -> float:
	match carry:
		AIM:
			return AIM_ANGLE
		LOW:
			return LOW_ANGLE
	return ready_kneel if kneel else ready_stand


# --- Body -----------------------------------------------------------------------------------------


## Legs and boots; the lowest point (boot soles, the kneeling knee pad) is y = 0.
static func legs(k: MeshKits, kneel: bool) -> void:
	if kneel:
		# Left knee up, right knee on the ground, right foot behind on its toes.
		leg(
			k,
			Vector3(0.0, HIP_KNEEL, -0.1),
			Vector3(0.44, 0.55, -0.12),
			Vector3(0.42, 0.12, -0.13),
			Basis.IDENTITY,
			false
		)
		leg(
			k,
			Vector3(0.0, HIP_KNEEL, 0.1),
			Vector3(0.06, 0.09, 0.12),
			Vector3(-0.36, 0.22, 0.13),
			Basis(Vector3.BACK, -0.75),
			true
		)
		return
	for side: float in [-1.0, 1.0]:
		var stride := -side * 0.06
		leg(
			k,
			Vector3(0.0, HIP, side * 0.1),
			Vector3(stride + 0.02, 0.5, side * 0.11),
			Vector3(stride * 1.6, 0.12, side * 0.12),
			Basis.IDENTITY,
			false
		)


## Thigh and shin as one smooth sweep with knee and calf shaping, cargo pocket, knee pad and the
## boot (shaft, rounded upper, chamfered sole); `foot` turns the boot (toes down for a kneeler's
## back foot), `knee_down` puts the knee pad on the ground.
static func leg(
	k: MeshKits, hip: Vector3, knee: Vector3, ankle: Vector3, foot: Basis, knee_down: bool
) -> void:
	var uni := k.k(&"uniform")
	var dark := k.k(&"dark")
	var thigh := (knee - hip).normalized()
	var shin := (ankle - knee).normalized()
	(
		uni
		. sweep(
			[
				hip - thigh * 0.04,
				hip,
				hip.lerp(knee, 0.35),
				hip.lerp(knee, 0.75),
				knee,
				knee.lerp(ankle, 0.3),
				knee.lerp(ankle, 0.75),
				ankle - shin * 0.04,
			],
			[
				Vector2(0.09, 0.09),
				Vector2(0.095, 0.095),
				Vector2(0.088, 0.09),
				Vector2(0.072, 0.074),
				Vector2(0.066, 0.068),
				Vector2(0.066, 0.07),
				Vector2(0.052, 0.054),
				Vector2(0.05, 0.05),
			],
			10
		)
	)
	var side := Vector3(0, 0, signf(hip.z))
	# Cargo pocket on the outer thigh.
	uni.pillow(
		hip.lerp(knee, 0.5) + side * 0.075,
		Vector3(0.11, 0.15, 0.04),
		Basis(thigh.cross(side).normalized(), -thigh, side).orthonormalized(),
		0.35,
		4,
		8
	)
	# Knee pad in front of the knee (on the ground when kneeling).
	var pad_dir := thigh.cross(side).normalized()
	if pad_dir.x < 0.0:
		pad_dir = -pad_dir
	var pad_c := knee + Vector3(0.03, -0.045, 0.0) if knee_down else knee + pad_dir * 0.055
	if not knee_down:
		pad_c += shin * 0.02
	dark.pillow(
		pad_c,
		Vector3(0.05, 0.12, 0.1),
		Basis(Vector3.BACK, 1.3 if knee_down else atan2(-shin.x, -shin.y)),
		0.45,
		4,
		8
	)
	# Boot: shaft, rounded upper and a chamfered sole.
	dark.sweep(
		[ankle - shin * 0.15, ankle - shin * 0.02], [Vector2(0.058, 0.06), Vector2(0.06, 0.062)], 10
	)
	dark.pillow(
		ankle + foot * Vector3(0.05, -0.05, 0.0), Vector3(0.28, 0.1, 0.11), foot, 0.45, 6, 8
	)
	dark.cbox(ankle + foot * Vector3(0.05, -0.105, 0.0), Vector3(0.29, 0.03, 0.115), 0.01, foot)


## Torso as one sweep (pelvis, waist, chest, shoulders, neck base) with deltoids and the shirt
## collar.
static func torso(k: MeshKits, up: Vector3) -> void:
	var uni := k.k(&"uniform")
	var path := []
	var radii := []
	for row: Array in [
		[0.84, 0.0, 0.15, 0.1],
		[0.92, 0.0, 0.17, 0.115],
		[1.02, 0.0, 0.155, 0.105],
		[1.14, 0.01, 0.165, 0.11],
		[1.27, 0.02, 0.19, 0.125],
		[1.37, 0.02, 0.2, 0.115],
		[1.43, 0.02, 0.17, 0.09],
		[1.47, 0.02, 0.08, 0.06],
	]:
		path.append(up + Vector3(row[1], row[0], 0.0))
		radii.append(Vector2(row[2], row[3]))
	uni.sweep(path, radii, 16)
	for side: float in [-1.0, 1.0]:
		uni.pillow(
			up + Vector3(0.0, 1.405, side * 0.2),
			Vector3(0.14, 0.13, 0.13),
			Basis.IDENTITY,
			0.9,
			6,
			8
		)
	uni.sweep(
		[up + Vector3(0.015, 1.45, 0.0), up + Vector3(0.02, 1.5, 0.0)],
		[Vector2(0.075, 0.068), Vector2(0.07, 0.064)],
		12
	)


## Neck and head: ellipsoid skull, jaw, nose and ears (no face – TASK-053).
static func head(k: MeshKits, up: Vector3) -> void:
	var skin := k.k(&"skin")
	skin.sweep(
		[up + Vector3(0.015, 1.47, 0.0), up + Vector3(0.03, 1.57, 0.0)],
		[Vector2(0.052, 0.05), Vector2(0.05, 0.048)],
		10
	)
	var c := up + HEAD
	skin.pillow(c, Vector3(0.19, 0.23, 0.16), Basis.IDENTITY, 0.9, 8, 12)
	skin.pillow(c + Vector3(0.05, -0.075, 0.0), Vector3(0.1, 0.08, 0.12), Basis.IDENTITY, 0.8, 4, 8)
	skin.cbox(
		c + Vector3(0.098, -0.01, 0.0), Vector3(0.03, 0.05, 0.026), 0.008, Basis(Vector3.BACK, 0.25)
	)
	for side: float in [-1.0, 1.0]:
		skin.pillow(
			c + Vector3(0.0, -0.005, side * 0.08),
			Vector3(0.04, 0.06, 0.02),
			Basis.IDENTITY,
			0.8,
			4,
			8
		)


## Upper arms and forearms (smooth, bent at the elbow) to the `hands` ([left, right]), gloves and
## a faction-colour patch on each sleeve.
static func arms(k: MeshKits, up: Vector3, hands: Array[Vector3]) -> void:
	var uni := k.k(&"uniform")
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := up + Vector3(SHOULDER.x, SHOULDER.y, side * SHOULDER.z)
		var hand: Vector3 = hands[i]
		var elbow := (shoulder + hand) / 2.0 + Vector3(-0.08, -0.12, side * 0.07)
		var wrist := hand + (elbow - hand).normalized() * 0.06
		(
			uni
			. sweep(
				[shoulder, shoulder.lerp(elbow, 0.5), elbow, elbow.lerp(wrist, 0.4), wrist],
				[
					Vector2(0.064, 0.064),
					Vector2(0.056, 0.058),
					Vector2(0.048, 0.05),
					Vector2(0.045, 0.046),
					Vector2(0.036, 0.036),
				],
				10
			)
		)
		var fore := (hand - elbow).normalized()
		var glove := Basis(fore, fore.cross(Vector3.BACK * side).normalized(), Vector3.BACK)
		k.k(&"dark").pillow(hand, Vector3(0.1, 0.05, 0.085), glove.orthonormalized(), 0.6, 4, 8)
		var patch := shoulder.lerp(elbow, 0.38) + Vector3(0.0, 0.0, side * 0.058)
		k.k(&"accent").cbox(patch, Vector3(0.06, 0.04, 0.006), 0.002)


# --- Kit helpers ----------------------------------------------------------------------------------


## Helmet frame: crown base at `up` + (0, base_y, 0), tilted `tilt` rad back (lathe axis = its Y).
static func helmet_frame(up: Vector3, base_y: float, tilt: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, tilt), up + Vector3(0.0, base_y, 0.0))


## Helmet shell (uniform camo cover): a lathe of `profile` (Vector2(radius, y) in metres around the
## frame's Y, top down) in the helmet frame `h`, and the chin strap from the shell's sides at
## `strap_y` under the chin.
static func helmet(
	k: MeshKits, up: Vector3, h: Transform3D, profile: Array, strap_y: float, sides := 18
) -> void:
	k.k(&"uniform").lathe(h.origin, h.basis, profile, sides)
	var c := up + HEAD
	for side: float in [-1.0, 1.0]:
		(
			k
			. k(&"dark")
			. tube(
				[
					h * Vector3(0.0, strap_y, side * 0.15),
					c + Vector3(0.03, -0.09, side * 0.065),
					c + Vector3(0.07, -0.12, 0.0),
				],
				0.007,
				4
			)
		)


## Chamfered box at `pos` in the frame `t` (metres), rolled by `roll` rad about the frame's Z.
static func part(
	kit: MeshKit, t: Transform3D, pos: Vector3, size: Vector3, roll := 0.0, b := 0.006
) -> void:
	kit.cbox(t * pos, size, b, t.basis * Basis(Vector3.BACK, roll))


## Turned part along the frame's X (bore axis): `profile` = Vector2(radius, distance along x from
## `x`) from the muzzle end backwards.
static func bore_lathe(
	kit: MeshKit, t: Transform3D, at: Vector3, profile: Array, sides := 8
) -> void:
	kit.lathe(t * at, t.basis * Basis(Vector3.BACK, -PI / 2.0), profile, sides)


## Sling (dark tube) through `points`.
static func sling(k: MeshKits, points: Array) -> void:
	k.k(&"dark").tube(points, 0.007, 4)


## RPG-7 along the X axis of frame `t` (origin = the tube's middle, on the shoulder): tube with
## the heat shield and venturi flare, the conical PG-7 warhead (olive, vest colour), two pistol
## grips and the sight. Returns the [left, right] hand positions on the grips.
static func rpg7(k: MeshKits, t: Transform3D) -> Array[Vector3]:
	var gun := k.k(&"gun")
	bore_lathe(
		gun,
		t,
		Vector3.ZERO,
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
		12
	)
	pg7(k.k(&"vest"), t.origin, t.basis * Basis(Vector3.BACK, -PI / 2.0))
	part(gun, t, Vector3(0.0, -0.07, 0.0), Vector3(0.03, 0.1, 0.025), -0.25)
	part(gun, t, Vector3(0.2, -0.07, 0.0), Vector3(0.03, 0.1, 0.025), -0.25)
	part(gun, t, Vector3(0.16, 0.05, -0.03), Vector3(0.05, 0.05, 0.02))
	return [t * Vector3(0.2, -0.12, -0.02), t * Vector3(0.0, -0.12, 0.0)]


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


## RPG-7 frame on the right shoulder (tube middle at the shoulder, muzzle 0.04 rad up) for
## `rpg7`; `up` = the kneeling offset of the upper body.
static func rpg7_shoulder(up: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, 0.04), up + Vector3(0.02, 1.49, 0.16))
