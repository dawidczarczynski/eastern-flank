class_name StaffMapPlaceName
extends RefCounted
## Names a hex by the nearest place of the imported map: "Suwałki, 5 km east" (the place stays in
## the nominative, so no Polish declension is needed). Pure maths over the map's place list.


## The place name of `coord` through `namer` ((Vector2i) -> String, set by the panel's owner), or ""
## when there is no namer or no name: the caller then falls back to the hex number.
static func named(namer: Callable, coord: Vector2i) -> String:
	return String(namer.call(coord)) if namer.is_valid() else ""


## Translated "Place, N km direction" of the place nearest to `coord`; "" when the map has none.
static func describe(map: ImportedMap, coord: Vector2i) -> String:
	var place := BattleName.place(map, coord)
	if place.is_empty():
		return ""
	if int(place["km"]) == 0:
		return place["name"]
	return (
		TranslationServer.translate("%s, %d km %s")
		% [place["name"], int(place["km"]), TranslationServer.translate(place["dir"])]
	)
