class_name VisualScale
extends RefCounted
## Visual scale of units relative to trees, bushes and rocks (TASK-059). One place for the
## constants: UnitModels reads `unit_model_scale`, MapView's scatter reads the others. The active
## preset is `balanced` (the human's choice, 2026-10-22; `current` is the pre-TASK-059 look). It
## is global presentation state: switch it before the
## battle is built (today only tools/screenshot.gd does, from SCREENSHOT_SCALE_PRESET).
## The `true` preset (TASK-110 study) is not a table: it is computed from MapScale so that units,
## trees, bushes, rocks and grass stand at 1:1 of the map (TRUE_HEIGHTS_M); unit models and tree
## species are then sized one by one (UnitModels.model_scale, tree_size).

const DEFAULT_PRESET := &"balanced"
const PRESETS := {
	&"current":
	{
		"unit_model_scale": 1.3,
		"tree_scale": 1.0,
		"bush_scale": 1.0,
		"rock_scale": 1.0,
		"grass_scale": 1.0
	},
	&"balanced":
	{
		"unit_model_scale": 1.1,
		"tree_scale": 1.8,
		"bush_scale": 1.4,
		"rock_scale": 1.0,
		"grass_scale": 1.4
	},
	&"realistic":
	{
		"unit_model_scale": 0.9,
		"tree_scale": 2.6,
		"bush_scale": 1.8,
		"rock_scale": 1.0,
		"grass_scale": 1.8
	},
}

const TRUE_PRESET := &"true"
## Model units per real metre of a unit model built at scale 1 (the shared nominal of the model
## files' `K`, tools/render_unit.gd and RocketVolley.MODEL_UNITS_PER_METRE): effects that follow
## unit_model_scale() (muzzle flash, tracks, rockets) are real-size with 1 / (m * this).
const NOMINAL_MODEL_UNITS_PER_METRE := 0.078
## Real sizes of the `true` preset, metres: tree species and scrub heights (mature trees of the
## Suwalki region's forests), `tree` = the mixed-forest mean (backdrop canopy, tree_scale()),
## a bush's height, a field boulder's diameter and a grass clump's height.
const TRUE_HEIGHTS_M := {
	&"pine": 25.0,
	&"spruce": 28.0,
	&"birch": 20.0,
	&"oak": 22.0,
	&"alder": 18.0,
	&"shrub": 3.0,
	&"undergrowth": 0.8,
	&"tree": 24.0,
	&"bush": 2.5,
	&"rock": 1.2,
	&"grass": 0.5,
}

static var _active: Dictionary = PRESETS[DEFAULT_PRESET]

## Model height (world units, scale 1) of a tree species' LOD0 variant, cached.
static var _tree_heights: Dictionary = {}


## The values of a preset (a copy); an unknown name warns and returns the default.
static func preset(preset_name: StringName) -> Dictionary:
	if preset_name == TRUE_PRESET:
		return _true_values()
	if not PRESETS.has(preset_name):
		push_warning("VisualScale: unknown preset '%s', using '%s'" % [preset_name, DEFAULT_PRESET])
		return (PRESETS[DEFAULT_PRESET] as Dictionary).duplicate()
	return (PRESETS[preset_name] as Dictionary).duplicate()


## Makes a preset the active one (unknown name -> the default).
static func apply(preset_name: StringName) -> void:
	_active = preset(preset_name)


## Back to the default preset.
static func reset() -> void:
	apply(DEFAULT_PRESET)


## Overrides single values of the active preset (tests, experiments).
static func apply_values(values: Dictionary) -> void:
	var merged := _active.duplicate()
	merged.merge(values, true)
	_active = merged


static func unit_model_scale() -> float:
	return _active["unit_model_scale"]


static func tree_scale() -> float:
	return _active["tree_scale"]


static func bush_scale() -> float:
	return _active["bush_scale"]


static func rock_scale() -> float:
	return _active["rock_scale"]


## Grass clump size multiplier (TASK-057); follows the bush scale.
static func grass_scale() -> float:
	return _active["grass_scale"]


## Whether the active preset is `true` (1:1 of MapScale, TASK-110).
static func is_true_size() -> bool:
	return _active.get("true_size", false)


## Size multiplier of one planned tree of `species` / `variant` (TreeField.tree_transform): under
## the `true` preset its model height becomes the species' real height, otherwise tree_scale().
static func tree_size(species: StringName, variant: int) -> float:
	if not is_true_size() or not TRUE_HEIGHTS_M.has(species):
		return tree_scale()
	var key := "%s:%d" % [species, variant]
	if not _tree_heights.has(key):
		_tree_heights[key] = TreeMeshes.lod0(species, variant).get_aabb().size.y
	return TRUE_HEIGHTS_M[species] / MapScale.metres_per_unit / _tree_heights[key]


## The `true` preset from the current MapScale: every multiplier turns its model's size at scale
## 1 into the real size of TRUE_HEIGHTS_M.
static func _true_values() -> Dictionary:
	var m := MapScale.metres_per_unit
	var bush_height := FoliageMeshes.bush().get_aabb().size.y * ScatterPlanner.BUSH_HEIGHT
	return {
		"unit_model_scale": 1.0 / (m * NOMINAL_MODEL_UNITS_PER_METRE),
		"tree_scale": TRUE_HEIGHTS_M[&"tree"] / m / TreeMeshes.TREE_HEIGHT,
		"bush_scale": TRUE_HEIGHTS_M[&"bush"] / m / bush_height,
		"rock_scale": TRUE_HEIGHTS_M[&"rock"] / m / FoliageMeshes.rock().get_aabb().size.x,
		"grass_scale": TRUE_HEIGHTS_M[&"grass"] / m / GrassField.CARD_HEIGHT,
		"true_size": true,
	}
