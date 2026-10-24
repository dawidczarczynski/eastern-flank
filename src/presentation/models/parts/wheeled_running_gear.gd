class_name WheeledRunningGear
extends RefCounted
## Shared wheeled running gear for the truck models (TASK-073), the wheeled counterpart of
## TrackedRunningGear with its kit techniques (TASK-069): per axle and side a "Wheel<i>" pivot
## spinning about its local Z (UnitModels.pose_tank) with an off-road tyre (directional lugs as
## chamfered blocks on the outer shoulder and crown), a dished steel disc recessed in the rim with a
## bolt ring and a hub cap (or a central tyre-inflation hub), and a plain inner half (a drum, no
## lugs or bolts: the camera never sees it). Optional hull parts: mudflaps and wheel-arch liners.
##
##   var spec := WheeledRunningGear.Spec.new()
##   spec.key = "homar_k"
##   spec.axle_x = AXLES
##   spec.wheel_radius = 0.7
##   var index := WheeledRunningGear.build(model, frame, spec, materials)
##
## All lengths in vehicle metres (see vehicle_frame.gd): `x` from the front, `h` above the ground,
## `z` across. One mesh set per side is built once (ModelParts.cached_meshes, key from the Spec) and
## shared by every wheel pivot of that side and by every faction.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
## Material roles `build` needs: &"body" (wheel disc, camo or a weathered paint), &"rubber" (tyres,
## mudflaps), &"dark" (hub cap / inflation hub, arch liners).
const MATERIAL_ROLES: Array[StringName] = [&"body", &"rubber", &"dark"]


class Spec:
	extends RefCounted
	## Prefix of the cached mesh keys (the other fields are part of the key too).
	var key := "wheeled"
	## Axle positions (x from the front); one wheel per axle and side.
	var axle_x: Array[float] = []
	var wheel_radius := 0.6
	## Wheel centre height; 0 = `wheel_radius` (the tyre touches the ground).
	var wheel_h := 0.0
	var tyre_width := 0.4
	## Wheel centre |z|.
	var track_z := 1.1
	## Lathe sides of tyre and disc.
	var wheel_sides := 16
	## --- Tread: directional off-road lugs (chevrons) on the crown and outer shoulder. ---
	var tread := true
	## Lugs per row (two rows: outer shoulder + crown, inner crown, offset by half a pitch).
	var tread_lugs := 14
	## Lug depth above the tyre carcass (m).
	var lug_depth := 0.035
	## Lug slant against the axle (degrees): 0 = straight cross bars, > 0 = chevrons.
	var lug_angle_deg := 25.0
	## --- Hub ---
	## Dished disc with a bolt ring and a hub cap; false = a flat disc only.
	var hub_detail := true
	var hub_bolts := 10
	## Central tyre-inflation hub (ZIL-135, Jelcz): a hub housing with a rotary union and an air
	## line to the rim valve instead of the plain cap.
	var inflation_hub := false
	## Rim flange radius as a share of `wheel_radius` (where the tyre's sidewall starts).
	var rim_share := 0.55
	## --- Hull parts (off by default) ---
	## Rubber mudflaps hanging at these x (both sides), from `mudflap_top_h` down to
	## `mudflap_bottom_h`.
	var mudflap_x: Array[float] = []
	var mudflap_top_h := 1.25
	var mudflap_bottom_h := 0.3
	## Axles (x) that get a wheel-arch liner: a curved dark strip over the top of the tyre,
	## `arch_gap` m clear of it.
	var arch_liner_x: Array[float] = []
	var arch_gap := 0.08
	var arch_thickness := 0.025

	## Wheel centre height (m).
	func centre_h() -> float:
		return wheel_h if wheel_h > 0.0 else wheel_radius

	## Whether there are hull parts (mudflaps or arch liners) for `add_hull_parts`.
	func has_hull_parts() -> bool:
		return not mudflap_x.is_empty() or not arch_liner_x.is_empty()

	## Everything the wheel meshes depend on (cache key).
	func mesh_key() -> String:
		return (
			"%s:%s:%s:%s:%d:%s:%d:%s:%s:%s:%d:%s:%s"
			% [
				key,
				wheel_radius,
				tyre_width,
				track_z,
				wheel_sides,
				tread,
				tread_lugs,
				lug_depth,
				lug_angle_deg,
				hub_detail,
				hub_bolts,
				inflation_hub,
				rim_share,
			]
		)


