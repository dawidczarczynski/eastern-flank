extends RefCounted
## Body of the shared soldier (TASK-085, soldier v4 stage A): torso, legs, boots, neck and head,
## arms and gloved hands as smooth `MeshKit.sweep_profile` / `loft_rings` surfaces of anatomical
## cross-sections (chest flatter in front, shoulder blades, waist, glutes, tapering thighs, knee,
## calf, deltoid, biceps, forearm to the wrist; skull, jaw, nose, brow and cheekbones) around the
## joints of a `SoldierPose`, in metres. The uniform is the body's shell (slightly loose sections,
## bunched at the knees and elbows, bloused over the boots). Also the torso-surface helpers the kits
## use to make armour and pouches follow the chest (`on_torso`, `torso_shell`) and the body's AO
## proxies. Sections are constant tables (presentation geometry, not balance data).

## Torso rows (neutral, from the crotch to the collar): [y, centre x, half width, front, back,
## exponent (1 elliptic, < 1 squarer), pectorals, shoulder blades / glutes, spine groove] (m).
const TORSO := [
	[0.8, 0.0, 0.07, 0.05, 0.06, 1.0, 0.0, 0.0, 0.0],
	[0.85, 0.0, 0.15, 0.085, 0.1, 0.9, 0.0, 0.012, 0.0],
	[0.92, -0.005, 0.18, 0.1, 0.122, 0.85, 0.0, 0.022, -0.006],
	[1.0, 0.0, 0.173, 0.106, 0.113, 0.85, 0.0, 0.012, -0.008],
	[1.08, 0.006, 0.165, 0.116, 0.104, 0.85, 0.0, 0.0, -0.01],
	[1.16, 0.008, 0.166, 0.122, 0.104, 0.85, 0.0, 0.006, -0.012],
	[1.25, 0.01, 0.173, 0.132, 0.11, 0.8, 0.008, 0.012, -0.012],
	[1.33, 0.012, 0.178, 0.137, 0.118, 0.8, 0.012, 0.016, -0.01],
	[1.4, 0.008, 0.188, 0.118, 0.118, 0.75, 0.006, 0.018, -0.008],
	[1.45, 0.0, 0.196, 0.086, 0.092, 0.7, 0.0, 0.01, 0.0],
	[1.485, -0.008, 0.13, 0.066, 0.075, 0.8, 0.0, 0.0, 0.0],
	[1.515, -0.012, 0.074, 0.058, 0.062, 1.0, 0.0, 0.0, 0.0],
]
const TORSO_SIDES := 20
## Leg rows along the leg (s: 0 hip joint, 1 knee, 2 ankle; < 0 inside the pelvis): [s, lateral,
## medial, front, back, front exponent, back exponent, fold] – trousers over the thigh, knee and
## calf, bloused over the boot top (1.62) and tucked into it.
const LEG := [
	[-0.12, 0.09, 0.07, 0.088, 0.098, 0.9, 0.9, 0.0],
	[0.0, 0.098, 0.078, 0.092, 0.105, 0.9, 0.85, 0.0],
	[0.22, 0.09, 0.079, 0.087, 0.09, 0.9, 0.9, 0.0],
	[0.48, 0.08, 0.071, 0.079, 0.077, 0.95, 0.95, 0.0],
	[0.72, 0.07, 0.064, 0.071, 0.068, 0.95, 1.0, 0.0],
	[1.0, 0.059, 0.057, 0.066, 0.06, 1.0, 1.0, 0.004],
	[1.14, 0.057, 0.055, 0.056, 0.066, 1.0, 1.0, 0.0],
	[1.32, 0.058, 0.053, 0.052, 0.072, 1.0, 1.0, 0.0],
	[1.5, 0.052, 0.048, 0.048, 0.062, 1.0, 1.0, 0.0],
	[1.56, 0.059, 0.057, 0.057, 0.063, 1.0, 1.0, 0.006],
	[1.63, 0.05, 0.048, 0.05, 0.052, 1.0, 1.0, 0.0],
]
const LEG_SIDES := 12
## Arm rows (s: 0 shoulder joint, 1 elbow, 2 wrist; < 0 the deltoid's cap): [s, lateral, medial,
## front (biceps / flexors), back (triceps), fold] – the sleeve, bunched at the elbow.
const ARM := [
	[-0.07, 0.03, 0.026, 0.03, 0.03, 0.0],
	[0.0, 0.07, 0.05, 0.058, 0.06, 0.0],
	[0.2, 0.064, 0.05, 0.056, 0.056, 0.0],
	[0.5, 0.052, 0.046, 0.054, 0.05, 0.0],
	[1.0, 0.047, 0.045, 0.045, 0.05, 0.004],
	[1.22, 0.047, 0.045, 0.046, 0.041, 0.0],
	[1.6, 0.04, 0.037, 0.036, 0.032, 0.0],
	[1.92, 0.034, 0.032, 0.027, 0.026, 0.003],
	[2.02, 0.029, 0.027, 0.021, 0.021, 0.0],
]
const ARM_SIDES := 12
## Head rows (head pivot coordinates, from the collar to the crown): [y, centre x, half width,
## front, back, front exponent, nose, cheekbones, brow ridge, eye sockets] – neck, jaw and chin,
## mouth, nose, cheekbones, eyes under the brow ridge, forehead, crown. Points crowd towards the
## face (HEAD_WARP).
const HEAD := [
	[-0.105, -0.012, 0.057, 0.057, 0.058, 1.0, 0.0, 0.0, 0.0, 0.0],
	[-0.07, -0.006, 0.054, 0.058, 0.056, 1.0, 0.0, 0.0, 0.0, 0.0],
	[-0.046, 0.0, 0.056, 0.07, 0.062, 1.2, 0.0, 0.0, 0.0, 0.0],
	[-0.037, 0.004, 0.06, 0.084, 0.07, 1.3, 0.0, 0.0, 0.0, 0.0],
	[-0.01, 0.004, 0.066, 0.088, 0.085, 1.1, 0.004, 0.0, 0.0, 0.0],
	[0.02, 0.0, 0.071, 0.084, 0.095, 0.95, 0.03, 0.005, 0.0, 0.0],
	[0.045, 0.0, 0.075, 0.08, 0.098, 0.85, 0.026, 0.01, 0.0, -0.006],
	[0.068, 0.0, 0.077, 0.08, 0.1, 0.85, 0.014, 0.003, 0.0, -0.016],
	[0.09, 0.0, 0.078, 0.086, 0.099, 0.85, 0.004, 0.0, 0.012, -0.002],
	[0.115, 0.0, 0.076, 0.091, 0.098, 0.9, 0.0, 0.0, 0.0, 0.0],
	[0.146, 0.0, 0.068, 0.074, 0.086, 0.9, 0.0, 0.0, 0.0, 0.0],
	[0.164, 0.0, 0.048, 0.05, 0.06, 0.9, 0.0, 0.0, 0.0, 0.0],
	[0.176, 0.0, 0.012, 0.012, 0.014, 1.0, 0.0, 0.0, 0.0, 0.0],
]
const HEAD_SIDES := 20
const HEAD_WARP := 0.45
## Short hair: a thin shell over the back and sides of the head (HEAD rows HAIR_ROWS), from
## HAIR_ARC (rad, 0 = right, PI / 2 = front) around the back.
const HAIR_ROWS := Vector2i(4, 10)
const HAIR_ARC := Vector2(PI - 0.35, TAU + 0.35)
## Boot upper along the foot (ankle frame, x forward): [x, half width, top, bottom] around the
## centre line at BOOT_Y; a rounded toe cap, the instep, the heel.
const BOOT := [
	[-0.082, 0.02, 0.03, 0.02],
	[-0.072, 0.036, 0.05, 0.035],
	[-0.04, 0.043, 0.066, 0.035],
	[0.02, 0.046, 0.058, 0.035],
	[0.08, 0.05, 0.04, 0.035],
	[0.135, 0.052, 0.03, 0.035],
	[0.18, 0.048, 0.026, 0.035],
	[0.205, 0.038, 0.021, 0.032],
	[0.218, 0.02, 0.012, 0.026],
]
const BOOT_Y := -0.045
const BOOT_SIDES := 10
## Sole (under the upper, metres): thickness and overhang.
const SOLE := Vector2(0.03, 0.007)

