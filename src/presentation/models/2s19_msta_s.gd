## 2S19 Msta-S: Soviet / Russian 152 mm / 47 cal. self-propelled howitzer on a T-80-family
## chassis. Blueprint: docs/design/units/units/2s19_msta_s/blueprint.md. Measurements are metres
## (vehicle_frame.gd): `x` from the hull nose (0) to the rear, `h` above the ground, `z` across
## (positive = vehicle's right). Turret at 12 o'clock, gun level.
##
## Built with MeshKit like the K9 Thunder: chamfered parts, individual track shoes, kit wheels.
## The big flat-sided turret sits at the rear of the hull, the drive sprocket is at the rear and the
## idler at the front (T-80 running gear, 6 road wheels per side). Constants from the reference
## GLB's measurements.json, widths scaled to the catalog's 3.38 m. The geometry does not depend on
## the faction, so it is generated once (ModelParts.cached_meshes) and only the materials differ.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {
	"wheels": {},
	"turret_traverse": {"traverse_deg": "full", "elevation_deg": [-4, 68]},
	"gun_recoil": {"recoil_m": 0.5},
}
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/tracked_running_gear.gd")

## Rear plate of the hull; the unditching log on the rear reaches REAR_X + REAR_OVERHANG.
const REAR_X := 7.15
const REAR_OVERHANG := 0.45
## The level gun protrudes this far beyond the hull nose (overall 12.0 m).
const GUN_OVERHANG := 4.4
## Model units per metre: 12.0 m -> 0.876 (x unit scale 1.3 = 1.139, budget 1.15).
const K := 0.073
## Hull: deck height, glacis top (x), nose top height, sponson bottom, half widths.
const DECK_H := 1.63
const GLACIS_X := 1.2
const NOSE_H := 1.12
const SPONSON_H := 0.98
const UPPER_HW := 1.66
const LOWER_HW := 1.05
## Turret ring centre (x) on the deck; turret box floor / roof heights, floor and roof plan.
const TURRET_X := 4.1
const TURRET_FLOOR := 1.72
const ROOF_H := 3.0
const TURRET_FRONT := 2.05
const TURRET_ROOF_FRONT := 2.5
const TURRET_REAR := 6.15
const TURRET_HW := 1.56
const TURRET_ROOF_HW := 1.42
## Gun trunnions (x, h).
const TRUNNION := Vector2(2.85, 2.45)
## Cradle / recoil sleeve: front end (x) and radius.
const SLEEVE_FRONT := 0.95
const SLEEVE_R := 0.2


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var frame := vehicle_frame()
	var m := Frame.kit_tank_materials(faction)
	var spec := running_gear()
	Gear.add_pivots(g, frame, spec, m)
	var hull := ModelParts.cached_meshes(
		"2s19_msta_s:hull", func() -> Dictionary: return _hull_meshes(frame, spec)
	)
	MeshKits.add_meshes(g, hull, m)
	_anchors(g, frame, spec)
	var turret := frame.add_turret(g, TURRET_X, DECK_H)
	var to_turret := Frame.to_local(turret)
	var shell := ModelParts.cached_meshes(
		"2s19_msta_s:turret", func() -> Dictionary: return _turret_meshes(frame, to_turret)
	)
	MeshKits.add_meshes(turret, shell, m)
	var gun := frame.add_gun(turret, TRUNNION, -GUN_OVERHANG - 0.05)
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	gun.add_child(barrel)
	var to_gun := Frame.to_local(gun)
	var gun_meshes := ModelParts.cached_meshes(
		"2s19_msta_s:gun", func() -> Dictionary: return _gun_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(gun, gun_meshes, m)
	var barrel_meshes := ModelParts.cached_meshes(
		"2s19_msta_s:barrel", func() -> Dictionary: return _barrel_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(barrel, barrel_meshes, m)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## Metres -> model space: K model units per metre, muzzle to rear log centred on x = 0.
static func vehicle_frame() -> Frame:
	return Frame.new(K, (REAR_X + REAR_OVERHANG - GUN_OVERHANG) / 2.0)


## The T-80 running gear: 6 rubber-tyred road wheels (0.67 m) per side with the gap between the
## 2nd and 3rd, 5 return rollers, front idler, rear drive sprocket, all-steel track; no skirts
## (the hull side comes down over the top run).
static func running_gear() -> Gear.Spec:
	var spec := Gear.Spec.new()
	spec.key = "2s19_msta_s"
	spec.road_wheel_x = [1.29, 2.19, 3.34, 4.2, 4.9, 5.71]
	spec.road_wheel_radius = 0.33
	spec.road_wheel_h = 0.41
	spec.wheel_width = 0.46
	spec.return_roller_x = [1.75, 2.75, 3.78, 4.55, 5.3]
	spec.return_roller_h = 0.72
	spec.return_roller_radius = 0.08
	spec.sprocket_x = 6.55
	spec.sprocket_h = 0.72
	spec.sprocket_radius = 0.31
	spec.sprocket_teeth = 12
	spec.idler_x = 0.45
	spec.idler_h = 0.7
	spec.idler_radius = 0.27
	spec.idler_arm_dir = 1.0
	spec.track_z = 1.36
	spec.track_width = 0.56
	spec.track_thickness = 0.08
	spec.skirt_panels = 0
	spec.detailed_wheels = true
	spec.wheel_sides = 14
	spec.wheel_bolts = 6
	spec.sprocket_bolts = 8
	spec.track_shoe_pitch = 0.17
	spec.track_pads = false
	return spec


## Effect anchors for MotionFx: the exhaust louvres on the rear plate, dust under the sprockets.
static func _anchors(g: Node3D, frame: Frame, spec: Gear.Spec) -> void:
	var at := {
		"Exhaust": frame.p(REAR_X + 0.04, 1.35, 0.0),
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
	_deck(hull)
	_sides(hull)
	_rear(hull)
	return hull.commit_all()


static func _turret_meshes(frame: Frame, to_turret: Transform3D) -> Dictionary:
	var t := MeshKits.new(frame, to_turret)
	_turret_box(t)
	_cupola(t)
	_roof(t)
	_turret_sides(t)
	_conveyor(t)
	return t.commit_all()


## Height of the glacis / deck at x.
static func _deck_h(x: float) -> float:
	if x >= GLACIS_X:
		return DECK_H
	return NOSE_H + (DECK_H - NOSE_H) * maxf(x, 0.0) / GLACIS_X


## Basis that lays a part flat on the glacis (its local x along the slope).
static func _on_glacis() -> Basis:
	return Basis(Vector3.BACK, atan2(DECK_H - NOSE_H, GLACIS_X))


## Outward normal of the glacis (vehicle axes).
static func _glacis_up() -> Vector3:
	return _on_glacis() * Vector3.UP


# --- Hull ---------------------------------------------------------------------------------------


## Upper hull over the tracks (short nose, long sloped glacis, flat deck dropping at the rear) and
## the lower hull between the tracks (raked lower front plate, flat belly, rear slope); fender
## lips over the track.
static func _hull(h: MeshKits) -> void:
	var body := h.k(&"body")
	var upper := [
		Vector2(0.02, SPONSON_H),
		Vector2(0.0, NOSE_H),
		Vector2(GLACIS_X, DECK_H),
		Vector2(6.9, DECK_H),
		Vector2(REAR_X, 1.5),
		Vector2(REAR_X, SPONSON_H)
	]
	body.profile(upper, UPPER_HW, 0.0, 0.03)
	var lower := [
		Vector2(0.06, 1.05),
		Vector2(0.85, 0.42),
		Vector2(6.85, 0.42),
		Vector2(REAR_X - 0.05, 0.72),
		Vector2(REAR_X - 0.05, 1.1)
	]
	body.profile(lower, LOWER_HW, 0.0, 0.03)
	var dark := h.k(&"dark")
	for s: float in [-1.0, 1.0]:
		# Fender lip along the sponson bottom edge, over the track.
		body.slab(0.1, REAR_X - 0.05, SPONSON_H - 0.03, SPONSON_H + 0.03, 0.04, s * 1.64, 0.01)
		# Dark rubber flap strip under the fender lip, between the wheels and the hull side.
		dark.slab(0.6, 6.7, SPONSON_H - 0.1, SPONSON_H - 0.03, 0.015, s * 1.65, 0.0)


## Nose: V-shaped splash board on the glacis, headlights with guards, tow hooks and bolts on the
## lower front plate, the folded travel lock.
static func _front(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var lay := _on_glacis()
	var up := _glacis_up()
	# Splash board: two low plates in a V on the glacis.
	for s: float in [-1.0, 1.0]:
		var c := Vector3(0.55, _deck_h(0.55), s * 0.55)
		body.cbox(c + up * 0.05, Vector3(0.05, 0.1, 1.1), 0.01, lay * Basis(Vector3.UP, s * 0.35))
	for s: float in [-1.0, 1.0]:
		var z := s * 1.38
		var lamp_h := _deck_h(0.3)
		body.slab(0.2, 0.42, lamp_h - 0.02, lamp_h + 0.1, 0.1, z, 0.015)
		dark.rod(Vector3(0.2, lamp_h + 0.05, z), Vector3.RIGHT, 0.06, 0.05, 12, 0.01)
		h.k(&"lens").rod(Vector3(0.17, lamp_h + 0.05, z), Vector3.RIGHT, 0.048, 0.01, 12)
		# Tow hook on the lower front plate.
		dark.slab(0.18, 0.32, 0.86, 1.0, 0.09, s * 0.62, 0.015)
		var hook := MeshKit.arc(
			Vector3(0.17, 0.93, s * 0.62),
			0.07,
			Vector3.UP,
			Vector3(-1, -0.6, 0).normalized(),
			-PI * 0.5,
			PI * 0.5,
			10
		)
		steel.tube(hook, 0.026, 8)
	for i in 6:
		body.bolt(Vector3(0.12, 1.0, -0.75 + i * 0.3), Vector3(-0.78, -0.62, 0.0), 0.022)
	# Travel lock folded back on the glacis: A-frame from the nose hinge, the barrel clamp on top.
	var hinge_x := 0.2
	var top_x := 1.0
	for s: float in [-1.0, 1.0]:
		dark.slab(
			hinge_x - 0.07,
			hinge_x + 0.07,
			_deck_h(hinge_x),
			_deck_h(hinge_x) + 0.09,
			0.05,
			s * 0.4,
			0.01
		)
		var arm := [
			Vector3(hinge_x, _deck_h(hinge_x) + 0.06, s * 0.4),
			Vector3(top_x, _deck_h(top_x) + 0.07, s * 0.12)
		]
		steel.tube(arm, 0.035, 8)
	dark.cbox(Vector3(top_x, _deck_h(top_x) + 0.1, 0.0), Vector3(0.18, 0.12, 0.3), 0.015, lay)


## Glacis and deck: the driver's hatch with periscopes low at the front left, access plates and the
## engine deck louvres behind the turret (kept under the turret floor inside its sweep).
static func _deck(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var glass := h.k(&"glass")
	var lay := _on_glacis()
	var up := _glacis_up()
	# Driver's hatch, front left.
	var dz := -0.62
	var dx := 0.95
	var hatch := Vector3(dx, _deck_h(dx), dz)
	body.rod(hatch + up * 0.025, up, 0.3, 0.05, 20, 0.012)
	body.rod(hatch + up * 0.06, up, 0.24, 0.03, 18, 0.01)
	steel.tube(
		MeshKit.arc(hatch + up * 0.08, 0.1, Vector3.RIGHT, Vector3.BACK, -0.9, 0.9, 6), 0.012
	)
	for i in 3:
		var a := (i - 1) * 0.45
		var p := hatch + Vector3(-0.36 * cos(a), 0.0, 0.36 * sin(a))
		p.y = _deck_h(p.x)
		body.cbox(p + up * 0.035, Vector3(0.09, 0.07, 0.15), 0.01, lay * Basis(Vector3.UP, a))
		glass.cbox(
			p + up * 0.045 + lay * Vector3(-0.046, 0, 0), Vector3(0.01, 0.035, 0.11), 0.0, lay
		)
	# Front deck access plate on the right.
	body.slab(1.3, 1.95, DECK_H, DECK_H + 0.02, 0.4, 0.75, 0.006)
	for bx: float in [1.36, 1.89]:
		for bz: float in [0.42, 1.08]:
			body.bolt(Vector3(bx, DECK_H + 0.02, bz), Vector3.UP, 0.016)
	# Engine deck behind the turret: two louvred grilles in raised frames, a centre access plate.
	for z: float in [-0.85, 0.85]:
		body.slab(6.2, 6.85, DECK_H, DECK_H + 0.03, 0.55, z, 0.008)
		dark.openness = 0.25
		dark.slab(6.25, 6.8, DECK_H + 0.03, DECK_H + 0.04, 0.5, z, 0.0)
		dark.openness = 1.0
		for i in 5:
			var lx := 6.3 + i * 0.11
			dark.cbox(
				Vector3(lx, DECK_H + 0.05, z),
				Vector3(0.035, 0.03, 0.98),
				0.0,
				Basis(Vector3.BACK, 0.45)
			)
	body.slab(6.25, 6.85, DECK_H, DECK_H + 0.02, 0.22, 0.0, 0.006)


## Hull sides: the faction plate, stowage bins on the fenders ahead of the turret, grab handles.
static func _sides(h: MeshKits) -> void:
	var body := h.k(&"body")
	var steel := h.k(&"steel")
	h.k(&"accent").pair(2.6, 3.3, 1.15, 1.5, 0.012, UPPER_HW, 0.006)
	for s: float in [-1.0, 1.0]:
		# Long low stowage bins along the deck edge (below the turret floor).
		body.slab(1.25, 2.6, DECK_H, DECK_H + 0.07, 0.12, s * 1.52, 0.012)
		body.slab(6.25, 6.95, DECK_H, DECK_H + 0.07, 0.12, s * 1.52, 0.012)
		for x: float in [3.8, 5.6]:
			var z := s * (UPPER_HW + 0.005)
			var grip := [
				Vector3(x - 0.14, 1.45, z),
				Vector3(x - 0.12, 1.45, z + s * 0.05),
				Vector3(x + 0.12, 1.45, z + s * 0.05),
				Vector3(x + 0.14, 1.45, z)
			]
			steel.tube(grip, 0.014, 6)


## Rear plate: exhaust louvres, tail lights, tow hooks and the unditching log on its brackets.
static func _rear(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var x := REAR_X
	dark.openness = 0.3
	dark.slab(x - 0.01, x + 0.02, 1.2, 1.45, 0.75, 0.0, 0.004)
	dark.openness = 1.0
	for i in 4:
		dark.slab(x, x + 0.05, 1.22 + i * 0.065, 1.25 + i * 0.065, 0.74, 0.0, 0.0)
	for s: float in [-1.0, 1.0]:
		var lz := s * 1.4
		body.slab(x - 0.02, x + 0.07, 1.3, 1.44, 0.1, lz, 0.015)
		h.k(&"red_lens").slab(x + 0.07, x + 0.08, 1.34, 1.4, 0.07, lz, 0.0)
		dark.slab(x - 0.06, x + 0.08, 0.66, 0.8, 0.08, s * 0.8, 0.015)
		var hook := MeshKit.arc(
			Vector3(x + 0.1, 0.72, s * 0.8), 0.06, Vector3.UP, Vector3.RIGHT, 0.0, PI * 1.3, 8
		)
		steel.tube(hook, 0.022, 8)
		# Log brackets.
		dark.slab(x - 0.02, x + 0.32, 1.08, 1.16, 0.05, s * 1.1, 0.01)
	var log_x := x + REAR_OVERHANG - 0.15
	h.k(&"rubber").rod(Vector3(log_x, 1.25, 0.0), Vector3.BACK, 0.15, 2.9, 10, 0.03)
	for s: float in [-1.0, 1.0]:
		steel.rod(Vector3(log_x, 1.25, s * 1.1), Vector3.BACK, 0.16, 0.05, 10)


# --- Turret -------------------------------------------------------------------------------------


## z of the turret side face at height hh on side s (the walls lean in towards the roof).
static func _side_face(s: float, hh: float) -> float:
	var t := (hh - TURRET_FLOOR) / (ROOF_H - TURRET_FLOOR)
	return s * lerpf(TURRET_HW, TURRET_ROOF_HW, t)


## x of the raked turret front face at height hh.
static func _front_face(hh: float) -> float:
	var t := (hh - TURRET_FLOOR) / (ROOF_H - TURRET_FLOOR)
	return lerpf(TURRET_FRONT, TURRET_ROOF_FRONT, t)


## The big welded box: a tapered loft with the front corners chamfered and the front face raked
## back, the dark turret ring gap under it, the gun port in the front face.
static func _turret_box(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var bottom := [
		Vector2(TURRET_FRONT, -0.85),
		Vector2(TURRET_FRONT + 0.5, -TURRET_HW),
		Vector2(TURRET_REAR, -TURRET_HW),
		Vector2(TURRET_REAR, TURRET_HW),
		Vector2(TURRET_FRONT + 0.5, TURRET_HW),
		Vector2(TURRET_FRONT, 0.85)
	]
	var top := [
		Vector2(TURRET_ROOF_FRONT, -0.75),
		Vector2(TURRET_ROOF_FRONT + 0.5, -TURRET_ROOF_HW),
		Vector2(TURRET_REAR - 0.05, -TURRET_ROOF_HW),
		Vector2(TURRET_REAR - 0.05, TURRET_ROOF_HW),
		Vector2(TURRET_ROOF_FRONT + 0.5, TURRET_ROOF_HW),
		Vector2(TURRET_ROOF_FRONT, 0.75)
	]
	body.loft(bottom, top, TURRET_FLOOR, ROOF_H, 0.04)
	dark.openness = 0.2
	dark.rod(Vector3(TURRET_X, DECK_H + 0.045, 0.0), Vector3.UP, 1.3, 0.09, 28, 0.006)
	dark.openness = 1.0
	# Gun port: dark recess around the mantlet.
	dark.openness = 0.15
	var fx := _front_face(TRUNNION.y)
	dark.slab(fx - 0.06, fx + 0.03, TRUNNION.y - 0.36, TRUNNION.y + 0.36, 0.48, 0.0, 0.0)
	dark.openness = 1.0


## Commander's cupola on the right of the roof with the remote 12.7 mm NSVT: ring with vision
## blocks, hatch, the gun cradle on a round mount, ammunition box.
static func _cupola(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var glass := t.k(&"glass")
	var c := Vector3(3.95, 0.0, 0.25)
	body.rod(Vector3(c.x, ROOF_H + 0.07, c.z), Vector3.UP, 0.42, 0.14, 24, 0.02)
	body.rod(Vector3(c.x + 0.05, ROOF_H + 0.17, c.z), Vector3.UP, 0.32, 0.06, 20, 0.012)
	for k in 6:
		var ang := PI + (k - 2.5) * 0.45
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var block := Vector3(c.x, ROOF_H + 0.08, c.z) + dir * 0.42
		glass.cbox(block, Vector3(0.02, 0.05, 0.11), 0.0, Basis(Vector3.UP, -ang))
	# NSVT on a pedestal ahead of the hatch: mount drum, cradle, receiver, barrel, ammo box.
	var mx := c.x - 0.15
	var mh := ROOF_H + 0.62
	dark.rod(Vector3(mx, ROOF_H + 0.36, c.z), Vector3.UP, 0.12, 0.32, 12, 0.01)
	body.rod(Vector3(mx, mh, c.z + 0.18), Vector3.BACK, 0.13, 0.08, 14, 0.012)
	dark.slab(mx - 0.2, mx + 0.3, mh - 0.07, mh + 0.07, 0.07, c.z, 0.012)
	var nsvt := [
		Vector2(0.0, 1.5),
		Vector2(0.03, 1.5),
		Vector2(0.03, 1.38),
		Vector2(0.02, 1.36),
		Vector2(0.02, 0.2),
		Vector2(0.035, 0.18),
		Vector2(0.035, 0.0),
		Vector2(0.0, 0.0)
	]
	steel.lathe(Vector3(mx - 0.2, mh + 0.02, c.z), Frame.axis_basis(Vector3.LEFT), nsvt, 8)
	body.slab(mx - 0.05, mx + 0.22, mh - 0.22, mh - 0.06, 0.08, c.z - 0.17, 0.015)


## Roof: loader's hatch (left), the gunner's sight head (left front), vent dome, antenna base with
## a short whip, roof plate bolts, lifting eyes.
static func _roof(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var glass := t.k(&"glass")
	var hatch := Vector3(4.85, 0.0, -0.45)
	body.rod(Vector3(hatch.x, ROOF_H + 0.02, hatch.z), Vector3.UP, 0.36, 0.04, 20, 0.008)
	body.rod(Vector3(hatch.x, ROOF_H + 0.06, hatch.z), Vector3.UP, 0.3, 0.05, 18, 0.01)
	steel.rod(Vector3(hatch.x + 0.32, ROOF_H + 0.07, hatch.z), Vector3.BACK, 0.025, 0.2, 8)
	# Gunner's sight head: armoured base, round head, window facing forward.
	var sz := -0.95
	body.slab(3.0, 3.45, ROOF_H, ROOF_H + 0.14, 0.18, sz, 0.02)
	body.rod(Vector3(3.22, ROOF_H + 0.27, sz), Vector3.UP, 0.15, 0.22, 16, 0.02)
	dark.rod(Vector3(3.22, ROOF_H + 0.39, sz), Vector3.UP, 0.13, 0.03, 16, 0.006)
	glass.slab(3.06, 3.08, ROOF_H + 0.21, ROOF_H + 0.33, 0.08, sz, 0.0)
	# Vent dome and a small periscope box.
	body.rod(Vector3(5.2, ROOF_H + 0.06, 0.55), Vector3.UP, 0.17, 0.12, 14, 0.03)
	body.slab(2.95, 3.15, ROOF_H, ROOF_H + 0.12, 0.12, 0.3, 0.015)
	glass.slab(2.94, 2.95, ROOF_H + 0.04, ROOF_H + 0.1, 0.09, 0.3, 0.0)
	# Antenna base on the right of the roof with a short whip (the reference's 4 m mast is left out).
	var a := Vector3(4.65, ROOF_H, 0.75)
	dark.rod(a + Vector3(0, 0.06, 0), Vector3.UP, 0.07, 0.12, 10, 0.012)
	steel.tube([a + Vector3(0, 0.12, 0), a + Vector3(0.03, 1.1, 0)], 0.015, 5)
	# Bolted roof plate over the breech.
	body.slab(3.6, 4.5, ROOF_H, ROOF_H + 0.02, 0.36, -0.2, 0.006)
	for bx: float in [3.66, 4.05, 4.44]:
		for bz: float in [-0.5, 0.1]:
			body.bolt(Vector3(bx, ROOF_H + 0.02, bz), Vector3.UP, 0.016)
	for p: Vector2 in [
		Vector2(3.1, -1.25), Vector2(3.1, 1.25), Vector2(5.95, -1.25), Vector2(5.95, 1.25)
	]:
		var e := MeshKit.arc(Vector3(p.x, ROOF_H, p.y), 0.06, Vector3.RIGHT, Vector3.UP, 0.0, PI, 8)
		dark.tube(e, 0.018, 6)


## Turret walls: the left side door, grab rails, the smoke grenade launchers on the front corners,
## the direct-fire sight box on the front face.
static func _turret_sides(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var lean := atan2(TURRET_HW - TURRET_ROOF_HW, ROOF_H - TURRET_FLOOR)
	# Side door, left wall.
	var s := -1.0
	var rot := Basis(Vector3.RIGHT, -s * lean)
	var dh := 2.35
	dark.openness = 0.3
	dark.cbox(Vector3(4.9, dh, _side_face(s, dh)), Vector3(0.96, 0.74, 0.02), 0.0, rot)
	dark.openness = 1.0
	body.cbox(Vector3(4.9, dh, _side_face(s, dh) + s * 0.015), Vector3(0.9, 0.68, 0.03), 0.008, rot)
	for hh: float in [2.12, 2.58]:
		steel.rod(Vector3(5.38, hh, _side_face(s, hh) + s * 0.02), Vector3.UP, 0.03, 0.12, 8)
	for side: float in [-1.0, 1.0]:
		# Grab rail along the wall under the roof edge.
		var rz := _side_face(side, 2.75) + side * 0.005
		var x0 := 3.2
		var x1 := 4.4 if side < 0.0 else 5.9
		steel.tube(
			[
				Vector3(x0, 2.75, rz),
				Vector3(x0 + 0.03, 2.75, rz + side * 0.06),
				Vector3(x1 - 0.03, 2.75, rz + side * 0.06),
				Vector3(x1, 2.75, rz)
			],
			0.014,
			6
		)
		# Smoke grenade launchers (902V): a bracket on the front corner, 6 tubes aimed forward-up.
		var bz := _side_face(side, 2.55) + side * 0.03
		dark.slab(2.65, 3.45, 2.5, 2.54, 0.06, bz, 0.008)
		var aim := Frame.axis_basis(Vector3(-0.6, 0.55, side * 0.3))
		var tube := [
			Vector2(0.0, 0.26),
			Vector2(0.034, 0.26),
			Vector2(0.034, 0.28),
			Vector2(0.048, 0.28),
			Vector2(0.048, 0.0),
			Vector2(0.0, 0.0)
		]
		for i in 6:
			dark.lathe(Vector3(2.72 + i * 0.13, 2.56, bz), aim, tube, 6)
		# Faction plate on the turret side.
		var plate_h := 2.25
		t.k(&"accent").cbox(
			Vector3(3.5, plate_h, _side_face(side, plate_h) + side * 0.008),
			Vector3(0.5, 0.3, 0.012),
			0.0,
			Basis(Vector3.RIGHT, -side * lean)
		)
	# Direct-fire sight box on the left of the front face.
	var sh := 2.75
	body.slab(_front_face(sh) - 0.15, _front_face(sh) + 0.2, sh - 0.1, sh + 0.1, 0.13, -0.62, 0.015)
	t.k(&"glass").slab(
		_front_face(sh) - 0.16, _front_face(sh) - 0.15, sh - 0.06, sh + 0.06, 0.1, -0.62, 0.0
	)


## The folded ammunition conveyor on the turret rear: two side rails slanting down to the engine
## deck, rungs, a dark belt plate between them, the hinge bracket at the roof edge.
static func _conveyor(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var zc := 0.15
	var hw := 0.5
	var top := Vector3(5.85, 3.2, 0.0)
	var low := Vector3(7.0, 2.25, 0.0)
	var rail := [Vector2(5.7, 3.45), Vector2(7.15, 2.55), Vector2(6.9, 1.95), Vector2(5.95, 3.0)]
	for s: float in [-1.0, 1.0]:
		body.plate(
			rail,
			Vector3(0, 0, zc + s * hw),
			Vector3.RIGHT,
			Vector3.UP,
			Vector3.BACK,
			-0.04,
			0.04,
			0.01
		)
	dark.openness = 0.4
	dark.plate(
		[Vector2(5.85, 3.3), Vector2(7.0, 2.55), Vector2(6.85, 2.05), Vector2(6.0, 3.05)],
		Vector3(0, 0, zc),
		Vector3.RIGHT,
		Vector3.UP,
		Vector3.BACK,
		-hw + 0.04,
		hw - 0.04,
		0.0
	)
	dark.openness = 1.0
	for i in 6:
		var p := top.lerp(low, (i + 0.5) / 6.0)
		steel.rod(Vector3(p.x + 0.08, p.y + 0.06, zc), Vector3.BACK, 0.025, hw * 2.0, 6)
	# Hinge bracket on the turret rear and the support strut down to the bustle.
	dark.slab(TURRET_REAR - 0.1, TURRET_REAR + 0.05, ROOF_H - 0.2, ROOF_H, hw, zc, 0.01)
	for s: float in [-1.0, 1.0]:
		steel.tube(
			[
				Vector3(TURRET_REAR, 2.0, zc + s * (hw - 0.1)),
				Vector3(6.75, 2.45, zc + s * (hw - 0.1))
			],
			0.03,
			6
		)


# --- Gun ----------------------------------------------------------------------------------------


## On `Turret/Gun`: the box mantlet with its bolted face, the cradle / recoil sleeve out ahead of
## the turret and the recoil cylinders above it.
static func _gun_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var g := MeshKits.new(frame, to_gun)
	var body := g.k(&"body")
	var steel := g.k(&"steel")
	var axis := TRUNNION.y
	var face := _front_face(axis)
	body.slab(face - 0.35, face + 0.25, axis - 0.32, axis + 0.34, 0.42, 0.0, 0.04)
	for bz: float in [-0.32, 0.32]:
		for bh: float in [-0.22, 0.24]:
			body.bolt(Vector3(face - 0.35, axis + bh, bz), Vector3.LEFT, 0.02)
	var sleeve_rear := face - 0.3
	var length := sleeve_rear - SLEEVE_FRONT
	var mid := Vector3((sleeve_rear + SLEEVE_FRONT) / 2.0, axis, 0.0)
	body.rod(mid, Vector3.RIGHT, SLEEVE_R, length, 16, 0.02)
	steel.rod(
		Vector3(SLEEVE_FRONT + 0.05, axis, 0.0), Vector3.RIGHT, SLEEVE_R + 0.025, 0.1, 16, 0.01
	)
	# Recoil cylinders above the sleeve.
	var cyl_front := SLEEVE_FRONT - 0.05
	var cyl_mid := Vector3((sleeve_rear + cyl_front) / 2.0, axis + 0.3, 0.0)
	for s: float in [-1.0, 1.0]:
		body.rod(
			cyl_mid + Vector3(0, 0, s * 0.1),
			Vector3.RIGHT,
			0.09,
			sleeve_rear - cyl_front,
			12,
			0.015
		)
		steel.rod(Vector3(cyl_front + 0.03, axis + 0.3, s * 0.1), Vector3.RIGHT, 0.06, 0.06, 10)
	body.slab(cyl_front + 0.1, cyl_front + 0.3, axis + 0.1, axis + 0.24, 0.12, 0.0, 0.01)
	return g.commit_all()


## On `Turret/Gun/Barrel` (identity at the gun pivot; slides back for the recoil): the 47-calibre
## barrel, the fume extractor at mid-length, the multi-baffle muzzle brake with dark ports and the
## dark bore.
static func _barrel_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var b := MeshKits.new(frame, to_gun)
	var length := TRUNNION.x + GUN_OVERHANG  # trunnion to muzzle
	var ext0 := TRUNNION.x + 1.06  # fume extractor rear end (1.06 m ahead of the hull nose)
	var ext1 := TRUNNION.x + 1.99
	var brake := 0.62
	var prof := [
		Vector2(0.0, length),
		Vector2(0.1, length),
		Vector2(0.175, length - 0.03),
		Vector2(0.175, length - 0.09),
		Vector2(0.13, length - 0.1),
		Vector2(0.13, length - 0.17),
		Vector2(0.175, length - 0.18),
		Vector2(0.175, length - 0.26),
		Vector2(0.13, length - 0.27),
		Vector2(0.13, length - 0.34),
		Vector2(0.175, length - 0.35),
		Vector2(0.175, length - 0.43),
		Vector2(0.13, length - 0.44),
		Vector2(0.13, length - 0.51),
		Vector2(0.175, length - 0.52),
		Vector2(0.175, length - brake + 0.03),
		Vector2(0.12, length - brake - 0.02),
		Vector2(0.118, ext1 + 0.08),
		Vector2(0.17, ext1),
		Vector2(0.17, ext0 + 0.04),
		Vector2(0.13, ext0),
		Vector2(0.14, TRUNNION.x + 0.15),
		Vector2(0.155, TRUNNION.x + 0.08),
		Vector2(0.17, 0.4),
		Vector2(0.0, 0.4)
	]
	var root := Vector3(TRUNNION.x, TRUNNION.y, 0.0)
	b.k(&"body").lathe(root, Frame.axis_basis(Vector3.LEFT), prof, 16)
	var dark := b.k(&"dark")
	dark.openness = 0.1
	for groove: float in [0.135, 0.305, 0.475]:
		# Ports between the brake baffles (dark so the slots read at a distance).
		dark.rod(root - Vector3(length - groove, 0, 0), Vector3.RIGHT, 0.14, 0.065, 16)
	dark.rod(Vector3(-GUN_OVERHANG + 0.004, TRUNNION.y, 0.0), Vector3.RIGHT, 0.076, 0.01, 16, 0.003)
	dark.openness = 1.0
	b.k(&"steel").rod(root - Vector3(TRUNNION.x + 0.12, 0, 0), Vector3.RIGHT, 0.15, 0.06, 16, 0.008)
	return b.commit_all()
