class_name TreeSpecies
extends RefCounted
## Species, variant and per-instance variation of a planned tree (TASK-060). Pure and static: a
## hash of the planned `position` and `k` (ScatterPlanner), never a random number generator, so
## the same plan always gives the same forest. Conifers (ScatterPlanner's high-ground rule) become
## pine or spruce, the others birch, oak or alder.
##
## `custom` is the tree's INSTANCE_CUSTOM in assets/shaders/foliage.gdshader: r = hue shift,
## g = value factor, b = saturation factor, a = wind phase in [0, 1).

const CONIFERS: Array[StringName] = [&"pine", &"spruce"]
const DECIDUOUS: Array[StringName] = [&"birch", &"oak", &"alder"]
## Shares of each species within its group (sum 1 per group).
const SHARES := {&"pine": 0.6, &"spruce": 0.4, &"birch": 0.35, &"oak": 0.3, &"alder": 0.35}
const HUE_SHIFT := 0.03
const VALUE_MIN := 0.85
const VALUE_MAX := 1.1
const SATURATION_MIN := 0.9
const SATURATION_MAX := 1.05
## Odd yellower deciduous tree: share of deciduous trees and its hue shift (towards yellow).
const AUTUMN_SHARE := 0.04
const AUTUMN_HUE_MIN := 0.04
const AUTUMN_HUE_MAX := 0.07


## {species: StringName, variant: int (0..TreeMeshes.VARIANTS - 1), custom: Color}.
static func pick(tree: Dictionary) -> Dictionary:
	var p: Vector3 = tree["position"]
	var k: float = tree["k"]
	var conifer: bool = tree["conifer"]
	var group := CONIFERS if conifer else DECIDUOUS
	var roll := _hash(p, k, 1)
	var species: StringName = group[group.size() - 1]
	var acc := 0.0
	for candidate in group:
		acc += LookPreset.share(candidate, SHARES[candidate])
		if roll < acc:
			species = candidate
			break
	# Scrub (shrub, undergrowth) is planned with its species; only variant and colour vary.
	if tree.has("species"):
		species = tree["species"]
	var variant := mini(int(_hash(p, k, 2) * TreeMeshes.VARIANTS), TreeMeshes.VARIANTS - 1)
	var hue := (_hash(p, k, 3) * 2.0 - 1.0) * HUE_SHIFT
	if not conifer and _hash(p, k, 7) < LookPreset.autumn_share(AUTUMN_SHARE):
		hue = lerpf(AUTUMN_HUE_MIN, AUTUMN_HUE_MAX, _hash(p, k, 8))
	var custom := Color(
		hue,
		lerpf(VALUE_MIN, VALUE_MAX, _hash(p, k, 4)),
		lerpf(SATURATION_MIN, SATURATION_MAX, _hash(p, k, 5)),
		_hash(p, k, 6)
	)
	return {"species": species, "variant": variant, "custom": custom}


static func is_conifer(species: StringName) -> bool:
	return CONIFERS.has(species)


static func all() -> Array[StringName]:
	var result: Array[StringName] = []
	result.append_array(CONIFERS)
	result.append_array(DECIDUOUS)
	return result


## Deterministic hash of a planned tree into [0, 1); `salt` gives independent values.
static func _hash(p: Vector3, k: float, salt: int) -> float:
	var s := (
		sin(p.x * 127.1 + p.z * 311.7 + p.y * 74.7 + k * 269.5 + salt * 183.31 + salt * salt * 0.37)
		* 43758.5453
	)
	return s - floor(s)
