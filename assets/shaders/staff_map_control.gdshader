// Terrain control fill (TASK-152): the occupied hexes in the holder colour (vertex colour) as a
// faint fill plus a 45 degree hatch of fixed pixel pitch, so the pattern does not swim with the
// zoom. `hatch` 0 … 1 fades the hatch lines in (Z0: fill only). Drawn over the ground without a
// depth test, ordered by render_priority like the other staff map layers.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix,
	shadows_disabled, fog_disabled;

uniform float fill_alpha = 0.13;
uniform float line_alpha = 0.55;
uniform float pitch_px = 6.0;
uniform float line_px = 2.0;
uniform float hatch = 1.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	float along = (FRAGCOORD.x + FRAGCOORD.y) * 0.70710678;
	float phase = mod(along, pitch_px);
	float d = abs(phase - 0.5 * pitch_px);
	// 1 on the line, antialiased over one pixel.
	float on_line = clamp(0.5 * line_px + 0.5 - d, 0.0, 1.0);
	ALPHA = mix(fill_alpha, line_alpha, on_line * hatch);
}