## Builds the wheels (and the hull parts, if any) into `parent`. Wheel pivots are numbered from
## `first_index`: the left side (-z) front to rear, then the right side (+z) – the order the truck
## models used with ModelParts.wheel. `materials` needs MATERIAL_ROLES. Returns the next index.
static func build(
	parent: Node3D, frame: Frame, spec: Spec, materials: Dictionary, first_index := 0
) -> int:
	var index := add_pivots(parent, frame, spec, materials, first_index)
	if spec.has_hull_parts():
		var kits := MeshKits.new(frame)
		add_hull_parts(kits, spec)
		kits.add_to(parent, materials)
	return index


## The "Wheel<i>" pivots with their (shared) meshes; returns the next index.
static func add_pivots(
	parent: Node3D, frame: Frame, spec: Spec, materials: Dictionary, first_index := 0
) -> int:
	var index := first_index
	for s: float in [-1.0, 1.0]:
		var meshes := wheel_meshes(frame, spec, s)
		for x in spec.axle_x:
			var pivot := Node3D.new()
			pivot.name = "Wheel%d" % index
			pivot.position = frame.p(x, spec.centre_h(), s * spec.track_z)
			parent.add_child(pivot)
			MeshKits.add_meshes(pivot, meshes, materials)
			index += 1
	return index


## Hull-level parts into `kits` (built with the vehicle's frame): mudflaps (&"rubber", &"dark"
## bracket) and arch liners (&"dark"). A model that builds its hull with MeshKits calls this
## itself (the parts then share its mesh instances) and `add_pivots` instead of `build`.
static func add_hull_parts(kits: MeshKits, spec: Spec) -> void:
	var w := spec.tyre_width
	for s: float in [-1.0, 1.0]:
		var z := s * spec.track_z
		for x in spec.mudflap_x:
			var h0 := spec.mudflap_bottom_h
			var h1 := spec.mudflap_top_h
			kits.k(&"rubber").cbox(
				Vector3(x, (h0 + h1) / 2.0, z), Vector3(0.012, h1 - h0, w + 0.08), 0.004
			)
			kits.k(&"dark").cbox(Vector3(x - 0.02, h1, z), Vector3(0.04, 0.05, w + 0.12), 0.008)
		for x in spec.arch_liner_x:
			_arch_liner(kits.k(&"dark"), spec, x, z)


## Meshes ({role: ArrayMesh}) of one wheel on side `s` (-1 left, +1 right) in the pivot's space,
## built once per Spec and side and shared by every pivot of that side and every faction.
static func wheel_meshes(frame: Frame, spec: Spec, s: float) -> Dictionary:
	var key := "wheeled:%s:%s:%d" % [spec.mesh_key(), frame.k, int(s)]
	return ModelParts.cached_meshes(key, func() -> Dictionary: return _build_wheel(frame, spec, s))


static func _build_wheel(frame: Frame, spec: Spec, s: float) -> Dictionary:
	var c := Vector3(spec.axle_x[0] if not spec.axle_x.is_empty() else 0.0, spec.centre_h(), 0.0)
	c.z = s * spec.track_z
	var kits := MeshKits.new(frame, Transform3D(Basis.IDENTITY, -frame.p(c.x, c.y, c.z)))
	_tyre(kits.k(&"rubber"), spec, c, s)
	_disc(kits.k(&"body"), spec, c, s)
	if spec.hub_detail:
		if spec.inflation_hub:
			_inflation_hub(kits, spec, c, s)
		else:
			_hub_cap(kits.k(&"dark"), spec, c, s)
	return kits.commit_all()


