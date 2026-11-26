class_name GraphicsQuality
extends RefCounted
## Graphics quality presets (TASK-050). LOW switches the expensive effects off on slow renderers
## (software rasteriser, Compatibility); HIGH is the look of project.godot and the environment.
## `features()` is the single place the realism features read their switches from.
## Usage: GraphicsQuality.features(GraphicsQuality.detect(method, adapter))

enum Level { LOW, HIGH }

const OPTION_PREFIX := "--quality="
## Godot's PSSM split defaults (the battle scene's Sun keeps them outside the `true` preset).
const DEFAULT_SHADOW_SPLITS := Vector3(0.1, 0.2, 0.5)
const SLOW_ADAPTERS: Array[String] = [
	"llvmpipe", "softpipe", "swiftshader", "microsoft basic render"
]


## LOW for the Compatibility renderer or a software adapter, otherwise HIGH.
static func detect(rendering_method: String, adapter_name: String) -> Level:
	if rendering_method == "gl_compatibility":
		return Level.LOW
	var adapter := adapter_name.to_lower()
	for slow in SLOW_ADAPTERS:
		if adapter.contains(slow):
			return Level.LOW
	return Level.HIGH


## Level from a `--quality=low|high` user argument (case-insensitive), -1 = no override.
static func parse_override(args: PackedStringArray) -> int:
	for arg in args:
		if not arg.to_lower().begins_with(OPTION_PREFIX):
			continue
		match arg.substr(OPTION_PREFIX.length()).to_lower():
			"low":
				return Level.LOW
			"high":
				return Level.HIGH
	return -1


static func level_name(level: Level) -> String:
	return "LOW" if level == Level.LOW else "HIGH"


static func features(level: Level) -> Dictionary:
	var high := level == Level.HIGH
	return {
		"ssao": high,
		"ssil": high,
		"ssr": high,
		"glow": high,
		"color_grade": high,
		"shadows": high,
		"shadow_atlas_size": 4096 if high else 2048,
		"shadow_max_distance": 80.0 if high else 40.0,
		# Real-scale sun shadows (TASK-201a, ADR 0030; `true` VisualScale preset only): the far end
		# of the last cascade in metres (MapScale converts it; 80 units = 11.5 km at 250 m hexes)
		# and the three PSSM split fractions, tighter near the camera than Godot's 0.1 / 0.2 / 0.5
		# so that the first cascade keeps trunk and tank detail. 0 = keep shadow_max_distance (LOW
		# has no shadows at all).
		"shadow_max_distance_true_m": 14000.0 if high else 0.0,
		"shadow_splits_true": Vector3(0.04, 0.12, 0.35),
		# HIGH is 4x MSAA (Viewport.MSAA_4X) to match project.godot (anti_aliasing/quality/msaa_3d=2),
		# so that HIGH looks exactly like before the presets existed.
		"msaa_3d": Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED,
		# The software rasteriser (llvmpipe) is geometry- and fill-bound: the trees, bushes and rocks
		# are most of the frame's triangles, so LOW drops them (forest shows by terrain colour) and
		# renders 3D at half resolution.
		"foliage": high,
		"render_scale": 1.0 if high else 0.5,
		"grass_density": 1.0 if high else 0.0,
		"decals_max": 64 if high else 16,
		"particles": high,
		"wind": high,
		# Moving cloud shadows (TASK-201b): a noise lookup per pixel in the world shaders.
		"clouds": high,
		"backdrop_scatter": high,
		# GPU-placed shrubs (TASK-217a, `true` VisualScale preset only): how far shrubs are drawn
		# (metres; LookPreset.vegetation() shrub_impostor_range_m caps it). LOW keeps them close.
		"shrub_range_m": 600.0 if high else 150.0,
		# Chunked world (TASK-072b): LOW builds within smaller rings (ChunkRings.low_quality_factor).
		"small_chunk_rings": not high,
		# Terrain shader (TASK-055): the rotated second texture scale against tiling, the
		# triplanar rock on steep slopes, and the ground texture array size in texels per side
		# (1024: ~84 MB of uncompressed arrays, packed in the background during the mesh build).
		"terrain_anti_tiling": high,
		# TASK-134: the near terrain LOD (LOW keeps the lattice mesh only).
		"terrain_lod": high,
		# TASK-134: the ground detail texture close to the camera.
		"terrain_detail": high,
		"terrain_triplanar": high,
		"terrain_texture_size": 1024 if high else 512,
		# HDRI sky (TASK-054): the sky is static, so HIGH bakes the radiance map once at full
		# quality (256 px per cube face); LOW converges it incrementally at a small size.
		"sky_process_mode": Sky.PROCESS_MODE_QUALITY if high else Sky.PROCESS_MODE_INCREMENTAL,
		"sky_radiance_size": Sky.RADIANCE_SIZE_256 if high else Sky.RADIANCE_SIZE_64,
		# Soldiers' uniform cloth (TASK-085): the crease / weave bump and sheen of the camo shader
		# (a few noise lookups and screen derivatives per pixel); LOW keeps the plain camo.
		"fabric": high,
		# Short OmniLight3D pulses of a rocket salvo (TASK-075): launcher flash and impact flash.
		"fx_lights": high,
		# Ripples drifting downstream on real-terrain rivers (TASK-108c); LOW keeps them still.
		"river_flow": high,
	}


