## M1A2 SEPv3 Abrams (M1A2C): the Polish Army's main battle tank. Blueprint:
## docs/design/units/units/m1a2_sepv3/blueprint.md. Measurements are metres (vehicle_frame.gd):
## `x` from the hull front (glacis nose, 0) to the rear plate (HULL_LENGTH), `h` above the ground,
## `z` across (positive = vehicle's right). Turret at 12 o'clock, gun level.
##
## Built with MeshKit (TASK-069, ADR 0012) after the detail study
## docs/design/showcase/m1a2_showcase.gd.txt: chamfered parts, bolts, hinges, cables, rails,
## individual track shoes; what the camera never sees is cut (no shoes on the top run behind the
## skirts, plain inner wheel halves, nothing inside the shell). The geometry does not depend on the
## faction, so it is generated once (ModelParts.cached_meshes) and only the materials differ.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {
	"wheels": {},
	"turret_traverse": {"traverse_deg": "full", "elevation_deg": [-10, 20]},
}
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/tracked_running_gear.gd")

const HULL_LENGTH := 7.93
## The gun protrudes this far beyond the hull front (overall 9.77 m).
const GUN_OVERHANG := 1.84
## Model units per metre: 9.77 m -> 0.86 (x unit scale 1.3 = 1.118 <= 1.15).
const K := 0.088
## Turret ring centre (x) on the hull deck (h) and the ring guard radius; gun trunnions (x, h).
const TURRET_X := 3.95
const TURRET_RING_R := 1.15
const DECK_H := 1.62
const ROOF_H := 2.36
## Roof add-ons (sights, CROWS, shields, antenna stubs) end here (blueprint: deliberate deviation).
const ROOF_CAP := 2.64
const TRUNNION := Vector2(2.3, 1.98)
## Hull half widths: upper hull / fenders over the tracks, lower hull between the tracks.
const UPPER_HW := 1.72
const LOWER_HW := 1.12
## A box strictly inside the armour shell (vehicle metres: position = (x from the front, h, z)):
## no triangle may lie entirely inside it (hidden-geometry test, test_tank_models.gd).
const HULL_INTERIOR := AABB(Vector3(1.5, 0.7, -0.9), Vector3(4.3, 0.75, 1.8))
## Lowest turret / bustle / rack underside outside the turret ring (m): the turret front block.
const TURRET_CLEARANCE_H := 1.67


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var frame := vehicle_frame()
	var m := Frame.kit_tank_materials(faction)
	var spec := running_gear()
	Gear.add_pivots(g, frame, spec, m)
	var hull := ModelParts.cached_meshes(
		"m1a2_sepv3:hull", func() -> Dictionary: return _hull_meshes(frame, spec)
	)
	MeshKits.add_meshes(g, hull, m)
	_anchors(g, frame, spec)
	var turret := frame.add_turret(g, TURRET_X, DECK_H)
	var to_turret := Frame.to_local(turret)
	var shell := ModelParts.cached_meshes(
		"m1a2_sepv3:turret", func() -> Dictionary: return _turret_meshes(frame, to_turret)
	)
	MeshKits.add_meshes(turret, shell, m)
	var gun := frame.add_gun(turret, TRUNNION, -GUN_OVERHANG - 0.05)
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	gun.add_child(barrel)
	var to_gun := Frame.to_local(gun)
	var gun_meshes := ModelParts.cached_meshes(
		"m1a2_sepv3:gun", func() -> Dictionary: return _gun_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(gun, gun_meshes, m)
	var barrel_meshes := ModelParts.cached_meshes(
		"m1a2_sepv3:barrel", func() -> Dictionary: return _barrel_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(barrel, barrel_meshes, m)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## Metres -> model space: K model units per metre, hull plus gun centred on x = 0.
static func vehicle_frame() -> Frame:
	return Frame.new(K, (HULL_LENGTH - GUN_OVERHANG) / 2.0)


## The Abrams running gear: 7 double road wheels (0.635 m) per side, 2 return rollers, rear
## sprocket, raised front idler, deep skirts (2 armoured front panels), all with the kit detail.
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
	spec.skirt_front_thickness = 0.13
	spec.skirt_front_rake = 0.4
	spec.accent_panel = 1
	spec.detailed_wheels = true
	spec.track_shoe_pitch = 0.193
	spec.detailed_skirts = true
	return spec


## Effect anchors for MotionFx (TASK-064): exhaust at the rear grille, dust under the sprockets.
static func _anchors(g: Node3D, frame: Frame, spec: Gear.Spec) -> void:
	var at := {
		"Exhaust": frame.p(HULL_LENGTH + 0.05, 1.35, 0.0),
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
	_rear(hull)
	return hull.commit_all()


static func _turret_meshes(frame: Frame, to_turret: Transform3D) -> Dictionary:
	var t := MeshKits.new(frame, to_turret)
	_turret(t)
	_turret_roof(t)
	_crows(t)
	_bustle(t)
	_turret_sides(t)
	return t.commit_all()


# --- Hull ---------------------------------------------------------------------------------------


## Upper hull (long shallow glacis, flat deck over the full width) and lower hull between the tracks
## as chamfered profiles, tie-down eyes, the turret ring guard. The study's fender lip and its
## brackets sit behind the skirt top and are cut.
static func _hull(h: MeshKits) -> void:
	var body := h.k(&"body")
	body.profile(
		[
			Vector2(0.0, 1.14),
			Vector2(0.0, 1.27),
			Vector2(2.25, 1.6),
			Vector2(7.8, DECK_H),
			Vector2(HULL_LENGTH, 1.55),
			Vector2(HULL_LENGTH, 1.14)
		],
		UPPER_HW,
		0.0,
		0.035
	)
	body.profile(
		[
			Vector2(0.04, 1.14),
			Vector2(0.95, 0.52),
			Vector2(7.45, 0.48),
			Vector2(7.88, 0.78),
			Vector2(7.88, 1.14)
		],
		LOWER_HW,
		0.0,
		0.03
	)
	var dark := h.k(&"dark")
	for s: float in [-1.0, 1.0]:
		for x: float in [0.35, 7.6]:
			var c := Vector3(x, 1.33 if x < 1.0 else DECK_H + 0.01, s * 1.55)
			dark.tube(MeshKit.arc(c, 0.06, Vector3.RIGHT, Vector3.UP, 0.0, PI, 8), 0.016, 6)
	dark.openness = 0.2
	dark.rod(Vector3(TURRET_X, DECK_H + 0.03, 0.0), Vector3.UP, TURRET_RING_R, 0.06, 40)
	dark.openness = 1.0


## Driver's hatch with periscopes, glacis seam and splash strip, headlight clusters with guards,
## front mud flaps, tow shackles, lower front plate bolts.
static func _front(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var glass := h.k(&"glass")
	var steel := h.k(&"steel")
	var lens := h.k(&"lens")
	var rubber := h.k(&"rubber")
	var tilt := Basis(Vector3.BACK, atan2(0.33, 2.25))
	dark.openness = 0.35
	dark.cbox(Vector3(1.95, 1.565, 0.0), Vector3(0.62, 0.04, 0.72), 0.01, tilt)
	dark.openness = 1.0
	body.cbox(Vector3(2.0, 1.585, 0.0), Vector3(0.5, 0.04, 0.6), 0.015, tilt)
	for z: float in [-0.22, 0.0, 0.22]:
		body.cbox(Vector3(1.72, 1.57, z), Vector3(0.1, 0.09, 0.17), 0.012, tilt)
		glass.cbox(Vector3(1.67, 1.58, z), Vector3(0.012, 0.05, 0.14), 0.0, tilt)
	dark.openness = 0.3
	dark.cbox(Vector3(1.2, 1.455, 0.0), Vector3(0.025, 0.012, 2.9), 0.0, tilt)
	dark.openness = 1.0
	body.cbox(Vector3(1.45, 1.51, 0.0), Vector3(0.06, 0.05, 1.3), 0.015, tilt)
	for s: float in [-1.0, 1.0]:
		var z := s * 1.42
		body.slab(0.06, 0.4, 1.27, 1.45, 0.17, z, 0.02)
		for dz: float in [-0.07, 0.07]:
			lens.rod(Vector3(0.05, 1.37, z + dz), Vector3.RIGHT, 0.045, 0.02, 12)
			dark.rod(Vector3(0.065, 1.37, z + dz), Vector3.RIGHT, 0.055, 0.02, 12)
		for side: float in [-1.0, 1.0]:
			var gz := z + side * 0.19
			steel.tube(
				[
					Vector3(0.35, 1.45, gz),
					Vector3(-0.02, 1.45, gz),
					Vector3(-0.04, 1.3, gz),
					Vector3(0.1, 1.27, gz)
				],
				0.012,
				6
			)
		steel.tube([Vector3(-0.02, 1.45, z - 0.19), Vector3(-0.02, 1.45, z + 0.19)], 0.012, 6)
		rubber.cbox(
			Vector3(0.08, 1.02, s * 1.47),
			Vector3(0.02, 0.24, 0.5),
			0.005,
			Basis(Vector3.BACK, 0.12)
		)
		var c := Vector3(0.06, 0.9, s * 0.72)
		dark.slab(0.1, 0.24, 0.88, 1.06, 0.1, s * 0.72, 0.015)
		steel.tube(
			MeshKit.arc(
				c, 0.07, Vector3.UP, Vector3(-1, -0.6, 0).normalized(), -PI * 0.5, PI * 0.5, 10
			),
			0.025,
			8
		)
		steel.rod(c, Vector3.BACK, 0.03, 0.22, 10, 0.006)
	for i in 8:
		var z := -0.9 + i * (1.8 / 7.0)
		body.bolt(Vector3(0.35, 1.02, z), Vector3(-1, 0.55, 0), 0.02)


## Three grille doors (raised frames, recessed louvres, handles), front access plates with bolts.
static func _engine_deck(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	for panel in 3:
		var z0 := -1.32 + panel * 0.9
		var z1 := z0 + 0.84
		var zc := (z0 + z1) / 2.0
		var hw := (z1 - z0) / 2.0
		dark.openness = 0.25
		dark.slab(6.05, 7.65, DECK_H - 0.01, DECK_H + 0.005, hw - 0.02, zc, 0.0)
		dark.openness = 1.0
		for i in 12:
			dark.cbox(
				Vector3(6.12 + i * 0.125, DECK_H + 0.012, zc),
				Vector3(0.05, 0.035, hw * 2.0 - 0.08),
				0.0,
				Basis(Vector3.BACK, 0.35)
			)
		body.slab(6.0, 6.06, DECK_H, DECK_H + 0.035, hw, zc, 0.012)
		body.slab(7.64, 7.7, DECK_H, DECK_H + 0.035, hw, zc, 0.012)
		body.slab(6.0, 7.7, DECK_H, DECK_H + 0.035, 0.03, z0 + 0.03, 0.012)
		body.slab(6.0, 7.7, DECK_H, DECK_H + 0.035, 0.03, z1 - 0.03, 0.012)
		for x: float in [6.42, 7.4]:
			steel.tube(
				[
					Vector3(x - 0.08, DECK_H + 0.035, zc),
					Vector3(x - 0.07, DECK_H + 0.1, zc),
					Vector3(x + 0.07, DECK_H + 0.1, zc),
					Vector3(x + 0.08, DECK_H + 0.035, zc)
				],
				0.012,
				6
			)
	for i in 2:
		var x0 := 4.95 + i * 0.52
		body.slab(x0 + 0.01, x0 + 0.49, DECK_H, DECK_H + 0.018, 1.4, 0.0, 0.006)
		for k in 6:
			var z := -1.3 + k * (2.6 / 5.0)
			body.bolt(Vector3(x0 + 0.04, DECK_H + 0.018, z), Vector3.UP, 0.015)
			body.bolt(Vector3(x0 + 0.46, DECK_H + 0.018, z), Vector3.UP, 0.015)


## Rear: big exhaust grille with louvres, tail lights with guards, tow hooks and pintle, tow cable
## across the grille, fender stowage boxes and the APU box with its exhaust (rear left), mud flaps.
## The boxes stay under the bustle rack's sweep (TURRET_CLEARANCE_H / test_tank_models.gd).
static func _rear(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var x := HULL_LENGTH
	dark.openness = 0.2
	dark.slab(x - 0.05, x + 0.01, 1.17, 1.53, 1.2, 0.0, 0.0)
	dark.openness = 1.0
	for i in 8:
		dark.cbox(
			Vector3(x + 0.02, 1.2 + i * 0.042, 0.0),
			Vector3(0.012, 0.05, 2.32),
			0.004,
			Basis(Vector3.BACK, -0.6)
		)
	body.slab(x - 0.02, x + 0.05, 1.14, 1.18, 1.27, 0.0, 0.012)
	body.slab(x - 0.02, x + 0.05, 1.52, 1.56, 1.27, 0.0, 0.012)
	body.pair(x - 0.02, x + 0.05, 1.14, 1.56, 0.05, 1.22, 0.012)
	body.slab(x - 0.02, x + 0.05, 1.14, 1.56, 0.03, 0.0, 0.01)
	for s: float in [-1.0, 1.0]:
		var z := s * 1.5
		body.slab(x - 0.05, x + 0.07, 1.22, 1.42, 0.13, z, 0.015)
		h.k(&"red_lens").slab(x + 0.07, x + 0.08, 1.33, 1.39, 0.08, z, 0.0)
		h.k(&"lens").slab(x + 0.07, x + 0.08, 1.25, 1.3, 0.08, z, 0.0)
		for side: float in [-1.0, 1.0]:
			var gz := z + side * 0.15
			steel.tube(
				[
					Vector3(x, 1.44, gz),
					Vector3(x + 0.12, 1.44, gz),
					Vector3(x + 0.12, 1.2, gz),
					Vector3(x, 1.2, gz)
				],
				0.01,
				6
			)
		dark.slab(7.8, 7.95, 0.82, 1.0, 0.07, s * 0.85, 0.015)
		steel.tube(
			MeshKit.arc(
				Vector3(7.98, 0.88, s * 0.85), 0.06, Vector3.UP, Vector3.RIGHT, 0.0, PI * 1.3, 8
			),
			0.022,
			8
		)
	body.slab(x - 0.02, x + 0.09, 1.2, 1.4, 0.11, 0.62, 0.015)
	dark.rod(Vector3(7.95, 0.9, 0.0), Vector3.UP, 0.07, 0.12, 12, 0.01)
	steel.tube(
		MeshKit.arc(
			Vector3(8.02, 0.96, 0.0), 0.06, Vector3.RIGHT, Vector3.UP, -PI * 0.5, PI * 0.5, 8
		),
		0.022,
		8
	)
	var cable := []
	for i in 17:
		var t := float(i) / 16.0
		var sag := 0.16 * (1.0 - pow(2.0 * t - 1.0, 2.0))
		cable.append(Vector3(x + 0.09 + 0.02 * sin(t * 9.0), 1.5 - sag, lerpf(-1.05, 1.05, t)))
	steel.tube(cable, 0.024, 8)
	for s: float in [-1.0, 1.0]:
		steel.tube(
			MeshKit.arc(
				Vector3(x + 0.09, 1.52, s * 1.1),
				0.06,
				Vector3.BACK * s,
				Vector3.UP,
				-PI * 0.2,
				PI * 1.6,
				10
			),
			0.016,
			6
		)
	for s: float in [-1.0, 1.0]:
		var z := s * 1.32
		body.slab(7.2, 7.9, DECK_H, 1.735, 0.36, z, 0.02)
		body.slab(7.18, 7.92, 1.735, 1.755, 0.38, z, 0.008)
		for dz: float in [-0.2, 0.2]:
			dark.slab(7.9, 7.93, 1.64, 1.72, 0.03, z + dz, 0.006)
			steel.rod(Vector3(7.19, 1.748, z + dz), Vector3.BACK, 0.012, 0.1, 8)
	body.slab(6.85, 7.18, DECK_H, 1.75, 0.33, -1.32, 0.02)
	dark.openness = 0.3
	for i in 5:
		dark.slab(6.9 + i * 0.055, 6.93 + i * 0.055, 1.745, 1.755, 0.26, -1.32, 0.0)
	dark.openness = 1.0
	dark.rod(Vector3(7.22, 1.69, -1.55), Vector3.RIGHT, 0.05, 0.1, 10, 0.008)
	dark.openness = 0.1
	dark.rod(Vector3(7.271, 1.69, -1.55), Vector3.RIGHT, 0.032, 0.004, 8)
	dark.openness = 1.0
	for s: float in [-1.0, 1.0]:
		h.k(&"rubber").cbox(
			Vector3(7.88, 1.0, s * 1.46), Vector3(0.02, 0.26, 0.5), 0.005, Basis(Vector3.BACK, -0.1)
		)


# --- Turret -------------------------------------------------------------------------------------


## Main block behind the gun recess, the two armour cheeks ahead of it, the bustle; module seams
## and the shadowed gap under the bustle.
static func _turret(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var base := DECK_H + 0.05
	body.loft(
		[
			Vector2(2.3, -1.45),
			Vector2(2.75, -1.66),
			Vector2(5.0, -1.66),
			Vector2(5.0, 1.66),
			Vector2(2.75, 1.66),
			Vector2(2.3, 1.45)
		],
		[
			Vector2(2.4, -1.4),
			Vector2(2.85, -1.58),
			Vector2(5.0, -1.58),
			Vector2(5.0, 1.58),
			Vector2(2.85, 1.58),
			Vector2(2.4, 1.4)
		],
		base,
		ROOF_H,
		0.04
	)
	for s: float in [-1.0, 1.0]:
		var lo := [
			Vector2(1.85, s * 0.46),
			Vector2(1.85, s * 0.92),
			Vector2(2.75, s * 1.66),
			Vector2(3.0, s * 1.66),
			Vector2(3.0, s * 0.46)
		]
		var hi := [
			Vector2(2.08, s * 0.48),
			Vector2(2.08, s * 0.9),
			Vector2(2.85, s * 1.58),
			Vector2(3.0, s * 1.58),
			Vector2(3.0, s * 0.48)
		]
		body.loft(lo, hi, base, ROOF_H, 0.04)
		dark.openness = 0.3
		dark.cbox(
			Vector3(2.55, ROOF_H + 0.002, s * 1.05),
			Vector3(0.02, 0.006, 0.9),
			0.0,
			Basis(Vector3.UP, s * 0.7)
		)
		dark.openness = 1.0
	body.loft(
		[Vector2(4.95, -1.66), Vector2(6.35, -1.52), Vector2(6.35, 1.52), Vector2(4.95, 1.66)],
		[Vector2(4.95, -1.58), Vector2(6.3, -1.44), Vector2(6.3, 1.44), Vector2(4.95, 1.58)],
		1.8,
		ROOF_H,
		0.035
	)
	dark.openness = 0.15
	dark.slab(4.9, 6.3, 1.76, 1.81, 1.45, 0.0, 0.0)
	dark.openness = 1.0


## Gunner's primary sight doghouse, CITV, loader's hatch with the M240 and its shield, blowout
## panels, lifting eyes, met sensor mast and antenna stubs (all capped at ROOF_CAP).
static func _turret_roof(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var glass := t.k(&"glass")
	var steel := t.k(&"steel")
	var r := ROOF_H
	body.slab(2.55, 3.35, r - 0.02, ROOF_CAP, 0.21, 0.98, 0.03)
	body.slab(2.5, 2.58, r + 0.04, r + 0.25, 0.2, 0.98, 0.015)
	dark.openness = 0.4
	dark.slab(2.48, 2.51, r + 0.08, r + 0.21, 0.16, 0.98, 0.0)
	dark.openness = 1.0
	glass.slab(2.475, 2.49, r + 0.1, r + 0.19, 0.14, 0.98, 0.0)
	for z: float in [0.8, 1.16]:
		steel.rod(Vector3(2.52, r + 0.255, z), Vector3.RIGHT, 0.018, 0.12, 8)
	# CITV: pedestal, head, window, rain shield.
	dark.rod(Vector3(3.3, r + 0.06, -0.95), Vector3.UP, 0.15, 0.12, 18, 0.02)
	body.rod(Vector3(3.3, r + 0.19, -0.95), Vector3.UP, 0.13, 0.14, 18, 0.025)
	body.slab(3.1, 3.42, r + 0.12, r + 0.26, 0.13, -0.95, 0.025)
	glass.slab(3.085, 3.1, r + 0.15, r + 0.24, 0.1, -0.95, 0.0)
	body.slab(3.05, 3.2, r + 0.26, ROOF_CAP, 0.15, -0.95, 0.008)
	# Loader's hatch, LAGS shield, M240 on its skate mount.
	var lz := -0.82
	body.rod(Vector3(4.35, r + 0.04, lz), Vector3.UP, 0.42, 0.08, 20, 0.02)
	body.rod(Vector3(4.35, r + 0.1, lz), Vector3.UP, 0.33, 0.05, 20, 0.015)
	steel.tube(
		MeshKit.arc(Vector3(4.35, r + 0.135, lz), 0.12, Vector3.RIGHT, Vector3.BACK, -0.8, 0.8, 6),
		0.012,
		6
	)
	for a in 3:
		var ang := -0.55 + a * 0.55
		var dir := Vector3(-cos(ang), 0.0, sin(ang))
		body.cbox(
			Vector3(4.35, r + 0.15, lz) + dir * 0.36,
			Vector3(0.03, 0.24, 0.34),
			0.01,
			Basis(Vector3.UP, atan2(-dir.z, dir.x))
		)
	dark.slab(3.85, 4.05, r + 0.16, r + 0.24, 0.05, lz, 0.01)
	dark.rod(Vector3(3.55, r + 0.21, lz), Vector3.RIGHT, 0.022, 0.6, 8)
	dark.slab(3.95, 4.3, r + 0.18, r + 0.25, 0.04, lz, 0.008)
	dark.slab(3.98, 4.1, r + 0.1, r + 0.18, 0.07, lz - 0.08, 0.01)
	steel.rod(Vector3(4.05, r + 0.12, lz), Vector3.UP, 0.025, 0.14, 8)
	# Ammunition blowout panels on the bustle roof with raised frames and bolts.
	for s: float in [-1.0, 1.0]:
		var zc := s * 0.72
		dark.openness = 0.35
		dark.slab(5.1, 6.15, r - 0.005, r + 0.006, 0.6, zc, 0.0)
		dark.openness = 1.0
		body.slab(5.13, 6.12, r, r + 0.03, 0.57, zc, 0.01)
		for k in 6:
			for side: float in [-1.0, 1.0]:
				body.bolt(Vector3(5.2 + k * 0.17, r + 0.03, zc + side * 0.52), Vector3.UP, 0.016)
	for p: Vector3 in [
		Vector3(2.9, r, 1.42), Vector3(2.9, r, -1.42), Vector3(6.1, r, 1.32), Vector3(6.1, r, -1.32)
	]:
		dark.tube(MeshKit.arc(p, 0.06, Vector3.RIGHT, Vector3.UP, 0.0, PI, 8), 0.018, 6)
	# Met sensor mast and antenna stubs with spring bases.
	steel.tube([Vector3(6.0, r, 0.0), Vector3(6.0, r + 0.2, 0.0)], 0.018, 6)
	dark.rod(Vector3(6.0, r + 0.23, 0.0), Vector3.UP, 0.045, 0.06, 10, 0.01)
	for s: float in [-1.0, 1.0]:
		var base := Vector3(6.15, r, s * 1.2)
		dark.rod(base + Vector3(0, 0.05, 0), Vector3.UP, 0.07, 0.1, 10, 0.012)
		for k in 2:
			steel.rod(base + Vector3(0, 0.12 + k * 0.035, 0), Vector3.UP, 0.035, 0.025, 8)
		dark.tube([base + Vector3(0, 0.17, 0), Vector3(base.x, ROOF_CAP, base.z)], 0.012, 6)


## CROWS-LP remote weapon station on the commander's cupola (low profile, capped at ROOF_CAP):
## cupola ring with vision blocks, turntable, cradle, M2 with carrying handle, sight, ammo box.
static func _crows(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var glass := t.k(&"glass")
	var steel := t.k(&"steel")
	var r := ROOF_H
	var c := Vector3(4.3, r, 0.82)
	body.rod(c + Vector3(0, 0.04, 0), Vector3.UP, 0.48, 0.08, 20, 0.02)
	for k in 8:
		var a := PI * 0.6 + TAU * k / 10.0
		var dir := Vector3(cos(a), 0, sin(a))
		glass.cbox(
			c + dir * 0.475 + Vector3(0, 0.045, 0),
			Vector3(0.02, 0.04, 0.1),
			0.0,
			Basis(Vector3.UP, -a)
		)
	body.rod(c + Vector3(0, 0.1, 0), Vector3.UP, 0.36, 0.04, 20, 0.01)
	dark.rod(c + Vector3(0, 0.145, 0), Vector3.UP, 0.22, 0.05, 20, 0.015)
	dark.slab(4.05, 4.55, r + 0.15, r + 0.27, 0.04, 0.6, 0.012)
	dark.slab(4.05, 4.55, r + 0.15, r + 0.27, 0.04, 1.04, 0.012)
	dark.slab(3.95, 4.6, r + 0.17, r + 0.25, 0.08, 0.82, 0.015)
	steel.lathe(
		Vector3(3.95, r + 0.21, 0.82),
		Basis(Vector3.BACK, PI / 2.0),
		[
			Vector2(0.0, 1.0),
			Vector2(0.03, 1.0),
			Vector2(0.03, 0.9),
			Vector2(0.022, 0.88),
			Vector2(0.022, 0.1),
			Vector2(0.035, 0.08),
			Vector2(0.035, 0.0),
			Vector2(0.0, 0.0)
		],
		10
	)
	dark.tube(
		[
			Vector3(3.92, r + 0.235, 0.82),
			Vector3(3.88, r + 0.265, 0.82),
			Vector3(3.76, r + 0.265, 0.82),
			Vector3(3.72, r + 0.235, 0.82)
		],
		0.012,
		6
	)
	body.slab(3.92, 4.28, r + 0.13, ROOF_CAP, 0.1, 1.17, 0.025)
	glass.slab(3.905, 3.92, r + 0.17, r + 0.25, 0.075, 1.17, 0.0)
	dark.slab(4.12, 4.48, r + 0.12, r + 0.26, 0.11, 0.45, 0.02)
	steel.tube(
		[Vector3(4.2, r + 0.26, 0.45), Vector3(4.3, r + 0.27, 0.45), Vector3(4.4, r + 0.26, 0.45)],
		0.008,
		6
	)
	dark.tube(
		[Vector3(4.5, r + 0.2, 1.1), Vector3(4.62, r + 0.15, 1.05), Vector3(4.7, r + 0.08, 0.95)],
		0.014,
		6
	)


## Bustle rack (tubular rails and posts, slatted floor) with stowage: duffel bags and a rolled tarp
## in the faction cloth, ammo cans and a jerrycan, cargo straps.
static func _bustle(t: MeshKits) -> void:
	var dark := t.k(&"dark")
	var cloth := t.k(&"cloth")
	var steel := t.k(&"steel")
	var body := t.k(&"body")
	var x0 := 6.3
	var x1 := 7.18
	var hw := 1.48
	for hh: float in [2.04, 2.36]:
		steel.tube(
			[Vector3(x0, hh, -hw), Vector3(x1, hh, -hw), Vector3(x1, hh, hw), Vector3(x0, hh, hw)],
			0.022,
			6
		)
	for z: float in [-hw, -0.74, 0.0, 0.74, hw]:
		steel.tube([Vector3(x1, 1.82, z), Vector3(x1, 2.37, z)], 0.02, 6)
	for s: float in [-1.0, 1.0]:
		steel.tube([Vector3(6.75, 1.82, s * hw), Vector3(6.75, 2.37, s * hw)], 0.02, 6)
	dark.slab(x0, x1, 1.8, 1.83, 0.04, -hw, 0.008)
	dark.slab(x0, x1, 1.8, 1.83, 0.04, hw, 0.008)
	for k in 9:
		dark.slab(x0, x1, 1.8, 1.83, 0.02, -hw + k * (2.0 * hw / 8.0), 0.005)
	dark.slab(x1 - 0.03, x1 + 0.01, 1.78, 1.84, hw, 0.0, 0.008)
	cloth.pillow(Vector3(6.72, 2.03, -1.0), Vector3(0.75, 0.42, 0.85), Basis(Vector3.UP, 0.08))
	cloth.pillow(Vector3(6.7, 2.0, -0.15), Vector3(0.7, 0.36, 0.7), Basis(Vector3.UP, -0.05))
	cloth.pillow(
		Vector3(6.75, 2.33, -0.6),
		Vector3(0.6, 0.3, 0.7),
		Basis(Vector3(0.2, 1, 0.1).normalized(), 0.3)
	)
	cloth.lathe(
		Vector3(6.72, 2.04, 0.75),
		Basis(Vector3.RIGHT, PI / 2.0),
		[
			Vector2(0.0, 0.6),
			Vector2(0.16, 0.6),
			Vector2(0.19, 0.55),
			Vector2(0.2, 0.0),
			Vector2(0.19, -0.55),
			Vector2(0.16, -0.6),
			Vector2(0.0, -0.6)
		],
		14
	)
	for k in 3:
		dark.tube(
			MeshKit.arc(
				Vector3(6.47 + k * 0.25, 2.04, 0.75), 0.205, Vector3.UP, Vector3.LEFT, 0.0, TAU, 14
			),
			0.012,
			5
		)
	for k in 2:
		body.slab(6.4 + k * 0.32, 6.68 + k * 0.32, 1.83, 2.02, 0.09, 1.3, 0.012)
	body.slab(6.92, 7.12, 1.83, 2.3, 0.16, 1.28, 0.03)
	for x: float in [6.55, 6.9]:
		dark.tube(
			[
				Vector3(x, 1.83, -1.45),
				Vector3(x, 2.25, -1.42),
				Vector3(x, 2.5, -0.9),
				Vector3(x, 2.48, -0.3),
				Vector3(x, 2.2, 0.15),
				Vector3(x, 1.83, 0.2)
			],
			0.01,
			4
		)


## Bustle side stowage boxes (lids, hinges, latches, faction plate), M250 smoke grenade
## launchers, grab handles and tie rings along the turret sides.
static func _turret_sides(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var accent := t.k(&"accent")
	for s: float in [-1.0, 1.0]:
		var side_z := s * 1.66
		body.slab(4.98, 6.2, 1.86, 2.3, 0.08, s * 1.73, 0.025)
		body.slab(4.96, 6.22, 2.26, 2.32, 0.1, s * 1.74, 0.012)
		for x: float in [5.15, 6.05]:
			dark.slab(x - 0.04, x + 0.04, 2.12, 2.25, 0.015, s * 1.815, 0.004)
		for x: float in [5.1, 5.6, 6.1]:
			steel.rod(Vector3(x, 2.31, s * 1.65), Vector3.RIGHT, 0.015, 0.12, 8)
		accent.slab(5.3, 5.88, 1.96, 2.2, 0.006, s * 1.81, 0.003)
		body.slab(2.85, 3.45, 1.95, 2.3, 0.05, s * 1.62, 0.015)
		var dir := Vector3(-0.55, 0.35, s * 0.75).normalized()
		for i in 3:
			for row in 2:
				dark.lathe(
					Vector3(2.98 + i * 0.17 + row * 0.08, 2.06 + row * 0.13, s * 1.66),
					Frame.axis_basis(dir),
					[
						Vector2(0.0, 0.26),
						Vector2(0.035, 0.26),
						Vector2(0.035, 0.28),
						Vector2(0.048, 0.28),
						Vector2(0.048, 0.0)
					],
					8
				)
		for x: float in [3.3, 3.75, 4.2, 4.65]:
			steel.tube(
				[
					Vector3(x - 0.12, 2.18, side_z),
					Vector3(x - 0.1, 2.18, side_z + s * 0.07),
					Vector3(x + 0.1, 2.18, side_z + s * 0.07),
					Vector3(x + 0.12, 2.18, side_z)
				],
				0.013,
				6
			)
		for x: float in [3.2, 4.4]:
			dark.tube(
				MeshKit.arc(
					Vector3(x, 1.82, side_z + s * 0.01),
					0.04,
					Vector3.RIGHT,
					Vector3.DOWN,
					0.0,
					PI,
					6
				),
				0.012,
				5
			)


# --- Gun ----------------------------------------------------------------------------------------


## On `Turret/Gun`: gun shield in the turret recess with bolts, the canvas mantlet cover behind it,
## coaxial M240 port, ammunition data link box.
static func _gun_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var g := MeshKits.new(frame, to_gun)
	var body := g.k(&"body")
	var cloth := g.k(&"cloth")
	var dark := g.k(&"dark")
	body.slab(1.8, 2.35, 1.74, 2.24, 0.42, 0.0, 0.035)
	for z: float in [-0.3, 0.3]:
		for hh: float in [1.82, 2.16]:
			body.bolt(Vector3(1.8, hh, z), Vector3.LEFT, 0.022)
	cloth.cbox(Vector3(2.38, 1.99, 0.0), Vector3(0.12, 0.5, 0.86), 0.05)
	for k in 3:
		cloth.cbox(Vector3(2.32, 1.82 + k * 0.17, 0.0), Vector3(0.04, 0.05, 0.88), 0.02)
	dark.rod(Vector3(1.79, 1.9, 0.27), Vector3.RIGHT, 0.04, 0.04, 10, 0.008)
	dark.openness = 0.1
	dark.rod(Vector3(1.775, 1.9, 0.27), Vector3.RIGHT, 0.022, 0.01, 8)
	dark.openness = 1.0
	dark.slab(2.05, 2.3, 2.22, 2.3, 0.1, -0.22, 0.015)
	return g.commit_all()


## On `Turret/Gun/Barrel` (identity transform at the gun pivot; TASK-048 slides it back for the
## recoil): M256 barrel with thermal sleeve sections and clamp bands, muzzle lip, bore, muzzle
## reference sensor.
static func _barrel_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var b := MeshKits.new(frame, to_gun)
	var body := b.k(&"body")
	var dark := b.k(&"dark")
	var steel := b.k(&"steel")
	var length := TRUNNION.x + GUN_OVERHANG
	body.lathe(
		Vector3(TRUNNION.x, TRUNNION.y, 0.0),
		Basis(Vector3.BACK, PI / 2.0),
		[
			Vector2(0.0, length),
			Vector2(0.075, length),
			Vector2(0.075, length - 0.005),
			Vector2(0.1, length - 0.02),
			Vector2(0.1, length - 0.2),
			Vector2(0.09, length - 0.22),
			Vector2(0.094, length - 0.88),
			Vector2(0.11, length - 0.9),
			Vector2(0.112, length - 1.0),
			Vector2(0.098, length - 1.02),
			Vector2(0.103, length - 1.9),
			Vector2(0.12, length - 1.92),
			Vector2(0.122, length - 2.04),
			Vector2(0.108, length - 2.06),
			Vector2(0.118, 1.0),
			Vector2(0.13, 0.98),
			Vector2(0.13, 0.5),
			Vector2(0.0, 0.5)
		],
		20
	)
	dark.openness = 0.05
	dark.rod(Vector3(-GUN_OVERHANG + 0.002, TRUNNION.y, 0.0), Vector3.RIGHT, 0.065, 0.01, 16)
	dark.openness = 1.0
	for x: float in [-GUN_OVERHANG + 0.55, -GUN_OVERHANG + 1.45, 0.3]:
		steel.rod(Vector3(x, TRUNNION.y, 0.0), Vector3.RIGHT, 0.118, 0.03, 20, 0.005)
	var y := TRUNNION.y
	dark.slab(-GUN_OVERHANG + 0.12, -GUN_OVERHANG + 0.3, y + 0.1, y + 0.16, 0.045, 0.0, 0.01)
	dark.slab(-GUN_OVERHANG + 0.25, -GUN_OVERHANG + 0.28, y + 0.08, y + 0.12, 0.03, 0.0, 0.0)
	return b.commit_all()