## Rings made by `section`, by their arguments: the tables are constant, so every soldier after
## the first reuses them (read-only).
static var _sections := {}


## Cross-section ring: `count` points counter-clockwise from +a (`warp` > 0 crowds them towards
## +b): a superellipse with the half sizes `ap` / `an` (±a), `bp` / `bn` (±b), exponent `x` on
## the +b half and `y` on the −b half of `exps` (1 elliptic, < 1 squarer, > 1 pinched), plus
## radial bumps Vector3(angle, width, height) (Gaussian) and folds Vector3(amplitude, lobes,
## phase). The returned Array is shared: do not modify it.
static func section(
	count: int,
	ap: float,
	an: float,
	bp: float,
	bn: float,
	exps := Vector2.ONE,
	bumps: Array = [],
	warp := 0.0,
	fold := Vector3.ZERO
) -> Array:
	var key := [count, Vector4(ap, an, bp, bn), exps, bumps, warp, fold]
	if _sections.has(key):
		return _sections[key]
	var ring := []
	for k in count:
		var u := TAU * k / count
		var th := u - warp * sin(u - PI / 2.0)
		ring.append(shape_point(th, Vector4(ap, an, bp, bn), exps, bumps, fold))
	_sections[key] = ring
	return ring


## One point of a `section` at angle `th` (`size` = (ap, an, bp, bn)).
static func shape_point(
	th: float, size: Vector4, exps: Vector2, bumps: Array, fold := Vector3.ZERO
) -> Vector2:
	var c := cos(th)
	var s := sin(th)
	var e := exps.x if s >= 0.0 else exps.y
	var q := Vector2(
		_spow(c, e) * (size.x if c >= 0.0 else size.y),
		_spow(s, e) * (size.z if s >= 0.0 else size.w)
	)
	var radial := 0.0
	for bump: Vector3 in bumps:
		if bump.z != 0.0:
			var x := angle_difference(th, bump.x) / bump.y
			radial += bump.z * exp(-x * x)
	if fold.x != 0.0:
		radial += fold.x * (0.5 + 0.5 * sin(fold.y * th + fold.z))
	return q + Vector2(c, s) * radial


