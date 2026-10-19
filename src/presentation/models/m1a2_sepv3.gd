## M1A2 SEPv3 Abrams (M1A2C): the Polish Army's main battle tank. Blueprint:
## docs/design/units/units/m1a2_sepv3/blueprint.md. Measurements are metres (vehicle_frame.gd):
## `x` from the hull front (glacis nose, 0) to the rear plate (HULL_LENGTH), `h` above the ground,
## `z` across (positive = vehicle's right). Turret at 12 o'clock, gun level.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/tracked_running_gear.gd")

const HULL_LENGTH := 7.93
## The gun protrudes this far beyond the hull front (overall 9.77 m).
const GUN_OVERHANG := 1.84
## Model units per metre: 9.77 m -> 0.86 (x MODEL_SCALE 1.3 = 1.118 <= 1.15).
const K := 0.088
## Turret ring centre (x) on the hull deck (h); gun trunnions (x, h).
const TURRET_X := 3.95
const DECK_H := 1.62
const ROOF_H := 2.36
const TRUNNION := Vector2(2.3, 1.98)
## Hull half widths: upper hull / fenders over the tracks, lower hull between the tracks.
const UPPER_HW := 1.72
const LOWER_HW := 1.12


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var frame := Frame.new(K, (HULL_LENGTH - GUN_OVERHANG) / 2.0)
	var body := ModelParts.faction_material(faction, &"body")
	var dark := ModelParts.pbr(ModelParts.DARK)
	var steel := ModelParts.pbr(ModelParts.STEEL)
	var glass := ModelParts.pbr(ModelParts.GLASS)
	var acc := ModelParts.accent(faction)
	var materials := {
		&"body": body,
		&"dark": dark,
		&"steel": steel,
		&"rubber": ModelParts.pbr(ModelParts.RUBBER),
		&"track": ModelParts.pbr(ModelParts.TRACK),
		&"accent": acc,
	}
	Gear.build(g, frame, running_gear(), materials)
	_merged(g, "m1a2_sepv3:hull", _hull_parts(frame), body)
	_merged(g, "m1a2_sepv3:hull_dark", _hull_dark_parts(frame), dark)
	_merged(g, "m1a2_sepv3:hull_glass", _hull_glass_parts(frame), glass)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = frame.p(TURRET_X, DECK_H)
	g.add_child(turret)
	var to_turret := turret.transform.affine_inverse()
	_merged(turret, "m1a2_sepv3:turret", _turret_parts(frame), body, to_turret)
	_merged(turret, "m1a2_sepv3:turret_dark", _turret_dark_parts(frame), dark, to_turret)
	_merged(turret, "m1a2_sepv3:turret_glass", _turret_glass_parts(frame), glass, to_turret)
	_merged(turret, "m1a2_sepv3:turret_steel", _turret_steel_parts(frame), steel, to_turret)
	_merged(turret, "m1a2_sepv3:turret_accent", _turret_accent_parts(frame), acc, to_turret)
	var cloth := ModelParts.vest(faction)
	_merged(turret, "m1a2_sepv3:bags", _bag_parts(frame), cloth, to_turret)
	_build_gun(turret, frame, body, dark)
	return g


## The Abrams running gear: 7 double road wheels (0.635 m) per side, 2 return rollers, rear
## sprocket, raised front idler, deep skirts (2 armoured front panels).
static func running_gear() -> Gear.Spec:
	var spec := Gear.Spec.new()
	spec.key = "m1a2_sepv3"
	spec.road_wheel_x = [1.72, 2.44, 3.16, 3.88, 4.6, 5.32, 6.04]
	spec.road_wheel_radius = 0.32
	spec.road_wheel_h = 0.44
	spec.wheel_width = 0.58
	spec.return_roller_x = [2.75, 4.95]
	spec.return_roller_h = 1.02
	spec.return_roller_radius = 0.1
	spec.sprocket_x = 7.3
	spec.sprocket_h = 0.8
	spec.sprocket_radius = 0.36
	spec.sprocket_teeth = 11
	spec.idler_x = 0.62
	spec.idler_h = 0.76
	spec.idler_radius = 0.3
	spec.track_z = 1.44
	spec.track_width = 0.63
	spec.track_thickness = 0.08
	spec.grouser_spacing = 0.25
	spec.skirt_x0 = 0.12
	spec.skirt_x1 = 7.05
	spec.skirt_h0 = 0.62
	spec.skirt_h1 = 1.24
	spec.skirt_z = 1.85
	spec.skirt_panels = 7
	spec.skirt_front_panels = 2
	spec.skirt_thickness = 0.05
	spec.skirt_front_thickness = 0.12
	spec.skirt_front_rake = 0.4
	spec.accent_panel = 1
	return spec


