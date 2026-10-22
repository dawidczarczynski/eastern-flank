// Ground overlays draped on the terrain (unit rings, reach / range / hover washes; TASK-057).
// Rings and outlines: grass clumps stand taller than their lift, so the vertices are pulled
// towards the camera along the view ray by depth_pull: the screen position stays the same, only
// the depth moves, and the overlay wins the depth test against the grass but not against trees,
// units or terrain ridges that are further than depth_pull in front of it.
// Fills (ground_only): they lie under the unit models, a little above the ground, so without a
// mask they tint the wheels, tracks and boots seen through them. The scene depth is
// reconstructed to a world Y (as in water.gdshader) and the fill is kept only where the opaque
// surface behind it is at least ground_band below the fill, i.e. the terrain itself.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float depth_pull = 0.0;
uniform bool ground_only = false;
// World units below the fill that still count as a model or grass standing on the ground.
uniform float ground_band = 0.015;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz -= normalize(v.xyz) * depth_pull;
	POSITION = PROJECTION_MATRIX * v;
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
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	if (ground_only) {
		float below = world_pos.y - scene_world_y(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		ALPHA *= smoothstep(0.5 * ground_band, ground_band, below);
	}
}
