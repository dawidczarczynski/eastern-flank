## T-72B3 obr. 2011: the Russian Army's main battle tank. Blueprint:
## docs/design/units/units/t72b3/blueprint.md. Measurements are metres (vehicle_frame.gd):
## `x` from the hull front (glacis nose, 0) to the rear plate (HULL_LENGTH), `h` above the ground,
## `z` across (positive = vehicle's right). Turret at 12 o'clock, gun level.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/tracked_running_gear.gd")

const HULL_LENGTH := 6.86
## The gun protrudes this far beyond the hull front (overall 9.53 m).
const GUN_OVERHANG := 2.67
## The fuel drums on the rear plate reach this far behind the hull.
const REAR_OVERHANG := 0.53
## Model units per metre: 10.06 m (muzzle to drums) -> 0.875 (x MODEL_SCALE 1.3 = 1.138).
const K := 0.087
## Turret ring centre (x) on the hull deck (h); gun trunnions (x, h).
const TURRET_X := 3.35
const DECK_H := 1.5
const ROOF_H := 2.2
const TRUNNION := Vector2(2.25, 1.8)
## Cast turret dome: centre (x), half length (x) and half width (z) at its base; the K-5 wedges
## stand in front of its front slope.
const DOME_X := 3.5
const DOME_HL := 1.25
const DOME_HW := 1.05
## Hull half widths: upper hull / fenders over the tracks, lower hull between the tracks.
const UPPER_HW := 1.7
const LOWER_HW := 1.08


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var frame := Frame.new(K, (HULL_LENGTH + REAR_OVERHANG - GUN_OVERHANG) / 2.0)
	var m := Frame.tank_materials(faction)
	Gear.build(g, frame, running_gear(), m)
	Frame.merged(g, "t72b3:hull", _hull_parts(frame), m[&"body"])
	Frame.merged(g, "t72b3:hull_dark", _hull_dark_parts(frame), m[&"dark"])
	Frame.merged(g, "t72b3:hull_glass", _hull_glass_parts(frame), m[&"glass"])
	var turret := frame.add_turret(g, TURRET_X, DECK_H)
	var to_turret := Frame.to_local(turret)
	Frame.merged(turret, "t72b3:turret", _turret_parts(frame), m[&"body"], to_turret)
	Frame.merged(turret, "t72b3:turret_dark", _turret_dark_parts(frame), m[&"dark"], to_turret)
	Frame.merged(turret, "t72b3:turret_glass", _turret_glass_parts(frame), m[&"glass"], to_turret)
	Frame.merged(turret, "t72b3:turret_steel", _turret_steel_parts(frame), m[&"steel"], to_turret)
	_build_gun(frame.add_gun(turret, TRUNNION, -GUN_OVERHANG - 0.05), frame, m)
	return g


## The T-72 running gear: 6 large rubber-tyred road wheels (0.75 m) per side, 3 small return
## rollers, rear sprocket, front idler; rubber-fabric skirts down to the wheel tops.
static func running_gear() -> Gear.Spec:
	var spec := Gear.Spec.new()
	spec.key = "t72b3"
	spec.road_wheel_x = [1.27, 2.12, 2.94, 3.8, 4.62, 5.44]
	spec.road_wheel_radius = 0.375
	spec.road_wheel_h = 0.49  # radius + track plate + grousers
	spec.wheel_width = 0.5
	spec.return_roller_x = [1.7, 3.37, 5.03]
	spec.return_roller_h = 0.92
	spec.return_roller_radius = 0.1
	spec.sprocket_x = 6.25
	spec.sprocket_h = 0.72
	spec.sprocket_radius = 0.33
	spec.sprocket_teeth = 12
	spec.idler_x = 0.42
	spec.idler_h = 0.72
	spec.idler_radius = 0.26
	spec.track_z = 1.395
	spec.track_width = 0.58
	spec.track_thickness = 0.08
	spec.grouser_spacing = 0.2
	spec.skirt_x0 = 0.6
	spec.skirt_x1 = 6.6
	spec.skirt_h0 = 0.8
	spec.skirt_h1 = 1.4
	spec.skirt_z = 1.79
	spec.skirt_panels = 6
	spec.skirt_front_panels = 1
	spec.skirt_thickness = 0.03
	spec.skirt_front_thickness = 0.06
	spec.skirt_front_rake = 0.25
	spec.accent_panel = 1
	return spec


