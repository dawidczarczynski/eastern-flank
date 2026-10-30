// Fire puffs (salvo TASK-075): additive and unshaded, brighter than 1 so HIGH's glow catches
// them; the denser middle of the texture burns hotter than its ragged edge.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

#include "res://assets/shaders/puff_billboard.gdshaderinc"

uniform float energy = 3.0;

void fragment() {
	vec4 tex = texture(puff_texture, UV);
	vec4 c = puff_color(COLOR);
	float core = tex.a * tex.a;
	ALBEDO = c.rgb * energy * mix(0.6, 1.4, core);
	ALPHA = clamp(core * c.a * soft_fade(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX), 0.0, 1.0);
}
