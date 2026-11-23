class_name Bridges
extends RefCounted
## The small bridges where a road crosses a river (TASK-108c): one merged ArrayMesh `Bridges` for
## the whole map (one draw call) from FeatureRibbonPlanner.bridges sites. Per site: a deck (two
## sloping halves meeting at mid-span, so both ends meet the road ribbon and the middle stands
## DECK_CLEARANCE_M above the water), two railings and two abutment blocks, at most
## MAX_TRIANGLES triangles. Look values, not balance data.

const DECK_THICKNESS_M := 0.6
const DECK_CLEARANCE_M := 1.5
const RAIL_WIDTH_M := 0.3
const RAIL_HEIGHT_M := 1.0
## Abutment block: length along the road, and how far it reaches below the ground.
const ABUTMENT_LENGTH_M := 1.5
const ABUTMENT_DEPTH_M := 1.0
const MAX_TRIANGLES := 60
const COLOR := Color("#8d8b84")
const ROUGHNESS := 0.9


## One `Bridges` MeshInstance3D for `sites` (FeatureRibbonPlanner.bridges); `drape` is
## Callable(points: PackedVector2Array, lift: float) -> PackedVector3Array (MapView._drape).
## Null without sites. `shadows`: the bridges cast shadows (GraphicsQuality `shadows`).
static func build(sites: Array[Dictionary], drape: Callable, shadows := true) -> MeshInstance3D:
	if sites.is_empty():
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for site in sites:
		_append_bridge(vertices, normals, profile(site, drape))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	var instance := MeshInstance3D.new()
	instance.name = "Bridges"
	instance.mesh = mesh
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return instance


static func material() -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = COLOR
	result.roughness = ROUGHNESS
	return result


## Where a bridge stands: {a, b: deck top at the two ends, mid: deck top at mid-span (Vector3),
## along: unit XZ direction, side: unit XZ direction across, half_span, half_width (world units),
## ground_a, ground_b: terrain height under the ends}. Deck ends sit on the road ribbon height,
## the middle at least DECK_CLEARANCE_M above the river surface.
static func profile(site: Dictionary, drape: Callable) -> Dictionary:
	var centre: Vector2 = site["position"]
	var along: Vector2 = site["direction"]
	var half_span := MapScale.to_units(site["span_m"]) / 2.0
	var end_a := centre - along * half_span
	var end_b := centre + along * half_span
	var road_lift := FeatureRibbonPlanner.lift(FeatureRibbonPlanner.Kind.ROAD)
	var river_lift := FeatureRibbonPlanner.lift(FeatureRibbonPlanner.Kind.RIVER)
	var road: PackedVector3Array = drape.call(PackedVector2Array([end_a, end_b]), road_lift)
	var ground: PackedVector3Array = drape.call(PackedVector2Array([end_a, end_b]), 0.0)
	var water: PackedVector3Array = drape.call(PackedVector2Array([centre]), river_lift)
	var mid_y := maxf(
		water[0].y + MapScale.to_units(DECK_CLEARANCE_M), (road[0].y + road[1].y) / 2.0
	)
	return {
		"a": road[0],
		"b": road[1],
		"mid": Vector3(centre.x, mid_y, centre.y),
		"along": along,
		"side": Vector2(-along.y, along.x),
		"half_span": half_span,
		"half_width": MapScale.to_units(site["width_m"]) / 2.0,
		"ground_a": ground[0].y,
		"ground_b": ground[1].y,
	}


static func _append_bridge(
	vertices: PackedVector3Array, normals: PackedVector3Array, p: Dictionary
) -> void:
	var side2: Vector2 = p["side"]
	var side := Vector3(side2.x, 0.0, side2.y)
	var half_width: float = p["half_width"]
	var thick := MapScale.to_units(DECK_THICKNESS_M)
	var rail_w := MapScale.to_units(RAIL_WIDTH_M)
	var rail_h := MapScale.to_units(RAIL_HEIGHT_M)
	var tops: Array[Vector3] = [p["a"], p["mid"], p["b"]]
	var up_dir := Vector3.UP
	# Deck: top, underside and the two outer faces of each half.
	for k in 2:
		var t0 := tops[k]
		var t1 := tops[k + 1]
		var d0 := t0 - Vector3.UP * thick
		var d1 := t1 - Vector3.UP * thick
		var w := side * half_width
		_quad(vertices, normals, [t0 - w, t0 + w, t1 + w, t1 - w], up_dir)
		_quad(vertices, normals, [d0 - w, d1 - w, d1 + w, d0 + w], -up_dir)
		for s in [-1.0, 1.0]:
			var o: Vector3 = w * s
			_quad(vertices, normals, [d0 + o, d1 + o, t1 + o, t0 + o], side * s)
		# Railings: top, outer and inner face of a box along each edge.
		for s in [-1.0, 1.0]:
			var outer: Vector3 = w * s
			var inner: Vector3 = side * (half_width - rail_w) * s
			var up := Vector3.UP * rail_h
			_quad(
				vertices,
				normals,
				[t0 + outer + up, t1 + outer + up, t1 + inner + up, t0 + inner + up],
				up_dir
			)
			_quad(
				vertices,
				normals,
				[t0 + outer, t1 + outer, t1 + outer + up, t0 + outer + up],
				side * s
			)
			_quad(
				vertices,
				normals,
				[t0 + inner, t0 + inner + up, t1 + inner + up, t1 + inner],
				-side * s
			)
	# Abutments: blocks under the two ends, from below the ground up to the deck's underside.
	var along2: Vector2 = p["along"]
	var along := Vector3(along2.x, 0.0, along2.y)
	var length := MapScale.to_units(ABUTMENT_LENGTH_M)
	var depth := MapScale.to_units(ABUTMENT_DEPTH_M)
	for end in 2:
		var top: Vector3 = (p["a"] if end == 0 else p["b"]) - Vector3.UP * thick
		var ground_y: float = p["ground_a"] if end == 0 else p["ground_b"]
		var bottom_y := minf(ground_y - depth, top.y - 0.001)
		var toward_mid := along if end == 0 else -along
		var inward := toward_mid * length
		var base := Vector3(top.x, bottom_y, top.z)
		var lo := base - side * half_width
		var hi := base + side * half_width
		var up := Vector3.UP * (top.y - bottom_y)
		# Front (towards mid-span) and the two sides.
		_quad(
			vertices,
			normals,
			[lo + inward, hi + inward, hi + inward + up, lo + inward + up],
			toward_mid
		)
		_quad(vertices, normals, [lo, lo + inward, lo + inward + up, lo + up], -side)
		_quad(vertices, normals, [hi, hi + up, hi + inward + up, hi + inward], side)


## The quad with corners `c` (in order around it) as two triangles facing `outward` (flat
## normal, wound clockwise seen from outside like Godot's front faces).
static func _quad(
	vertices: PackedVector3Array, normals: PackedVector3Array, c: Array, outward: Vector3
) -> void:
	var normal: Vector3 = (c[1] - c[0]).cross(c[3] - c[0]).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	for tri: Array in [[c[0], c[1], c[2]], [c[0], c[2], c[3]]]:
		# A front face is clockwise seen from outside: its geometric normal points inward.
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(normal) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for v in tri:
			vertices.append(v)
			normals.append(normal)
