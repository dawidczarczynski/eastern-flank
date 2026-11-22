class_name LookPreset
extends RefCounted
## Colour look of the battlefield (TASK-071): ground tints, tree leaf colours, species mix,
## colour grade, water and fog/exposure. The active preset is `muted_summer` (the human's
## choice, 2026-10-23; `current` is the pre-TASK-071 look, no overrides). Global presentation
## state like VisualScale: switch it before the battle is built (today only
## tools/screenshot.gd does, from SCREENSHOT_LOOK). Tinted values are sRGB for leaves and linear
## albedo multipliers for ground layers (TerrainGround.LAYER_TINTS order).

const DEFAULT_PRESET := &"muted_summer"
## Farmland look (TASK-108f): per crop the share of parcels (FieldParcels.CROPS order), the plant
## and furrow colours (sRGB; the shader mixes them by the row pattern), the row spacing in metres
## (exaggerated so rows read at the default zoom), the plant width as a fraction of the spacing
## and the grass clump keep factor on the parcel (GrassPlanner). A preset's "fields" entry is
## merged over it by fields().
const FIELDS_DEFAULT := {
	"crops":
	{
		&"wheat":
		{
			"share": 0.24,
			"plant": Color("#b8984a"),
			"furrow": Color("#a48a46"),
			"spacing_m": 7.0,
			"plant_frac": 0.7,
			"grass_keep": 0.0,
		},
		&"maize":
		{
			"share": 0.10,
			"plant": Color("#3f5530"),
			"furrow": Color("#47472d"),
			"spacing_m": 10.0,
			"plant_frac": 0.6,
			"grass_keep": 0.0,
		},
		&"potato":
		{
			"share": 0.10,
			"plant": Color("#5a7a50"),
			"furrow": Color("#4b6743"),
			"spacing_m": 8.0,
			"plant_frac": 0.6,
			"grass_keep": 0.0,
		},
		&"green":
		{
			"share": 0.16,
			"plant": Color("#7a8c4c"),
			"furrow": Color("#6b7d42"),
			"spacing_m": 7.0,
			"plant_frac": 0.7,
			"grass_keep": 0.0,
		},
		&"stubble":
		{
			"share": 0.15,
			"plant": Color("#b3a272"),
			"furrow": Color("#a39465"),
			"spacing_m": 8.0,
			"plant_frac": 0.6,
			"grass_keep": 0.0,
		},
		&"ploughed":
		{
			"share": 0.16,
			"plant": Color("#6a4c34"),
			"furrow": Color("#53392a"),
			"spacing_m": 10.0,
			"plant_frac": 0.5,
			"grass_keep": 0.0,
		},
		&"meadow":
		{
			"share": 0.09,
			"plant": Color("#66803f"),
			"furrow": Color("#5e7a3b"),
			"spacing_m": 30.0,
			"plant_frac": 0.5,
			"grass_keep": 1.0,
		},
	},
	"balk": {"plant": Color("#4b6230"), "furrow": Color("#4b6230")},
	# Per-parcel brightness variation (+- fraction) and hue shift (+- fraction of red / blue).
	"parcel_brightness": 0.14,
	"parcel_hue": 0.1,
	# Row stripes fade to the crop's average colour as one row spans this many screen pixels.
	"row_fade_from": 0.3,
	"row_fade_to": 0.8,
}

