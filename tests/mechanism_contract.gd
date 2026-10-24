extends RefCounted
## Test-only helper for the unit mechanisms contract (TASK-043): reads the registry
## (docs/design/units/mechanisms.json) and the catalog entries, and checks a model's pivots and
## `mechanisms` metadata against them. The game itself never reads docs/.

const REGISTRY := "res://docs/design/units/mechanisms.json"
const CATALOG := "res://docs/design/units/units/%s/unit.json"
const MAX_INDEX := 64


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data


## The mechanism registry: id -> entry (the entries carry their `id` too).
static func load_registry() -> Dictionary:
	var result := {}
	var data: Variant = _read_json(REGISTRY)
	if data is Array:
		for entry: Dictionary in data:
			result[entry["id"]] = entry
	return result


## `mechanisms` of the unit's catalog entry; null if the unit has no entry.
static func load_catalog_mechanisms(unit_id: String) -> Variant:
	var data: Variant = _read_json(CATALOG % unit_id)
	if not data is Dictionary:
		return null
	return data.get("mechanisms", {})


## Violations of the pivots a mechanism entry (registry) requires of the model: `path` with `{i}`
## counts consecutive indices from 0 and needs `min` of them, every found node needs the nodes
## in `with` and the metadata keys in `meta`; a path without `{i}` must exist.
static func pivot_violations(model: Node, mechanism_entry: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var id: String = mechanism_entry.get("id", "?")
	for pivot: Dictionary in mechanism_entry.get("pivots", []):
		var path: String = pivot["path"]
		if not "{i}" in path:
			var node := model.get_node_or_null(path)
			if node == null:
				result.append("%s: needs the node %s" % [id, path])
			else:
				_check_node(model, node, path, pivot, "", result, id)
			continue
		var count := 0
		for i in MAX_INDEX:
			var node := model.get_node_or_null(path.replace("{i}", str(i)))
			if node == null:
				break
			count += 1
			_check_node(model, node, path.replace("{i}", str(i)), pivot, str(i), result, id)
		var needed: int = pivot.get("min", 1)
		if count < needed:
			result.append("%s: %s has %d, needs at least %d" % [id, path, count, needed])
	return result


static func _check_node(
	model: Node,
	node: Node,
	path: String,
	pivot: Dictionary,
	index: String,
	result: Array[String],
	id: String
) -> void:
	for other: String in pivot.get("with", []):
		var other_path := other.replace("{i}", index)
		if model.get_node_or_null(other_path) == null:
			result.append("%s: %s needs %s" % [id, path, other_path])
	for key: String in pivot.get("meta", []):
		if not node.has_meta(key):
			result.append("%s: %s needs the metadata '%s'" % [id, path, key])


## Owned pivots (`owns`) of implemented registry mechanisms that are not in `declared` (a
## mechanisms dictionary) but exist in the model.
static func owned_pivots(model: Node, registry: Dictionary, declared: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id: String in registry:
		var entry: Dictionary = registry[id]
		if entry.get("status", "") != "implemented" or declared.has(id):
			continue
		for owned: String in entry.get("owns", []):
			var path := owned.replace("{i}", "0")
			if model.get_node_or_null(path) != null:
				result.append(path)
	return result


## Numbers as floats, strings as strings, arrays element-wise: makes JSON and GDScript literals
## comparable.
static func normalise(value: Variant) -> Variant:
	if value is int or value is float:
		return float(value)
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(normalise(item))
		return items
	if value is Dictionary:
		var entries := {}
		for key: Variant in value:
			entries[key] = normalise(value[key])
		return entries
	return value


## Everything wrong with a model's mechanisms against the catalog (`catalog` null = no entry) and
## the registry; empty when the contract holds. `model_file` is named in the messages.
static func problems(
	unit_id: String, model: Node, catalog: Variant, registry: Dictionary
) -> Array[String]:
	var result: Array[String] = []
	var file := "src/presentation/models/%s.gd" % unit_id
	if catalog == null:
		result.append("%s: the model declares mechanisms but has no catalog entry" % unit_id)
		return result
	var declared: Dictionary = catalog
	if declared.is_empty():
		result.append("%s: the catalog entry has no mechanisms, declare and verify them" % unit_id)
		return result
	if not model.has_meta(&"mechanisms"):
		result.append(
			"%s: no mechanisms metadata, copy the catalog mechanisms into MECHANISMS" % file
		)
		return result
	var meta: Dictionary = model.get_meta(&"mechanisms")
	if normalise(meta) != normalise(declared):
		result.append(
			(
				"%s: MECHANISMS %s differs from the catalog %s, update %s (or run /model-unit %s)"
				% [unit_id, JSON.stringify(meta), JSON.stringify(declared), file, unit_id]
			)
		)
	for id: String in declared:
		var entry: Dictionary = registry.get(id, {})
		if entry.is_empty():
			result.append("%s: mechanism '%s' is not in the registry" % [unit_id, id])
		elif entry.get("status", "") == "implemented":
			for violation in pivot_violations(model, entry):
				result.append("%s: %s" % [unit_id, violation])
	for path in owned_pivots(model, registry, declared):
		result.append(
			(
				"%s: pivot %s belongs to a mechanism the catalog entry doesn't declare"
				% [unit_id, path]
			)
		)
	return result


## Lowest y of the meshes below `node`, in `model`'s space; INF without meshes.
static func lowest_y(model: Node3D, node: Node3D) -> float:
	var lowest := INF
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var to_model := _relative(node, model)
		var box := (node as MeshInstance3D).mesh.get_aabb()
		for corner in 8:
			lowest = minf(lowest, (to_model * box.get_endpoint(corner)).y)
	for child in node.get_children():
		if child is Node3D:
			lowest = minf(lowest, lowest_y(model, child as Node3D))
	return lowest


static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var current := node
	while current != ancestor and current != null:
		t = current.transform * t
		current = current.get_parent() as Node3D
	return t


## Stabiliser contract: deployed (t = 1) the lowest point of each `Stabiliser<i>` is on the ground
## (y = 0 ± 0.005 in the model's space), stowed (t = 0) at least 0.005 above it. Leaves the model
## stowed.
static func stabiliser_violations(model: Node3D) -> Array[String]:
	var result: Array[String] = []
	for t in [1.0, 0.0]:
		UnitModels.pose_deployables(model, t)
		for i in UnitModels.MAX_DEPLOYABLES:
			var jack := model.get_node_or_null("Stabiliser%d" % i) as Node3D
			if jack == null:
				break
			var low := lowest_y(model, jack)
			if t == 1.0 and absf(low) > 0.005:
				result.append("Stabiliser%d: deployed foot at y = %.4f, needs 0 ± 0.005" % [i, low])
			elif t == 0.0 and low < 0.005:
				result.append("Stabiliser%d: stowed foot at y = %.4f, needs >= 0.005" % [i, low])
	return result