static func _spow(x: float, e: float) -> float:
	if absf(x) < 1e-9:
		return 0.0
	return signf(x) * pow(absf(x), e)


# --- Legs and boots -----------------------------------------------------------------------------


## Both legs: trouser sweeps hip – knee – boot top, cargo pockets, knee pads (on the ground for a
## kneeling right knee), boots; AO proxies for thighs, shins and boots.
static func legs(k: MeshKits, pose: SoldierPose) -> void:
	var uni := k.k(&"uniform")
	var dark := k.k(&"dark")
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tag := "l" if i == 0 else "r"
		var hip: Vector3 = pose.joints[StringName("hip_" + tag)]
		var knee: Vector3 = pose.joints[StringName("knee_" + tag)]
		var ankle: Vector3 = pose.joints[StringName("ankle_" + tag)]
		var bend := (knee - hip).angle_to(ankle - knee)
		var path := []
		var profiles := []
		var knee_index := 0
		var t0 := (knee - hip).normalized()
		var side0 := pose.pelvis.basis.x.cross(t0)
		var mirror := signf(side0.dot(pose.pelvis.basis.z * side))
		for row: Array in LEG:
			var s: float = row[0]
			if bend > 0.9 and absf(s - 1.0) > 0.0 and absf(s - 1.0) < 0.15:
				continue
			if s == 1.0:
				knee_index = path.size()
			path.append(hip + (knee - hip) * s if s <= 1.0 else knee + (ankle - knee) * (s - 1.0))
			var bumps := [Vector3(PI / 2.0, 0.35, 0.008)] if s == 1.0 else []
			var fold := Vector3(row[7], 5.0, i * 1.3) if row[7] > 0.0 else Vector3.ZERO
			profiles.append(
				_mirrored(
					section(
						LEG_SIDES,
						row[1],
						row[2],
						row[3],
						row[4],
						Vector2(row[5], row[6]),
						bumps,
						0.0,
						fold
					),
					mirror
				)
			)
		uni.sweep_profile(path, profiles, side0)
		var frames := MeshKit.sweep_frames(path, side0)
		_leg_kit(k, path, frames, knee_index, mirror, i == 1 and pose.kneel)
		boot(dark, pose.feet[i], knee)
		pose.occluders.capsule(hip, knee, 0.066)
		pose.occluders.capsule(knee, ankle, 0.046)
		var foot: Transform3D = pose.feet[i]
		pose.occluders.capsule(
			foot * Vector3(-0.04, -0.06, 0.0), foot * Vector3(0.16, -0.07, 0.0), 0.035
		)