static func _merged(
	parent: Node3D, key: String, parts: Array, material: Material, base := Transform3D.IDENTITY
) -> MeshInstance3D:
	return ModelParts.add(parent, ModelParts.merged_mesh(key, parts, base), material, Vector3.ZERO)


## Prism of a side profile (x, h pairs) across the hull, `hw` half width.
static func _profile(parts: Array, frame: Frame, key: String, points: Array, hw: float) -> void:
	var outline: Array[Vector2] = []
	for point: Vector2 in points:
		outline.append(frame.xy(point.x, point.y))
	parts.append([ModelParts.prism_mesh(key, outline, hw * 2.0 * K), Transform3D.IDENTITY])


## Model-space XZ point for turret plan outlines.
static func _xz(frame: Frame, x: float, z: float) -> Vector2:
	var p := frame.p(x, 0.0, z)
	return Vector2(p.x, p.z)


static func _loft(
	parts: Array, frame: Frame, key: String, bottom: Array, top: Array, h0: float, h1: float
) -> void:
	var lo: Array[Vector2] = []
	var hi: Array[Vector2] = []
	for point: Vector2 in bottom:
		lo.append(_xz(frame, point.x, point.y))
	for point: Vector2 in top:
		hi.append(_xz(frame, point.x, point.y))
	parts.append([ModelParts.loft_mesh(key, lo, hi, h0 * K, h1 * K), Transform3D.IDENTITY])


## Camo hull: upper hull with the long shallow glacis and flat engine deck over the full width,
## lower hull with the lower front plate between the tracks, rear stowage boxes.
static func _hull_parts(frame: Frame) -> Array:
	var p: Array = []
	var upper := [
		Vector2(0.0, 1.14),
		Vector2(0.0, 1.27),
		Vector2(2.25, 1.6),
		Vector2(7.8, DECK_H),
		Vector2(HULL_LENGTH, 1.55),
		Vector2(HULL_LENGTH, 1.14),
	]
	_profile(p, frame, "m1a2_sepv3:upper_hull", upper, UPPER_HW)
	var lower := [
		Vector2(0.04, 1.2),
		Vector2(0.95, 0.52),
		Vector2(7.45, 0.48),
		Vector2(7.88, 0.78),
		Vector2(7.88, 1.2),
	]
	_profile(p, frame, "m1a2_sepv3:lower_hull", lower, LOWER_HW)
	frame.pair(p, 7.25, 7.9, 1.62, 1.82, 0.32, 1.32)  # rear fender stowage boxes
	return p


## Dark: box-like rear grille with louvres, engine deck grilles, APU exhaust (rear left), driver's
## hatch, headlight housings, tow hooks.
static func _hull_dark_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.slab(p, HULL_LENGTH - 0.04, HULL_LENGTH + 0.04, 0.95, 1.5, 1.05)  # rear grille box
	for i in 5:
		var h := 1.0 + i * 0.1
		frame.slab(p, HULL_LENGTH + 0.04, HULL_LENGTH + 0.07, h, h + 0.04, 1.0)  # louvres
	for i in 7:
		var x := 6.05 + i * 0.25
		frame.slab(p, x, x + 0.14, DECK_H, DECK_H + 0.025, 1.05)  # deck grille slats
	frame.slab(p, 7.5, 7.88, DECK_H, 1.78, 0.14, -1.34)  # APU exhaust box (rear left)
	frame.drum(p, 7.95, 1.72, -1.34, 0.07, 0.18, &"x", 8)  # APU exhaust pipe
	frame.slab(p, 1.75, 2.2, 1.55, 1.6, 0.32, 0.0, 0.15)  # driver's hatch on the glacis
	frame.pair(p, 0.06, 0.36, 1.27, 1.43, 0.13, 1.45)  # headlight housings on the fenders
	frame.pair(p, -0.04, 0.12, 0.98, 1.1, 0.07, 0.75)  # tow hooks
	frame.pair(p, HULL_LENGTH, HULL_LENGTH + 0.08, 1.2, 1.4, 0.1, 1.45)  # tail light boxes
	return p