## Real-scale vegetation (TASK-135, ADR 0026): used only under the `true` VisualScale preset
## (`balanced` never reads it). Sizes and distances in metres (MapScale converts them), so they
## hold at any map scale. A preset's "vegetation" entry is merged over it by vegetation().
## - forest_trees_per_ha: visual tree density of a forest tile (planned trees + ForestFill),
##   370 / ha ≈ 2 000 per 250 m hex; forest_clearing_m: the fill keeps the tile centre clear
##   (where the unit stands); forest_crown_width_m: crown width of the dense fill trees (closed
##   stands grow narrow crowns; the models are open-grown, ~17-24 m wide at real height).
## - Ranges (VegetationRanges) for a tree reference_height_m tall, scaled by each species' real
##   height: full 3D trees to full_range_m, impostors to impostor_range_m (then the canopy shell
##   on forest tiles), floors min_full_range_m / min_impostor_range_m for small scrub; off-forest
##   items keep their impostor until they are under vanish_angle (radians, ~2 px at 720p);
##   band_share: half width of the per-tree hand-over band as a share of its distance.
## - full_tree_cap: most full (LOD0) dense-forest trees submitted per frame, nearest chunks first.
## - tree_sink_m / scrub_sink_m: how far a trunk / a shrub base sinks into the drawn ground;
##   impostor_sink_m: how much deeper the GPU-placed forest impostors sink (they stand on the
##   coarser lattice, TASK-189); impostor_thin_from_m / impostor_thin_widen: beyond this camera
##   distance the impostors keep every other tree, crowns this much wider.
## - near_grass_range_m / near_grass_per_m2: GrassNear draws real-density grass (clumps per m² on
##   meadow; other terrain by GrassPlanner's density ratio) within this range of the camera.
## - shell_fade: the canopy shell fades in over (from, to) x the reference impostor range;
##   shell_height_share: shell lift as a share of the mean tree height; shell_crown_m: crown
##   pattern cell of the shell; shell_brightness: its albedo factor (to meet the impostors' tone);
##   shell_view_share: how far its crown normals lean towards the camera (as the visible half of
##   an impostor's crown does, TASK-191).
## - impostor_albedo: albedo factor of the lit impostors against the full trees (TASK-191; a full
##   crown shades its own inner leaves, the picture does not); impostor_slope_share: how far the
##   impostors' and the shell's normals turn with the ground's slope (0 upright .. 1 the slope).
const VEGETATION_DEFAULT := {
	"forest_trees_per_ha": 370.0,
	"forest_clearing_m": 15.0,
	"forest_crown_width_m": 7.0,
	"reference_height_m": 24.0,
	"full_range_m": 250.0,
	"impostor_range_m": 1400.0,
	"min_full_range_m": 30.0,
	"min_impostor_range_m": 100.0,
	"vanish_angle": 0.002,
	"band_share": 0.08,
	"full_tree_cap": 6000,
	"tree_sink_m": 0.3,
	"scrub_sink_m": 0.05,
	"impostor_sink_m": 0.5,
	"impostor_thin_from_m": 900.0,
	"impostor_thin_widen": 1.4,
	"near_grass_range_m": 100.0,
	"near_grass_per_m2": 1.2,
	"shell_fade": Vector2(0.72, 0.95),
	"shell_height_share": 0.8,
	"shell_crown_m": 9.0,
	"shell_brightness": 1.55,
	"shell_view_share": 0.55,
	"impostor_albedo": 1.08,
	"impostor_slope_share": 0.6,
}

## Leaf colours under the `true` VisualScale preset, for every look (TASK-135 playtest): at real
## size thousands of crowns show them, and the looks' yellowed greens (muted_summer's birch) and
## autumn share read as a beige forest. Close, dark summer greens (a forest reads as one canopy
## from above, look reference 2026-11-21), birch only a little lighter; few autumn trees.
const REAL_SIZE_LEAF_COLORS := {
	&"pine": Color("#34502f"),
	&"spruce": Color("#2a422e"),
	&"birch": Color("#56743a"),
	&"oak": Color("#47652f"),
	&"alder": Color("#42602e"),
	&"shrub": Color("#4b6832"),
	&"undergrowth": Color("#587437"),
}
const REAL_SIZE_AUTUMN_SHARE := 0.015

