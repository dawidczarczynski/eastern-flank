// Salvo smoke and dust puffs (TASK-075): alpha-blended, lit like a soft ball by the sun (a sphere
// normal across the quad), with the texture's grain as self-shadowing, so a puff reads as a
// volume of smoke rather than a flat disc.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

#include "res://assets/shaders/salvo_puff.gdshaderinc"

// World direction towards the sun, its colour on the lit side and the colour of the shaded side.
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.3);
uniform vec3 lit_color : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 shade_color : source_color = vec3(0.45, 0.47, 0.52);

void fragment() {
	vec4 tex = texture(puff_texture, UV);
	vec4 c = puff_color(COLOR);
	vec2 p = corner * 2.0;
	vec3 n = normalize(vec3(p, sqrt(max(1.0 - dot(p, p), 0.0)) + 0.2));
	vec3 l = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	float diffuse = clamp(dot(n, l) * 0.6 + 0.45, 0.0, 1.0);
	vec3 light = mix(shade_color, lit_color, diffuse) * mix(0.72, 1.08, tex.r);
	ALBEDO = c.rgb * light;
	ALPHA = clamp(tex.a * c.a * soft_fade(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX), 0.0, 1.0);
}
