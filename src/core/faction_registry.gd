class_name FactionRegistry
extends RefCounted
## Looks up FactionDefinition resources (data/factions/*.tres) by id.
## An explicit path table instead of listing the folder: exported builds list `.remap`/`.import`
## files in DirAccess, and the table keeps the order of `all()` deterministic.
## Adding a faction = a .tres file + a line in _PATHS.

const _PATHS: Array[String] = [
	"res://data/factions/poland.tres",
	"res://data/factions/russia.tres",
]

## Faction ids of players 0, 1, ... when nothing else is chosen.
const DEFAULT_IDS: Array[StringName] = [&"poland", &"russia"]

static var _by_id: Dictionary = {}  # StringName -> FactionDefinition
static var _ordered: Array[FactionDefinition] = []
static var _loaded := false


## The faction with this id; null if there is none.
static func get_faction(faction_id: StringName) -> FactionDefinition:
	_ensure_loaded()
	return _by_id.get(faction_id)


static func has_faction(faction_id: StringName) -> bool:
	_ensure_loaded()
	return _by_id.has(faction_id)


## All factions in _PATHS order.
static func all() -> Array[FactionDefinition]:
	_ensure_loaded()
	return _ordered.duplicate()


static func ids() -> Array[StringName]:
	_ensure_loaded()
	var result: Array[StringName] = []
	for faction in _ordered:
		result.append(faction.id)
	return result


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _PATHS:
		var faction := load(path) as FactionDefinition
		if faction == null:
			push_error("FactionRegistry: cannot load %s" % path)
			continue
		if _by_id.has(faction.id):
			push_error("FactionRegistry: duplicate faction id '%s' in %s" % [faction.id, path])
			continue
		_by_id[faction.id] = faction
		_ordered.append(faction)
