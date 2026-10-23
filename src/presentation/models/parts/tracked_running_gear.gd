extends RefCounted
## Shared tracked running gear for the tank / IFV models (TASK-031): per side a track loop with
## grousers around the wheels, double road wheels with rubber tyres, return rollers, a rear drive
## sprocket, a front idler and deep skirt panels with a faction plate. Everything is described by
## a `Spec` in vehicle metres (see vehicle_frame.gd), so the next tank is mostly parameters:
##
##   var spec := TrackedRunningGear.Spec.new()
##   spec.key = "t72b3"
##   spec.road_wheel_x = [...]
##   TrackedRunningGear.build(model, frame, spec, materials)
##
## Road wheels, idlers and sprockets are "Wheel<i>" pivots spinning about their local Z
## (UnitModels.pose_tank); track, rollers and skirts are merged meshes (4 body mesh instances).
##
## Kit detail (TASK-069, opt-in per Spec option, off by default): `detailed_wheels`,
## `track_shoe_pitch` and `detailed_skirts` build those parts with MeshKit instead (chamfers, bolts,
## individual shoes, vertex masks for the paint) and cut what the camera never sees (inner wheel
## halves as plain drums, no shoes on the top run behind the skirts). A model that builds its hull
## with MeshKits calls `add_pivots` and `add_hull_parts(kits, spec)` itself (the hull parts then
## share the model's mesh instances); `build` does both on its own kits otherwise.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")


## All lengths in metres, `x` from the hull front backwards, `h` above the ground.
class Spec:
	extends RefCounted
	## Prefix of the cached mesh keys: must be unique per vehicle (the meshes depend on the spec).
	var key := "tracked"
	var road_wheel_x: Array[float] = []
	var road_wheel_radius := 0.32
	## Wheel centre height (radius + track thickness for a wheel resting on the track).
	var road_wheel_h := 0.4
	var wheel_width := 0.6
	## Rubber tyre bands on the road wheels (false = steel-rimmed wheels).
	var rubber_tyres := true
	var return_roller_x: Array[float] = []
	var return_roller_h := 0.98
	var return_roller_radius := 0.1
	var sprocket_x := 7.3
	var sprocket_h := 0.75
	var sprocket_radius := 0.36
	var sprocket_teeth := 11
	var idler_x := 0.6
	var idler_h := 0.7
	var idler_radius := 0.3
	## Track centre |z|, width, plate thickness, grouser pitch and height.
	var track_z := 1.43
	var track_width := 0.63
	var track_thickness := 0.08
	var grouser_spacing := 0.25
	var grouser_height := 0.04
	## Skirt: x range, bottom/top height, outer face |z|, panel count; the first
	## `skirt_front_panels` panels are thicker (armoured); `skirt_front_rake` cuts the front-bottom
	## corner of the first panel back (m). No skirts when skirt_panels is 0.
	var skirt_x0 := 0.15
	var skirt_x1 := 7.0
	var skirt_h0 := 0.6
	var skirt_h1 := 1.22
	var skirt_z := 1.85
	var skirt_panels := 7
	var skirt_front_panels := 2
	var skirt_thickness := 0.05
	var skirt_front_thickness := 0.12
	var skirt_front_rake := 0.35
	## Lowers the front end of the first panel's top edge by this much (m), sloping back to
	## `skirt_h1` over `skirt_front_top_run` m (a skirt following a low glacis, e.g. the T-72).
	## No slope when 0.
	var skirt_front_top_drop := 0.0
	var skirt_front_top_run := 0.4
	## Cuts the rear-bottom corner of the last panel: the bottom edge rises by `skirt_rear_rise`
	## over the last `skirt_rear_rake` metres (e.g. the T-72's skirt slanting up over the
	## sprocket). No cut when skirt_rear_rake is 0.
	var skirt_rear_rake := 0.0
	var skirt_rear_rise := 0.0
	## Bottom edge polyline (Vector2(x, h), front to rear) that replaces `skirt_h0` from its first
	## point backwards, e.g. the T-72's skirt rising gently and then curving up at the rear plate;
	## before its first point the bottom stays at `skirt_h0`, behind its last point at its last
	## height. Empty = straight bottom (and the rear rake, if set).
	var skirt_bottom_profile: Array[Vector2] = []
	## Height (m) of a dark rubber strip along the panels' bottom edges (rakes included), which
	## separates the skirts from the hull side behind them. No strip when 0.
	var skirt_edge := 0.0
	## Skirt panel carrying the faction accent plate (both sides).
	var accent_panel := 0
	## --- Kit detail (TASK-069): all off by default. ---
	## Road wheels, idlers and sprockets from MeshKit: detailed outer half (dished disc, tyre, hub
	## cap, bolt ring), plain inner drum; one mesh per side shared by every road-wheel pivot; road
	## arms, idler arms and plain return rollers go into the hull parts (`add_hull_parts`).
	var detailed_wheels := false
	## Bolts on a road wheel / idler hub, on a sprocket hub.
	var wheel_bolts := 6
	## Second bolt ring on the road wheel disc, near the rim (e.g. the T-72's 8 disc bolts). 0 = none.
	var wheel_rim_bolts := 0
	var sprocket_bolts := 10
	## Lathe sides of the road wheels and idlers.
	var wheel_sides := 12
	## Trailing road arm: its hull pivot is `road_arm_length` ahead of and `road_arm_rise` above the
	## wheel hub.
	var road_arm_length := 0.42
	var road_arm_rise := 0.18
	## Individual track shoes (steel body + rubber pad) every `track_shoe_pitch` metres instead of
	## the band with grousers; none on the top run behind the skirts. 0 = band.
	var track_shoe_pitch := 0.0
	## Rubber pads on the shoes (Abrams); false = all-steel shoes with a grouser bar (T-72 RMSh).
	var track_pads := true
	## Skirt panels as chamfered plates: bolt grid (`skirt_bolt_rows` x `skirt_bolt_cols`) on the
	## armoured front panels, rubber edge strip (`skirt_edge` high, 0.06 m when 0), bolt row and
	## stiffener on the others, hinge knuckles, a top rail.
	var detailed_skirts := false
	var skirt_bolt_rows := 3
	var skirt_bolt_cols := 4