## Cargo pocket on the outer thigh and the knee pad, oriented with the leg (`frames` of the leg's
## sweep; the frames' side axis times `lateral` points outwards).
static func _leg_kit(
	k: MeshKits, path: Array, frames: Array, knee_index: int, lateral: float, kneeling: bool
) -> void:
	var tk: Vector3 = frames[knee_index][0]
	var ak: Vector3 = frames[knee_index][1]
	var bk := tk.cross(ak)
	var knee: Vector3 = path[knee_index]
	var hip: Vector3 = path[1]
	var thigh := (knee - hip).normalized()
	var out: Vector3 = (frames[2][1] as Vector3) * lateral
	var pocket := hip.lerp(knee, 0.48) + out * 0.078
	var pb := Basis(out, -thigh, out.cross(-thigh)).orthonormalized()
	k.k(&"uniform").pillow(pocket, Vector3(0.022, 0.15, 0.11), pb, 0.6, 4, 8)
	var pad := knee + bk * (0.072 if kneeling else 0.075) + tk * 0.012
	k.k(&"dark").pillow(
		pad, Vector3(0.028, 0.11, 0.09), Basis(bk, tk, ak).orthonormalized(), 0.45, 4, 8
	)


## Boot on the ankle frame `foot` (sole bottom at its local y = −ANKLE_H): shaft up the shin
## (towards `knee`), the upper from a last profile (heel, instep, ball, rounded toe cap) and a thin
## chamfered sole following its outline.
static func boot(dark: MeshKit, foot: Transform3D, knee: Vector3) -> void:
	var ankle := foot.origin
	var up := (knee - ankle).normalized()
	dark.sweep(
		[ankle - up * 0.03, ankle + up * 0.07, ankle + up * 0.15, ankle + up * 0.16],
		[Vector2(0.044, 0.05), Vector2(0.043, 0.048), Vector2(0.048, 0.052), Vector2(0.044, 0.048)],
		BOOT_SIDES,
		foot.basis.z
	)
	var path := []
	var profiles := []
	var outline_right := []
	var outline_left := []
	for row: Array in BOOT:
		path.append(foot * Vector3(row[0], BOOT_Y, 0.0))
		profiles.append(
			section(BOOT_SIDES, row[1], row[1], row[2], row[3], Vector2(0.9, 0.3), [], 0.0)
		)
		if path.size() % 2 == 0:
			outline_right.append(Vector2(row[0], row[1] + SOLE.y))
			outline_left.append(Vector2(row[0], -row[1] - SOLE.y))
	dark.sweep_profile(path, profiles, foot.basis.y.cross(foot.basis.x))
	outline_left.reverse()
	var outline := [Vector2(-0.09, 0.0)] + outline_right + [Vector2(0.228, 0.0)] + outline_left
	dark.plate(
		outline,
		foot * Vector3(0.0, -SoldierPose.ANKLE_H, 0.0),
		foot.basis.x,
		foot.basis.z,
		foot.basis.y,
		0.0,
		SOLE.x,
		0.008
	)


# --- Torso, neck and head -------------------------------------------------------------------------


## Torso: pelvis with glutes, waist, chest, shoulder blades, shoulders and the collar, posed along
## the spine (`SoldierPose.torso`); AO proxies across the pelvis, belly and chest.
static func torso(k: MeshKits, pose: SoldierPose) -> void:
	var loops := []
	for row: Array in TORSO:
		var y: float = row[0]
		var xf := pose.torso(y)
		var loop := []
		for q: Vector2 in torso_section(row, TORSO_SIDES):
			loop.append(xf * Vector3(row[1] + q.y, y, q.x))
		loops.append(loop)
	k.k(&"uniform").loft_rings(loops)
	for level: Vector3 in [
		Vector3(0.95, -0.01, 0.09), Vector3(1.12, 0.005, 0.095), Vector3(1.3, 0.02, 0.1)
	]:
		var xf := pose.torso(level.x)
		pose.occluders.capsule(
			xf * Vector3(level.y, level.x, -0.07), xf * Vector3(level.y, level.x, 0.07), level.z
		)


## Ring of a TORSO row (or an interpolated one).
static func torso_section(row: Array, count: int) -> Array:
	return section(
		count, row[2], row[2], row[3], row[4], Vector2(row[5], row[5]), _torso_bumps(row)
	)


