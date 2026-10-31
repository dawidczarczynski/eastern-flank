class_name BurntGround
extends RefCounted
## Scorched ground around a wreck: the planted scatter (bushes, trees, undergrowth, twigs) inside
## the circle disappears, rocks stay but turn dark and sooty. Works on the built MultiMeshes of a
## MapView in place; grass and flowers are handled by GrassField.add_clearing().

const SOOT_COLOR := Color("#2a2622")
const HIDDEN_SCALE := 0.0001
## MapView's rock chunks are "Rocks_<x>_<z>" (under a "Rocks" node).
const ROCK_NODE_NAME := "Rocks"


## Indices of the instances of a node at `node_position` whose transform origins lie within
## `radius` of `center` (XZ plane).
static func indices_within(
	transforms: Array[Transform3D], node_position: Vector3, center: Vector2, radius: float
) -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in transforms.size():
		var p := node_position + transforms[i].origin
		if Vector2(p.x, p.z).distance_to(center) < radius:
			result.append(i)
	return result


## Burns every scatter instance of `root`'s subtree (the playable map, not the backdrop).
static func burn(root: Node, center: Vector2, radius: float) -> void:
	for node: Node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var instance := node as MultiMeshInstance3D
		if instance.multimesh == null or _is_excluded(instance):
			continue
		var multi := instance.multimesh
		var transforms: Array[Transform3D] = []
		for i in multi.instance_count:
			transforms.append(multi.get_instance_transform(i))
		var hit := indices_within(transforms, instance.position, center, radius)
		var is_rock := instance.name.begins_with(ROCK_NODE_NAME)
		for i in hit:
			if is_rock:
				multi.set_instance_color(i, SOOT_COLOR)
			else:
				var t := transforms[i]
				multi.set_instance_transform(
					i, Transform3D(Basis.from_scale(Vector3.ONE * HIDDEN_SCALE), t.origin)
				)


static func _is_excluded(instance: MultiMeshInstance3D) -> bool:
	if instance.name.begins_with("Backdrop") or instance.get_meta(&"backdrop", false):
		return true
	var ancestor := instance.get_parent()
	while ancestor != null:
		if ancestor is GrassField:
			return true
		ancestor = ancestor.get_parent()
	return false
