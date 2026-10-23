class_name LookPreset
extends RefCounted
## Colour look of the battlefield (TASK-071): ground tints, tree leaf colours, species mix,
## colour grade, water and fog/exposure. The active preset is `muted_summer` (the human's
## choice, 2026-10-23; `current` is the pre-TASK-071 look, no overrides). Global presentation
## state like VisualScale: switch it before the battle is built (today only
## tools/screenshot.gd does, from SCREENSHOT_LOOK). Tinted values are sRGB for leaves and linear
## albedo multipliers for ground layers (TerrainGround.LAYER_TINTS order).

const DEFAULT_PRESET := &"muted_summer"
const PRESETS := {
	&"current": {},
	# B: muted late summer – yellowed greens, sandy soil, more pine and birch, darker conifers.
	&"muted_summer":
	{
		"layer_tints":
		[
			Vector3(0.95, 0.97, 0.66),
			Vector3(1.0, 0.9, 0.58),
			Vector3(0.58, 0.52, 0.42),
			Vector3(1.0, 0.98, 0.92),
			Vector3(0.95, 0.97, 1.02),
			Vector3(1.0, 1.1, 1.25),
		],
		"leaf_colors":
		{
			&"pine": Color("#38573a"),
			&"spruce": Color("#294539"),
			&"birch": Color("#a5a85a"),
			&"oak": Color("#718040"),
			&"alder": Color("#5b723e"),
			&"shrub": Color("#6f8040"),
			&"undergrowth": Color("#8f9446"),
		},
		"shares": {&"pine": 0.78, &"spruce": 0.22, &"birch": 0.5, &"oak": 0.2, &"alder": 0.3},
		"water":
		{
			"shallow_color": Color("#506239"),
			"deep_color": Color("#1b2e22"),
			"shallow_alpha": 0.82,
			"deep_alpha": 0.97,
			"deep_distance": 0.25,
		},
		"autumn_share": 0.1,
		"grade":
		{
			"saturation": 0.8,
			"green_shift": -0.04,
			"highlight_tint": Color("#fff0d4"),
			"highlight_weight": 0.07,
		},
	},
	# C: early autumn – ochre grass, yellow birches, brown oaks, warm low light.
	&"early_autumn":
	{
		"layer_tints":
		[
			Vector3(1.0, 0.92, 0.55),
			Vector3(1.05, 0.85, 0.45),
			Vector3(0.58, 0.47, 0.36),
			Vector3(1.0, 0.97, 0.9),
			Vector3(0.95, 0.97, 1.02),
			Vector3(1.0, 1.1, 1.25),
		],
		"leaf_colors":
		{
			&"pine": Color("#3a5238"),
			&"spruce": Color("#2b4636"),
			&"birch": Color("#d2a63c"),
			&"oak": Color("#a0702e"),
			&"alder": Color("#7f7b36"),
			&"shrub": Color("#8b7a35"),
			&"undergrowth": Color("#a18b3c"),
		},
		"shares": {&"pine": 0.78, &"spruce": 0.22, &"birch": 0.5, &"oak": 0.2, &"alder": 0.3},
		"water":
		{
			"shallow_color": Color("#5c6238"),
			"deep_color": Color("#232e20"),
			"shallow_alpha": 0.82,
			"deep_alpha": 0.97,
			"deep_distance": 0.25,
		},
		"autumn_share": 0.35,
		"grade":
		{
			"saturation": 0.88,
			"green_shift": -0.07,
			"highlight_tint": Color("#ffe8c4"),
			"highlight_weight": 0.09,
		},
	},
	# D: B under an overcast, hazy sky – grey-brown grade, closer grey fog, lower exposure.
	&"overcast":
	{
		"layer_tints":
		[
			Vector3(0.95, 0.97, 0.66),
			Vector3(1.0, 0.9, 0.58),
			Vector3(0.58, 0.52, 0.42),
			Vector3(1.0, 0.98, 0.92),
			Vector3(0.95, 0.97, 1.02),
			Vector3(1.0, 1.1, 1.25),
		],
		"leaf_colors":
		{
			&"pine": Color("#38573a"),
			&"spruce": Color("#294539"),
			&"birch": Color("#a5a85a"),
			&"oak": Color("#718040"),
			&"alder": Color("#5b723e"),
			&"shrub": Color("#6f8040"),
			&"undergrowth": Color("#8f9446"),
		},
		"shares": {&"pine": 0.78, &"spruce": 0.22, &"birch": 0.5, &"oak": 0.2, &"alder": 0.3},
		"water":
		{
			"shallow_color": Color("#4b5a3c"),
			"deep_color": Color("#1c2a22"),
			"shallow_alpha": 0.85,
			"deep_alpha": 0.97,
			"deep_distance": 0.25,
		},
		"autumn_share": 0.15,
		"grade":
		{
			"saturation": 0.68,
			"contrast": 1.02,
			"green_shift": -0.04,
			"shadow_tint": Color("#2a2f31"),
			"shadow_weight": 0.1,
			"highlight_tint": Color("#e8e6e0"),
			"highlight_weight": 0.08,
		},
		"fog_color": Color("#a2a6a6"),
		"fog_depth_begin": 18.0,
		"fog_depth_end": 100.0,
		"exposure": 1.15,
	},
}

static var _active: Dictionary = PRESETS[DEFAULT_PRESET]


## The values of a preset (a copy); an unknown name warns and returns the default.
static func preset(preset_name: StringName) -> Dictionary:
	if not PRESETS.has(preset_name):
		push_warning("LookPreset: unknown preset '%s', using '%s'" % [preset_name, DEFAULT_PRESET])
		return (PRESETS[DEFAULT_PRESET] as Dictionary).duplicate(true)
	return (PRESETS[preset_name] as Dictionary).duplicate(true)


## Makes a preset the active one (unknown name -> the default) and drops the baked grade.
static func apply(preset_name: StringName) -> void:
	_active = preset(preset_name)
	ColorGrade.reset_cache()


static func reset() -> void:
	apply(DEFAULT_PRESET)


static func layer_tints(base: Array[Vector3]) -> Array[Vector3]:
	var tints: Array = _active.get("layer_tints", base)
	var result: Array[Vector3] = []
	result.assign(tints)
	return result


static func leaf_color(species: StringName, base: Color) -> Color:
	return (_active.get("leaf_colors", {}) as Dictionary).get(species, base)


static func share(species: StringName, base: float) -> float:
	return (_active.get("shares", {}) as Dictionary).get(species, base)


static func autumn_share(base: float) -> float:
	return _active.get("autumn_share", base)


## `base` with the active preset's overrides merged in.
static func grade(base: Dictionary) -> Dictionary:
	var merged := base.duplicate()
	merged.merge(_active.get("grade", {}), true)
	return merged


## Water shader parameters of the active preset (empty for `current`).
static func water_params() -> Dictionary:
	return (_active.get("water", {}) as Dictionary).duplicate()


## Fog / exposure overrides of the active preset (nothing for `current`).
static func apply_to_environment(env: Environment) -> void:
	if _active.has("fog_color"):
		env.fog_light_color = _active["fog_color"]
	if _active.has("fog_depth_begin"):
		env.fog_depth_begin = _active["fog_depth_begin"]
	if _active.has("fog_depth_end"):
		env.fog_depth_end = _active["fog_depth_end"]
	if _active.has("exposure"):
		env.tonemap_exposure = _active["exposure"]
