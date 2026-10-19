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
	## Cuts the rear-bottom corner of the last panel: the bottom edge rises by `skirt_rear_rise`
	## over the last `skirt_rear_rake` metres (e.g. the T-72's skirt slanting up over the
	## sprocket). No cut when skirt_rear_rake is 0.
	var skirt_rear_rake := 0.0
	var skirt_rear_rise := 0.0
	## Height (m) of a dark rubber strip along the panels' bottom edges (rakes included), which
	## separates the skirts from the hull side behind them. No strip when 0.
	var skirt_edge := 0.0
	## Skirt panel carrying the faction accent plate (both sides).
	var accent_panel := 0


## Builds the gear of both sides into `parent`. `materials` needs the keys &"body" (camo),
## &"dark", &"steel", &"rubber", &"track" and &"accent". Wheel pivots are numbered from
## `first_index`: road wheels (right side, then left), idlers, sprockets. Returns the next index.
static func build(
	parent: Node3D, frame: Frame, spec: Spec, materials: Dictionary, first_index := 0
) -> int:
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
	ModelParts.add(parent, _track_mesh(frame, spec), materials[&"track"], Vector3.ZERO)
	ModelParts.add(parent, _roller_mesh(frame, spec), materials[&"steel"], Vector3.ZERO)
	if spec.skirt_panels > 0:
		ModelParts.add(parent, _skirt_mesh(frame, spec), materials[&"body"], Vector3.ZERO)
		ModelParts.add(parent, _accent_mesh(frame, spec), materials[&"accent"], Vector3.ZERO)
		if spec.skirt_edge > 0.0:
			ModelParts.add(
				parent, _skirt_edge_mesh(frame, spec), materials[&"rubber"], Vector3.ZERO
			)
	return index


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
		var outline: Array[Vector2] = [frame.xy(x0, spec.skirt_h1), frame.xy(x1, spec.skirt_h1)]
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
		bottom.append(Vector2(x0, spec.skirt_h0))
	if i == spec.skirt_panels - 1 and spec.skirt_rear_rake > 0.0:
		bottom.append(Vector2(x1 - spec.skirt_rear_rake, spec.skirt_h0))
		bottom.append(Vector2(x1, spec.skirt_h0 + spec.skirt_rear_rise))
	else:
		bottom.append(Vector2(x1, spec.skirt_h0))
	return bottom


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
