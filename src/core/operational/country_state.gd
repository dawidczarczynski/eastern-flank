class_name CountryState
extends RefCounted
## Political state of one country in an operation (TASK-114). Changed only through
## CountryRules.set_stance (the flags by the rules of TASK-115 / 116). Relations to a player are
## computed (CountryRules.relation), never stored.

const NEUTRAL := &"neutral"
const ALIGNED := &"aligned"
const BELLIGERENT := &"belligerent"
const STANCES: Array[StringName] = [NEUTRAL, ALIGNED, BELLIGERENT]

var id: StringName
var definition: CountryDefinition
var stance: StringName = NEUTRAL
## Side (player) of an aligned / belligerent country, -1 when neutral.
var side: int = -1
## Side the country goes to when the war widens (-1, 0, 1); static.
var leaning: int = -1
## Per player: may declare hostilities on this country without escalation.
var casus_belli: Array[bool] = [false, false]
## Per player: has breached this country as a sanctuary (it stays open to that player).
var breached_by: Array[bool] = [false, false]
## Per player: declared hostilities on this country.
var declared_by: Array[bool] = [false, false]
## Formations that join on the leaning side (static, from CountrySetup.contribution).
var contribution: Array[FormationPlacement] = []
## The contribution has already come (or been lost): it never comes twice.
var contributed := false


static func from_setup(setup: CountrySetup) -> CountryState:
	var country := CountryState.new()
	country.definition = setup.country
	country.id = setup.country.id
	country.stance = setup.stance
	country.side = setup.side
	country.leaning = setup.leaning
	country.contribution = setup.contribution.duplicate()
	return country


func snapshot() -> Dictionary:
	return {
		"id": id,
		"stance": stance,
		"side": side,
		"casus_belli": casus_belli.duplicate(),
		"breached_by": breached_by.duplicate(),
		"declared_by": declared_by.duplicate(),
		"contributed": contributed,
	}
