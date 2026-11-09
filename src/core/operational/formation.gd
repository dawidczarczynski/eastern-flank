class_name Formation
extends RefCounted
## A formation on the operational map at runtime (TASK-092b, GDD "Formations"): a named
## battalion of companies built from a FormationPlacement.


## One company of a formation; `ref` is the BattleSetup.Company.ref it fights under.
class Company:
	extends RefCounted
	var unit_type: StringName
	## Current strength (battle HP), 1 … max_strength.
	var strength: int
	## The unit type's max_hp.
	var max_strength: int
	## "<formation id>/<n>", n from 1.
	var ref: String

	func _init(p_unit_type: StringName, p_max: int, p_ref: String) -> void:
		unit_type = p_unit_type
		strength = p_max
		max_strength = p_max
		ref = p_ref


var id: StringName
## Translation keys (static, not in the snapshot).
var display_name: String
var parent: String
var owner_id: int
var definition: FormationDefinition
var coord: Vector2i
var companies: Array[Company] = []
## OperationalPosture id.
var posture: StringName = &"defend"
## Standing order; null = none.
var order: FormationOrder = null
## Readiness 0 … 100 (TASK-095): a battle lowers it, a quiet turn restores it; it scales the
## order budget (OperationalOrders.budget).
var readiness: int = 100
## Fought a battle since the owner's last turn began (decides the readiness recovery).
var fought: bool = false


static func from_placement(
	placement: FormationPlacement, initial_posture: StringName = &"defend"
) -> Formation:
	var f := Formation.new()
	f.id = placement.id
	f.display_name = placement.display_name
	f.parent = placement.parent
	f.owner_id = placement.player
	f.definition = placement.definition
	f.coord = placement.coord
	f.posture = initial_posture
	var n := 0
	for unit in placement.definition.companies:
		n += 1
		f.companies.append(Company.new(unit.id, unit.max_hp, "%s/%d" % [placement.id, n]))
	return f


## Current strength: the sum of the companies.
func strength() -> int:
	var total := 0
	for company in companies:
		total += company.strength
	return total


## Full strength: the sum of the companies' max_strength.
func max_strength() -> int:
	var total := 0
	for company in companies:
		total += company.max_strength
	return total


## This formation's entry of OperationalState.snapshot() – the one place it is built
## (posture and order: TASK-092d).
func snapshot() -> Dictionary:
	var company_entries: Array = []
	for company in companies:
		company_entries.append([String(company.unit_type), company.strength])
	return {
		"id": String(id),
		"player": owner_id,
		"coord": [coord.x, coord.y],
		"companies": company_entries,
		"posture": String(posture),
		"order": null if order == null else [order.destination.x, order.destination.y],
		"readiness": readiness,
		"fought": fought,
	}