## Camo hull: upper hull with the steep upper glacis and flat deck over the full width, lower hull
## with the lower front plate between the tracks, Kontakt-5 pack on the glacis, dozer blade, fender
## fuel tanks / boxes, fuel drums on the rear plate.
static func _hull_parts(frame: Frame) -> Array:
	var p: Array = []
	var upper := [
		Vector2(0.0, 1.02),
		Vector2(0.0, 1.1),
		Vector2(1.2, 1.47),
		Vector2(4.6, DECK_H),
		Vector2(6.7, 1.52),
		Vector2(HULL_LENGTH, 1.4),
		Vector2(HULL_LENGTH, 1.02),
	]
	frame.profile(p, "t72b3:upper_hull", upper, UPPER_HW)
	var lower := [
		Vector2(0.02, 1.05),
		Vector2(0.75, 0.48),
		Vector2(6.45, 0.46),
		Vector2(6.84, 0.85),
		Vector2(6.84, 1.05),
	]
	frame.profile(p, "t72b3:lower_hull", lower, LOWER_HW)
	# Kontakt-5 pack on the upper glacis (0.14 m thick, stepped top edge under the driver).
	var era := [Vector2(0.02, 1.1), Vector2(1.0, 1.4), Vector2(1.0, 1.54), Vector2(-0.05, 1.24)]
	frame.profile(p, "t72b3:glacis_era", era, 1.25)
	var blade := [
		Vector2(0.24, 0.88), Vector2(0.64, 0.565), Vector2(0.58, 0.49), Vector2(0.17, 0.8)
	]
	frame.profile(p, "t72b3:dozer_blade", blade, 1.15)  # self-entrenching blade
	for i in 3:
		var x := 4.05 + i * 0.85
		frame.pair(p, x, x + 0.78, 1.5, 1.64, 0.18, 1.5)  # fender fuel tanks / boxes
	for z: float in [-0.5, 0.5]:
		frame.drum(p, HULL_LENGTH + 0.25, 1.42, z, 0.28, 0.85, &"z", 14)  # 200 l fuel drums
	return p


## Dark: drum brackets, engine deck grilles, exhaust (left rear fender), driver's hatch ring,
## headlights, tow hooks, block seams on the glacis ERA.
static func _hull_dark_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.slab(p, HULL_LENGTH, HULL_LENGTH + 0.05, 1.18, 1.62, 1.0)  # drum bracket
	for i in 6:
		var x := 4.95 + i * 0.27
		frame.slab(p, x, x + 0.06, 1.5, 1.52, 0.55)  # engine deck grille slats
	frame.slab(p, 5.5, 6.0, 1.3, 1.46, 0.08, -1.72)  # exhaust on the left fender
	frame.drum(p, 1.45, 1.49, 0.0, 0.3, 0.04, &"y", 14)  # driver's hatch
	frame.pair(p, 0.08, 0.32, 1.12, 1.26, 0.1, 1.45)  # headlight housings
	frame.pair(p, -0.08, 0.1, 0.9, 1.0, 0.07, 0.7)  # tow hooks
	for i in 3:  # seams between the glacis ERA block rows
		var t := 0.25 + i * 0.25
		var x := lerpf(0.02, 1.0, t)
		var h := lerpf(1.1, 1.4, t)
		var seam := [
			Vector2(x - 0.02, h + 0.14), Vector2(x + 0.02, h + 0.155), Vector2(x + 0.03, h + 0.12)
		]
		frame.profile(p, "t72b3:era_seam%d" % i, seam, 1.26)
	return p


static func _hull_glass_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.slab(p, 1.15, 1.2, 1.5, 1.56, 0.1)  # driver's periscope
	frame.pair(p, 0.05, 0.08, 1.15, 1.23, 0.07, 1.45)  # headlight lenses
	return p


## Camo turret: low rounded cast dome (sloping shoulders, rounded front and rear, narrower than
## the hull), Kontakt-5 wedges on both sides of the gun, Sosna-U sight housing, cupola, hatch.
static func _turret_parts(frame: Frame) -> Array:
	var p: Array = []
	var dome: Array[Vector2] = [
		Vector2(0.0, ROOF_H - DECK_H),
		Vector2(0.3, 0.7),
		Vector2(0.55, 0.65),
		Vector2(0.75, 0.55),
		Vector2(0.88, 0.42),
		Vector2(0.96, 0.27),
		Vector2(1.0, 0.12),
		Vector2(1.0, 0.0),
		Vector2(0.0, 0.0),
	]
	var mesh := ModelParts.lathe_mesh("t72b3:dome", dome, 28)
	var stretch := Basis.from_scale(Vector3(DOME_HL, 1.0, DOME_HW) * K)
	p.append([mesh, Transform3D(stretch, frame.p(DOME_X, DECK_H))])
	for s: float in [-1.0, 1.0]:
		_era_wedge(p, frame, s)
	frame.slab(p, 2.62, 3.12, 1.95, 2.55, 0.24, 0.6)  # Sosna-U sight housing (right)
	frame.drum(p, 3.6, 2.2, 0.52, 0.4, 0.18, &"y", 18)  # commander's cupola
	frame.drum(p, 3.62, 2.16, -0.55, 0.34, 0.06, &"y", 16)  # gunner's hatch
	return p


