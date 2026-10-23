class_name GraphicsQuality
extends RefCounted
## Graphics quality presets (TASK-050). LOW switches the expensive effects off on slow renderers
## (software rasteriser, Compatibility); HIGH is the look of project.godot and the environment.
## `features()` is the single place the realism features read their switches from.
## Usage: GraphicsQuality.features(GraphicsQuality.detect(method, adapter))

enum Level { LOW, HIGH }

const OPTION_PREFIX := "--quality="
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
		"backdrop_scatter": high,
		# Terrain shader (TASK-055): the rotated second texture scale against tiling, the
		# triplanar rock on steep slopes, and the ground texture array size in texels per side
		# (1024: ~84 MB of uncompressed arrays, packed in the background during the mesh build).
		"terrain_anti_tiling": high,
		"terrain_triplanar": high,
		"terrain_texture_size": 1024 if high else 512,
		# HDRI sky (TASK-054): the sky is static, so HIGH bakes the radiance map once at full
		# quality (256 px per cube face); LOW converges it incrementally at a small size.
		"sky_process_mode": Sky.PROCESS_MODE_QUALITY if high else Sky.PROCESS_MODE_INCREMENTAL,
		"sky_radiance_size": Sky.RADIANCE_SIZE_256 if high else Sky.RADIANCE_SIZE_64,
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
	sun.directional_shadow_max_distance = feature_set["shadow_max_distance"]


## Shadow atlas (global), MSAA and 3D render scale (per viewport).
static func apply_viewport(viewport: Viewport, feature_set: Dictionary) -> void:
	RenderingServer.directional_shadow_atlas_set_size(feature_set["shadow_atlas_size"], true)
	viewport.msaa_3d = feature_set["msaa_3d"]
	viewport.scaling_3d_scale = feature_set["render_scale"]