static func _torso_bumps(row: Array) -> Array:
	return [
		Vector3(PI / 2.0 - 0.55, 0.35, row[6]),
		Vector3(PI / 2.0 + 0.55, 0.35, row[6]),
		Vector3(-PI / 2.0 - 0.6, 0.4, row[7]),
		Vector3(-PI / 2.0 + 0.6, 0.4, row[7]),
		Vector3(-PI / 2.0, 0.22, row[8]),
	]


## TORSO row interpolated at the neutral height `y`.
static func torso_row(y: float) -> Array:
	var last: Array = TORSO[TORSO.size() - 1]
	if y >= last[0]:
		return last
	for i in range(1, TORSO.size()):
		var hi: Array = TORSO[i]
		if y <= hi[0]:
			var lo: Array = TORSO[i - 1]
			var f := clampf((y - lo[0]) / (hi[0] - lo[0]), 0.0, 1.0)
			var row := []
			for c in lo.size():
				row.append(lerpf(lo[c], hi[c], f))
			return row
	return TORSO[0]


## Neutral torso surface point at height `y` and angle `th` (0 right, PI / 2 front, PI left,
## −PI / 2 back) pushed `out` metres along the surface normal: [point, outward normal].
static func torso_point(y: float, th: float, out := 0.0) -> Array:
	var row := torso_row(y)
	var size := Vector4(row[2], row[2], row[3], row[4])
	var exps := Vector2(row[5], row[5])
	var bumps := _torso_bumps(row)
	var q := shape_point(th, size, exps, bumps)
	var tangent := (
		shape_point(th + 0.02, size, exps, bumps) - shape_point(th - 0.02, size, exps, bumps)
	)
	var n2 := Vector2(tangent.y, -tangent.x).normalized()
	if n2.dot(q) < 0.0:
		n2 = -n2
	q += n2 * out
	return [Vector3(row[1] + q.y, y, q.x), Vector3(n2.y, 0.0, n2.x)]


## Padded shoulder straps of a carrier / armour: a flat pad of `size` (along the shoulder,
## thickness, width) on each trapezius, sloping down to the shoulder.
static func shoulder_pads(kit: MeshKit, pose: SoldierPose, size: Vector3) -> void:
	for side: float in [-1.0, 1.0]:
		var c := pose.chest * Vector3(-0.012, 1.496 + size.y * 0.5, side * 0.105)
		var b := pose.chest.basis * Basis(Vector3.RIGHT, side * 0.42)
		kit.pillow(c, size, b, 0.45, 4, 8)


## Posed frame on the torso surface at height `y`, angle `th`, `out` metres off it: origin on the
## surface, x = outward normal, y = up the spine, z = x × y (pouches, plates, packs).
static func on_torso(pose: SoldierPose, y: float, th: float, out := 0.0) -> Transform3D:
	var at := torso_point(y, th, out)
	var n: Vector3 = at[1]
	var local := Transform3D(Basis(n, Vector3.UP, n.cross(Vector3.UP)), at[0])
	return pose.torso(y) * local


## Closed shell around the torso (armour, cummerbund, belt) from `y0` to `y1` (neutral), grown off
## the body by `grow` = (front, sides, back) metres, its top edge `dip` lower at the sides
## (armholes); `levels` rings with rounded rims.
static func torso_shell(
	kit: MeshKit, pose: SoldierPose, y0: float, y1: float, grow: Vector3, dip := 0.0, levels := 5
) -> void:
	var loops := []
	for level in levels:
		var f := float(level) / (levels - 1)
		var rim := 0.35 if level == 0 or level == levels - 1 else 1.0
		var loop := []
		for j in TORSO_SIDES:
			var th := TAU * j / TORSO_SIDES
			var s := sin(th)
			var g := (
				grow.y
				+ (grow.x - grow.y) * maxf(s, 0.0) ** 2
				+ (grow.z - grow.y) * maxf(-s, 0.0) ** 2
			)
			var top := y1 - dip * cos(th) ** 2
			var y := lerpf(y0, top, f)
			var at := torso_point(y, th, g * rim)
			loop.append(pose.torso(y) * (at[0] as Vector3))
		loops.append(loop)
	kit.loft_rings(loops)