## Aerial perspective under the `true` VisualScale preset (look reference 2026-11-21): the
## distance fades into a bluish haze from ~1 km, so the real-size landscape reads deep (distances
## in metres, through MapScale). Depth fog, so it costs no frame time.
const REAL_SIZE_AIR := {
	"begin_m": 700.0,
	"end_m": 11000.0,
	"curve": 1.0,
	"color": Color("#a8bccf"),
	"energy": 0.62,
	"sun_scatter": 0.18,
	"aerial_perspective": 0.85,
	"sky_affect": 0.35,
}

## The sun and the ambient light (TASK-201a, ADR 0030). SUN_DEFAULT is the battle scene's Sun
## node and its environment's ambient energy (tested to stay equal), so outside `true` nothing
## changes; a preset's "sun" entry is merged over it, and REAL_SIZE_SUN over that under the `true`
## VisualScale preset. Direction: elevation above the horizon and azimuth of the side the sun is
## on (atan2(x, -z) of the toward-sun vector, as the HDRI sun in test_battle_look), degrees.
## color (sRGB), energy, angular_distance (degrees, the PCSS penumbra), shadow_blur / shadow_bias /
## shadow_normal_bias as on DirectionalLight3D, ambient_energy = Environment.ambient_light_energy
## (the floor that keeps the shaded side from going black).
const SUN_DEFAULT := {
	"elevation_deg": 37.901,
	"azimuth_deg": -127.893,
	"color": Color("#ffeedd"),
	"energy": 1.1,
	"angular_distance": 0.3,
	"shadow_blur": 0.8,
	"shadow_bias": 0.03,
	"shadow_normal_bias": 1.0,
	"ambient_energy": 0.65,
}

## The real-size sun (look reference: Arma 3 / Reforger aerial views, TASK-190): a lower, warmer
## late-afternoon sun from the HDRI sun's side, so hillsides facing away from it read darker and
## forests throw long shadows over the fields; more energy keeps the flats as bright as before,
## less ambient deepens the shaded side without crushing it.
const REAL_SIZE_SUN := {
	"elevation_deg": 24.0,
	"color": Color("#ffdcb8"),
	"energy": 1.45,
	"ambient_energy": 0.5,
}

## Moving cloud shadows (TASK-201b, CloudShadows): strength 0 = off (every look but `true`), the
## cloud pattern's period scale_m and drift speed_m (m/s) in metres (MapScale converts them), and
## height_m, the cloud height that shifts the shadow away from the sun. A preset's "clouds" entry
## is merged over CLOUDS_DEFAULT, and REAL_SIZE_CLOUDS over that under the `true` VisualScale
## preset (patches a few km wide, as on the aerial look reference).
const CLOUDS_DEFAULT := {"strength": 0.0, "scale_m": 2600.0, "speed_m": 22.0, "height_m": 2000.0}
const REAL_SIZE_CLOUDS := {"strength": 0.55}

## The colour grade under the `true` VisualScale preset (look reference: Arma 3 / Reforger aerial
## views, TASK-190): fuller colour than the muted looks, a little more contrast, cool blue-ish
## shadows and warm highlights (the late-afternoon sun), the greens kept natural. Merged over the
## active look's grade; `balanced` is untouched.
const REAL_SIZE_GRADE := {
	"saturation": 1.0,
	"contrast": 1.1,
	"shadow_tint": Color("#1c2b3d"),
	"shadow_weight": 0.11,
	"highlight_tint": Color("#ffeacc"),
	"highlight_weight": 0.08,
	"green_shift": -0.01,
}

