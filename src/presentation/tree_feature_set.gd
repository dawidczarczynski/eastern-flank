class_name TreeFeatureSet
extends RefCounted
## The real tree features of an imported map (TASK-199a data, TASK-199b drawing) in the view's
## metres (east x, south y of tile (0, 0)'s centre, MapScale.metres_per_unit per world unit, like
## RealParcels): single trees, open tree-row polylines, orchard and farmyard polygons (outer ring
## first, then holes). Pure data with the bounds the chunked planner uses to skip features far
## from a chunk.

var points := PackedVector2Array()
var rows: Array[PackedVector2Array] = []
## Orchards and farmyards: Array of Array[PackedVector2Array] (rings).
var orchards: Array = []
var farmyards: Array = []
var row_bounds: Array[Rect2] = []
var orchard_bounds: Array[Rect2] = []
var farmyard_bounds: Array[Rect2] = []


## The features of `map` in view metres; null when it has none.
static func from_imported(map: ImportedMap) -> TreeFeatureSet:
	if map == null or not map.has_tree_features():
		return null
	var k := MapScale.metres_per_unit / map.metres_per_world_unit()
	var scale := Transform2D.IDENTITY.scaled(Vector2(k, k))
	var points := PackedVector2Array()
	for i in map.tree_point_count():
		points.append(map.tree_point(i) * k)
	var rows: Array[PackedVector2Array] = []
	for i in map.tree_row_count():
		rows.append(scale * map.tree_row_polyline(i))
	var orchards: Array = []
	for i in map.orchard_count():
		orchards.append(_scaled(map.orchard_polygon(i), scale))
	var farmyards: Array = []
	for i in map.farmyard_count():
		farmyards.append(_scaled(map.farmyard_polygon(i), scale))
	return make(points, rows, orchards, farmyards)


## A set of the given features (view metres); computes the bounds.
static func make(
	points: PackedVector2Array, rows: Array[PackedVector2Array], orchards: Array, farmyards: Array
) -> TreeFeatureSet:
	var result := TreeFeatureSet.new()
	result.points = points
	result.rows = rows
	result.orchards = orchards
	result.farmyards = farmyards
	for row in rows:
		result.row_bounds.append(bounds_of(row))
	for polygon: Array in orchards:
		result.orchard_bounds.append(bounds_of(polygon[0]))
	for polygon: Array in farmyards:
		result.farmyard_bounds.append(bounds_of(polygon[0]))
	return result


## The smallest rectangle around `points` (zero rectangle for none).
static func bounds_of(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var result := Rect2(points[0], Vector2.ZERO)
	for p in points:
		result = result.expand(p)
	return result


static func _scaled(rings: Array[PackedVector2Array], scale: Transform2D) -> Array:
	var result: Array[PackedVector2Array] = []
	for ring in rings:
		result.append(scale * ring)
	return result