## Neck and head: one loft of head sections from the collar to the crown (the neck blends from the
## chest to the head frame), ears; AO proxies for the skull and the neck.
static func head(k: MeshKits, pose: SoldierPose) -> void:
	var loops := []
	for row: Array in HEAD:
		var y: float = row[0]
		var xf := pose.chest.interpolate_with(pose.head, smoothstep(-0.1, -0.035, y))
		var bumps := _head_bumps(row)
		var ring := section(
			HEAD_SIDES, row[2], row[2], row[3], row[4], Vector2(row[5], 1.0), bumps, HEAD_WARP
		)
		var loop := []
		for q: Vector2 in ring:
			loop.append(xf * (SoldierPose.HEAD_PIVOT + Vector3(row[1] + q.y, y, q.x)))
		loops.append(loop)
	var skin := k.k(&"skin")
	skin.loft_rings(loops)
	_hair(k.k(&"dark"), pose)
	for side: float in [-1.0, 1.0]:
		skin.pillow(
			pose.head * (SoldierPose.HEAD_PIVOT + Vector3(-0.012, 0.058, side * 0.074)),
			Vector3(0.034, 0.058, 0.02),
			pose.head.basis * Basis(Vector3.BACK, 0.2),
			0.7,
			4,
			8
		)
	var face := pose.head * Transform3D(Basis.IDENTITY, SoldierPose.HEAD_PIVOT)
	pose.occluders.sphere(face * Vector3(0.0, 0.075, 0.0), 0.07)
	# Brow ridge and nose: the eye sockets, the sides of the nose and the mouth line read by AO.
	for side: float in [-1.0, 1.0]:
		pose.occluders.sphere(face * Vector3(0.088, 0.088, side * 0.033), 0.014, 1.5)
	pose.occluders.sphere(face * Vector3(0.108, 0.035, 0.0), 0.012, 1.2)
	pose.occluders.capsule(
		face * Vector3(0.098, 0.0, -0.022), face * Vector3(0.098, 0.0, 0.022), 0.008, 1.2
	)
	pose.occluders.capsule(
		pose.chest * SoldierPose.NECK_BASE, pose.head * SoldierPose.HEAD_PIVOT, 0.04, 0.7
	)


static func _head_bumps(row: Array) -> Array:
	return [
		Vector3(PI / 2.0, 0.17, row[6]),
		Vector3(PI / 2.0 - 0.85, 0.3, row[7]),
		Vector3(PI / 2.0 + 0.85, 0.3, row[7]),
		Vector3(PI / 2.0 - 0.4, 0.35, row[8]),
		Vector3(PI / 2.0 + 0.4, 0.35, row[8]),
		Vector3(PI / 2.0 - 0.4, 0.2, row[9]),
		Vector3(PI / 2.0 + 0.4, 0.2, row[9]),
	]


## Short hair over the back and sides of the head: a thin crescent loft (an arc just outside the
## skin and back just inside it) along the HAIR_ROWS, the nape row narrower.
static func _hair(kit: MeshKit, pose: SoldierPose) -> void:
	var loops := []
	var arc := 8
	for r in range(HAIR_ROWS.x, HAIR_ROWS.y + 1):
		var row: Array = HEAD[r]
		var size := Vector4(row[2], row[2], row[3], row[4])
		var exps := Vector2(row[5], 1.0)
		var bumps := _head_bumps(row)
		var narrow := 0.45 if r == HAIR_ROWS.x else 0.0
		var loop := []
		for out: float in [0.007, -0.004]:
			for j in arc:
				var f := float(j) / (arc - 1)
				if out < 0.0:
					f = 1.0 - f
				var th := lerpf(HAIR_ARC.x + narrow, HAIR_ARC.y - narrow, f)
				var q := shape_point(th, size, exps, bumps)
				q += q.normalized() * out
				loop.append(
					pose.head * (SoldierPose.HEAD_PIVOT + Vector3(row[1] + q.y, row[0], q.x))
				)
		loops.append(loop)
	kit.loft_rings(loops)


# --- Arms and hands -----------------------------------------------------------------------------


