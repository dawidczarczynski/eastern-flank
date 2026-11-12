class_name StaffMapLauncherGlyphs
extends RefCounted
## The silhouettes of the strike launcher markers (TASK-147, variant B of
## docs/design/operational_map/strike_launcher_marker.html): fighter, bomber, ship, submarine,
## truck launcher and drone launch site as filled polygons in the mockup's 24 x 24 box, nose /
## bow to the right (symbols g-fighter … g-drone_site); the old `aircraft` kind is drawn as a
## fighter; an unknown kind is a plain dot (g-dot). Pure geometry, nothing is
## drawn here: StaffMapStrikeLayer scales the polygons to the 28 px glyph, outlines them with the
## halo and fills them.

const BOX := 24.0
const CIRCLE_SEGMENTS := 14
const CURVE_SEGMENTS := 6
const DOT := &"dot"
const KINDS: Array[StringName] = [
	&"fighter", &"bomber", &"ship", &"submarine", &"launcher", &"drone_site"
]
## Older kinds drawn with another kind's silhouette.
const ALIASES := {&"aircraft": &"fighter"}

static var _cache := {}


## The shape drawn for a launcher kind: the kind itself when it has a silhouette, else DOT.
static func shape_of(kind: Variant) -> StringName:
	var name := StringName(str(kind)) if kind != null else &""
	name = ALIASES.get(name, name)
	return name if KINDS.has(name) else DOT


## {fills: Array[PackedVector2Array], cutouts: Array[PackedVector2Array]} of a kind (DOT for an
## unknown one), in the 24 x 24 box. Cutouts are holes of the mockup (the aircraft canopy) drawn
## in the halo colour on top of the fill.
static func shape(kind: Variant) -> Dictionary:
	var key := shape_of(kind)
	if not _cache.has(key):
		_cache[key] = _build(key)
	return _cache[key]


