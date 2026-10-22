class_name MeshKits
extends RefCounted
## One `MeshKit` per material role for one pivot (TASK-030): `k(&"body").cbox(...)` collects the
## parts, `add_to(pivot, materials)` adds one MeshInstance3D per non-empty kit through
## `ModelParts.add` (so camo materials work with `ModelParts.cached`). Pivots that move (turret,
## gun, wheels) get their own `MeshKits` with the pivot's `base` and stay separate nodes.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")

var _frame: Frame
var _base: Transform3D
var _kits := {}


## `frame` / `base`: see MeshKit._init (shared by all kits of this pivot).
func _init(frame: Frame = null, base := Transform3D.IDENTITY) -> void:
	_frame = frame
	_base = base


## The kit of `material` (created on first use; insertion order = child order in `add_to`).
func k(material: StringName) -> MeshKit:
	if not _kits.has(material):
		_kits[material] = MeshKit.new(_frame, _base)
	return _kits[material]


## Triangles in all kits.
func triangle_count() -> int:
	var total := 0
	for name: StringName in _kits:
		total += (_kits[name] as MeshKit).count
	return total


## One MeshInstance3D per non-empty kit under `parent`, with `materials[role]`.
func add_to(parent: Node3D, materials: Dictionary) -> Array[MeshInstance3D]:
	var added: Array[MeshInstance3D] = []
	for name: StringName in _kits:
		var kit: MeshKit = _kits[name]
		if kit.count == 0:
			continue
		if not materials.has(name):
			push_error("MeshKits: no material for %s" % name)
			continue
		added.append(ModelParts.add(parent, kit.commit(), materials[name], Vector3.ZERO))
	return added