static func _hull_glass_parts(frame: Frame) -> Array:
	var p: Array = []
	for z: float in [-0.2, 0.0, 0.2]:
		frame.slab(p, 1.68, 1.74, 1.56, 1.62, 0.07, z)  # driver's periscopes
	frame.pair(p, 0.03, 0.06, 1.3, 1.4, 0.09, 1.45)  # headlight lenses
	return p


## Camo turret: flat wide wedge (front block on the ring, bustle overhanging the engine deck with
## a gap below), gunner's sight doghouse, CITV pedestal, cupola and hatch rings, side boxes.
static func _turret_parts(frame: Frame) -> Array:
	var p: Array = []
	var front_bottom := [
		Vector2(1.85, -0.75),
		Vector2(2.7, -1.66),
		Vector2(5.0, -1.66),
		Vector2(5.0, 1.66),
		Vector2(2.7, 1.66),
		Vector2(1.85, 0.75),
	]
	var front_top := [
		Vector2(2.5, -0.7),
		Vector2(3.1, -1.56),
		Vector2(5.0, -1.56),
		Vector2(5.0, 1.56),
		Vector2(3.1, 1.56),
		Vector2(2.5, 0.7),
	]
	_loft(p, frame, "m1a2_sepv3:turret_front", front_bottom, front_top, DECK_H, ROOF_H)
	var bustle_bottom := [
		Vector2(4.95, -1.66), Vector2(6.35, -1.52), Vector2(6.35, 1.52), Vector2(4.95, 1.66)
	]
	var bustle_top := [
		Vector2(4.95, -1.56), Vector2(6.35, -1.44), Vector2(6.35, 1.44), Vector2(4.95, 1.56)
	]
	_loft(p, frame, "m1a2_sepv3:bustle", bustle_bottom, bustle_top, 1.8, ROOF_H)
	frame.slab(p, 2.6, 3.3, ROOF_H - 0.05, 2.58, 0.22, 0.95)  # gunner's primary sight doghouse
	frame.drum(p, 3.3, 2.45, -0.85, 0.12, 0.2, &"y", 10)  # CITV pedestal (left front)
	frame.slab(p, 3.12, 3.45, 2.5, 2.64, 0.18, -0.85)  # CITV head
	frame.drum(p, 4.3, 2.4, 0.82, 0.44, 0.08, &"y", 18)  # commander's cupola ring (right)
	frame.drum(p, 4.35, 2.4, -0.82, 0.38, 0.08, &"y", 16)  # loader's hatch ring (left)
	frame.slab(p, 3.8, 3.86, 2.42, 2.63, 0.32, -0.82, -0.2)  # loader's M240 armoured shield
	frame.pair(p, 5.0, 6.1, 1.86, 2.3, 0.06, 1.66)  # bustle side boxes
	return p


## Dark: low-profile CROWS RWS on the commander's ring, loader's M240, smoke grenade dischargers
## on both turret sides, bustle rack frame, antenna bases, mantlet slot.
static func _turret_dark_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.drum(p, 4.3, 2.48, 0.82, 0.2, 0.1, &"y", 12)  # RWS base
	frame.slab(p, 4.05, 4.6, 2.5, 2.63, 0.2, 0.82)  # RWS cradle with the M2
	frame.slab(p, 4.0, 4.25, 2.5, 2.64, 0.1, 1.12)  # RWS sight head
	frame.slab(p, 4.2, 4.55, 2.5, 2.62, 0.12, 0.5)  # RWS ammo box
	frame.drum(p, 3.4, 2.58, -0.82, 0.03, 0.8, &"x", 6)  # loader's M240
	frame.drum(p, 3.95, 2.5, -0.82, 0.03, 0.18, &"y", 6)  # M240 pintle
	for s: float in [-1.0, 1.0]:
		var dir := Vector3(0.45, 0.35, s * 0.82)
		for i in 3:
			for row in 2:
				var x := 2.95 + i * 0.17 + row * 0.08
				frame.drum(p, x, 2.06 + row * 0.13, s * 1.62, 0.055, 0.28, dir, 8)  # M250 tubes
	frame.slab(p, 6.35, 7.15, 1.82, 1.86, 1.45)  # bustle rack floor
	for z: float in [-1.42, 0.0, 1.42]:
		frame.slab(p, 7.1, 7.15, 1.82, 2.32, 0.025, z)  # rear posts
	frame.slab(p, 7.1, 7.15, 2.28, 2.32, 1.45)  # rear top rail
	frame.pair(p, 6.35, 7.15, 2.28, 2.32, 0.025, 1.42)  # side top rails
	frame.pair(p, 6.35, 7.15, 2.0, 2.03, 0.025, 1.42)  # side middle rails
	frame.pair(p, 6.0, 6.2, ROOF_H, 2.42, 0.07, 1.2)  # antenna bases
	frame.pair(p, 6.08, 6.12, 2.42, 2.64, 0.018, 1.2)  # antenna stubs
	frame.slab(p, 1.9, 2.05, 1.72, 2.25, 0.46)  # mantlet slot between the cheeks
	return p


