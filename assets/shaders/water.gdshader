// Water v2 (TASK-056): depth colour, two scrolling ripple layers and a
// Schlick fresnel (F0 = 0.02). Alpha blended, no depth write, cull back.
//
// Water depth = vertical distance (world Y) from the surface down to the scene geometry seen
// through it: the scene depth is reconstructed to a world position (INV_PROJECTION_MATRIX,
// INV_VIEW_MATRIX) and compared with the water fragment's world Y. Unlike a view-ray distance
// this does not change with the camera angle, so the colour stays stable while the camera moves.
// Ripples sample in world space (x, z), so the pattern scale does not depend on the plane size.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec4 shallow_color : source_color = vec4(0.2980, 0.4549, 0.3922, 1.0); // #4c7464
uniform vec4 deep_color : source_color = vec4(0.1059, 0.2196, 0.2588, 1.0); // #1b3842
// Water depth (world units) at which the colour is fully deep.
uniform float deep_distance = 0.45;
uniform float shallow_alpha = 0.55;
uniform float deep_alpha = 0.92;

// Ripple layers: normal map repeats per world unit and scroll speeds (UV units per second).
// The old 36 / 23 repeats over the plane correspond to about 0.33 / 0.21 per world unit.
uniform vec2 ripple_scales = vec2(0.33, 0.21);
uniform vec2 ripple_speeds = vec2(0.010, 0.016);
uniform float normal_scale = 0.3;
// Fixed wind direction (the global wind uniform of TASK-057 does not exist yet).
uniform vec2 wind_direction = vec2(0.8, 0.6);

uniform float roughness = 0.05;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float scene_world_y(vec2 screen_uv, mat4 inv_proj, mat4 inv_view) {
	float d = textureLod(depth_texture, screen_uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, d);
#endif
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return (inv_view * vec4(view.xyz, 1.0)).y;
}

void fragment() {
	// Depth below the surface.
	float scene_y = scene_world_y(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float depth = max(world_pos.y - scene_y, 0.0);

	float t = clamp(depth / deep_distance, 0.0, 1.0);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, t);
	float alpha = mix(shallow_alpha, deep_alpha, t);

	// Two ripple layers scrolling in different directions around the wind direction.
	vec2 wind = normalize(wind_direction);
	vec2 dir_a = wind;
	vec2 dir_b = vec2(-wind.y, wind.x) * 0.6 - wind * 0.8;
	vec2 uv_a = world_pos.xz * ripple_scales.x + dir_a * ripple_speeds.x * TIME;
	vec2 uv_b = world_pos.xz * ripple_scales.y + dir_b * ripple_speeds.y * TIME;
	vec3 n_a = texture(normal_map, uv_a).rgb;
	vec3 n_b = texture(normal_map, uv_b).rgb;
	NORMAL_MAP = (n_a + n_b) * 0.5;
	NORMAL_MAP_DEPTH = normal_scale;

	ALBEDO = color;
	ALPHA = alpha;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	// Schlick F0 = 0.16 * SPECULAR^2 (Godot 4) = 0.02.
	SPECULAR = 0.354;
}