static func _build(key: StringName) -> Dictionary:
	var fills: Array[PackedVector2Array] = []
	var cutouts: Array[PackedVector2Array] = []
	match key:
		&"fighter":
			# fmt: off
			(
				fills
				. append(
					_poly(
						[
							23,
							12,
							19.6,
							10.7,
							15.6,
							10.3,
							9.6,
							2.4,
							6.8,
							2.4,
							9.4,
							10.3,
							6.2,
							10.5,
							3.8,
							7.2,
							1.8,
							7.2,
							3,
							11,
							1,
							11.5,
							1,
							12.5,
							3,
							13,
							1.8,
							16.8,
							3.8,
							16.8,
							6.2,
							13.5,
							9.4,
							13.7,
							6.8,
							21.6,
							9.6,
							21.6,
							15.6,
							13.7,
							19.6,
							13.3,
						]
					)
				)
			)
			# fmt: on
			cutouts.append(_ellipse(Vector2(15.1, 12.0), Vector2(2.3, 0.9)))
		&"bomber":
			# Heavy four-engine bomber: long, nearly straight wings, tailplane, engine nacelles.
			fills.append(_poly([23, 12, 21.5, 11, 4, 11, 1.5, 11.4, 1.5, 12.6, 4, 13, 21.5, 13]))
			fills.append(_poly([14.6, 11.2, 11.6, 1.2, 9.8, 1.2, 9.4, 11.2]))
			fills.append(_poly([14.6, 12.8, 11.6, 22.8, 9.8, 22.8, 9.4, 12.8]))
			fills.append(_poly([4.6, 11.4, 2.6, 6.4, 1.2, 6.4, 1.8, 11.4]))
			fills.append(_poly([4.6, 12.6, 2.6, 17.6, 1.2, 17.6, 1.8, 12.6]))
			for y: float in [3.6, 7.3, 15.3, 19.0]:
				var x := 11.6 + (absf(y + 0.7 - 12.0) * -1.0 + 10.8) / 10.0 * 3.0
				fills.append(_rect(x - 1.0, y, 3.2, 1.4))
		&"ship":
			fills.append(
				_poly([1, 12.5, 14, 12.5, 17, 11.4, 23, 11.4, 20.6, 17.6, 3, 17.6, 1, 15.6])
			)
			fills.append(_poly([6, 12.5, 6, 9.6, 9, 9.6, 9, 7.6, 13, 7.6, 14.6, 10, 14.6, 12.5]))
			fills.append(_rect(10.6, 3.4, 1.0, 4.2))
			fills.append(_rect(9.2, 4.6, 3.8, 1.0))
			fills.append(_rect(16, 9.5, 3, 1.9))
			fills.append(_rect(19, 10, 3, 0.8))
		&"submarine":
			fills.append(_submarine_hull())
			fills.append(_rect(11.3, 5.4, 0.9, 2.6))
			fills.append(_poly([2.8, 14.2, 0.8, 11.8, 2.4, 11.8, 4.6, 13.4]))
			fills.append(_poly([2.8, 15.8, 0.8, 18.2, 2.4, 18.2, 4.6, 16.6]))
			fills.append(_poly([15, 17.4, 16.4, 19.8, 18, 19.8, 17.6, 17.4]))
		&"launcher":
			fills.append(_rect(1.5, 15, 21.3, 2.4))
			fills.append(_poly([16.8, 15, 16.8, 10.4, 20.4, 10.4, 22.8, 13, 22.8, 15]))
			fills.append(_poly([2, 14.6, 13.4, 5, 15.6, 7.3, 4.6, 14.6]))
			fills.append(_rect(2, 13.6, 4.4, 1.4))
			for x: float in [5.0, 9.6, 16.0, 20.4]:
				fills.append(_ellipse(Vector2(x, 19.2), Vector2(1.9, 1.9)))
		&"drone_site":
			fills.append(_poly([22.5, 9.5, 7, 3, 7, 4.4, 11, 9.5, 7, 14.6, 7, 16]))
			fills.append(_rect(2.8, 7.6, 0.9, 3.8))
			fills.append(_rect(3.7, 8.8, 2.7, 1.4))
			fills.append(_rect(4, 17.6, 16, 1.2))
			fills.append(_rect(2, 20, 20, 1.4))
			fills.append(_rect(5, 18.8, 1.4, 1.2))
			fills.append(_rect(17.6, 18.8, 1.4, 1.2))
		_:
			fills.append(_ellipse(Vector2(12, 12), Vector2(4.5, 4.5)))
	return {"fills": fills, "cutouts": cutouts}


static func _poly(xy: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		points.append(Vector2(float(xy[i]), float(xy[i + 1])))
	return points


static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
	)


static func _ellipse(centre: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in CIRCLE_SEGMENTS:
		var angle := TAU * i / CIRCLE_SEGMENTS
		points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


## The g-submarine hull with its sail: the mockup's cubic curves sampled.
static func _submarine_hull() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(2.5, 15)])
	_cubic(points, Vector2(2.5, 15), Vector2(2.5, 13.2), Vector2(5, 12.4), Vector2(8, 12.4))
	# fmt: off
	(
		points
		. append_array(
			_poly(
				[
					9.8,
					12.4,
					9.8,
					9.8,
					10.5,
					9.8,
					10.5,
					8,
					13,
					8,
					13,
					9.8,
					13.8,
					9.8,
					13.8,
					12.4,
					17,
					12.4,
				]
			)
		)
	)
	# fmt: on
	_cubic(points, Vector2(17, 12.4), Vector2(20.5, 12.4), Vector2(23, 13.4), Vector2(23, 15))
	_cubic(points, Vector2(23, 15), Vector2(23, 16.6), Vector2(20.5, 17.6), Vector2(17, 17.6))
	points.append(Vector2(8, 17.6))
	_cubic(points, Vector2(8, 17.6), Vector2(5, 17.6), Vector2(2.5, 16.8), Vector2(2.5, 15))
	points.remove_at(points.size() - 1)  # closes on the first point
	return points


## Appends the points of a cubic Bezier after its start point.
static func _cubic(
	points: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2
) -> void:
	for i in range(1, CURVE_SEGMENTS + 1):
		var t := float(i) / CURVE_SEGMENTS
		var u := 1.0 - t
		points.append(u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3)