## Builds the gear of both sides into `parent`. `materials` needs the keys &"body" (camo),
## &"dark", &"steel", &"rubber", &"track" and &"accent". Wheel pivots are numbered from
## `first_index`: road wheels (right side, then left), idlers, sprockets. Returns the next index.
static func build(
	parent: Node3D, frame: Frame, spec: Spec, materials: Dictionary, first_index := 0
) -> int:
	var index := add_pivots(parent, frame, spec, materials, first_index)
	if uses_kit(spec):
		var kits := MeshKits.new(frame)
		add_hull_parts(kits, spec)
		kits.add_to(parent, materials)
	_add_coarse_hull_parts(parent, frame, spec, materials)
	return index


## Whether any kit detail option is on (then `add_hull_parts` has parts to add).
static func uses_kit(spec: Spec) -> bool:
	return spec.detailed_wheels or spec.track_shoe_pitch > 0.0 or spec.detailed_skirts


## The "Wheel<i>" pivots with their meshes (see `build`); returns the next index.
static func add_pivots(
	parent: Node3D, frame: Frame, spec: Spec, materials: Dictionary, first_index := 0
) -> int:
	if spec.detailed_wheels:
		return _kit_pivots(parent, frame, spec, materials, first_index)
	var index := first_index
	var k := frame.k
	var wheel := _wheel_mesh(spec.key + ":road", spec.road_wheel_radius * k, spec.wheel_width * k)
	var tyre := _tyre_mesh(spec.road_wheel_radius * k, spec.wheel_width * k)
	var idler := _wheel_mesh(spec.key + ":idler", spec.idler_radius * k, spec.wheel_width * k)
	var idler_tyre := _tyre_mesh(spec.idler_radius * k, spec.wheel_width * k)
	for s: float in [1.0, -1.0]:
		for x in spec.road_wheel_x:
			var pivot := _pivot(parent, index, frame.p(x, spec.road_wheel_h, s * spec.track_z))
			_part(pivot, wheel, materials[&"body"], s)
			if spec.rubber_tyres:
				_part(pivot, tyre, materials[&"rubber"], s)
			index += 1
	for s: float in [1.0, -1.0]:
		var pivot := _pivot(parent, index, frame.p(spec.idler_x, spec.idler_h, s * spec.track_z))
		_part(pivot, idler, materials[&"body"], s)
		_part(pivot, idler_tyre, materials[&"steel"], s)
		index += 1
	var gear := _sprocket_mesh(spec, k)
	var hub := _hub_mesh(spec.sprocket_radius * k * 0.55, spec.wheel_width * k)
	for s: float in [1.0, -1.0]:
		var at := frame.p(spec.sprocket_x, spec.sprocket_h, s * spec.track_z)
		var pivot := _pivot(parent, index, at)
		_part(pivot, gear, materials[&"dark"], s)
		_part(pivot, hub, materials[&"body"], s)
		index += 1
	return index


## The coarse merged parts of the options that are off: track band, return rollers, skirts.
static func _add_coarse_hull_parts(
	parent: Node3D, frame: Frame, spec: Spec, materials: Dictionary
) -> void:
	if spec.track_shoe_pitch <= 0.0:
		ModelParts.add(parent, _track_mesh(frame, spec), materials[&"track"], Vector3.ZERO)
	if not spec.detailed_wheels:
		ModelParts.add(parent, _roller_mesh(frame, spec), materials[&"steel"], Vector3.ZERO)
	if spec.skirt_panels > 0 and not spec.detailed_skirts:
		ModelParts.add(parent, _skirt_mesh(frame, spec), materials[&"body"], Vector3.ZERO)
		ModelParts.add(parent, _accent_mesh(frame, spec), materials[&"accent"], Vector3.ZERO)
		if spec.skirt_edge > 0.0:
			ModelParts.add(
				parent, _skirt_edge_mesh(frame, spec), materials[&"rubber"], Vector3.ZERO
			)