## Lathe basis (local +Y) pointing out of the vehicle side `s`.
static func _out_basis(s: float) -> Basis:
	return Basis(Vector3.RIGHT, PI / 2.0 if s > 0.0 else -PI / 2.0)


## Tyre carcass as one lathe ring (outer bead -> bulging outer sidewall -> rounded shoulder ->
## crown -> plain inner sidewall -> inner bead) and the lugs.
static func _tyre(rubber: MeshKit, spec: Spec, c: Vector3, s: float) -> void:
	var r := spec.wheel_radius
	var w := spec.tyre_width
	var crown := r - spec.lug_depth if spec.tread else r
	var bead := spec.rim_share * r
	(
		rubber
		. lathe(
			c,
			_out_basis(s),
			[
				Vector2(bead, 0.39 * w),
				Vector2(bead + 0.07 * r, 0.47 * w),
				Vector2(0.8 * r, 0.5 * w),
				Vector2(0.93 * r, 0.47 * w),
				Vector2(crown, 0.36 * w),
				Vector2(crown, -0.36 * w),
				Vector2(0.9 * r, -0.48 * w),
				Vector2(bead, -0.42 * w),
			],
			spec.wheel_sides
		)
	)
	if spec.tread:
		_lugs(rubber, spec, c, s)


## Directional lugs: the outer row runs from the tyre centre over the outer shoulder (chamfered,
## the part the camera sees), the inner row (half a pitch later, slanted the other way: chevrons)
## stays on the crown as plain blocks; no lugs on the inner shoulder.
static func _lugs(rubber: MeshKit, spec: Spec, c: Vector3, s: float) -> void:
	var r := spec.wheel_radius
	var w := spec.tyre_width
	var depth := spec.lug_depth
	var embed := 0.05 * r
	var pitch := TAU / spec.tread_lugs
	var lug_w := r * pitch * 0.42
	var angle := deg_to_rad(spec.lug_angle_deg)
	# Axial lengths chosen so the slanted lugs stay inside the tyre width.
	var outer_len := (0.47 * w - lug_w * sin(angle)) / cos(angle)
	var inner_len := (0.3 * w - lug_w * sin(angle)) / cos(angle)
	var radial := r - (depth + embed) / 2.0
	for i in spec.tread_lugs:
		for row in 2:
			var a := pitch * (i + 0.5 * row)
			var radius_dir := Vector3(cos(a), sin(a), 0.0)
			var tangent := Vector3(-sin(a), cos(a), 0.0)
			var out := 1.0 if row == 0 else -1.0  # outer or inner row
			var z_mid := 0.5 * w - outer_len / 2.0 if row == 0 else -0.04 * w - inner_len / 2.0
			var at := c + radius_dir * radial + Vector3(0, 0, s * z_mid)
			# Right-handed lug basis: x tangential, y radial, z axial; slanted about the radius.
			var rot := (
				Basis(tangent, radius_dir, Vector3(0, 0, -1)) * Basis(Vector3.UP, s * out * angle)
			)
			var length := outer_len if row == 0 else inner_len
			var size := Vector3(lug_w, depth + embed, length)
			rubber.cbox(at, size, depth * 0.3 if row == 0 else 0.0, rot)