## Open-ground vegetation (TASK-070). MEADOW_OFF turns every feature off (the `current` look =
## TASK-057/061 output); a preset's "meadow" entry is merged over it by meadow().
const MEADOW_OFF := {
	"patch_frequency": 0.45,
	"patch_seed": 131.0,
	"tall_from": 2.0,
	"tall_to": 3.0,
	"hills_tall_factor": 1.0,
	"edge_band": 1.15,
	"edge_tall_bonus": 0.0,
	"bare_thinning": 0.0,
	"dry_stalk_share": 0.0,
	"nettle_share": 0.0,
	"centre_clear": 0.4,
	"tall_height": 1.0,
	"dry_stalk_height": 1.0,
	"nettle_height": 1.0,
	"tall_color": Color.WHITE,
	"tall_mix": 0.0,
	"dry_stalk_color": Color.WHITE,
	"dry_stalk_mix": 0.0,
	"nettle_color": Color.WHITE,
	"nettle_mix": 0.0,
	# Reeds (TASK-108e): off = no marsh reeds, no bank reeds, marsh as dense as plains.
	"marsh_density": 1.0,
	"reed_share": 0.0,
	"reed_from": 0.35,
	"reed_seed": 151.0,
	"bank_reeds": 0.0,
	"reed_band_m": 10.0,
	"reed_height": 1.0,
	"reed_color": Color.WHITE,
	"reed_dry_color": Color.WHITE,
	"reed_mix": 0.0,
	"flower_density": 0.0,
	"flower_frequency": 0.9,
	"flower_seed": 137.0,
	"flower_from": 0.55,
	"flower_to": 0.7,
	"flower_cell": 1.2,
	"flower_dominance": 0.75,
	"flower_height": Vector2(1.0, 1.0),
	"flower_stem_color": Color("#5d6f36"),
	"flowers": [],
	"scrub_chance_plains": 0.0,
	"scrub_chance_hills": 0.0,
	"scrub_radius": Vector2(0.55, 0.92),
	"scrub_shrub_scale": Vector2(0.6, 1.0),
	"scrub_companions": 2,
	"scrub_companion_offset": Vector2(0.06, 0.14),
	"scrub_companion_scale": Vector2(0.7, 1.1),
}
const MEADOW_SUMMER := {
	# Patches
	"patch_frequency": 0.45,
	"patch_seed": 131.0,
	"tall_from": 0.56,
	"tall_to": 0.68,
	"hills_tall_factor": 0.5,
	"edge_band": 1.15,
	"edge_tall_bonus": 0.6,
	"bare_thinning": 0.8,
	"dry_stalk_share": 0.3,
	"nettle_share": 0.25,
	"centre_clear": 0.4,
	# Heights (vertical multiplier on the clump, on top of the 0.7-1.3 scale)
	"tall_height": 1.5,
	"dry_stalk_height": 1.3,
	"nettle_height": 1.35,
	# Colours (sRGB) and how strongly they replace the ground colour
	"tall_color": Color("#a3a25e"),
	"tall_mix": 0.3,
	"dry_stalk_color": Color("#b8a46a"),
	"dry_stalk_mix": 0.7,
	"nettle_color": Color("#4e6a34"),
	"nettle_mix": 0.6,
	"marsh_density": 1.3,
	"reed_share": 1.0,
	"bank_reeds": 0.7,
	"reed_height": 1.5,
	"reed_color": Color("#6f7a45"),
	"reed_dry_color": Color("#a39466"),
	"reed_mix": 0.85,
	# Flowers
	"flower_density": 20.0,
	"flower_frequency": 0.9,
	"flower_seed": 137.0,
	"flower_from": 0.55,
	"flower_to": 0.7,
	"flower_cell": 1.2,
	"flower_dominance": 0.75,
	"flower_height": Vector2(1.1, 1.4),
	"flower_stem_color": Color("#5d6f36"),
	"flowers":
	[
		{"name": &"white", "color": Color("#e4e0cf"), "share": 0.38},
		{"name": &"yellow", "color": Color("#d2ad3a"), "share": 0.27},
		{"name": &"violet", "color": Color("#8c5d8f"), "share": 0.25},
		{"name": &"blue", "color": Color("#5f78b2"), "share": 0.10},
	],
	# Scrub clumps on open ground
	"scrub_chance_plains": 0.35,
	"scrub_chance_hills": 0.2,
	"scrub_radius": Vector2(0.55, 0.92),
	"scrub_shrub_scale": Vector2(0.6, 1.0),
	"scrub_companions": 2,
	"scrub_companion_offset": Vector2(0.06, 0.14),
	"scrub_companion_scale": Vector2(0.7, 1.1),
}
const MEADOW_AUTUMN := {
	# Patches
	"patch_frequency": 0.45,
	"patch_seed": 131.0,
	"tall_from": 0.56,
	"tall_to": 0.68,
	"hills_tall_factor": 0.5,
	"edge_band": 1.15,
	"edge_tall_bonus": 0.6,
	"bare_thinning": 0.8,
	"dry_stalk_share": 0.5,
	"nettle_share": 0.25,
	"centre_clear": 0.4,
	# Heights (vertical multiplier on the clump, on top of the 0.7-1.3 scale)
	"tall_height": 1.5,
	"dry_stalk_height": 1.3,
	"nettle_height": 1.35,
	# Colours (sRGB) and how strongly they replace the ground colour
	"tall_color": Color("#b09a55"),
	"tall_mix": 0.3,
	"dry_stalk_color": Color("#b8a46a"),
	"dry_stalk_mix": 0.7,
	"nettle_color": Color("#4e6a34"),
	"nettle_mix": 0.6,
	"marsh_density": 1.3,
	"reed_share": 1.0,
	"bank_reeds": 0.7,
	"reed_height": 1.5,
	"reed_color": Color("#6f7a45"),
	"reed_dry_color": Color("#a39466"),
	"reed_mix": 0.85,
	# Flowers
	"flower_density": 12.0,
	"flower_frequency": 0.9,
	"flower_seed": 137.0,
	"flower_from": 0.55,
	"flower_to": 0.7,
	"flower_cell": 1.2,
	"flower_dominance": 0.75,
	"flower_height": Vector2(1.1, 1.4),
	"flower_stem_color": Color("#5d6f36"),
	"flowers":
	[
		{"name": &"white", "color": Color("#e4e0cf"), "share": 0.30},
		{"name": &"yellow", "color": Color("#d2ad3a"), "share": 0.45},
		{"name": &"violet", "color": Color("#8c5d8f"), "share": 0.20},
		{"name": &"blue", "color": Color("#5f78b2"), "share": 0.05},
	],
	# Scrub clumps on open ground
	"scrub_chance_plains": 0.35,
	"scrub_chance_hills": 0.2,
	"scrub_radius": Vector2(0.55, 0.92),
	"scrub_shrub_scale": Vector2(0.6, 1.0),
	"scrub_companions": 2,
	"scrub_companion_offset": Vector2(0.06, 0.14),
	"scrub_companion_scale": Vector2(0.7, 1.1),
}

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
			Vector3(0.9, 0.82, 0.7),
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
		"meadow": MEADOW_SUMMER,
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
			Vector3(0.9, 0.82, 0.7),
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
		"meadow": MEADOW_AUTUMN,
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
			Vector3(0.9, 0.82, 0.7),
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
		"meadow": MEADOW_SUMMER,
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
	if VisualScale.is_true_size() and REAL_SIZE_LEAF_COLORS.has(species):
		return REAL_SIZE_LEAF_COLORS[species]
	return (_active.get("leaf_colors", {}) as Dictionary).get(species, base)