static func _turret_glass_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.slab(p, 2.57, 2.61, 2.4, 2.54, 0.16, 0.95)  # gunner's sight window
	frame.slab(p, 3.1, 3.13, 2.53, 2.61, 0.12, -0.85)  # CITV window
	frame.slab(p, 3.98, 4.01, 2.54, 2.61, 0.07, 1.12)  # RWS sight window
	return p


static func _turret_steel_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.drum(p, 3.55, 2.58, 0.82, 0.035, 1.05, &"x", 6)  # M2 barrel on the RWS
	return p


static func _turret_accent_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.pair(p, 5.25, 5.85, 1.96, 2.2, 0.012, 1.72)  # plates on the bustle side boxes
	return p


## Stowage bags in the bustle rack (faction cloth colour).
static func _bag_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.slab(p, 6.42, 7.05, 1.86, 2.2, 0.4, -0.92)
	frame.slab(p, 6.45, 7.02, 1.86, 2.12, 0.42, 0.0)
	frame.slab(p, 6.4, 7.06, 1.86, 2.24, 0.38, 0.9)
	return p


## "Gun" pivot at the trunnions (hinge = its local Z, level as built): mantlet and the long M256
## barrel (thermal sleeve bands, no fume extractor, muzzle reference sensor); "Muzzle" just in
## front of the bore.
static func _build_gun(turret: Node3D, frame: Frame, body: Material, dark: Material) -> void:
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = turret.transform.affine_inverse() * frame.p(TRUNNION.x, TRUNNION.y)
	turret.add_child(gun)
	var to_gun := (turret.transform * gun.transform).affine_inverse()
	var trunnion := frame.p(TRUNNION.x, TRUNNION.y)
	var length := TRUNNION.x + GUN_OVERHANG  # trunnion to muzzle
	var profile: Array[Vector2] = []
	for point: Vector2 in [
		Vector2(0.0, length),
		Vector2(0.1, length),
		Vector2(0.1, length - 0.2),
		Vector2(0.088, length - 0.22),
		Vector2(0.094, length - 0.9),
		Vector2(0.11, length - 0.93),
		Vector2(0.11, length - 1.02),
		Vector2(0.098, length - 1.05),
		Vector2(0.104, length - 1.95),
		Vector2(0.12, length - 1.98),
		Vector2(0.12, length - 2.08),
		Vector2(0.11, length - 2.1),
		Vector2(0.12, 0.95),
		Vector2(0.17, 0.9),
		Vector2(0.17, 0.5),
		Vector2(0.0, 0.5),
	]:
		profile.append(point * K)
	var barrel := ModelParts.lathe_mesh("m1a2_sepv3:barrel", profile, 16)
	var along_x := Transform3D(Basis(Vector3.BACK, -PI / 2.0), trunnion)
	var shell: Array = [[barrel, along_x]]
	frame.slab(shell, 1.8, 2.55, 1.8, 2.17, 0.32)  # mantlet / gun shield
	_merged(gun, "m1a2_sepv3:gun", shell, body, to_gun)
	var trim: Array = []
	frame.drum(trim, -GUN_OVERHANG - 0.005, TRUNNION.y, 0.0, 0.07, 0.02, &"x", 12)  # bore
	frame.slab(trim, -GUN_OVERHANG + 0.12, -GUN_OVERHANG + 0.3, 2.07, 2.13, 0.04)  # MRS
	frame.drum(trim, 1.78, 1.9, 0.24, 0.04, 0.08, &"x", 8)  # coaxial M240 port
	_merged(gun, "m1a2_sepv3:gun_dark", trim, dark, to_gun)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = to_gun * frame.p(-GUN_OVERHANG - 0.05, TRUNNION.y)
	gun.add_child(muzzle)
