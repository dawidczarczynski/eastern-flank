class_name WeaponModels
extends RefCounted
## Registry of the strike weapon models (TASK-144): procedural turntable models of the strike
## means (data/strike/<id>.tres) shown by the strike panel's model card (WeaponTurntable).
## One file per weapon, src/presentation/models/weapons/<means_id>.gd with
## `static func build() -> Node3D`, listed in MODELS.
##
## Weapon model contract (unlike the unit models: no faction, mechanisms, footprint or battle
## scene): 1 unit = 1 m, origin at the centre of mass, nose along +X, wings and fins deployed,
## <= MAX_TRIANGLES triangles, plain PBR materials from the ModelParts palette. Catalog entries
## with the real dimensions: docs/design/units/weapons/<means_id>/unit.json.

const MODELS := {
	&"jassm_er": preload("res://src/presentation/models/weapons/jassm_er.gd"),
}
const MAX_TRIANGLES := 400


static func has_model(means_id: StringName) -> bool:
	return MODELS.has(means_id)


## The weapon's model (an independent copy, built once and cached), or null when the weapon has
## none (the panel then shows the class glyph).
static func build(means_id: StringName) -> Node3D:
	if not has_model(means_id):
		return null
	return ModelParts.cached("weapon:%s" % means_id, Callable(MODELS[means_id], "build"))