static func share(species: StringName, base: float) -> float:
	return (_active.get("shares", {}) as Dictionary).get(species, base)


static func autumn_share(base: float) -> float:
	if VisualScale.is_true_size():
		return REAL_SIZE_AUTUMN_SHARE
	return _active.get("autumn_share", base)


static func _apply_real_size_air(env: Environment) -> void:
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = MapScale.to_units(REAL_SIZE_AIR["begin_m"])
	env.fog_depth_end = MapScale.to_units(REAL_SIZE_AIR["end_m"])
	env.fog_depth_curve = REAL_SIZE_AIR["curve"]
	env.fog_light_color = REAL_SIZE_AIR["color"]
	env.fog_light_energy = REAL_SIZE_AIR["energy"]
	env.fog_sun_scatter = REAL_SIZE_AIR["sun_scatter"]
	env.fog_aerial_perspective = REAL_SIZE_AIR["aerial_perspective"]
	env.fog_sky_affect = REAL_SIZE_AIR["sky_affect"]


## Open-ground vegetation values of the active preset (a copy): MEADOW_OFF with the preset's
## "meadow" entry merged in.
static func meadow() -> Dictionary:
	var merged := MEADOW_OFF.duplicate(true)
	merged.merge((_active.get("meadow", {}) as Dictionary).duplicate(true), true)
	return merged