## Arms from the shoulders to `hands` ([left grip, right grip] and optionally the fingers' curl
## directions [left, right]) by two-bone IK, the elbows towards the pose's poles; sleeves with the
## deltoid and biceps, gloved hands closed around the grips (glove kit `gloves`), the faction
## patch on each sleeve; records the arm joints and AO proxies.
static func arms(k: MeshKits, pose: SoldierPose, hands: Array, gloves: StringName) -> void:
	var uni := k.k(&"uniform")
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tag := "l" if i == 0 else "r"
		var shoulder := pose.shoulder(side)
		var grip: Vector3 = hands[i]
		var chain := SoldierPose.two_bone(
			shoulder,
			grip,
			SoldierPose.UPPER_ARM,
			SoldierPose.FOREARM + SoldierPose.HAND_GRIP,
			pose.elbow_poles[i]
		)
		var elbow := chain[0]
		var end := chain[1]
		var wrist := elbow + (end - elbow).normalized() * SoldierPose.FOREARM
		pose.joints[StringName("shoulder_" + tag)] = shoulder
		pose.joints[StringName("elbow_" + tag)] = elbow
		pose.joints[StringName("wrist_" + tag)] = wrist
		pose.joints[StringName("hand_" + tag)] = end
		var t0 := (elbow - shoulder).normalized()
		var inner := (shoulder + wrist) * 0.5 - elbow
		var hint := inner - t0 * inner.dot(t0)
		if hint.length() < 0.02:
			hint = pose.chest.basis.x - t0 * pose.chest.basis.x.dot(t0)
		var side0 := hint.normalized().cross(t0)
		var mirror := signf(side0.dot(pose.chest.basis.z * side))
		var bend := t0.angle_to(wrist - elbow)
		var path := []
		var profiles := []
		for row: Array in ARM:
			var s: float = row[0]
			if bend > 1.0 and absf(s - 1.0) > 0.0 and absf(s - 1.0) < 0.2:
				continue
			path.append(
				(
					shoulder + (elbow - shoulder) * s
					if s <= 1.0
					else elbow + (wrist - elbow) * (s - 1.0)
				)
			)
			var fold := Vector3(row[5], 6.0, side) if row[5] > 0.0 else Vector3.ZERO
			profiles.append(
				_mirrored(
					section(ARM_SIDES, row[1], row[2], row[3], row[4], Vector2.ONE, [], 0.0, fold),
					mirror
				)
			)
		uni.sweep_profile(path, profiles, side0)
		var curl: Vector3 = (
			hands[2 + i] if hands.size() > 3 else pose.chest.basis.z * -side + Vector3.DOWN * 0.3
		)
		hand(k.k(gloves), wrist, end, curl)
		var out := side0 * mirror
		var patch := shoulder.lerp(elbow, 0.32) + out * 0.059
		var flat := Basis(t0, out, t0.cross(out).normalized()).orthonormalized()
		k.k(&"accent").cbox(patch, Vector3(0.045, 0.004, 0.058), 0.0015, flat)
		pose.occluders.capsule(shoulder, elbow, 0.042)
		pose.occluders.capsule(elbow, wrist, 0.032)


## Gloved hand from `wrist` to the grip at `end`: a mitten (palm, knuckles, fingers curled towards
## `curl` around the grip) and a separate thumb.
static func hand(kit: MeshKit, wrist: Vector3, end: Vector3, curl: Vector3) -> void:
	var h := (end - wrist).normalized()
	var c := curl - h * curl.dot(h)
	if c.length_squared() < 1e-6:
		c = h.cross(Vector3.BACK if absf(h.z) < 0.9 else Vector3.UP)
	c = c.normalized()
	var w := c.cross(h)
	var path := [
		wrist - h * 0.012,
		wrist + h * 0.03,
		wrist + h * 0.068,
		wrist + h * 0.092 + c * 0.02,
		wrist + h * 0.086 + c * 0.044,
	]
	var profiles := [
		section(10, 0.03, 0.03, 0.022, 0.022),
		section(10, 0.042, 0.042, 0.018, 0.016, Vector2(0.7, 0.7)),
		section(10, 0.041, 0.041, 0.015, 0.014, Vector2(0.7, 0.7)),
		section(10, 0.037, 0.037, 0.012, 0.012, Vector2(0.8, 0.8)),
		section(10, 0.03, 0.03, 0.009, 0.009),
	]
	kit.sweep_profile(path, profiles, c.cross(h))
	var ts := 1.0 if w.y >= 0.0 else -1.0
	(
		kit
		. tube(
			[
				wrist + h * 0.02 + w * 0.03 * ts,
				wrist + h * 0.055 + w * 0.042 * ts + c * 0.004,
				wrist + h * 0.085 + w * 0.028 * ts + c * 0.016,
			],
			0.0115,
			6
		)
	)


## `ring` with its a coordinates flipped when `mirror` < 0 (the lateral side on −a).
static func _mirrored(ring: Array, mirror: float) -> Array:
	if mirror >= 0.0:
		return ring
	var flipped := []
	for q: Vector2 in ring:
		flipped.append(Vector2(-q.x, q.y))
	return flipped
