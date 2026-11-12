class_name StaffMapPlaceName
extends RefCounted
## Names a hex by the nearest place of the imported map: "Suwałki, 5 km east" (the place stays in
## the nominative, so no Polish declension is needed). Pure maths over the map's place list.

const COMPASS: Array[String] = [
	"DIR_E", "DIR_SE", "DIR_S", "DIR_SW", "DIR_W", "DIR_NW", "DIR_N", "DIR_NE"
]
## Closer than this (km) the bare place name is enough.
const NEAR_KM := 1.5


## Translated "Place, N km direction" of the place nearest to `coord`; "" when the map has none.
static func describe(map: ImportedMap, coord: Vector2i) -> String:
	if map == null or map.place_count() == 0:
		return ""
	var at := Hex.to_world(coord, 1.0)
	var here := Vector2(at.x, at.z)
	var best := -1
	var best_distance := INF
	for i in map.place_count():
		var distance := here.distance_to(map.place_at(i)["position"])
		if distance < best_distance:
			best_distance = distance
			best = i
	var place: Dictionary = map.place_at(best)
	var km := best_distance * map.hex_spacing_m / Hex.SQRT3 / 1000.0
	if km < NEAR_KM:
		return place["name"]
	var offset: Vector2 = here - place["position"]  # from the place to the hex; +y is south
	var sector := posmod(roundi(atan2(offset.y, offset.x) / (TAU / 8.0)), 8)
	return (
		TranslationServer.translate("%s, %d km %s")
		% [place["name"], roundi(km), TranslationServer.translate(COMPASS[sector])]
	)