## Real-scale vegetation values of the active preset (a copy): VEGETATION_DEFAULT with the
## preset's "vegetation" entry merged in.
static func vegetation() -> Dictionary:
	var merged := VEGETATION_DEFAULT.duplicate(true)
	merged.merge((_active.get("vegetation", {}) as Dictionary).duplicate(true), true)
	return merged


## Sun and ambient values of the active preset (a copy): SUN_DEFAULT with the preset's "sun"
## entry merged in, and REAL_SIZE_SUN under the `true` VisualScale preset.
static func sun() -> Dictionary:
	var merged := SUN_DEFAULT.duplicate(true)
	merged.merge((_active.get("sun", {}) as Dictionary).duplicate(true), true)
	if VisualScale.is_true_size():
		merged.merge(REAL_SIZE_SUN.duplicate(true), true)
	return merged


## The active sun on the battle's light and environment (BattleController, after
## GraphicsQuality.apply_sun): direction, colour, energy, penumbra, shadow filter / bias and the
## ambient energy.
static func apply_to_sun(light: DirectionalLight3D, env: Environment) -> void:
	var values := sun()
	var elevation := deg_to_rad(values["elevation_deg"])
	var azimuth := deg_to_rad(values["azimuth_deg"])
	var toward := Vector3(
		sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation)
	)
	light.basis = Basis.looking_at(-toward, Vector3.UP)
	light.light_color = values["color"]
	light.light_energy = values["energy"]
	light.light_angular_distance = values["angular_distance"]
	light.shadow_blur = values["shadow_blur"]
	light.shadow_bias = values["shadow_bias"]
	light.shadow_normal_bias = values["shadow_normal_bias"]
	env.ambient_light_energy = values["ambient_energy"]


## Farmland look values of the active preset (a copy): FIELDS_DEFAULT with the preset's "fields"
## entry merged in.
static func fields() -> Dictionary:
	var merged := FIELDS_DEFAULT.duplicate(true)
	merged.merge((_active.get("fields", {}) as Dictionary).duplicate(true), true)
	return merged


## Cloud shadow values of the active preset (a copy): CLOUDS_DEFAULT with the preset's "clouds"
## entry merged in, and REAL_SIZE_CLOUDS under the `true` VisualScale preset.
static func clouds() -> Dictionary:
	var merged := CLOUDS_DEFAULT.duplicate(true)
	merged.merge((_active.get("clouds", {}) as Dictionary).duplicate(true), true)
	if VisualScale.is_true_size():
		merged.merge(REAL_SIZE_CLOUDS.duplicate(true), true)
	return merged


## `base` with the active preset's overrides merged in, and REAL_SIZE_GRADE under the `true`
## VisualScale preset.
static func grade(base: Dictionary) -> Dictionary:
	var merged := base.duplicate()
	merged.merge(_active.get("grade", {}), true)
	if VisualScale.is_true_size():
		merged.merge(REAL_SIZE_GRADE, true)
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
	if VisualScale.is_true_size():
		_apply_real_size_air(env)
	if _active.has("exposure"):
		env.tonemap_exposure = _active["exposure"]
