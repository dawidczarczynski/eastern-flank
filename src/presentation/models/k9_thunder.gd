## K9 Thunder (Polish K9PL): South Korean 155 mm / 52 cal. self-propelled howitzer. Blueprint:
## docs/design/units/units/k9_thunder/blueprint.md. Measurements are metres (vehicle_frame.gd):
## `x` from the hull nose (0) to the rear plate, `h` above the ground, `z` across (positive =
## vehicle's right). Turret at 12 o'clock, gun level.
##
## Built with MeshKit like the T-72B3: chamfered parts, bolts, hinges, individual track shoes. The
## running gear has no skirts (the top run of the track shows), the drive sprocket is at the front
## (front power pack) and the idler at the rear. The geometry does not depend on the faction, so it
## is generated once (ModelParts.cached_meshes) and only the materials differ.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {
	"wheels": {},
	"turret_traverse": {"traverse_deg": "full", "elevation_deg": [-8, 20]},
	"gun_recoil": {"recoil_m": 0.5},
}
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/tracked_running_gear.gd")

const HULL_LENGTH := 7.44
## Rear plate of the hull body (the track and idler reach HULL_LENGTH).
const REAR_X := 7.1
## The gun protrudes this far beyond the hull nose, the rear basket this far behind HULL_LENGTH
## (overall 12.0 m).
const GUN_OVERHANG := 4.06
const REAR_OVERHANG := 0.5
## Model units per metre: 12.0 m -> 0.876 (x unit scale 1.3 = 1.139, budget 1.15).
const K := 0.073
## Hull: deck height, glacis top (x), nose top height, sponson bottom, half widths.
const DECK_H := 1.82
const GLACIS_X := 2.5
const NOSE_H := 1.47
const SPONSON_H := 1.2
const UPPER_HW := 1.65
const LOWER_HW := 1.08
## Turret ring centre (x) on the deck; turret box floor / roof heights, floor and roof plan.
const TURRET_X := 5.2
const TURRET_FLOOR := 1.88
const ROOF_H := 2.72
const TURRET_FRONT := 3.24
const TURRET_ROOF_FRONT := 3.7
const TURRET_REAR := 7.54
const TURRET_HW := 1.5
const TURRET_ROOF_HW := 1.36
## Gun trunnions (x, h).
const TRUNNION := Vector2(3.94, 2.22)
## Recoil sleeve: front end (x) and radius.
const SLEEVE_FRONT := 0.15
const SLEEVE_R := 0.17


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var frame := vehicle_frame()
	var m := Frame.kit_tank_materials(faction)
	var spec := running_gear()
	Gear.add_pivots(g, frame, spec, m)
	var hull := ModelParts.cached_meshes(
		"k9_thunder:hull", func() -> Dictionary: return _hull_meshes(frame, spec)
	)
	MeshKits.add_meshes(g, hull, m)
	_anchors(g, frame, spec)
	var turret := frame.add_turret(g, TURRET_X, DECK_H)
	var to_turret := Frame.to_local(turret)
	var shell := ModelParts.cached_meshes(
		"k9_thunder:turret", func() -> Dictionary: return _turret_meshes(frame, to_turret)
	)
	MeshKits.add_meshes(turret, shell, m)
	var gun := frame.add_gun(turret, TRUNNION, -GUN_OVERHANG - 0.05)
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	gun.add_child(barrel)
	var to_gun := Frame.to_local(gun)
	var gun_meshes := ModelParts.cached_meshes(
		"k9_thunder:gun", func() -> Dictionary: return _gun_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(gun, gun_meshes, m)
	var barrel_meshes := ModelParts.cached_meshes(
		"k9_thunder:barrel", func() -> Dictionary: return _barrel_meshes(frame, to_gun)
	)
	MeshKits.add_meshes(barrel, barrel_meshes, m)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## Metres -> model space: K model units per metre, muzzle to rear basket centred on x = 0.
static func vehicle_frame() -> Frame:
	return Frame.new(K, (HULL_LENGTH + REAR_OVERHANG - GUN_OVERHANG) / 2.0)


## The K9 running gear: 6 dual rubber-tyred road wheels (0.68 m) per side, 3 return rollers,
## front drive sprocket, rear idler, steel track with rubber pads; no skirts.
static func running_gear() -> Gear.Spec:
	var spec := Gear.Spec.new()
	spec.key = "k9_thunder"
	spec.road_wheel_x = [1.57, 2.47, 3.34, 4.24, 5.12, 5.99]
	spec.road_wheel_radius = 0.34
	spec.road_wheel_h = 0.42
	spec.wheel_width = 0.48
	spec.return_roller_x = [2.0, 3.8, 5.55]
	spec.return_roller_h = 0.98
	spec.return_roller_radius = 0.09
	spec.sprocket_x = 0.6
	spec.sprocket_h = 0.72
	spec.sprocket_radius = 0.33
	spec.sprocket_teeth = 11
	spec.idler_x = 6.99
	spec.idler_h = 0.74
	spec.idler_radius = 0.3
	spec.idler_arm_dir = -1.0
	spec.track_z = 1.375
	spec.track_width = 0.55
	spec.track_thickness = 0.08
	spec.skirt_panels = 0
	spec.detailed_wheels = true
	spec.wheel_sides = 14
	spec.wheel_bolts = 6
	spec.sprocket_bolts = 6
	spec.track_shoe_pitch = 0.2
	spec.track_pads = true
	return spec


## Effect anchors for MotionFx: the exhaust grille on the right hull side by the engine, dust
## under the rear idlers.
static func _anchors(g: Node3D, frame: Frame, spec: Gear.Spec) -> void:
	var at := {
		"Exhaust": frame.p(1.5, 1.62, UPPER_HW + 0.04),
		"Dust_L": frame.p(spec.idler_x, 0.02, -spec.track_z),
		"Dust_R": frame.p(spec.idler_x, 0.02, spec.track_z),
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
	_glacis(hull)
	_sides(hull)
	_rear(hull)
	return hull.commit_all()


static func _turret_meshes(frame: Frame, to_turret: Transform3D) -> Dictionary:
	var t := MeshKits.new(frame, to_turret)
	_turret_box(t)
	_cupola(t)
	_roof(t)
	_turret_sides(t)
	_basket(t)
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


## Upper hull over the tracks (vertical nose, long shallow glacis, flat deck) and the lower hull
## between the tracks (raked lower front plate, flat belly, short rear slope), fender lips over
## the track, lifting eyes on the deck corners.
static func _hull(h: MeshKits) -> void:
	var body := h.k(&"body")
	var upper := [
		Vector2(0.0, 1.35),
		Vector2(0.0, NOSE_H),
		Vector2(GLACIS_X, DECK_H),
		Vector2(REAR_X, DECK_H),
		Vector2(REAR_X, SPONSON_H),
		Vector2(0.45, SPONSON_H)
	]
	body.profile(upper, UPPER_HW, 0.0, 0.03)
	var lower := [
		Vector2(0.05, 1.36),
		Vector2(0.65, 0.45),
		Vector2(6.85, 0.42),
		Vector2(REAR_X, 0.65),
		Vector2(REAR_X, 1.36)
	]
	body.profile(lower, LOWER_HW, 0.0, 0.03)
	var dark := h.k(&"dark")
	for s: float in [-1.0, 1.0]:
		# Fender lip along the sponson bottom edge, over the track.
		body.slab(0.5, REAR_X - 0.02, SPONSON_H - 0.03, SPONSON_H + 0.02, 0.05, s * 1.62, 0.01)
		for x: float in [0.4, 6.9]:
			var c := Vector3(x, _deck_h(x) - 0.01, s * 1.5)
			dark.tube(MeshKit.arc(c, 0.06, Vector3.RIGHT, Vector3.UP, 0.0, PI, 8), 0.018, 6)


## Nose: headlights with guards on the front corners, tow hooks and bolts on the lower front plate.
static func _front(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	for s: float in [-1.0, 1.0]:
		var z := s * 1.38
		var lamp_h := _deck_h(0.25)
		body.slab(0.12, 0.38, lamp_h - 0.02, lamp_h + 0.1, 0.11, z, 0.015)
		dark.rod(Vector3(0.14, lamp_h + 0.05, z), Vector3.RIGHT, 0.065, 0.06, 12, 0.01)
		h.k(&"lens").rod(Vector3(0.105, lamp_h + 0.05, z), Vector3.RIGHT, 0.052, 0.01, 12)
		var guard := [
			Vector3(0.3, lamp_h + 0.1, z - 0.12),
			Vector3(0.06, lamp_h + 0.12, z - 0.12),
			Vector3(0.06, lamp_h + 0.12, z + 0.12),
			Vector3(0.3, lamp_h + 0.1, z + 0.12)
		]
		steel.tube(guard, 0.012, 5)
		# Tow hook on the lower front plate.
		dark.slab(0.2, 0.36, 0.95, 1.1, 0.09, s * 0.72, 0.015)
		var hook := MeshKit.arc(
			Vector3(0.2, 1.02, s * 0.72),
			0.07,
			Vector3.UP,
			Vector3(-1, -0.6, 0).normalized(),
			-PI * 0.5,
			PI * 0.5,
			10
		)
		steel.tube(hook, 0.026, 8)
	for i in 7:
		var bx := 0.1
		body.bolt(Vector3(bx, 1.28, -0.9 + i * 0.3), Vector3(-0.83, -0.55, 0.0), 0.022)


## Glacis and front deck: driver's hatch with periscopes (front left), louvred engine grilles
## (front right), the travel lock folded flat, access plates between glacis and turret.
static func _glacis(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var glass := h.k(&"glass")
	var lay := _on_glacis()
	var up := _glacis_up()
	# Driver's hatch.
	var dz := -0.95
	var dx := 1.5
	var hatch := Vector3(dx, _deck_h(dx), dz)
	body.rod(hatch + up * 0.03, up, 0.33, 0.06, 20, 0.015)
	body.rod(hatch + up * 0.075, up, 0.26, 0.035, 18, 0.01)
	steel.tube(
		MeshKit.arc(hatch + up * 0.1, 0.11, Vector3.RIGHT, Vector3.BACK, -0.9, 0.9, 6), 0.012
	)
	for i in 3:
		var a := (i - 1) * 0.5
		var p := hatch + Vector3(-0.42 * cos(a), 0.0, 0.42 * sin(a))
		p.y = _deck_h(p.x)
		body.cbox(p + up * 0.04, Vector3(0.1, 0.08, 0.16), 0.01, lay * Basis(Vector3.UP, a))
		glass.cbox(p + up * 0.05 + lay * Vector3(-0.05, 0, 0), Vector3(0.01, 0.04, 0.12), 0.0, lay)
	# Engine grilles on the right: two louvred panels in raised frames.
	for x0: float in [0.75, 1.55]:
		var xm := x0 + 0.35
		var c := Vector3(xm, _deck_h(xm), 0.9)
		body.cbox(c + up * 0.015, Vector3(0.74, 0.03, 1.08), 0.008, lay)
		dark.openness = 0.25
		dark.cbox(c + up * 0.03, Vector3(0.64, 0.01, 0.98), 0.0, lay)
		dark.openness = 1.0
		for i in 6:
			var lx := x0 + 0.08 + i * 0.105
			var louvre := Vector3(lx, _deck_h(lx) + 0.04, 0.9)
			dark.cbox(louvre, Vector3(0.035, 0.03, 0.96), 0.0, lay * Basis(Vector3.BACK, 0.45))
	# Travel lock folded back on the glacis: two arms from the nose hinge, a cross bar with the
	# barrel clamp.
	var hinge_x := 0.25
	var top_x := 1.2
	for s: float in [-1.0, 1.0]:
		dark.slab(
			hinge_x - 0.08,
			hinge_x + 0.08,
			_deck_h(hinge_x),
			_deck_h(hinge_x) + 0.1,
			0.05,
			s * 0.28,
			0.01
		)
		var arm := [
			Vector3(hinge_x, _deck_h(hinge_x) + 0.07, s * 0.28),
			Vector3(top_x, _deck_h(top_x) + 0.07, s * 0.2)
		]
		steel.tube(arm, 0.035, 8)
	var bar := Vector3(top_x, _deck_h(top_x) + 0.07, 0.0)
	steel.tube([bar - Vector3(0, 0, 0.24), bar + Vector3(0, 0, 0.24)], 0.035, 8)
	dark.cbox(bar + up * 0.05, Vector3(0.16, 0.1, 0.24), 0.015, lay)
	# Access plates on the front deck, in front of the turret.
	for z: float in [-0.75, 0.75]:
		body.slab(2.55, 3.15, DECK_H, DECK_H + 0.02, 0.5, z, 0.006)
		for bx: float in [2.6, 3.1]:
			for bz: float in [-0.42, 0.42]:
				body.bolt(Vector3(bx, DECK_H + 0.02, z + bz), Vector3.UP, 0.016)


## Hull sides: faction plate (where the K9PL carries the flag), exhaust grille on the right by the
## engine, grab handles.
static func _sides(h: MeshKits) -> void:
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	h.k(&"accent").pair(2.05, 2.6, 1.42, 1.68, 0.012, UPPER_HW, 0.006)
	var ez := UPPER_HW + 0.01
	dark.slab(1.0, 1.95, 1.38, 1.74, 0.02, ez, 0.006)
	dark.openness = 0.2
	dark.slab(1.04, 1.91, 1.42, 1.7, 0.02, ez + 0.006, 0.0)
	dark.openness = 1.0
	for i in 8:
		var x := 1.08 + i * 0.105
		dark.cbox(
			Vector3(x, 1.56, ez + 0.03), Vector3(0.03, 0.28, 0.035), 0.0, Basis(Vector3.UP, 0.5)
		)
	for s: float in [-1.0, 1.0]:
		for x: float in [3.6, 6.4]:
			var z := s * (UPPER_HW + 0.005)
			var grip := [
				Vector3(x - 0.15, 1.62, z),
				Vector3(x - 0.13, 1.62, z + s * 0.06),
				Vector3(x + 0.13, 1.62, z + s * 0.06),
				Vector3(x + 0.15, 1.62, z)
			]
			steel.tube(grip, 0.014, 6)


## Rear plate: the large ammunition resupply door (frame, hinges, handle, vision block), tail
## lights with guards, tow hooks.
static func _rear(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var x := REAR_X
	dark.openness = 0.35
	dark.slab(x - 0.01, x + 0.015, 0.62, 1.7, 0.6, 0.0, 0.004)
	dark.openness = 1.0
	body.slab(x - 0.01, x + 0.05, 0.65, 1.67, 0.56, 0.0, 0.015)
	for hh: float in [0.8, 1.5]:
		steel.rod(Vector3(x + 0.05, hh, 0.58), Vector3.UP, 0.035, 0.16, 8, 0.006)
		dark.slab(x + 0.03, x + 0.06, hh - 0.05, hh + 0.05, 0.12, 0.47, 0.006)
	var handle := [
		Vector3(x + 0.05, 1.15, -0.45),
		Vector3(x + 0.11, 1.15, -0.43),
		Vector3(x + 0.11, 1.3, -0.43),
		Vector3(x + 0.05, 1.3, -0.45)
	]
	steel.tube(handle, 0.014, 6)
	body.slab(x + 0.04, x + 0.1, 1.38, 1.52, 0.1, -0.1, 0.01)
	h.k(&"glass").slab(x + 0.1, x + 0.11, 1.41, 1.49, 0.08, -0.1, 0.0)
	for s: float in [-1.0, 1.0]:
		var lz := s * 1.38
		body.slab(x - 0.02, x + 0.07, 1.48, 1.64, 0.11, lz, 0.015)
		h.k(&"red_lens").slab(x + 0.07, x + 0.08, 1.57, 1.62, 0.07, lz, 0.0)
		h.k(&"lens").slab(x + 0.07, x + 0.08, 1.5, 1.55, 0.07, lz, 0.0)
		var guard := [
			Vector3(x, 1.66, lz - 0.13),
			Vector3(x + 0.13, 1.66, lz - 0.13),
			Vector3(x + 0.13, 1.66, lz + 0.13),
			Vector3(x, 1.66, lz + 0.13)
		]
		steel.tube(guard, 0.011, 5)
		dark.slab(x - 0.02, x + 0.1, 0.62, 0.78, 0.08, s * 0.82, 0.015)
		var hook := MeshKit.arc(
			Vector3(x + 0.12, 0.7, s * 0.82), 0.065, Vector3.UP, Vector3.RIGHT, 0.0, PI * 1.3, 8
		)
		steel.tube(hook, 0.024, 8)


# --- Turret -------------------------------------------------------------------------------------


## z of the turret side face at height hh on side s (the walls lean in towards the roof).
static func _side_face(s: float, hh: float) -> float:
	var t := (hh - TURRET_FLOOR) / (ROOF_H - TURRET_FLOOR)
	return s * lerpf(TURRET_HW, TURRET_ROOF_HW, t)


## The big welded box: a tapered loft with the front corners chamfered and the front face raked
## back, the dark turret ring gap under it, a roof edge band, the gun port in the front face.
static func _turret_box(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var bottom := [
		Vector2(TURRET_FRONT, -0.55),
		Vector2(3.95, -TURRET_HW),
		Vector2(TURRET_REAR, -TURRET_HW),
		Vector2(TURRET_REAR, TURRET_HW),
		Vector2(3.95, TURRET_HW),
		Vector2(TURRET_FRONT, 0.55)
	]
	var top := [
		Vector2(TURRET_ROOF_FRONT, -0.5),
		Vector2(4.25, -TURRET_ROOF_HW),
		Vector2(TURRET_REAR - 0.04, -TURRET_ROOF_HW),
		Vector2(TURRET_REAR - 0.04, TURRET_ROOF_HW),
		Vector2(4.25, TURRET_ROOF_HW),
		Vector2(TURRET_ROOF_FRONT, 0.5)
	]
	body.loft(bottom, top, TURRET_FLOOR, ROOF_H, 0.03)
	dark.openness = 0.2
	dark.rod(Vector3(TURRET_X, DECK_H + 0.03, 0.0), Vector3.UP, 1.2, 0.06, 28, 0.006)
	dark.openness = 1.0
	# Gun port: dark recess around the mantlet.
	dark.openness = 0.15
	var face_x := TURRET_FRONT + (TURRET_ROOF_FRONT - TURRET_FRONT) * 0.4
	dark.slab(face_x - 0.06, face_x + 0.02, 1.96, 2.5, 0.42, 0.0, 0.0)
	dark.openness = 1.0


## Commander's cupola on the right rear roof: ring with vision blocks, hatch lid with hinge, the
## K6 12.7 mm machine gun on its mount with ammo box.
static func _cupola(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var glass := t.k(&"glass")
	var c := Vector3(6.55, 0.0, 0.72)
	body.rod(Vector3(c.x, ROOF_H + 0.06, c.z), Vector3.UP, 0.4, 0.12, 24, 0.02)
	body.rod(Vector3(c.x + 0.03, ROOF_H + 0.145, c.z), Vector3.UP, 0.32, 0.05, 20, 0.012)
	steel.rod(Vector3(c.x + 0.34, ROOF_H + 0.15, c.z), Vector3.BACK, 0.03, 0.2, 8)
	for k in 5:
		var ang := PI + (k - 2) * 0.5
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var block := Vector3(c.x, ROOF_H + 0.07, c.z) + dir * 0.4
		glass.cbox(block, Vector3(0.02, 0.05, 0.11), 0.0, Basis(Vector3.UP, -ang))
	# K6 on a pintle ahead of the cupola: cradle, receiver, barrel with flash hider, ammo box.
	var mx := c.x - 0.45
	var mh := ROOF_H + 0.3
	dark.rod(Vector3(mx, ROOF_H + 0.1, c.z), Vector3.UP, 0.045, 0.2, 8, 0.008)
	dark.slab(mx - 0.15, mx + 0.25, mh - 0.06, mh + 0.06, 0.06, c.z, 0.012)
	var k6 := [
		Vector2(0.0, 1.15),
		Vector2(0.026, 1.15),
		Vector2(0.026, 1.05),
		Vector2(0.018, 1.03),
		Vector2(0.016, 0.15),
		Vector2(0.03, 0.13),
		Vector2(0.03, 0.0),
		Vector2(0.0, 0.0)
	]
	steel.lathe(Vector3(mx - 0.15, mh, c.z), Frame.axis_basis(Vector3.LEFT), k6, 8)
	body.slab(mx - 0.05, mx + 0.2, mh - 0.18, mh - 0.04, 0.08, c.z + 0.16, 0.015)
	dark.slab(mx + 0.1, mx + 0.28, mh + 0.06, mh + 0.12, 0.03, c.z, 0.006)


## Roof: gunner's hatch (right front), loader's hatch (left), panoramic sight head (left front),
## lifting eyes, antenna bases with whips at the rear corners, roof plate bolts.
static func _roof(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var glass := t.k(&"glass")
	for p: Vector3 in [Vector3(5.35, 0.0, 0.62), Vector3(6.35, 0.0, -0.78)]:
		body.rod(Vector3(p.x, ROOF_H + 0.02, p.z), Vector3.UP, 0.33, 0.04, 20, 0.008)
		body.rod(Vector3(p.x, ROOF_H + 0.055, p.z), Vector3.UP, 0.28, 0.04, 18, 0.01)
		steel.rod(Vector3(p.x + 0.3, ROOF_H + 0.06, p.z), Vector3.BACK, 0.025, 0.18, 8)
		var grip := MeshKit.arc(
			Vector3(p.x, ROOF_H + 0.075, p.z), 0.1, Vector3.RIGHT, Vector3.BACK, -0.9, 0.9, 6
		)
		steel.tube(grip, 0.012, 6)
	# Gunner's periscope ahead of his hatch.
	body.slab(4.85, 5.0, ROOF_H, ROOF_H + 0.14, 0.12, 0.62, 0.015)
	glass.slab(4.84, 4.85, ROOF_H + 0.05, ROOF_H + 0.12, 0.09, 0.62, 0.0)
	# Panoramic sight: armoured base, round head, window facing forward.
	var sz := -0.72
	body.slab(4.15, 4.55, ROOF_H, ROOF_H + 0.12, 0.17, sz, 0.02)
	body.rod(Vector3(4.33, ROOF_H + 0.24, sz), Vector3.UP, 0.15, 0.2, 16, 0.02)
	dark.rod(Vector3(4.33, ROOF_H + 0.35, sz), Vector3.UP, 0.13, 0.03, 16, 0.006)
	glass.slab(4.17, 4.19, ROOF_H + 0.19, ROOF_H + 0.3, 0.08, sz, 0.0)
	# Lifting eyes on the roof corners.
	for p: Vector2 in [
		Vector2(4.4, -1.2), Vector2(4.4, 1.2), Vector2(7.3, -1.2), Vector2(7.3, 1.2)
	]:
		var e := MeshKit.arc(Vector3(p.x, ROOF_H, p.y), 0.06, Vector3.RIGHT, Vector3.UP, 0.0, PI, 8)
		dark.tube(e, 0.018, 6)
	# Antenna bases at the rear corners; a tall whip on the left, a short one on the right.
	for s: float in [-1.0, 1.0]:
		var a := Vector3(7.2, ROOF_H, s * 1.12)
		dark.rod(a + Vector3(0, 0.05, 0), Vector3.UP, 0.07, 0.1, 10, 0.012)
		dark.rod(a + Vector3(0, 0.16, 0), Vector3.UP, 0.035, 0.12, 8, 0.006)
		var tip := 1.9 if s < 0.0 else 1.1
		steel.tube([a + Vector3(0, 0.2, 0), a + Vector3(0.02, tip, 0)], 0.016, 5)
	# Bolted roof plate over the breech.
	body.slab(4.6, 5.6, ROOF_H, ROOF_H + 0.02, 0.32, -0.15, 0.006)
	for bx: float in [4.66, 5.1, 5.54]:
		for bz: float in [-0.42, 0.12]:
			body.bolt(Vector3(bx, ROOF_H + 0.02, bz), Vector3.UP, 0.016)


## Turret walls: the side door on the left (frame seam, hinges, handle), smoke grenade launchers
## at the front corners, grab rails, the direct-fire sight box on the front face.
static func _turret_sides(t: MeshKits) -> void:
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var lean := atan2(TURRET_HW - TURRET_ROOF_HW, ROOF_H - TURRET_FLOOR)
	# Side door, left wall.
	var s := -1.0
	var rot := Basis(Vector3.RIGHT, -s * lean)
	var dh := 2.3
	dark.openness = 0.3
	dark.cbox(Vector3(5.85, dh, _side_face(s, dh)), Vector3(1.06, 0.66, 0.02), 0.0, rot)
	dark.openness = 1.0
	body.cbox(Vector3(5.85, dh, _side_face(s, dh) + s * 0.015), Vector3(1.0, 0.6, 0.03), 0.008, rot)
	for hh: float in [2.08, 2.52]:
		steel.rod(Vector3(6.37, hh, _side_face(s, hh) + s * 0.02), Vector3.UP, 0.03, 0.12, 8)
	var hz := _side_face(s, 2.3) + s * 0.03
	steel.tube(
		[
			Vector3(5.45, 2.24, hz),
			Vector3(5.43, 2.24, hz + s * 0.05),
			Vector3(5.43, 2.38, hz + s * 0.05),
			Vector3(5.45, 2.38, hz)
		],
		0.013,
		6
	)
	# Grab rails along both walls under the roof edge.
	for side: float in [-1.0, 1.0]:
		var rz := _side_face(side, 2.6) + side * 0.005
		var x0 := 4.6 if side > 0.0 else 6.55
		var x1 := 7.2
		steel.tube(
			[
				Vector3(x0, 2.6, rz),
				Vector3(x0 + 0.03, 2.6, rz + side * 0.06),
				Vector3(x1 - 0.03, 2.6, rz + side * 0.06),
				Vector3(x1, 2.6, rz)
			],
			0.014,
			6
		)
		# Smoke grenade launchers on a bracket at the front corner, aimed forward, up and out.
		var bz := _side_face(side, 2.35) + side * 0.03
		dark.slab(4.05, 4.65, 2.3, 2.34, 0.06, bz, 0.008)
		var aim := Frame.axis_basis(Vector3(-0.55, 0.5, side * 0.4))
		var tube := [
			Vector2(0.0, 0.26),
			Vector2(0.034, 0.26),
			Vector2(0.034, 0.28),
			Vector2(0.048, 0.28),
			Vector2(0.048, 0.0),
			Vector2(0.0, 0.0)
		]
		for i in 4:
			dark.lathe(Vector3(4.12 + i * 0.15, 2.36, bz), aim, tube, 6)
	# Direct-fire sight box on the left of the front face.
	body.slab(3.45, 3.78, 2.45, 2.64, 0.13, -0.38, 0.015)
	t.k(&"glass").slab(3.44, 3.45, 2.5, 2.6, 0.1, -0.38, 0.0)


## Stowage basket on the turret rear: dark floor, steel tube frame with uprights, bracket arms.
static func _basket(t: MeshKits) -> void:
	var dark := t.k(&"dark")
	var steel := t.k(&"steel")
	var x0 := TURRET_REAR
	var x1 := TURRET_REAR + REAR_OVERHANG - 0.02
	var hw := 1.15
	dark.slab(x0, x1, 2.0, 2.04, hw, 0.0, 0.008)
	for hh: float in [2.3, 2.58]:
		steel.tube(
			[Vector3(x0, hh, -hw), Vector3(x1, hh, -hw), Vector3(x1, hh, hw), Vector3(x0, hh, hw)],
			0.018,
			5
		)
	for i in 7:
		var z := -hw + i * hw * 2.0 / 6.0
		steel.tube([Vector3(x1, 2.04, z), Vector3(x1, 2.58, z)], 0.014, 5)
	for s: float in [-1.0, 1.0]:
		steel.tube([Vector3(x0, 2.04, s * hw), Vector3(x0 + 0.2, 2.58, s * hw)], 0.014, 5)
		steel.tube([Vector3(x1, 2.04, s * hw), Vector3(x1, 2.58, s * hw)], 0.014, 5)
	# Stowed kit in the basket: a tarp roll and two boxes.
	t.k(&"body").pillow(
		Vector3(x0 + 0.22, 2.2, -0.45), Vector3(0.34, 0.3, 1.0), Basis.IDENTITY, 0.6, 6, 8
	)
	dark.slab(x0 + 0.06, x0 + 0.4, 2.04, 2.32, 0.25, 0.55, 0.02)


# --- Gun ----------------------------------------------------------------------------------------


## On `Turret/Gun`: the box mantlet with its bolted face and the long dark cradle / recoil sleeve
## out to the hull nose with a collar at its front end.
static func _gun_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var g := MeshKits.new(frame, to_gun)
	var body := g.k(&"body")
	var dark := g.k(&"dark")
	var axis := TRUNNION.y
	body.slab(3.0, 3.5, axis - 0.24, axis + 0.24, 0.36, 0.0, 0.03)
	for bz: float in [-0.28, 0.28]:
		for bh: float in [-0.17, 0.17]:
			body.bolt(Vector3(3.0, axis + bh, bz), Vector3.LEFT, 0.02)
	var sleeve_rear := 3.05
	var length := sleeve_rear - SLEEVE_FRONT
	var mid := Vector3((sleeve_rear + SLEEVE_FRONT) / 2.0, axis, 0.0)
	dark.rod(mid, Vector3.RIGHT, SLEEVE_R, length, 16, 0.02)
	dark.rod(Vector3(2.9, axis, 0.0), Vector3.RIGHT, SLEEVE_R + 0.04, 0.16, 16, 0.015)
	g.k(&"steel").rod(
		Vector3(SLEEVE_FRONT + 0.06, axis, 0.0), Vector3.RIGHT, SLEEVE_R + 0.025, 0.1, 16, 0.01
	)
	return g.commit_all()


## On `Turret/Gun/Barrel` (identity at the gun pivot; slides back for the recoil): the 52-calibre
## barrel (radius tapering to the muzzle), the bore evacuator, the double-baffle muzzle brake and
## the dark bore.
static func _barrel_meshes(frame: Frame, to_gun: Transform3D) -> Dictionary:
	var b := MeshKits.new(frame, to_gun)
	var length := TRUNNION.x + GUN_OVERHANG  # trunnion to muzzle
	var evac := TRUNNION.x + 0.26  # evacuator rear end (x 0.26 ahead of the hull nose)
	var prof := [
		Vector2(0.0, length),
		Vector2(0.11, length),
		Vector2(0.19, length - 0.03),
		Vector2(0.19, length - 0.12),
		Vector2(0.13, length - 0.13),
		Vector2(0.13, length - 0.21),
		Vector2(0.19, length - 0.22),
		Vector2(0.19, length - 0.31),
		Vector2(0.13, length - 0.32),
		Vector2(0.13, length - 0.4),
		Vector2(0.19, length - 0.41),
		Vector2(0.19, length - 0.52),
		Vector2(0.15, length - 0.57),
		Vector2(0.15, length - 0.68),
		Vector2(0.112, length - 0.72),
		Vector2(0.118, evac + 0.72),
		Vector2(0.2, evac + 0.64),
		Vector2(0.2, evac + 0.08),
		Vector2(0.125, evac),
		Vector2(0.128, 0.6),
		Vector2(0.0, 0.6)
	]
	var root := Vector3(TRUNNION.x, TRUNNION.y, 0.0)
	b.k(&"body").lathe(root, Frame.axis_basis(Vector3.LEFT), prof, 16)
	var dark := b.k(&"dark")
	dark.openness = 0.1
	for groove: float in [0.17, 0.36]:
		# Side ports between the brake baffles (dark so the slots read at a distance).
		dark.rod(root - Vector3(length - groove, 0, 0), Vector3.RIGHT, 0.14, 0.08, 16)
	dark.rod(Vector3(-GUN_OVERHANG + 0.004, TRUNNION.y, 0.0), Vector3.RIGHT, 0.078, 0.01, 16, 0.003)
	dark.openness = 1.0
	b.k(&"steel").rod(root - Vector3(evac + 0.74, 0, 0), Vector3.RIGHT, 0.124, 0.05, 16, 0.006)
	return b.commit_all()