static func _pivot(parent: Node3D, index: int, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Wheel%d" % index
	pivot.position = pos
	parent.add_child(pivot)
	return pivot


## A wheel part laid along the pivot's Z with its outer face towards the vehicle side `side`.
static func _part(pivot: Node3D, mesh: Mesh, material: Material, side: float) -> void:
	var instance := ModelParts.add(pivot, mesh, material, Vector3.ZERO)
	instance.rotation.x = PI / 2.0 if side > 0.0 else -PI / 2.0


## Double road wheel (two dished discs with a guide-horn groove between them) as one lathe
## around +Y; the outer face is at +Y.
static func _wheel_mesh(key: String, r: float, w: float) -> ArrayMesh:
	var profile: Array[Vector2] = [
		Vector2(0.0, 0.52 * w),
		Vector2(0.2 * r, 0.52 * w),
		Vector2(0.25 * r, 0.42 * w),
		Vector2(0.55 * r, 0.38 * w),
		Vector2(0.64 * r, 0.45 * w),
		Vector2(0.86 * r, 0.45 * w),
		Vector2(0.86 * r, 0.08 * w),
		Vector2(0.7 * r, 0.06 * w),
		Vector2(0.7 * r, -0.06 * w),
		Vector2(0.86 * r, -0.08 * w),
		Vector2(0.86 * r, -0.45 * w),
		Vector2(0.0, -0.45 * w),
	]
	return ModelParts.lathe_mesh("wheel:%s:%s:%s" % [key, r, w], profile, 16)


## The two rubber tyre bands of a double road wheel.
static func _tyre_mesh(r: float, w: float) -> ArrayMesh:
	# Kept inside the disc faces (|y| <= 0.42 w < 0.45 w): only the rim shows as the sidewall.
	var band := ModelParts.cyl_mesh(r, r, 0.3 * w, 16)
	var parts: Array = []
	for y: float in [0.27 * w, -0.27 * w]:
		parts.append([band, Transform3D(Basis.IDENTITY, Vector3(0, y, 0))])
	return ModelParts.merged_mesh("tyres:%s:%s" % [r, w], parts)


## Sprocket: two toothed rings (along +Y after the part rotation) with a disc between them.
static func _sprocket_mesh(spec: Spec, k: float) -> ArrayMesh:
	var r := spec.sprocket_radius * k
	var w := spec.wheel_width * k
	var outline := ModelParts.gear_outline(r * 0.86, r, spec.sprocket_teeth)
	var ring_key := "%s:sprocket:%s:%s:%d" % [spec.key, r, w, spec.sprocket_teeth]
	var ring := ModelParts.prism_mesh(ring_key, outline, 0.14 * w)
	var disc := ModelParts.cyl_mesh(r * 0.8, r * 0.8, 0.5 * w, 14)
	var to_y := Basis(Vector3.RIGHT, -PI / 2.0)
	var parts: Array = [[disc, Transform3D.IDENTITY]]
	for y: float in [0.32 * w, -0.32 * w]:
		parts.append([ring, Transform3D(to_y, Vector3(0, y, 0))])
	return ModelParts.merged_mesh("%s:sprocket_gear" % spec.key, parts)


static func _hub_mesh(r: float, w: float) -> ArrayMesh:
	var profile: Array[Vector2] = [
		Vector2(0.0, 0.56 * w),
		Vector2(0.3 * r, 0.56 * w),
		Vector2(0.45 * r, 0.47 * w),
		Vector2(r, 0.44 * w),
		Vector2(r, 0.36 * w),
		Vector2(0.0, 0.36 * w),
	]
	return ModelParts.lathe_mesh("hub:%s:%s" % [r, w], profile, 12)


## Inner surface of the track loop in the model XY plane: hull of all wheels and rollers.
static func _track_path(frame: Frame, spec: Spec) -> Array[Vector2]:
	var k := frame.k
	var circles: Array[Vector3] = []
	for x in spec.road_wheel_x:
		var c := frame.xy(x, spec.road_wheel_h)
		circles.append(Vector3(c.x, c.y, spec.road_wheel_radius * k))
	for x in spec.return_roller_x:
		var c := frame.xy(x, spec.return_roller_h)
		circles.append(Vector3(c.x, c.y, spec.return_roller_radius * k))
	var idler := frame.xy(spec.idler_x, spec.idler_h)
	circles.append(Vector3(idler.x, idler.y, spec.idler_radius * k))
	var sprocket := frame.xy(spec.sprocket_x, spec.sprocket_h)
	circles.append(Vector3(sprocket.x, sprocket.y, spec.sprocket_radius * 0.9 * k))
	return ModelParts.circle_hull(circles, 24)


## Both track loops with grousers, one merged mesh.
static func _track_mesh(frame: Frame, spec: Spec) -> ArrayMesh:
	var k := frame.k
	var inner := _track_path(frame, spec)
	var thickness := spec.track_thickness * k
	var band := ModelParts.band_mesh(spec.key + ":track", inner, thickness, spec.track_width * k)
	var outer := ModelParts.offset_path(inner, thickness)
	var height := spec.grouser_height * k
	var grouser := ModelParts.box_mesh(
		Vector3(spec.grouser_spacing * 0.4 * k, height, spec.track_width * 1.04 * k)
	)
	var parts: Array = []
	for s: float in [1.0, -1.0]:
		var at := Vector3(0, 0, s * spec.track_z * k)
		parts.append([band, Transform3D(Basis.IDENTITY, at)])
		for station: Array in ModelParts.path_stations(outer, spec.grouser_spacing * k):
			var point: Vector2 = station[0]
			var tangent: Vector2 = station[1]
			var normal := Vector2(tangent.y, -tangent.x)
			var centre := point + normal * height * 0.4
			var basis := Basis(Vector3.BACK, tangent.angle())
			parts.append([grouser, Transform3D(basis, Vector3(centre.x, centre.y, 0) + at)])
	return ModelParts.merged_mesh(spec.key + ":tracks", parts)


## Return rollers on the inner half of each track.
static func _roller_mesh(frame: Frame, spec: Spec) -> ArrayMesh:
	var parts: Array = []
	for s: float in [1.0, -1.0]:
		for x in spec.return_roller_x:
			var z := s * (spec.track_z - spec.track_width * 0.2)
			frame.drum(
				parts,
				x,
				spec.return_roller_h,
				z,
				spec.return_roller_radius,
				spec.track_width * 0.5,
				&"z",
				10
			)
	return ModelParts.merged_mesh(spec.key + ":rollers", parts)


## Skirt panels (prisms of their side outline) on both sides with small seams between them.
static func _skirt_mesh(frame: Frame, spec: Spec) -> ArrayMesh:
	var parts: Array = []
	for i in spec.skirt_panels:
		var t := _skirt_panel_thickness(spec, i)
		var bottom := _skirt_bottom(spec, i)
		var x0: float = bottom[0].x
		var x1: float = bottom[-1].x
		var outline: Array[Vector2] = []
		for point in _skirt_top(spec, i):
			outline.append(frame.xy(point.x, point.y))
		for j in range(bottom.size() - 1, -1, -1):
			outline.append(frame.xy(bottom[j].x, bottom[j].y))
		var key := "%s:skirt%d" % [spec.key, i]
		var panel := ModelParts.prism_mesh(key, outline, t * frame.k)
		for s: float in [1.0, -1.0]:
			var at := Vector3(0, 0, s * (spec.skirt_z - t / 2.0) * frame.k)
			parts.append([panel, Transform3D(Basis.IDENTITY, at)])
	return ModelParts.merged_mesh(spec.key + ":skirts", parts)


static func _skirt_panel_thickness(spec: Spec, i: int) -> float:
	return spec.skirt_front_thickness if i < spec.skirt_front_panels else spec.skirt_thickness


## Bottom edge of skirt panel `i` from its front to its rear end: Vector2(x, h) points, with the
## front rake on the first panel and the rear rake on the last.
static func _skirt_bottom(spec: Spec, i: int) -> Array[Vector2]:
	var length := (spec.skirt_x1 - spec.skirt_x0) / spec.skirt_panels
	var x0 := spec.skirt_x0 + i * length
	var seam := 0.03
	var x1 := x0 + length - seam
	var bottom: Array[Vector2] = []
	if i == 0 and spec.skirt_front_rake > 0.0:
		bottom.append(Vector2(x0, spec.skirt_h0 + spec.skirt_front_rake * 0.6))
		bottom.append(Vector2(x0 + spec.skirt_front_rake, spec.skirt_h0))
	else:
		bottom.append(Vector2(x0, _profile_h(spec, x0)))
	if not spec.skirt_bottom_profile.is_empty():
		for p in spec.skirt_bottom_profile:
			if p.x > bottom[-1].x + 0.01 and p.x < x1 - 0.01:
				bottom.append(p)
		bottom.append(Vector2(x1, _profile_h(spec, x1)))
	elif i == spec.skirt_panels - 1 and spec.skirt_rear_rake > 0.0:
		bottom.append(Vector2(x1 - spec.skirt_rear_rake, spec.skirt_h0))
		bottom.append(Vector2(x1, spec.skirt_h0 + spec.skirt_rear_rise))
	else:
		bottom.append(Vector2(x1, spec.skirt_h0))
	return bottom


## Top edge of skirt panel `i` from its front to its rear end: Vector2(x, h) points (the first
## panel's front end lowered by `skirt_front_top_drop`).
static func _skirt_top(spec: Spec, i: int) -> Array[Vector2]:
	var bottom := _skirt_bottom(spec, i)
	var x0: float = bottom[0].x
	var x1: float = bottom[-1].x
	if i == 0 and spec.skirt_front_top_drop > 0.0:
		return (
			[
				Vector2(x0, spec.skirt_h1 - spec.skirt_front_top_drop),
				Vector2(x0 + spec.skirt_front_top_run, spec.skirt_h1),
				Vector2(x1, spec.skirt_h1)
			]
			as Array[Vector2]
		)
	return [Vector2(x0, spec.skirt_h1), Vector2(x1, spec.skirt_h1)] as Array[Vector2]


## Skirt top height at `x` (`skirt_h1`, lower over the front slope).
static func _top_at(spec: Spec, x: float) -> float:
	var run := spec.skirt_front_top_run
	if spec.skirt_front_top_drop <= 0.0 or x >= spec.skirt_x0 + run:
		return spec.skirt_h1
	var t := clampf((x - spec.skirt_x0) / run, 0.0, 1.0)
	return spec.skirt_h1 - spec.skirt_front_top_drop * (1.0 - t)


## Skirt bottom height at `x` from `skirt_bottom_profile` (`skirt_h0` when it is empty or before
## its first point).
static func _profile_h(spec: Spec, x: float) -> float:
	var profile := spec.skirt_bottom_profile
	if profile.is_empty() or x <= profile[0].x:
		return spec.skirt_h0
	for j in profile.size() - 1:
		if x <= profile[j + 1].x:
			return lerpf(
				profile[j].y, profile[j + 1].y, inverse_lerp(profile[j].x, profile[j + 1].x, x)
			)
	return profile[-1].y


## Dark rubber strip (`skirt_edge` high) along every bottom edge segment of the skirts, standing
## slightly proud of the panel faces on both sides.
static func _skirt_edge_mesh(frame: Frame, spec: Spec) -> ArrayMesh:
	var parts: Array = []
	var proud := 0.016
	for i in spec.skirt_panels:
		var t := _skirt_panel_thickness(spec, i) + proud
		var bottom := _skirt_bottom(spec, i)
		for j in bottom.size() - 1:
			var a := bottom[j]
			var b := bottom[j + 1]
			var quad: Array[Vector2] = [
				frame.xy(a.x, a.y),
				frame.xy(b.x, b.y),
				frame.xy(b.x, b.y + spec.skirt_edge),
				frame.xy(a.x, a.y + spec.skirt_edge)
			]
			var strip := ModelParts.prism_mesh(
				"%s:skirt_edge%d_%d" % [spec.key, i, j], quad, t * frame.k
			)
			for s: float in [1.0, -1.0]:
				var at := Vector3(0, 0, s * (spec.skirt_z - (t - proud) / 2.0) * frame.k)
				parts.append([strip, Transform3D(Basis.IDENTITY, at)])
	return ModelParts.merged_mesh(spec.key + ":skirt_edges", parts)


## Faction plate on the outer face of skirt panel `accent_panel`, both sides.
static func _accent_mesh(frame: Frame, spec: Spec) -> ArrayMesh:
	var parts: Array = []
	var length := (spec.skirt_x1 - spec.skirt_x0) / spec.skirt_panels
	var x0 := spec.skirt_x0 + spec.accent_panel * length + length * 0.2
	var height := spec.skirt_h1 - spec.skirt_h0
	var h0 := spec.skirt_h0 + height * 0.45
	frame.pair(parts, x0, x0 + length * 0.55, h0, h0 + height * 0.32, 0.012, spec.skirt_z)
	return ModelParts.merged_mesh(spec.key + ":skirt_accent", parts)


# --- Kit detail (TASK-069) ------------------------------------------------------------------------


## Hull-level kit parts of the options that are on, into `kits` (built with the vehicle's frame):
## track shoes (&"track", &"rubber"), road arms / idler arms / return rollers (&"dark"), skirts
## (&"body", &"rubber", &"steel", &"accent").
static func add_hull_parts(kits: MeshKits, spec: Spec) -> void:
	if spec.track_shoe_pitch > 0.0:
		_track_shoes(kits, spec)
	if spec.detailed_wheels:
		_suspension(kits, spec)
	if spec.detailed_skirts and spec.skirt_panels > 0:
		_kit_skirts(kits, spec)


## Wheel pivots whose meshes come from `_pivot_meshes` (one set per wheel kind and side).
static func _kit_pivots(
	parent: Node3D, frame: Frame, spec: Spec, materials: Dictionary, first_index: int
) -> int:
	var index := first_index
	for kind: StringName in [&"road", &"idler", &"sprocket"]:
		for s: float in [1.0, -1.0]:
			var meshes := _pivot_meshes(frame, spec, kind, s)
			for x in _wheel_xs(spec, kind):
				var c := _wheel_centre(spec, kind, s, x)
				var pivot := _pivot(parent, index, frame.p(c.x, c.y, c.z))
				MeshKits.add_meshes(pivot, meshes, materials)
				index += 1
	return index


static func _wheel_xs(spec: Spec, kind: StringName) -> Array[float]:
	match kind:
		&"road":
			return spec.road_wheel_x
		&"idler":
			return [spec.idler_x] as Array[float]
	return [spec.sprocket_x] as Array[float]


## Centre (vehicle metres) of a wheel of `kind` at `x` on side `s`.
static func _wheel_centre(spec: Spec, kind: StringName, s: float, x: float) -> Vector3:
	var h := spec.road_wheel_h
	if kind == &"idler":
		h = spec.idler_h
	elif kind == &"sprocket":
		h = spec.sprocket_h
	return Vector3(x, h, s * spec.track_z)


## Meshes ({role: ArrayMesh}) of one wheel kind on side `s`, built once in the pivot's space and
## shared by every pivot of that kind and side and by every faction (ModelParts.cached_meshes).
static func _pivot_meshes(frame: Frame, spec: Spec, kind: StringName, s: float) -> Dictionary:
	var key := "%s:%s:%d" % [spec.key, kind, int(s)]
	return ModelParts.cached_meshes(
		key, func() -> Dictionary: return _build_pivot_meshes(frame, spec, kind, s)
	)


static func _build_pivot_meshes(frame: Frame, spec: Spec, kind: StringName, s: float) -> Dictionary:
	var c := _wheel_centre(spec, kind, s, _wheel_xs(spec, kind)[0])
	var kits := MeshKits.new(frame, Transform3D(Basis.IDENTITY, -frame.p(c.x, c.y, c.z)))
	match kind:
		&"road":
			_road_wheel(kits, spec, c, s)
		&"idler":
			_idler(kits, spec, c, s)
		_:
			_sprocket(kits, spec, c, s)
	return kits.commit_all()


## Lathe basis (local +Y) pointing out of the vehicle side `s`.
static func _out_basis(s: float) -> Basis:
	return Basis(Vector3.RIGHT, PI / 2.0 if s > 0.0 else -PI / 2.0)


## Double road wheel: the outer half detailed (dished disc, tyre, hub cap, bolt ring); the inner
## half is hidden behind it and the track, so a plain drum. Proportions of the study's Abrams wheel
## (r 0.32, 0.58 wide) scaled by radius and width.
static func _road_wheel(kits: MeshKits, spec: Spec, c: Vector3, s: float) -> void:
	var r := spec.road_wheel_radius
	var w := spec.wheel_width
	var rot := _out_basis(s)
	var outer := c + Vector3(0, 0, s * w * 0.14)
	var body := kits.k(&"body")
	var disc_rim := r * 0.84 if spec.rubber_tyres else r
	body.lathe(
		outer,
		rot,
		[
			Vector2(0.0, 0.29 * w),
			Vector2(0.25 * r, 0.29 * w),
			Vector2(0.31 * r, 0.224 * w),
			Vector2(0.73 * r, 0.155 * w),
			Vector2(disc_rim, 0.19 * w),
			Vector2(disc_rim, 0.0),
			Vector2(0.0, 0.0)
		],
		spec.wheel_sides
	)
	body.lathe(
		outer,
		rot,
		[
			Vector2(0.0, 0.37 * w),
			Vector2(0.14 * r, 0.37 * w),
			Vector2(0.17 * r, 0.345 * w),
			Vector2(0.17 * r, 0.276 * w),
			Vector2(0.0, 0.276 * w)
		],
		8
	)
	_bolt_ring(body, outer, s, spec.wheel_bolts, 0.39 * r, 0.21 * w, 0.044 * r)
	if spec.wheel_rim_bolts > 0:
		_bolt_ring(body, outer, s, spec.wheel_rim_bolts, 0.62 * r, 0.168 * w, 0.04 * r)
	var rubber := kits.k(&"rubber")
	if spec.rubber_tyres:
		rubber.lathe(
			outer,
			rot,
			[
				Vector2(0.84 * r, 0.18 * w),
				Vector2(0.94 * r, 0.18 * w),
				Vector2(r, 0.147 * w),
				Vector2(r, 0.034 * w),
				Vector2(0.94 * r, 0.0)
			],
			spec.wheel_sides
		)
	rubber.rod(c - Vector3(0, 0, s * w * 0.14), Vector3.BACK, r * 0.94, w * 0.17, 8)


## Idler: detailed outer half with hub bolts, plain inner drum.
static func _idler(kits: MeshKits, spec: Spec, c: Vector3, s: float) -> void:
	var r := spec.idler_radius
	var w := spec.wheel_width
	var outer := c + Vector3(0, 0, s * w * 0.14)
	var body := kits.k(&"body")
	body.lathe(
		outer,
		_out_basis(s),
		[
			Vector2(0.0, 0.26 * w),
			Vector2(0.23 * r, 0.26 * w),
			Vector2(0.3 * r, 0.224 * w),
			Vector2(0.7 * r, 0.17 * w),
			Vector2(0.9 * r, 0.19 * w),
			Vector2(r, 0.17 * w),
			Vector2(r, 0.0),
			Vector2(0.0, 0.0)
		],
		spec.wheel_sides + 4
	)
	_bolt_ring(body, outer, s, spec.wheel_bolts, 0.45 * r, 0.2 * w, 0.05 * r)
	kits.k(&"steel").rod(c - Vector3(0, 0, s * w * 0.14), Vector3.BACK, r * 0.97, w * 0.17, 8, 0.01)


## Drive sprocket: two toothed steel rings with discs, hub with a bolt ring, final drive stub.
static func _sprocket(kits: MeshKits, spec: Spec, c: Vector3, s: float) -> void:
	var r := spec.sprocket_radius
	var w := spec.wheel_width
	var rot := _out_basis(s)
	var body := kits.k(&"body")
	var steel := kits.k(&"steel")
	var gear: Array = []
	gear.assign(ModelParts.gear_outline(r * 0.83, r, spec.sprocket_teeth))
	for half: float in [-1.0, 1.0]:
		var ring := c + Vector3(0, 0, s * half * w * 0.17)
		body.lathe(
			ring,
			rot,
			[
				Vector2(0.0, 0.06 * w),
				Vector2(0.78 * r, 0.06 * w),
				Vector2(0.83 * r, 0.034 * w),
				Vector2(0.83 * r, -0.034 * w),
				Vector2(0.78 * r, -0.06 * w),
				Vector2(0.0, -0.06 * w)
			],
			16
		)
		steel.plate(
			gear, ring, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -0.043 * w, 0.043 * w, 0.006
		)
	var hub := c + Vector3(0, 0, s * w * 0.17)
	body.lathe(
		hub,
		rot,
		[
			Vector2(0.0, 0.28 * w),
			Vector2(0.25 * r, 0.28 * w),
			Vector2(0.31 * r, 0.24 * w),
			Vector2(0.47 * r, 0.21 * w),
			Vector2(0.56 * r, 0.1 * w),
			Vector2(0.56 * r, 0.0),
			Vector2(0.0, 0.0)
		],
		18
	)
	for k in spec.sprocket_bolts:
		var a := TAU * k / spec.sprocket_bolts
		steel.bolt(
			hub + Vector3(cos(a) * 0.42 * r, sin(a) * 0.42 * r, s * 0.215 * w),
			Vector3(-cos(a) * 0.3, -sin(a) * 0.3, s).normalized(),
			0.045 * r
		)
	body.rod(c - Vector3(0, 0, s * w * 0.41), Vector3.BACK, 0.67 * r, 0.21 * w, 12)


## `count` bolt heads on a circle of `radius` around the wheel axis, `out` m outside the centre.
static func _bolt_ring(
	kit: MeshKit, c: Vector3, s: float, count: int, radius: float, out: float, size: float
) -> void:
	for k in count:
		var a := TAU * k / count
		kit.bolt(c + Vector3(cos(a) * radius, sin(a) * radius, s * out), Vector3(0, 0, s), size)


## Inner surface of the track loop (Vector2(x, h), metres, counter-clockwise): hull of the wheels.
static func _track_loop(spec: Spec) -> Array[Vector2]:
	var circles: Array[Vector3] = []
	for x in spec.road_wheel_x:
		circles.append(Vector3(x, spec.road_wheel_h, spec.road_wheel_radius))
	for x in spec.return_roller_x:
		circles.append(Vector3(x, spec.return_roller_h, spec.return_roller_radius))
	circles.append(Vector3(spec.sprocket_x, spec.sprocket_h, spec.sprocket_radius * 0.85))
	circles.append(Vector3(spec.idler_x, spec.idler_h, spec.idler_radius))
	return ModelParts.circle_hull(circles, 24)


## Individual "lite" shoes along the loop: steel body (chamfered, worn edges) and rubber pad down to
## the ground (the guide horns and end connectors would only show from below). The top run between
## the skirt ends is never seen, so it gets no shoes.
static func _track_shoes(kits: MeshKits, spec: Spec) -> void:
	var loop := _track_loop(spec)
	var pitch := spec.track_shoe_pitch
	var depth := spec.road_wheel_h - spec.road_wheel_radius
	var top := spec.road_wheel_h + spec.road_wheel_radius
	var skip0 := spec.skirt_x0 + 0.5 - pitch * 0.6
	var skip1 := spec.skirt_x1 - 0.5 + pitch * 0.6
	var w := spec.track_width
	var track := kits.k(&"track")
	var rubber := kits.k(&"rubber")
	for s: float in [-1.0, 1.0]:
		for station: Array in ModelParts.path_stations(loop, pitch):
			var p: Vector2 = station[0]
			var t: Vector2 = station[1]
			if spec.skirt_panels > 0 and p.y > top and p.x > skip0 and p.x < skip1:
				continue
			var out := Vector3(t.y, -t.x, 0.0)
			var rot := Basis(Vector3(t.x, t.y, 0.0), out, Vector3(0, 0, -1))
			var c := Vector3(p.x, p.y, s * spec.track_z)
			if spec.track_pads:
				track.cbox(
					c + out * depth * 0.32,
					Vector3(pitch * 0.96, depth * 0.55, w - 0.02),
					0.008,
					rot
				)
				rubber.cbox(
					c + out * depth * 0.77, Vector3(pitch * 0.83, depth * 0.46, w - 0.14), 0.0, rot
				)
			else:
				track.cbox(
					c + out * depth * 0.37,
					Vector3(pitch * 0.94, depth * 0.64, w - 0.02),
					0.008,
					rot
				)
				track.cbox(
					c + out * depth * 0.845, Vector3(pitch * 0.32, depth * 0.31, w - 0.1), 0.0, rot
				)


## Road arms (only their lower ends show between the wheels), idler arms and the return rollers
## (behind the skirts: plain rods).
static func _suspension(kits: MeshKits, spec: Spec) -> void:
	var dark := kits.k(&"dark")
	var w := spec.wheel_width
	for s: float in [-1.0, 1.0]:
		var arm_z := s * (spec.track_z - w * 0.6)
		for x in spec.road_wheel_x:
			var pivot := Vector3(
				x - spec.road_arm_length, spec.road_wheel_h + spec.road_arm_rise, arm_z
			)
			var hub := Vector3(x, spec.road_wheel_h, arm_z)
			var d := hub - pivot
			dark.cbox(
				(pivot + hub) / 2.0,
				Vector3(d.length() + 0.12, 0.12, 0.09),
				0.0,
				Basis(Vector3.BACK, atan2(d.y, d.x))
			)
		for x in spec.return_roller_x:
			dark.rod(
				Vector3(x, spec.return_roller_h, s * spec.track_z),
				Vector3.BACK,
				spec.return_roller_radius,
				w * 0.45,
				8
			)
		dark.cbox(
			Vector3(spec.idler_x + 0.25, spec.idler_h + 0.09, arm_z),
			Vector3(0.5, 0.14, 0.1),
			0.0,
			Basis(Vector3.BACK, -0.35)
		)


## Skirt panels as chamfered plates (outline from `_skirt_bottom`, so the rakes apply): bolt grid on
## the armoured panels, rubber edge strip, top bolt row and stiffener on the thin ones, hinge
## knuckles under the fender, top rail, faction plate on `accent_panel`.
static func _kit_skirts(kits: MeshKits, spec: Spec) -> void:
	var body := kits.k(&"body")
	var rubber := kits.k(&"rubber")
	var steel := kits.k(&"steel")
	var h0 := spec.skirt_h0
	var h1 := spec.skirt_h1
	var plate := _accent_rect(spec)
	for i in spec.skirt_panels:
		var thick := _skirt_panel_thickness(spec, i)
		var bottom := _skirt_bottom(spec, i)
		var x0: float = bottom[0].x
		var x1: float = bottom[-1].x
		var outline: Array = []
		outline.append_array(_skirt_top(spec, i))
		for j in range(bottom.size() - 1, -1, -1):
			outline.append(bottom[j])
		var zc := spec.skirt_z - thick / 2.0
		for s: float in [-1.0, 1.0]:
			var face := Vector3(0, 0, s)
			body.plate(
				outline,
				Vector3.ZERO,
				Vector3.RIGHT,
				Vector3.UP,
				Vector3.BACK * s,
				spec.skirt_z - thick,
				spec.skirt_z,
				0.018
			)
			if i < spec.skirt_front_panels:
				for row in spec.skirt_bolt_rows:
					for col in spec.skirt_bolt_cols:
						var bx := (
							x0 + 0.12 + col * (x1 - x0 - 0.24) / maxf(spec.skirt_bolt_cols - 1, 1)
						)
						var bh := (
							h1 - 0.1 - row * (h1 - h0 - 0.2) / maxf(spec.skirt_bolt_rows - 1, 1)
						)
						if bh < _bottom_at(bottom, bx) + 0.08 or bh > _top_at(spec, bx) - 0.06:
							continue
						if i == spec.accent_panel and plate.grow(0.04).has_point(Vector2(bx, bh)):
							continue
						body.bolt(Vector3(bx, bh, s * spec.skirt_z), face, 0.03)
			else:
				_skirt_edge_strips(rubber, spec, bottom, s * zc, thick + 0.016)
				for col in 4:
					var bx := x0 + 0.1 + col * (x1 - x0 - 0.2) / 3.0
					body.bolt(Vector3(bx, h1 - 0.06, s * spec.skirt_z), face, 0.02)
				var stiff := h0 + 0.25
				var stiff_x1 := x1 - 0.04
				while stiff_x1 > x0 + 0.3 and _bottom_at(bottom, stiff_x1) > stiff - 0.08:
					stiff_x1 -= 0.05  # stop before a raised rear edge
				if stiff < h1 - 0.12 and not (i == spec.accent_panel):
					body.slab(
						x0 + 0.04,
						stiff_x1,
						stiff,
						stiff + 0.03,
						0.012,
						s * (spec.skirt_z + 0.008),
						0.004
					)
			for hx: float in [x0 + 0.15, x1 - 0.15]:
				steel.rod(
					Vector3(hx, _top_at(spec, hx) - 0.02, s * zc), Vector3.RIGHT, 0.025, 0.12, 8
				)
	for s: float in [-1.0, 1.0]:
		body.slab(
			(
				spec.skirt_x0
				if spec.skirt_front_top_drop <= 0.0
				else spec.skirt_x0 + spec.skirt_front_top_run
			),
			spec.skirt_x1,
			h1,
			h1 + 0.04,
			0.06,
			s * (spec.skirt_z - 0.06),
			0.01
		)
	kits.k(&"accent").pair(
		plate.position.x, plate.end.x, plate.position.y, plate.end.y, 0.012, spec.skirt_z, 0.006
	)


## Rubber strip (`skirt_edge` high, 0.06 m when 0) along each bottom edge segment of a panel,
## hanging below it by two thirds of its height.
static func _skirt_edge_strips(
	rubber: MeshKit, spec: Spec, bottom: Array[Vector2], z: float, depth: float
) -> void:
	var edge := spec.skirt_edge if spec.skirt_edge > 0.0 else 0.06
	for j in bottom.size() - 1:
		var a := bottom[j]
		var b := bottom[j + 1]
		var d := b - a
		var mid := (a + b) / 2.0
		rubber.cbox(
			Vector3(mid.x, mid.y - edge * 0.17, z),
			Vector3(d.length() - 0.01, edge, depth),
			0.006,
			Basis(Vector3.BACK, atan2(d.y, d.x))
		)


## Bottom edge height of a panel at `x` (linear between the `_skirt_bottom` points).
static func _bottom_at(bottom: Array[Vector2], x: float) -> float:
	for j in bottom.size() - 1:
		if x <= bottom[j + 1].x:
			var t := inverse_lerp(bottom[j].x, bottom[j + 1].x, x)
			return lerpf(bottom[j].y, bottom[j + 1].y, clampf(t, 0.0, 1.0))
	return bottom[-1].y


## Faction plate on panel `accent_panel` as a Rect2 of (x, h), same place as `_accent_mesh`.
static func _accent_rect(spec: Spec) -> Rect2:
	var length := (spec.skirt_x1 - spec.skirt_x0) / spec.skirt_panels
	var x0 := spec.skirt_x0 + spec.accent_panel * length + length * 0.2
	var height := spec.skirt_h1 - spec.skirt_h0
	var h0 := spec.skirt_h0 + height * 0.45
	return Rect2(x0, h0, length * 0.55, height * 0.32)
