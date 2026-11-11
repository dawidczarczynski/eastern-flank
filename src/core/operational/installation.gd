class_name Installation
extends RefCounted
## A fixed installation on the operational map at runtime (TASK-097a, GDD "Deep strikes"):
## airfield, depot, command post or air-defence site with an integrity of 0-100.

## Installation classes (the strike classes of the escalation ladder; formations are `formation`).
const CLASSES: Array[StringName] = [&"airfield", &"depot", &"c2", &"air_defence"]
const MAX_INTEGRITY := 100

var id: StringName
## Translation key (static, not in the snapshot).
var display_name: String
var class_id: StringName
var owner: int
var coord: Vector2i
var integrity: int = MAX_INTEGRITY
## Air-defence type id (AirDefenceDefinition) of an `air_defence` site, else &"" (static).
var ad_type: StringName = &""
## Rounds an air-defence site stays silent after a hit (0 = active; TASK-098a).
var suppressed_rounds: int = 0


static func from_placement(placement: InstallationPlacement) -> Installation:
	var installation := Installation.new()
	installation.id = placement.id
	installation.display_name = placement.display_name
	installation.class_id = placement.class_id
	installation.owner = placement.owner
	installation.coord = placement.coord
	installation.ad_type = placement.ad_type
	return installation


func destroyed() -> bool:
	return integrity <= 0


## Whether a hit silenced this site (it intercepts nothing while this holds).
func suppressed() -> bool:
	return suppressed_rounds > 0


## This installation's entry of OperationalState.snapshot().
func snapshot() -> Dictionary:
	return {
		"id": String(id),
		"owner": owner,
		"class": String(class_id),
		"coord": [coord.x, coord.y],
		"integrity": integrity,
		"ad_type": String(ad_type),
		"suppressed_rounds": suppressed_rounds,
	}