## One side's Kontakt-5 wedge (`s` = side sign): three blocks along a front edge swept back 35 deg
## from the gun (x 1.95, z 0.32) to the turret side (x 2.6, z 1.25). Each block is a prism of a
## wedge cross-section (0.55 m deep, top sloping from 2.02 m at the back down to 1.74 m at the
## sharp front edge), stepping up 0.04 m per block outwards: from the front the two packs form a
## shallow V with the gun collar in the notch.
static func _era_wedge(p: Array, frame: Frame, s: float) -> void:
	var inner := Vector2(1.95, 0.32 * s)
	var outer := Vector2(2.6, 1.25 * s)
	var along := frame.p(outer.x, 0.0, outer.y) - frame.p(inner.x, 0.0, inner.y)
	var length := along.length()
	var forward := Vector3(absf(along.z), 0.0, s * absf(along.x)).normalized()
	var axis := forward.cross(Vector3.UP)  # block length; right-handed with forward and up
	var section: Array[Vector2] = []
	for point: Vector2 in [
		Vector2(-0.55, 1.6), Vector2(0.08, 1.6), Vector2(0.0, 1.74), Vector2(-0.55, 2.02)
	]:
		section.append(point * K)
	var gap := 0.03 * K
	var block := ModelParts.prism_mesh("t72b3:k5_block", section, length / 3.0 - gap)
	var basis := Basis(forward, Vector3.UP, axis)
	for i in 3:
		var t := (i + 0.5) / 3.0
		var centre := frame.p(lerpf(inner.x, outer.x, t), 0.04 * i, lerpf(inner.y, outer.y, t))
		p.append([block, Transform3D(basis, centre)])


## Dark: NSVT on the commander's cupola, 902B smoke grenade launchers, wind sensor mast, turret
## ring collar, Sosna-U armoured doors frame.
static func _turret_dark_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.drum(p, 3.75, ROOF_H + 0.2, 0.52, 0.05, 0.16, &"y", 8)  # NSVT pintle
	frame.slab(p, 3.5, 4.0, 2.4, 2.54, 0.07, 0.52)  # NSVT receiver
	frame.slab(p, 3.55, 3.8, 2.33, 2.48, 0.08, 0.68)  # NSVT ammo box
	for s: float in [-1.0, 1.0]:
		var dir := Vector3(0.6, 0.45, s * 0.35)
		for i in 4:
			frame.drum(p, 3.3 + i * 0.13, 1.84, s * 0.92, 0.05, 0.3, dir, 8)  # 902B tubes
	frame.drum(p, 4.35, 2.42, 0.0, 0.018, 0.6, &"y", 6)  # wind sensor mast
	frame.drum(p, 4.35, 2.74, 0.0, 0.05, 0.08, &"y", 8)  # wind sensor head
	frame.drum(p, TURRET_X, DECK_H + 0.03, 0.0, 1.0, 0.06, &"y", 24)  # turret ring collar
	return p


static func _turret_glass_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.slab(p, 2.59, 2.63, 2.28, 2.47, 0.17, 0.6)  # Sosna-U window
	return p


static func _turret_steel_parts(frame: Frame) -> Array:
	var p: Array = []
	frame.drum(p, 2.95, 2.47, 0.52, 0.03, 1.1, &"x", 6)  # NSVT barrel
	return p


## On the "Gun" pivot (Frame.add_gun): the long 2A46M-5 barrel (segmented thermal sleeve, fume
## extractor) with the dust-cover collar at the turret front, bore and coaxial MG port.
static func _build_gun(gun: Node3D, frame: Frame, m: Dictionary) -> void:
	var to_gun := Frame.to_local(gun)
	var trunnion := frame.p(TRUNNION.x, TRUNNION.y)
	var length := TRUNNION.x + GUN_OVERHANG  # trunnion to muzzle
	var profile: Array[Vector2] = [
		Vector2(0.0, length),
		Vector2(0.09, length),
		Vector2(0.09, length - 0.04),
		Vector2(0.082, length - 0.05),
		Vector2(0.088, length - 0.6),
		Vector2(0.106, length - 0.62),
		Vector2(0.106, length - 0.68),
		Vector2(0.092, length - 0.7),
		Vector2(0.095, 3.66),
		Vector2(0.108, 3.66),
		Vector2(0.108, 3.6),
		Vector2(0.097, 3.6),
		Vector2(0.1, 2.74),
		Vector2(0.11, 2.74),
		Vector2(0.11, 2.68),
		Vector2(0.102, 2.68),
		Vector2(0.104, 1.85),
		Vector2(0.15, 1.78),
		Vector2(0.15, 1.02),
		Vector2(0.112, 0.95),
		Vector2(0.115, 0.62),
		Vector2(0.2, 0.6),
		Vector2(0.23, 0.45),
		Vector2(0.23, -0.15),
		Vector2(0.0, -0.15),
	]
	for i in profile.size():
		profile[i] *= K
	var barrel := ModelParts.lathe_mesh("t72b3:barrel", profile, 16)
	var along_x := Transform3D(Basis(Vector3.BACK, -PI / 2.0), trunnion)
	Frame.merged(gun, "t72b3:gun", [[barrel, along_x]], m[&"body"], to_gun)
	var trim: Array = []
	frame.drum(trim, -GUN_OVERHANG - 0.005, TRUNNION.y, 0.0, 0.065, 0.02, &"x", 12)  # bore
	frame.drum(trim, 1.95, 1.72, 0.3, 0.04, 0.1, &"x", 8)  # coaxial PKTM port
	Frame.merged(gun, "t72b3:gun_dark", trim, m[&"dark"], to_gun)
