class_name SupportState
extends RefCounted
## Dynamic state of one support package in an operation (TASK-121). Changed only by
## RequestSupportCommand and SupportRules.deliver.

var id: StringName
var definition: SupportPackage
## Turn of the request, -1 = not requested.
var requested_turn: int = -1
var delivered: bool = false
var withdrawn: bool = false
## Placements not yet on the map (all of them after the request, in placement order).
var waiting: Array[FormationPlacement] = []


static func from_package(package: SupportPackage) -> SupportState:
	var support := SupportState.new()
	support.id = package.id
	support.definition = package
	return support


func requested() -> bool:
	return requested_turn >= 0


## Requested, neither delivered nor withdrawn: on its way (possibly waiting for an open entry).
func on_its_way() -> bool:
	return requested() and not delivered and not withdrawn


## Some formation of the package has joined the map.
func joined_any() -> bool:
	return requested() and not withdrawn and waiting.size() < definition.formations.size()


func snapshot() -> Dictionary:
	return {
		"id": id,
		"requested_turn": requested_turn,
		"delivered": delivered,
		"withdrawn": withdrawn,
		"waiting": waiting.map(func(p: FormationPlacement) -> StringName: return p.id),
	}