## Wheel disc: the hub face (bolt ring) recessed in a dished disc, the rim flange, then a hidden
## band inside the tyre to the plain inner disc that closes the wheel.
static func _disc(body: MeshKit, spec: Spec, c: Vector3, s: float) -> void:
	var r := spec.wheel_radius
	var w := spec.tyre_width
	var rim := spec.rim_share * r
	var prof: Array
	if spec.hub_detail:
		prof = [
			Vector2(0.0, 0.27 * w),
			Vector2(0.62 * rim, 0.27 * w),
			Vector2(0.7 * rim, 0.235 * w),
			Vector2(0.84 * rim, 0.17 * w),
			Vector2(0.92 * rim, 0.18 * w),
			Vector2(0.96 * rim, 0.38 * w),
			Vector2(rim + 0.01, 0.41 * w),
			Vector2(rim + 0.01, 0.35 * w),
			Vector2(0.96 * rim, -0.4 * w),
			Vector2(0.0, -0.4 * w),
		]
	else:
		prof = [
			Vector2(0.0, 0.3 * w),
			Vector2(rim + 0.01, 0.3 * w),
			Vector2(0.96 * rim, -0.4 * w),
			Vector2(0.0, -0.4 * w),
		]
	body.lathe(c, _out_basis(s), prof, spec.wheel_sides)
	if spec.hub_detail:
		for k in spec.hub_bolts:
			var a := TAU * k / spec.hub_bolts
			var at := c + Vector3(cos(a) * 0.42 * rim, sin(a) * 0.42 * rim, s * 0.27 * w)
			body.bolt(at, Vector3(0, 0, s), 0.055 * rim)


## Plain hub cap in the disc centre.
static func _hub_cap(dark: MeshKit, spec: Spec, c: Vector3, s: float) -> void:
	var rim := spec.rim_share * spec.wheel_radius
	var w := spec.tyre_width
	(
		dark
		. lathe(
			c,
			_out_basis(s),
			[
				Vector2(0.0, 0.37 * w),
				Vector2(0.16 * rim, 0.37 * w),
				Vector2(0.2 * rim, 0.34 * w),
				Vector2(0.25 * rim, 0.27 * w),
			],
			10
		)
	)


## Central tyre-inflation hub: a stepped housing standing out of the disc with a rotary union on
## the axis and an air line curving to the valve at the rim.
static func _inflation_hub(kits: MeshKits, spec: Spec, c: Vector3, s: float) -> void:
	var rim := spec.rim_share * spec.wheel_radius
	var w := spec.tyre_width
	var dark := kits.k(&"dark")
	(
		dark
		. lathe(
			c,
			_out_basis(s),
			[
				Vector2(0.0, 0.44 * w),
				Vector2(0.1 * rim, 0.44 * w),
				Vector2(0.12 * rim, 0.42 * w),
				Vector2(0.12 * rim, 0.39 * w),
				Vector2(0.24 * rim, 0.37 * w),
				Vector2(0.28 * rim, 0.34 * w),
				Vector2(0.33 * rim, 0.27 * w),
			],
			12
		)
	)
	var valve := c + Vector3(0.0, 0.8 * rim, s * 0.2 * w)
	(
		dark
		. tube(
			[
				c + Vector3(0.0, 0.2 * rim, s * 0.37 * w),
				c + Vector3(0.0, 0.5 * rim, s * 0.31 * w),
				c + Vector3(0.0, 0.72 * rim, s * 0.23 * w),
				valve,
			],
			0.03 * rim,
			6
		)
	)
	dark.cbox(valve, Vector3(0.12 * rim, 0.1 * rim, 0.08 * rim), 0.01 * rim)


## Arch liner over the wheel at `x`, side z: a curved strip (plate of an annular sector, 20° to
## 160° above the axle) across the tyre width.
static func _arch_liner(dark: MeshKit, spec: Spec, x: float, z: float) -> void:
	var r_in := spec.wheel_radius + spec.arch_gap
	var r_out := r_in + spec.arch_thickness
	var h := spec.centre_h()
	var outline: Array = []
	var segments := 10
	for i in segments + 1:
		var a := lerpf(deg_to_rad(20.0), deg_to_rad(160.0), float(i) / segments)
		outline.append(Vector2(x + cos(a) * r_out, h + sin(a) * r_out))
	for i in range(segments, -1, -1):
		var a := lerpf(deg_to_rad(20.0), deg_to_rad(160.0), float(i) / segments)
		outline.append(Vector2(x + cos(a) * r_in, h + sin(a) * r_in))
	var hw := spec.tyre_width / 2.0 + 0.05
	dark.plate(
		outline,
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.UP,
		Vector3.BACK,
		z - hw,
		z + hw,
		spec.arch_thickness * 0.3
	)
