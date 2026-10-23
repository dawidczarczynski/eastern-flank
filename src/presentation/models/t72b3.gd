## T-72B3 obr. 2011: the Russian Army's main battle tank. Blueprint:
## docs/design/units/units/t72b3/blueprint.md. Measurements are metres (vehicle_frame.gd):
## `x` from the hull front (glacis nose, 0) to the rear plate (HULL_LENGTH), `h` above the ground,
## `z` across (positive = vehicle's right). Turret at 12 o'clock, gun level.
##
## Built with MeshKit (TASK-069, ADR 0012) with the techniques of the M1A2 detail study: chamfered
## parts, bolts, hinges, cables, individual steel track shoes; what the camera never sees is cut
## (no shoes on the top run behind the skirts, plain inner wheel halves, nothing inside the shell,
## no turret floor). The geometry does not depend on the faction, so it is generated once
## (ModelParts.cached_meshes) and only the materials differ.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/tracked_running_gear.gd")

const HULL_LENGTH := 6.86
## The gun protrudes this far beyond the hull front (overall 9.53 m).
const GUN_OVERHANG := 2.67
## The fuel drums on the rear plate reach this far behind the hull.
const REAR_OVERHANG := 0.53
## Model units per metre: 10.06 m (muzzle to drums) -> 0.875 (x unit scale 1.3 = 1.138).
const K := 0.087
## Turret ring centre (x) on the hull deck (h) and the ring radius; gun trunnions (x, h).
const TURRET_X := 3.35
const TURRET_RING_R := 1.08
const DECK_H := 1.5
const ROOF_H := 2.2
const TRUNNION := Vector2(2.25, 1.8)
## Cast turret dome: centre (x), half length (x) and half width (z) at its rim, rim height (a
## ring gap above the deck). The K-5 wedges stand in front of its front slope.
const DOME_X := 3.5
const DOME_HL := 1.25
const DOME_HW := 1.05
const DOME_BASE := 1.53
## Hull half widths: upper hull / fenders over the tracks, lower hull between the tracks.
const UPPER_HW := 1.7
const LOWER_HW := 1.08
## Sosna-U sight head: front face (x) and the centre of its round window (h, z).
const SOSNA_X0 := 2.62
const SOSNA_H := 2.22
const SOSNA_Z := 0.6
## Turret stowage bins: underside of the side bins and of the rear bin, lid tops, lid thickness.
const BIN_H0 := 1.66
const BIN_REAR_H0 := 1.74
const BIN_SIDE_TOP := 2.04
const BIN_REAR_TOP := 2.1
const BIN_LID := 0.03
## Fuel drums on the rear plate: centre (x, h) and |z|; radius.
const DRUM := Vector3(7.11, 1.37, 0.5)
const DRUM_R := 0.28
## A box strictly inside the armour shell (vehicle metres: position = (x from the front, h, z)):
## no triangle may lie entirely inside it (hidden-geometry test, test_tank_models.gd).
const HULL_INTERIOR := AABB(Vector3(1.5, 0.7, -0.9), Vector3(4.3, 0.65, 1.8))
## Lowest turret / bin underside outside the turret ring (m): the dome rim.
const TURRET_CLEARANCE_H := DOME_BASE


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var frame := vehicle_frame()
	var m := Frame.kit_tank_materials(faction)
	var spec := running_gear()
	Gear.add_pivots(g, frame, spec, m)
	var hull := ModelParts.cached_meshes(
		"t72b3:hull", func() -> Dictionary: return _hull_meshes(frame, spec)
	)
	MeshKits.add_meshes(g, hull, m)
	_anchors(g, frame, spec)
	var turret := frame.add_turret(g, TURRET_X, DECK_H)
	var to_turret := Frame.to_local(turret)
	var shell := ModelParts.cached_meshes(
		"t72b3:turret", func() -> Dictionary: return _turret_meshes(frame, to_turret)
	)
	MeshKits.add_meshes(turret, shell, m)
	var gun := frame.add_gun(turret, TRUNNION, -GUN_OVERHANG - 0.05)
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	gun.add_child(barrel)
	var to_gun := Frame.to_local(gun)
	var gun_meshes := ModelParts.cached_meshes(
		"t72b3:gun", func() -> Dictionary: return _gun_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(gun, gun_meshes, m)
	var barrel_meshes := ModelParts.cached_meshes(
		"t72b3:barrel", func() -> Dictionary: return _barrel_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(barrel, barrel_meshes, m)
	return g


## Metres -> model space: K model units per metre, muzzle to fuel drums centred on x = 0.
static func vehicle_frame() -> Frame:
	return Frame.new(K, (HULL_LENGTH + REAR_OVERHANG - GUN_OVERHANG) / 2.0)


## The T-72 running gear: 6 large rubber-tyred road wheels (0.75 m) per side, 3 small return
## rollers, rear sprocket, front idler, all-steel RMSh track; rubber-fabric skirts down to the wheel
## tops whose bottom edge rises gently behind the fourth wheel and curves up to the rear plate.
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
	spec.skirt_x1 = 6.93
	spec.skirt_h0 = 0.8
	spec.skirt_h1 = 1.4
	spec.skirt_z = 1.79
	spec.skirt_panels = 6
	spec.skirt_front_panels = 1
	spec.skirt_thickness = 0.03
	spec.skirt_front_thickness = 0.06
	spec.skirt_front_rake = 0.25
	spec.skirt_front_top_drop = 0.12
	spec.skirt_bottom_profile = (
		[
			Vector2(4.8, 0.8),
			Vector2(6.6, 0.98),
			Vector2(6.76, 1.04),
			Vector2(6.85, 1.12),
			Vector2(6.9, 1.24)
		]
		as Array[Vector2]
	)
	spec.skirt_edge = 0.07
	spec.accent_panel = 1
	spec.detailed_wheels = true
	spec.wheel_sides = 14
	spec.wheel_bolts = 6
	spec.sprocket_bolts = 6
	spec.wheel_rim_bolts = 8
	spec.track_shoe_pitch = 0.19
	spec.track_pads = false
	spec.detailed_skirts = true
	spec.skirt_bolt_rows = 2
	spec.skirt_bolt_cols = 3
	return spec


## Effect anchors for MotionFx (TASK-064): the exhaust louvres on the left rear fender, dust under
## the sprockets.
static func _anchors(g: Node3D, frame: Frame, spec: Gear.Spec) -> void:
	var at := {
		"Exhaust": frame.p(5.75, 1.62, -1.56),
		"Dust_L": frame.p(spec.sprocket_x, 0.02, -spec.track_z),
		"Dust_R": frame.p(spec.sprocket_x, 0.02, spec.track_z),
	}
	for name: String in at:
		var marker := Marker3D.new()
		marker.name = name
		marker.position = at[name]
		g.add_child(marker)


static func _hull_meshes(frame: Frame, spec: Gear.Spec) -> Dictionary:
	var hull := MeshKits.new(frame)
	_hull(hull)
	Gear.add_hull_parts(hull, spec)
	_front(hull)
	_engine_deck(hull)
	_fenders(hull)
	_rear(hull)
	return hull.commit_all()


static func _turret_meshes(frame: Frame, to_turret: Transform3D) -> Dictionary:
	var t := MeshKits.new(frame, to_turret)
	_dome(t)
	for s: float in [-1.0, 1.0]:
		_era_wedge(t, s)
	_sosna(t)
	_cupola(t)
	_roof(t)
	_bins(t)
	_smoke_launchers(t)
	return t.commit_all()


## Height (m) of the cast dome's surface over (x, z): the curve the dome lathe samples
## (superellipse 1 - rho^3, ^0.45), DOME_BASE outside the rim.
static func _dome_h(x: float, z: float) -> float:
	var rho := Vector2((x - DOME_X) / DOME_HL, z / DOME_HW).length()
	if rho >= 1.0:
		return DOME_BASE
	return DOME_BASE + (ROOF_H - DOME_BASE) * pow(1.0 - pow(rho, 3.0), 0.45)


## Engine deck height at x (the upper hull rises 0.02 m from x 4.6 to 6.7).
static func _deck_h(x: float) -> float:
	return DECK_H + (x - 4.6) * 0.02 / 2.1


# --- Hull ---------------------------------------------------------------------------------------


## Upper hull (steep upper glacis, flat deck over the full width, fenders rising over the
## sprocket) and lower hull between the tracks as chamfered profiles, the shadowed engine
## compartment side under the raised rear fenders, lifting eyes.
static func _hull(h: MeshKits) -> void:
	var body := h.k(&"body")
	var upper := [
		Vector2(0.0, 1.02),
		Vector2(0.0, 1.1),
		Vector2(1.2, 1.47),
		Vector2(4.6, DECK_H),
		Vector2(6.7, 1.52),
		Vector2(HULL_LENGTH, 1.4),
		Vector2(HULL_LENGTH, 1.3),
		Vector2(5.8, 1.02)
	]
	body.profile(upper, UPPER_HW, 0.0, 0.03)
	var lower := [
		Vector2(0.02, 1.05),
		Vector2(0.75, 0.48),
		Vector2(6.45, 0.46),
		Vector2(6.84, 0.85),
		Vector2(6.84, 1.05)
	]
	body.profile(lower, LOWER_HW, 0.0, 0.03)
	var dark := h.k(&"dark")
	dark.openness = 0.3
	dark.slab(5.8, 6.84, 1.0, 1.36, LOWER_HW, 0.0, 0.01)
	dark.openness = 1.0
	for s: float in [-1.0, 1.0]:
		for x: float in [0.75, 6.55]:
			var c := Vector3(x, 1.1 + x * 0.37 / 1.2 if x < 2.0 else 1.52, s * 1.6)
			dark.tube(MeshKit.arc(c, 0.055, Vector3.RIGHT, Vector3.UP, 0.0, PI, 8), 0.016, 6)


## Kontakt-5 pack on the upper glacis (base block with a grid of bolted lids), driver's hatch and
## periscope, headlights with guards on the fender fronts, front mudguards, self-entrenching blade,
## tow hooks, lower front plate bolts.
static func _front(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var era := [Vector2(0.02, 1.1), Vector2(1.0, 1.4), Vector2(1.0, 1.54), Vector2(-0.05, 1.24)]
	body.profile(era, 1.25, 0.0, 0.02)
	# Lids on the pack's top face (from (-0.05, 1.24) to (1.0, 1.54)): 3 rows x 8 columns.
	var a := atan2(0.3, 1.05)
	var along := Vector3(cos(a), sin(a), 0.0)
	var up := Vector3(-sin(a), cos(a), 0.0)
	for row in 3:
		var on := Vector3(-0.05, 1.24, 0.0) + along * (1.09 * (row + 0.5) / 3.0)
		for col in 8:
			var c := on + up * 0.012 + Vector3(0, 0, -1.05 + col * 0.3)
			body.cbox(c, Vector3(0.32, 0.024, 0.27), 0.008, Basis(Vector3.BACK, a))
	dark.openness = 0.4
	dark.cbox(Vector3(1.0, 1.47, 0.0), Vector3(0.03, 0.14, 2.5), 0.0)
	dark.openness = 1.0
	# Driver's hatch, TNPO periscope.
	body.rod(Vector3(1.55, 1.5, 0.0), Vector3.UP, 0.29, 0.06, 18, 0.015)
	body.rod(Vector3(1.57, 1.535, 0.0), Vector3.UP, 0.22, 0.03, 16, 0.01)
	var handle := MeshKit.arc(
		Vector3(1.57, 1.55, 0.0), 0.1, Vector3.RIGHT, Vector3.BACK, -0.9, 0.9, 6
	)
	steel.tube(handle, 0.012, 6)
	body.slab(1.12, 1.27, 1.46, 1.57, 0.13, 0.0, 0.015)
	h.k(&"glass").slab(1.112, 1.12, 1.49, 1.55, 0.1, 0.0, 0.0)
	for s: float in [-1.0, 1.0]:
		var z := s * 1.5
		# Headlight on a bracket with a wire guard.
		body.slab(0.22, 0.42, 1.18, 1.3, 0.09, z, 0.015)
		dark.rod(Vector3(0.28, 1.38, z), Vector3.RIGHT, 0.075, 0.14, 12, 0.012)
		h.k(&"lens").rod(Vector3(0.205, 1.38, z), Vector3.RIGHT, 0.06, 0.01, 12)
		var guard := [
			Vector3(0.33, 1.3, z - 0.1),
			Vector3(0.13, 1.33, z - 0.1),
			Vector3(0.13, 1.46, z),
			Vector3(0.13, 1.33, z + 0.1),
			Vector3(0.33, 1.3, z + 0.1)
		]
		steel.tube(guard, 0.01, 5)
		# Front mudguard: a curved band over the idler from the skirt front down to the nose.
		var guard_band := []
		for k in 9:
			var phi := 1.45 * k / 8.0
			guard_band.append(Vector2(0.62 - 0.36 * sin(phi), 0.92 + 0.36 * cos(phi)))
		for k in range(8, -1, -1):
			var phi := 1.45 * k / 8.0
			guard_band.append(Vector2(0.62 - 0.27 * sin(phi), 0.92 + 0.27 * cos(phi)))
		body.plate(
			guard_band, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK * s, 1.7, 1.79, 0.012
		)
		h.k(&"rubber").cbox(Vector3(0.05, 0.93, s * 1.52), Vector3(0.02, 0.16, 0.42), 0.005)
		# Tow hook on the lower front plate.
		dark.slab(0.12, 0.26, 0.86, 1.02, 0.09, s * 0.68, 0.015)
		var hook := MeshKit.arc(
			Vector3(0.1, 0.93, s * 0.68),
			0.07,
			Vector3.UP,
			Vector3(-1, -0.6, 0).normalized(),
			-PI * 0.5,
			PI * 0.5,
			10
		)
		steel.tube(hook, 0.024, 8)
	# Self-entrenching blade on the lower front plate, bolts above it.
	var blade := [
		Vector2(0.24, 0.88), Vector2(0.64, 0.565), Vector2(0.58, 0.49), Vector2(0.17, 0.8)
	]
	body.profile(blade, 1.15, 0.0, 0.015)
	for i in 9:
		body.bolt(Vector3(0.09, 0.995, -1.0 + i * 0.25), Vector3(-0.62, -0.78, 0.0), 0.02)


## Engine deck: louvred radiator grilles across the rear with raised frames and handles, bolted
## access plates behind the turret.
static func _engine_deck(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var top := _deck_h(6.6)
	for zc: float in [-0.62, 0.62]:
		dark.openness = 0.25
		dark.slab(5.72, 6.62, top - 0.01, top + 0.004, 0.52, zc, 0.0)
		dark.openness = 1.0
		for i in 9:
			var x := 5.78 + i * 0.1
			var louvre := Vector3(x, _deck_h(x) + 0.012, zc)
			dark.cbox(louvre, Vector3(0.04, 0.03, 0.98), 0.0, Basis(Vector3.BACK, 0.4))
		body.slab(5.68, 5.74, _deck_h(5.7), _deck_h(5.7) + 0.035, 0.54, zc, 0.01)
		body.slab(6.6, 6.66, top, top + 0.035, 0.54, zc, 0.01)
		for side: float in [-1.0, 1.0]:
			body.slab(5.68, 6.66, top, top + 0.035, 0.03, zc + side * 0.52, 0.01)
		var hh := _deck_h(6.1)
		var grip := [
			Vector3(6.1, hh + 0.035, zc - 0.08),
			Vector3(6.1, hh + 0.1, zc - 0.07),
			Vector3(6.1, hh + 0.1, zc + 0.07),
			Vector3(6.1, hh + 0.035, zc + 0.08)
		]
		steel.tube(grip, 0.012, 6)
	for i in 2:
		var x0 := 4.78 + i * 0.45
		body.slab(x0, x0 + 0.42, DECK_H, DECK_H + 0.018, 1.2, 0.0, 0.006)
		for k in 5:
			var z := -1.1 + k * 0.55
			body.bolt(Vector3(x0 + 0.04, DECK_H + 0.018, z), Vector3.UP, 0.015)
			body.bolt(Vector3(x0 + 0.38, DECK_H + 0.018, z), Vector3.UP, 0.015)


## Fender stowage: fuel tanks on the right rear fender, tool boxes and the louvred exhaust outlet
## on the left, tool boxes on the front fenders, tow cables along both fender edges. All under the
## turret bins' sweep (TURRET_CLEARANCE_H / test_tank_models.gd).
static func _fenders(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	for i in 3:
		var x0 := 4.42 + i * 0.74
		_fender_box(h, x0, x0 + 0.7, 1.555, 0.13, true)
	for span: Vector2 in [Vector2(4.42, 5.3), Vector2(6.18, 6.62)]:
		_fender_box(h, span.x, span.y, -1.555, 0.13, false)
	for s: float in [-1.0, 1.0]:
		_fender_box(h, 1.35, 2.2, s * 1.56, 0.11, false)
	# Exhaust outlet (left rear fender): raised duct with louvres.
	body.slab(5.38, 6.12, DECK_H, 1.58, 0.13, -1.56, 0.02)
	dark.openness = 0.2
	dark.slab(5.43, 6.07, 1.58, 1.595, 0.1, -1.56, 0.0)
	dark.openness = 1.0
	for i in 7:
		var louvre := Vector3(5.48 + i * 0.09, 1.6, -1.56)
		dark.cbox(louvre, Vector3(0.025, 0.03, 0.2), 0.0, Basis(Vector3.BACK, 0.5))
	# Tow cables along the fender edges, eyes at both ends, clamps.
	for s: float in [-1.0, 1.0]:
		var z := s * 1.64
		var cable := []
		for i in 9:
			var x := lerpf(2.35, 4.3, i / 8.0)
			cable.append(Vector3(x, DECK_H + 0.025 + 0.005 * sin(i * 1.7), z))
		steel.tube(cable, 0.022, 6)
		for x: float in [2.3, 4.35]:
			var eye := MeshKit.arc(
				Vector3(x, DECK_H + 0.025, z),
				0.06,
				Vector3.RIGHT,
				Vector3.BACK,
				-PI * 0.8,
				PI * 0.8,
				8
			)
			steel.tube(eye, 0.014, 5)
		for x: float in [2.8, 3.8]:
			dark.slab(x - 0.03, x + 0.03, DECK_H, DECK_H + 0.06, 0.04, z, 0.006)


## One fender box spanning x0..x1 at z (half width `hw`): chamfered body, lid seam, latches; a
## fuel tank (`fuel`) gets a filler cap and straps instead of the latches.
static func _fender_box(h: MeshKits, x0: float, x1: float, z: float, hw: float, fuel: bool) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var top := 1.6
	body.slab(x0, x1, DECK_H, top, hw, z, 0.025)
	dark.openness = 0.4
	dark.slab(x0 + 0.01, x1 - 0.01, top - 0.035, top - 0.025, hw + 0.004, z, 0.0)
	dark.openness = 1.0
	if fuel:
		h.k(&"steel").rod(Vector3(x0 + 0.15, top + 0.015, z), Vector3.UP, 0.04, 0.03, 10, 0.008)
		for x: float in [x0 + 0.2, x1 - 0.2]:
			dark.slab(x - 0.02, x + 0.02, DECK_H, top + 0.006, hw + 0.006, z, 0.004)
	else:
		for x: float in [x0 + 0.15, x1 - 0.15]:
			var zz := z + signf(z) * hw
			dark.slab(x - 0.03, x + 0.03, top - 0.07, top - 0.02, 0.012, zz, 0.004)


## Rear: two 200 l fuel drums (rims, rolling hoops, straps, filler bungs) on brackets, the
## unditching log under them on chains, tail lights with guards, tow hooks.
static func _rear(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var r := DRUM_R
	var drum := [
		Vector2(0.0, 0.425),
		Vector2(r - 0.02, 0.425),
		Vector2(r + 0.006, 0.415),
		Vector2(r, 0.4),
		Vector2(r, 0.19),
		Vector2(r + 0.012, 0.18),
		Vector2(r + 0.012, 0.16),
		Vector2(r, 0.15),
		Vector2(r, -0.15),
		Vector2(r + 0.012, -0.16),
		Vector2(r + 0.012, -0.18),
		Vector2(r, -0.19),
		Vector2(r, -0.4),
		Vector2(r + 0.006, -0.415),
		Vector2(r - 0.02, -0.425),
		Vector2(0.0, -0.425)
	]
	var x := HULL_LENGTH
	for s: float in [-1.0, 1.0]:
		var c := Vector3(DRUM.x, DRUM.y, s * DRUM.z)
		body.lathe(c, Frame.axis_basis(Vector3.BACK), drum, 16)
		steel.rod(c + Vector3(0.12, 0.12, s * 0.43), Vector3.BACK * s, 0.035, 0.03, 8, 0.006)
		for dz: float in [-0.3, 0.3]:
			var strap := MeshKit.arc(
				c + Vector3(0, 0, dz), r + 0.01, Vector3.RIGHT, Vector3.UP, -PI * 0.55, PI * 0.6, 14
			)
			dark.tube(strap, 0.014, 5)
			dark.slab(x - 0.01, x + 0.06, 1.12, 1.62, 0.035, c.z + dz, 0.008)
		# Tail light with a guard on the fender end.
		var lz := s * 1.48
		body.slab(x - 0.05, x + 0.06, 1.3, 1.46, 0.1, lz, 0.015)
		h.k(&"red_lens").slab(x + 0.06, x + 0.07, 1.39, 1.44, 0.06, lz, 0.0)
		h.k(&"lens").slab(x + 0.06, x + 0.07, 1.32, 1.37, 0.06, lz, 0.0)
		var guard := [
			Vector3(x, 1.47, lz - 0.12),
			Vector3(x + 0.12, 1.47, lz - 0.12),
			Vector3(x + 0.12, 1.47, lz + 0.12),
			Vector3(x, 1.47, lz + 0.12)
		]
		steel.tube(guard, 0.01, 5)
		# Tow hook on the lower rear plate.
		dark.slab(6.78, 6.9, 0.78, 0.94, 0.08, s * 0.72, 0.015)
		var hook := MeshKit.arc(
			Vector3(6.93, 0.86, s * 0.72), 0.065, Vector3.UP, Vector3.RIGHT, 0.0, PI * 1.3, 8
		)
		steel.tube(hook, 0.022, 8)
	# Unditching log on chains under the drums (weathered track paint reads as old wood).
	var log_c := Vector3(6.99, 0.97, 0.0)
	var log_profile := [
		Vector2(0.0, 1.55),
		Vector2(0.1, 1.55),
		Vector2(0.12, 1.52),
		Vector2(0.125, 0.8),
		Vector2(0.118, 0.0),
		Vector2(0.126, -0.9),
		Vector2(0.12, -1.52),
		Vector2(0.1, -1.55),
		Vector2(0.0, -1.55)
	]
	h.k(&"track").lathe(log_c, Frame.axis_basis(Vector3.BACK), log_profile, 10)
	for z: float in [-1.0, 1.0]:
		var chain := MeshKit.arc(
			log_c + Vector3(0, 0, z), 0.135, Vector3.RIGHT, Vector3.UP, -PI * 0.5, PI, 10
		)
		steel.tube(chain, 0.012, 4)


# --- Turret -------------------------------------------------------------------------------------


## Low rounded cast dome (an oval lathe: sloping shoulders, rounded front and rear, narrower than
## the hull; slight undercut at the rim, no floor), the dark turret ring collar under the rim,
## lifting eyes.
static func _dome(t: MeshKits) -> void:
	var body := t.k(&"body")
	var prof := []
	for rho: float in [0.0, 0.22, 0.38, 0.52, 0.63, 0.72, 0.8, 0.86, 0.91, 0.95, 0.98, 1.0]:
		var hh := (ROOF_H - DOME_BASE) * pow(1.0 - pow(rho, 3.0), 0.45)
		prof.append(Vector2(rho * DOME_HL, hh))
	prof.append(Vector2(DOME_HL * 0.93, 0.0))
	var oval := Vector2(1.0, DOME_HW / DOME_HL)
	body.lathe(Vector3(DOME_X, DOME_BASE, 0.0), Basis.IDENTITY, prof, 32, true, oval)
	var dark := t.k(&"dark")
	dark.openness = 0.2
	dark.rod(Vector3(TURRET_X, DECK_H + 0.016, 0.0), Vector3.UP, 1.02, 0.03, 32, 0.006)
	dark.openness = 1.0
	for p: Vector3 in [Vector3(3.0, 0.0, -0.95), Vector3(3.0, 0.0, 0.95), Vector3(4.6, 0.0, 0.0)]:
		var c := Vector3(p.x, _dome_h(p.x, p.z) - 0.01, p.z)
		var e1 := Vector3.BACK if p.z == 0.0 else Vector3.RIGHT
		dark.tube(MeshKit.arc(c, 0.06, e1, Vector3.UP, 0.0, PI, 8), 0.018, 6)


## One side's Kontakt-5 wedge (`s` = side sign) along a front edge swept back 35 deg from the gun
## (x 1.95, z 0.32) to the turret side (x 2.6, z 1.25): two rows of four chamfered blocks with
## gaps and two bolts each. The front row is a wedge (sharp 1.74 m front edge, top sloping up
## backwards), the back row a taller block whose top continues the slope up to 2.06 m; each
## block steps up 0.03 m outwards, so from the front the two packs form a shallow V with the gun
## collar in the notch.
static func _era_wedge(t: MeshKits, s: float) -> void:
	var body := t.k(&"body")
	var inner := Vector3(1.95, 0.0, 0.32 * s)
	var outer := Vector3(2.6, 0.0, 1.25 * s)
	var along := outer - inner
	var axis := along.normalized()
	var forward := Vector3(-absf(along.z), 0.0, s * absf(along.x)).normalized()
	var block := along.length() / 4.0 - 0.04
	var rows := [
		[Vector2(-0.29, 1.6), Vector2(0.08, 1.6), Vector2(0.0, 1.74), Vector2(-0.29, 1.89)],
		[Vector2(-0.57, 1.6), Vector2(-0.33, 1.6), Vector2(-0.33, 1.95), Vector2(-0.57, 2.06)]
	]
	for section: Array in rows:
		var a: Vector2 = section[2]
		var b: Vector2 = section[3]
		var top := (a + b) / 2.0
		var normal := Vector2(a.y - b.y, b.x - a.x).normalized()
		if normal.y < 0.0:
			normal = -normal
		var bolt_dir := forward * normal.x + Vector3.UP * normal.y
		for i in 4:
			var c := inner.lerp(outer, (i + 0.5) / 4.0) + Vector3(0, 0.03 * i, 0)
			body.plate(section, c, forward, Vector3.UP, axis, -block / 2.0, block / 2.0, 0.012)
			for d: float in [-0.25, 0.25]:
				var at := c + forward * top.x + Vector3.UP * top.y + axis * (d * block)
				body.bolt(at, bolt_dir, 0.02)


## Sosna-U gunner's sight head on the right front roof: armoured box with a round front barrel
## whose big round window (dark bezel, glass) faces forward under an opened armoured visor.
static func _sosna(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var z := SOSNA_Z
	body.slab(2.8, 3.16, _dome_h(3.16, z) - 0.04, 2.46, 0.24, z, 0.035)
	body.slab(2.68, 2.86, _dome_h(2.68, z) - 0.04, SOSNA_H - 0.12, 0.17, z, 0.02)
	body.rod(Vector3(2.73, SOSNA_H, z), Vector3.RIGHT, 0.23, 0.22, 24, 0.025)
	var c := Vector3(SOSNA_X0, SOSNA_H, z)
	var bezel := [
		Vector2(0.15, -0.005),
		Vector2(0.15, 0.03),
		Vector2(0.19, 0.03),
		Vector2(0.2, 0.02),
		Vector2(0.2, -0.005)
	]
	dark.lathe(c, Frame.axis_basis(Vector3.LEFT), bezel, 24)
	t.k(&"glass").rod(c + Vector3(-0.005, 0.0, 0.0), Vector3.LEFT, 0.152, 0.01, 24)
	# Opened visor: hinged on the top front edge, standing forward and up.
	body.cbox(Vector3(2.52, 2.5, z), Vector3(0.32, 0.03, 0.46), 0.01, Basis(Vector3.BACK, -0.45))
	for dz: float in [-0.17, 0.17]:
		t.k(&"steel").rod(Vector3(2.68, 2.44, z + dz), Vector3.BACK, 0.025, 0.08, 8)
	# Bolted roof plate, seam between head and box.
	for bx: float in [2.88, 3.08]:
		for dz: float in [-0.16, 0.16]:
			body.bolt(Vector3(bx, 2.46, z + dz), Vector3.UP, 0.018)
	dark.openness = 0.4
	dark.slab(2.79, 2.81, 2.0, 2.44, 0.245, z, 0.0)
	dark.openness = 1.0


## Commander's cupola (right): ring with vision blocks, hatch lid with hinge, TKN-3MK sight block,
## round OU-3GA2M IR lamp, NSVT 12.7 mm on its mount with ammo box and sight.
static func _cupola(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var glass := t.k(&"glass")
	var c := Vector3(3.6, 0.0, 0.52)
	body.rod(Vector3(c.x, 2.1, c.z), Vector3.UP, 0.42, 0.33, 24, 0.025)
	body.rod(Vector3(c.x + 0.02, 2.29, c.z), Vector3.UP, 0.32, 0.05, 20, 0.015)
	steel.rod(Vector3(c.x + 0.36, 2.29, c.z), Vector3.BACK, 0.03, 0.2, 8)
	for k in 4:
		var ang := PI + (k - 1.5) * 0.45
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var block := Vector3(c.x, 2.22, c.z) + dir * 0.415
		glass.cbox(block, Vector3(0.02, 0.045, 0.1), 0.0, Basis(Vector3.UP, -ang))
	body.slab(3.18, 3.38, 2.22, 2.42, 0.13, c.z, 0.02)
	glass.slab(3.165, 3.18, 2.29, 2.38, 0.09, c.z, 0.0)
	# IR lamp on its bracket, left of the sight.
	dark.slab(3.22, 3.28, 2.3, 2.44, 0.03, 0.24, 0.006)
	body.rod(Vector3(3.24, 2.52, 0.24), Vector3.RIGHT, 0.11, 0.2, 16, 0.02)
	t.k(&"lens").rod(Vector3(3.135, 2.52, 0.24), Vector3.RIGHT, 0.09, 0.012, 16)
	# NSVT: pintle, cradle, receiver, barrel with flash hider, ammo box, sight.
	dark.rod(Vector3(3.78, 2.4, c.z), Vector3.UP, 0.05, 0.24, 8, 0.008)
	dark.slab(3.62, 3.9, 2.45, 2.51, 0.06, c.z, 0.01)
	dark.slab(3.45, 3.98, 2.5, 2.6, 0.05, c.z, 0.012)
	dark.slab(3.88, 3.98, 2.45, 2.55, 0.02, c.z, 0.004)
	var nsvt := [
		Vector2(0.0, 1.07),
		Vector2(0.024, 1.07),
		Vector2(0.024, 0.98),
		Vector2(0.017, 0.96),
		Vector2(0.015, 0.12),
		Vector2(0.028, 0.1),
		Vector2(0.028, 0.0),
		Vector2(0.0, 0.0)
	]
	steel.lathe(Vector3(3.45, 2.555, c.z), Frame.axis_basis(Vector3.LEFT), nsvt, 8)
	body.slab(3.58, 3.84, 2.41, 2.57, 0.08, c.z + 0.17, 0.015)
	dark.slab(3.52, 3.62, 2.6, 2.67, 0.03, c.z, 0.006)


## Roof: gunner's hatch with periscope and the backup 1A40-1 sight head (left), wind sensor mast at
## the rear, radio antenna base, grab rails on the dome shoulders.
static func _roof(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var glass := t.k(&"glass")
	var gz := -0.55
	body.rod(Vector3(3.62, 2.07, gz), Vector3.UP, 0.34, 0.27, 22, 0.02)
	body.rod(Vector3(3.62, 2.215, gz), Vector3.UP, 0.25, 0.04, 18, 0.012)
	var grip := MeshKit.arc(
		Vector3(3.62, 2.235, gz), 0.1, Vector3.RIGHT, Vector3.BACK, -0.9, 0.9, 6
	)
	steel.tube(grip, 0.012, 6)
	steel.rod(Vector3(3.95, 2.2, gz), Vector3.BACK, 0.03, 0.22, 8)
	body.slab(3.2, 3.3, 2.12, 2.24, 0.08, gz, 0.012)
	glass.slab(3.19, 3.2, 2.16, 2.22, 0.06, gz, 0.0)
	body.slab(2.88, 3.12, _dome_h(2.88, gz) - 0.03, 2.3, 0.12, gz, 0.025)
	glass.slab(2.87, 2.88, 2.2, 2.27, 0.09, gz, 0.0)
	dark.slab(2.9, 3.0, 2.3, 2.32, 0.1, gz, 0.006)
	# Wind sensor mast (DVE-BS) at the rear centre.
	var mx := 4.3
	dark.rod(Vector3(mx, _dome_h(mx, 0.0) + 0.02, 0.0), Vector3.UP, 0.05, 0.06, 10, 0.01)
	steel.tube([Vector3(mx, _dome_h(mx, 0.0), 0.0), Vector3(mx, 2.7, 0.0)], 0.018, 6)
	dark.cbox(Vector3(mx, 2.74, 0.0), Vector3(0.1, 0.08, 0.12), 0.015)
	# Radio antenna base on the left bin, whip stub.
	dark.rod(Vector3(4.45, BIN_SIDE_TOP + 0.04, -1.1), Vector3.UP, 0.06, 0.08, 10, 0.012)
	steel.tube([Vector3(4.45, BIN_SIDE_TOP + 0.08, -1.1), Vector3(4.45, 2.6, -1.1)], 0.01, 5)
	# Grab rails on the dome shoulders.
	for s: float in [-1.0, 1.0]:
		var pts := []
		for x: float in [3.3, 3.35, 3.65, 3.7]:
			var half := DOME_HW * sqrt(maxf(1.0 - pow((x - DOME_X) / DOME_HL, 2.0), 0.0))
			var zz := s * half * 0.86
			var lift := 0.06 if x > 3.32 and x < 3.68 else 0.0
			pts.append(Vector3(x, _dome_h(x, zz) - 0.01 + lift, zz + s * lift * 0.5))
		steel.tube(pts, 0.014, 6)


## U-shaped stowage around the turret rear: a side bin on each side (outer face leaning out, lid,
## hinges, latches, ribs, handle) and the rear bin across the back (rear face raked), the OPVT
## snorkel tube strapped on the left bin.
static func _bins(t: MeshKits) -> void:
	for s: float in [-1.0, 1.0]:
		_side_bin(t, s)
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var lid_h := BIN_REAR_TOP - BIN_LID
	var rear_bottom := [
		Vector2(4.45, -0.62), Vector2(4.98, -0.62), Vector2(4.98, 0.62), Vector2(4.45, 0.62)
	]
	var rear_top := [
		Vector2(4.45, -0.62), Vector2(5.1, -0.62), Vector2(5.1, 0.62), Vector2(4.45, 0.62)
	]
	body.loft(rear_bottom, rear_top, BIN_REAR_H0, lid_h, 0.02)
	var rear_lid := [
		Vector2(4.45, -0.635), Vector2(5.115, -0.635), Vector2(5.115, 0.635), Vector2(4.45, 0.635)
	]
	body.loft(rear_lid, rear_lid, lid_h, BIN_REAR_TOP, 0.012)
	dark.openness = 0.4
	var seam := [
		Vector2(4.45, -0.626), Vector2(5.106, -0.626), Vector2(5.106, 0.626), Vector2(4.45, 0.626)
	]
	dark.loft(seam, seam, lid_h - 0.012, lid_h, 0.0)
	dark.openness = 1.0
	var rake := Basis(Vector3.BACK, atan2(0.12, lid_h - BIN_REAR_H0))
	for hh: float in [1.84, 1.94]:
		body.cbox(Vector3(_rear_face(hh) + 0.008, hh, 0.0), Vector3(0.02, 0.025, 1.1), 0.006, rake)
	for z: float in [-0.4, 0.4]:
		dark.cbox(Vector3(_rear_face(2.0) + 0.012, 2.0, z), Vector3(0.025, 0.07, 0.06), 0.006, rake)
		steel.rod(Vector3(4.47, BIN_REAR_TOP + 0.005, z), Vector3.BACK, 0.018, 0.16, 8)
	var bx := _rear_face(1.8)
	var handle := [
		Vector3(bx, 1.8, -0.15),
		Vector3(bx + 0.06, 1.8, -0.13),
		Vector3(bx + 0.06, 1.8, 0.13),
		Vector3(bx, 1.8, 0.15)
	]
	steel.tube(handle, 0.012, 6)
	# OPVT snorkel tube strapped lengthwise on the left bin.
	var sc := Vector3(4.22, BIN_SIDE_TOP + 0.125, -1.06)
	var tube := [
		Vector2(0.0, 0.56),
		Vector2(0.1, 0.56),
		Vector2(0.125, 0.535),
		Vector2(0.125, -0.535),
		Vector2(0.1, -0.56),
		Vector2(0.0, -0.56)
	]
	body.lathe(sc, Frame.axis_basis(Vector3.RIGHT), tube, 14)
	for dx: float in [-0.3, 0.3]:
		var strap := MeshKit.arc(
			sc + Vector3(dx, 0, 0), 0.135, Vector3.BACK, Vector3.UP, -0.2, PI + 0.2, 10
		)
		dark.tube(strap, 0.012, 4)


## The side bin on side `s`: plan from the dome side (x 3.62) back to x 4.8, outer face leaning
## out from z 1.3 to 1.42; lid, lid seam, two ribs, latches, hinges, handle.
static func _side_bin(t: MeshKits, s: float) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var bottom := [
		Vector2(3.62, s * 0.85),
		Vector2(4.45, s * 0.6),
		Vector2(4.8, s * 0.6),
		Vector2(4.8, s * 1.3),
		Vector2(3.74, s * 1.3)
	]
	var top := [
		Vector2(3.62, s * 0.85),
		Vector2(4.45, s * 0.6),
		Vector2(4.8, s * 0.6),
		Vector2(4.8, s * 1.42),
		Vector2(3.66, s * 1.42)
	]
	var lid_h := BIN_SIDE_TOP - BIN_LID
	body.loft(bottom, top, BIN_H0, lid_h, 0.02)
	var lid := []
	var seam := []
	for p: Vector2 in top:
		var out := absf(p.y) > 1.0
		lid.append(p + Vector2(-0.012 if p.x < 4.0 else 0.0, s * 0.012 if out else 0.0))
		seam.append(p + Vector2(0.0, s * 0.006 if out else 0.0))
	body.loft(lid, lid, lid_h, BIN_SIDE_TOP, 0.012)
	dark.openness = 0.4
	dark.loft(seam, seam, lid_h - 0.012, lid_h, 0.0)
	dark.openness = 1.0
	var lean := Basis(Vector3.RIGHT, s * atan2(0.12, lid_h - BIN_H0))
	for hh: float in [1.76, 1.86]:
		var rib := Vector3(4.24, hh, _side_face(s, hh) + s * 0.008)
		body.cbox(rib, Vector3(0.95, 0.025, 0.02), 0.006, lean)
	for x: float in [3.95, 4.55]:
		var latch := Vector3(x, 1.95, _side_face(s, 1.95) + s * 0.012)
		dark.cbox(latch, Vector3(0.06, 0.07, 0.025), 0.006, lean)
		steel.rod(Vector3(x, BIN_SIDE_TOP + 0.005, s * 0.8), Vector3.RIGHT, 0.018, 0.14, 8)
	var fz := _side_face(s, 1.72)
	var handle := [
		Vector3(3.92, 1.72, fz),
		Vector3(3.95, 1.72, fz + s * 0.06),
		Vector3(4.15, 1.72, fz + s * 0.06),
		Vector3(4.18, 1.72, fz)
	]
	steel.tube(handle, 0.012, 6)


## z of a side bin's outer face (leaning out by 0.12 m) at height hh on side s.
static func _side_face(s: float, hh: float) -> float:
	return s * (1.3 + (hh - BIN_H0) * 0.12 / (BIN_SIDE_TOP - BIN_LID - BIN_H0))


## x of the rear bin's raked rear face at height hh.
static func _rear_face(hh: float) -> float:
	return 4.98 + (hh - BIN_REAR_H0) * 0.12 / (BIN_REAR_TOP - BIN_LID - BIN_REAR_H0)


## 902B smoke grenade launchers on brackets on the turret sides behind the K-5 wedges: 8 on the
## left (two rows), 4 on the right, aimed forward, up and out; dark tubes with recessed muzzles.
static func _smoke_launchers(t: MeshKits) -> void:
	var dark := t.k(&"dark")
	var tube := [
		Vector2(0.0, 0.28),
		Vector2(0.035, 0.28),
		Vector2(0.035, 0.3),
		Vector2(0.05, 0.3),
		Vector2(0.05, 0.0),
		Vector2(0.0, 0.0)
	]
	for s: float in [-1.0, 1.0]:
		dark.slab(3.0, 3.62, 1.7, 1.75, 0.22, s * 1.18, 0.01)
		var aim := Frame.axis_basis(Vector3(-0.6, 0.45, s * 0.35))
		for row in 2 if s < 0.0 else 1:
			for i in 4:
				var x := 3.1 + i * 0.14 + row * 0.07
				dark.lathe(Vector3(x, 1.78 + row * 0.13, s * (1.22 + row * 0.08)), aim, tube, 6)


# --- Gun ----------------------------------------------------------------------------------------


## On `Turret/Gun`: the canvas dust cover around the gun root (folds), its steel collar, the
## coaxial PKTM port block.
static func _gun_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var g := MeshKits.new(frame, to_gun)
	var prof := [Vector2(0.12, 0.6), Vector2(0.2, 0.585)]
	for i in 6:
		var y := 0.56 - i * 0.09
		prof.append(Vector2(0.235, y))
		prof.append(Vector2(0.222, y - 0.045))
	prof.append(Vector2(0.235, -0.1))
	prof.append(Vector2(0.0, -0.1))
	var root := Vector3(TRUNNION.x, TRUNNION.y, 0.0)
	g.k(&"cloth").lathe(root, Frame.axis_basis(Vector3.LEFT), prof, 16)
	g.k(&"steel").rod(root - Vector3(0.62, 0, 0), Vector3.RIGHT, 0.13, 0.05, 16, 0.008)
	g.k(&"body").slab(1.96, 2.3, 1.68, 1.84, 0.065, 0.31, 0.015)
	var dark := g.k(&"dark")
	dark.openness = 0.15
	dark.rod(Vector3(1.955, 1.76, 0.31), Vector3.RIGHT, 0.032, 0.02, 10, 0.006)
	dark.openness = 1.0
	return g.commit_all()


## On `Turret/Gun/Barrel` (identity transform at the gun pivot; TASK-048 slides it back for the
## recoil): the long 2A46M-5 barrel with the fume extractor, thermal sleeve sections with clamp
## bands, muzzle lip and bore.
static func _barrel_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var b := MeshKits.new(frame, to_gun)
	var length := TRUNNION.x + GUN_OVERHANG  # trunnion to muzzle
	var prof := [
		Vector2(0.0, length),
		Vector2(0.074, length),
		Vector2(0.09, length - 0.016),
		Vector2(0.09, length - 0.04),
		Vector2(0.082, length - 0.05),
		Vector2(0.088, length - 0.6),
		Vector2(0.094, length - 0.62),
		Vector2(0.095, 3.66),
		Vector2(0.1, 2.74),
		Vector2(0.104, 1.84),
		Vector2(0.15, 1.8),
		Vector2(0.15, 1.04),
		Vector2(0.112, 1.0),
		Vector2(0.115, 0.56),
		Vector2(0.0, 0.56)
	]
	var root := Vector3(TRUNNION.x, TRUNNION.y, 0.0)
	b.k(&"body").lathe(root, Frame.axis_basis(Vector3.LEFT), prof, 16)
	for y: float in [length - 0.65, 3.63, 2.71, 1.9]:
		var r := 0.104 if y > 3.0 else 0.11
		b.k(&"steel").rod(root - Vector3(y, 0, 0), Vector3.RIGHT, r, 0.05, 16, 0.006)
	var dark := b.k(&"dark")
	dark.openness = 0.05
	dark.rod(Vector3(-GUN_OVERHANG + 0.004, TRUNNION.y, 0.0), Vector3.RIGHT, 0.064, 0.01, 16, 0.003)
	dark.openness = 1.0
	return b.commit_all()
