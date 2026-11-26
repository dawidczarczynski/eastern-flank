class_name VegetationRanges
extends RefCounted
## Distances and densities of real-scale vegetation (TASK-135, ADR 0026), pure and static: the
## metre values of LookPreset.vegetation() turned into world units through MapScale, so they hold
## at any map scale. Only the `true` VisualScale preset uses them.
##
## A tree is drawn as a full 3D tree (TreeMeshes LOD0) up to its full range, as an impostor
## (TreeImpostors) up to its impostor range and, on a forest tile, beyond that by the canopy shell
## (ForestShell); off-forest items keep the impostor until it is under `vanish_angle`. The ranges
## scale with the item's real height (a tree half as tall swaps at half the distance: the same
## size on screen), with floors for small scrub. Each tree swaps at its own point of a band of
## +- band_share around a range (TreeField / foliage_body.gdshaderinc), so a stand changes tree by
## tree.

const HECTARE_M2 := 10000.0


## The active values (LookPreset.vegetation()) unless `values` is given (tests).
static func values(values_override: Dictionary = {}) -> Dictionary:
	return values_override if not values_override.is_empty() else LookPreset.vegetation()


## Area of one hex in m² at the current MapScale (circumradius = one world unit).
static func hex_area_m2() -> float:
	var m := MapScale.metres_per_unit
	return 1.5 * Hex.SQRT3 * m * m


## Visual trees per forest hex (planned trees + ForestFill) from the density per hectare and the
## hex area of MapScale: ~2 000 at the 250 m hex.
static func trees_per_hex(v: Dictionary = {}) -> float:
	return float(values(v)["forest_trees_per_ha"]) * hex_area_m2() / HECTARE_M2


## Full 3D range of an item `height_m` tall, world units.
static func full_range(height_m: float, v: Dictionary = {}) -> float:
	var d := values(v)
	var metres := maxf(
		float(d["full_range_m"]) * height_m / float(d["reference_height_m"]),
		float(d["min_full_range_m"])
	)
	return MapScale.to_units(metres)


## Impostor range of an item `height_m` tall (where the canopy shell takes over on forest
## tiles), world units.
static func impostor_range(height_m: float, v: Dictionary = {}) -> float:
	var d := values(v)
	var metres := maxf(
		float(d["impostor_range_m"]) * height_m / float(d["reference_height_m"]),
		float(d["min_impostor_range_m"])
	)
	return MapScale.to_units(metres)


## Where an off-forest item's impostor is smaller than vanish_angle, world units (never closer
## than its impostor range).
static func vanish_range(height_m: float, v: Dictionary = {}) -> float:
	var d := values(v)
	return maxf(MapScale.to_units(height_m / float(d["vanish_angle"])), impostor_range(height_m, v))


## The hand-over band (begin, end) around `distance`.
static func band(distance: float, v: Dictionary = {}) -> Vector2:
	var share := float(values(v)["band_share"])
	return Vector2(distance * (1.0 - share), distance * (1.0 + share))


## Real height (m) of a species under the `true` preset (VisualScale.TRUE_HEIGHTS_M; unknown
## species: the mixed-forest mean).
static func species_height_m(species: StringName) -> float:
	return VisualScale.TRUE_HEIGHTS_M.get(species, VisualScale.TRUE_HEIGHTS_M[&"tree"])
