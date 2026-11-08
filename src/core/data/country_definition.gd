class_name CountryDefinition
extends Resource
## A country of an operational map (TASK-114, GDD "Countries and stances"). Instances are kept as
## data/countries/<id>.tres. A country is not a side; its stance towards the sides lives in
## CountryState.

const COUNTRIES_DIR := "res://data/countries/"
## Countries shipped in data/countries/.
const NAMES: Array[StringName] = [&"poland", &"lithuania", &"belarus", &"russia"]

@export var id: StringName
## ISO 3166 alpha-2 code, as in ImportedMap.countries.
@export var iso_code: String
## Translation key (English), translated in the UI.
@export var display_name: String
## Sovereign soil of a nuclear power: an enemy of it may enter only after a breach or at open war.
@export var sanctuary: bool = false


## The country data/countries/<country_id>.tres; null when there is none.
static func find(country_id: StringName) -> CountryDefinition:
	if not NAMES.has(country_id):
		return null
	var path := COUNTRIES_DIR + String(country_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as CountryDefinition


## The country with this ISO code (case-sensitive, upper case); null when unknown.
static func find_by_iso(code: String) -> CountryDefinition:
	for country_id in NAMES:
		var definition := find(country_id)
		if definition != null and definition.iso_code == code:
			return definition
	return null
