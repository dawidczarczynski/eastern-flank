// Screen decoration of the HUD v3 look (TASK-076): vignette, scanlines and four L-shaped corner
// brackets in ONE full-screen quad. Everything is analytic (no textures), so it costs a few ALU
// ops per pixel. Layout and values from docs/design/hud_v3/README.md "Screen-level decoration":
//   vignette  radial-gradient(ellipse 110% 85% at 50% 50%, transparent 62%, rgba(0,0,0,.42))
//   scanlines 1 px dark every 4 px (the 4th row of each period)
//   brackets  22 px arms, 1.5 px stroke, 10 px inset from every screen corner
shader_type canvas_item;

uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float vignette_alpha : hint_range(0.0, 1.0) = 0.42;
uniform vec2 vignette_radius = vec2(1.10, 0.85); // ellipse radii as a fraction of width / height
uniform float vignette_start : hint_range(0.0, 1.0) = 0.62;
uniform float scanline_alpha : hint_range(0.0, 1.0) = 0.05;
uniform float scanline_period = 4.0;
// Overridden by ScreenDecor with UiPalette.LINE; this default is only a fallback.
uniform vec4 bracket_color : source_color = vec4(0.91, 0.69, 0.29, 0.34);
uniform float bracket_inset = 10.0;
uniform float bracket_arm = 22.0;
uniform float bracket_stroke = 1.5;

void fragment() {
	vec2 px = floor(UV * rect_size); // integer pixel index; its centre is px + 0.5

	// Vignette: 0 until vignette_start of the ellipse radius, then linear to the edge value.
	vec2 centered = (px + 0.5 - rect_size * 0.5) / (rect_size * vignette_radius);
	float vig = vignette_alpha * clamp((length(centered) - vignette_start) / (1.0 - vignette_start), 0.0, 1.0);

	// Scanlines: the last row of every period darkens.
	float scan = (mod(px.y, scanline_period) >= scanline_period - 1.0) ? scanline_alpha : 0.0;

	float dark = 1.0 - (1.0 - vig) * (1.0 - scan);

	// Corner brackets: fold the pixel into the top-left corner, then test the two arms.
	vec2 q = min(px, rect_size - 1.0 - px) - vec2(bracket_inset);
	float stroke_x = clamp(bracket_stroke - q.x, 0.0, 1.0);
	float stroke_y = clamp(bracket_stroke - q.y, 0.0, 1.0);
	float arm_x = step(0.0, q.x) * step(q.x, bracket_arm - 1.0);
	float arm_y = step(0.0, q.y) * step(q.y, bracket_arm - 1.0);
	float on_x = step(0.0, q.x) * stroke_y * arm_x * step(0.0, q.y); // horizontal arm
	float on_y = step(0.0, q.y) * stroke_x * arm_y * step(0.0, q.x); // vertical arm
	float bracket = max(on_x, on_y) * bracket_color.a;

	float out_a = bracket + dark * (1.0 - bracket);
	vec3 out_rgb = out_a > 0.0 ? bracket_color.rgb * bracket / out_a : vec3(0.0);
	COLOR = vec4(out_rgb, out_a);
}