## LOW forces all four off. HIGH enables SSAO and leaves ssil/ssr/glow to the resource
## (configured by the realism tasks; HIGH must not switch on unconfigured effects).
static func apply_environment(env: Environment, feature_set: Dictionary) -> void:
	var ssao: bool = feature_set["ssao"]
	var ssil: bool = feature_set["ssil"]
	var ssr: bool = feature_set["ssr"]
	var glow: bool = feature_set["glow"]
	env.ssao_enabled = ssao
	env.ssil_enabled = env.ssil_enabled and ssil
	env.ssr_enabled = env.ssr_enabled and ssr
	env.glow_enabled = env.glow_enabled and glow
	if env.sky != null:
		# Own Sky: a shallow Environment.duplicate() shares the Sky resource with the cached .tres.
		env.sky = env.sky.duplicate() as Sky
		env.sky.process_mode = feature_set["sky_process_mode"]
		env.sky.radiance_size = feature_set["sky_radiance_size"]
	LookPreset.apply_to_environment(env)
	if feature_set["color_grade"]:
		ColorGrade.apply_to(env)
	else:
		env.adjustment_enabled = false


static func apply_sun(sun: DirectionalLight3D, feature_set: Dictionary) -> void:
	sun.shadow_enabled = feature_set["shadows"]
	var true_distance_m: float = feature_set["shadow_max_distance_true_m"]
	var splits := DEFAULT_SHADOW_SPLITS
	if VisualScale.is_true_size() and true_distance_m > 0.0:
		sun.directional_shadow_max_distance = MapScale.to_units(true_distance_m)
		splits = feature_set["shadow_splits_true"]
	else:
		sun.directional_shadow_max_distance = feature_set["shadow_max_distance"]
	sun.directional_shadow_split_1 = splits.x
	sun.directional_shadow_split_2 = splits.y
	sun.directional_shadow_split_3 = splits.z


## Shared unit materials: the uniform camo's fabric term on or off (ModelParts.set_fabric; also for
## materials made later).
static func apply_materials(feature_set: Dictionary) -> void:
	ModelParts.set_fabric(feature_set["fabric"])


## Shadow atlas (global), MSAA and 3D render scale (per viewport); also the shared unit materials
## (`apply_materials`), which every scene with a viewport to set up needs too.
static func apply_viewport(viewport: Viewport, feature_set: Dictionary) -> void:
	apply_materials(feature_set)
	RenderingServer.directional_shadow_atlas_set_size(feature_set["shadow_atlas_size"], true)
	viewport.msaa_3d = feature_set["msaa_3d"]
	viewport.scaling_3d_scale = feature_set["render_scale"]
