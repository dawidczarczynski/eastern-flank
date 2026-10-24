class_name CatalogUnits
extends RefCounted
## The units the in-game catalog lists (TASK-084): every unit definition in data/units/, grouped by
## class. An explicit path table like FactionRegistry (exported builds do not list the folder);
## tests/unit/test_unit_catalog.gd keeps it equal to the folder.

const PATHS: Array[String] = [
	"res://data/units/pl_mech_infantry.tres",
	"res://data/units/ru_motor_rifle.tres",
	"res://data/units/m1a2_sepv3.tres",
	"res://data/units/t72b3.tres",
	"res://data/units/homar_k.tres",
	"res://data/units/bm27_uragan.tres",
]
## Class order in the list.
const CLASS_ORDER: Array[StringName] = [&"infantry", &"tank", &"mlrs"]


## All unit definitions, in PATHS order.
static func definitions() -> Array[UnitDefinition]:
	var result: Array[UnitDefinition] = []
	for path in PATHS:
		var definition := load(path) as UnitDefinition
		if definition != null:
			result.append(definition)
	return result


## Definitions grouped by class: [{class_id, label (translation key), units}] in CLASS_ORDER,
## classes outside it last, no empty groups.
static func grouped() -> Array[Dictionary]:
	var by_class := {}
	for definition in definitions():
		if not by_class.has(definition.unit_class):
			by_class[definition.unit_class] = []
		(by_class[definition.unit_class] as Array).append(definition)
	var order: Array = CLASS_ORDER.duplicate()
	for class_id: StringName in by_class:
		if class_id not in order:
			order.append(class_id)
	var groups: Array[Dictionary] = []
	for class_id: StringName in order:
		if by_class.has(class_id):
			(
				groups
				. append(
					{
						"class_id": class_id,
						"label": "CLASS_%s" % String(class_id).to_upper(),
						"units": by_class[class_id],
					}
				)
			)
	return groups


## Factions that field the unit (their models are coloured differently); empty when none does.
static func factions_for(definition: UnitDefinition) -> Array[FactionDefinition]:
	var result: Array[FactionDefinition] = []
	for faction in FactionRegistry.all():
		if faction.has_unit(definition):
			result.append(faction)
	return result
