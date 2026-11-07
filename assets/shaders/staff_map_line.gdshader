// Staff map lines (TASK-125): polylines of a constant width in screen pixels under any zoom and
// pitch. Each segment is a quad; a vertex carries its point (VERTEX), the previous and the next
// point of the polyline (CUSTOM0.xyz / CUSTOM1.xyz, equal to VERTEX at an end) and its side in
// UV.x (+1 / -1). The shader offsets it along the screen-space miter of the joint, so neighbouring
// quads share their edge exactly (no overlap, no darker beads at the joints of faint lines); the
// ends get a square cap of half the width; 1 px of antialiasing fringe on both sides.
// Drawn over the ground without a depth test: the map is a height field seen from above, so
// nothing on it hides a line; render_priority orders the layers.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix,
	shadows_disabled, fog_disabled;

uniform vec4 line_color : source_color = vec4(1.0);
uniform float width_px = 1.0;
uniform float opacity = 1.0;

varying float across;  // signed distance from the centre line, pixels

vec2 to_screen(vec4 clip, vec2 half_size) {
	return clip.xy / clip.w * half_size;
}

void vertex() {
	mat4 to_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX;
	vec4 here = to_clip * vec4(VERTEX, 1.0);
	vec2 half_size = VIEWPORT_SIZE * 0.5;
	vec2 s = to_screen(here, half_size);
	vec2 to_prev = s - to_screen(to_clip * vec4(CUSTOM0.xyz, 1.0), half_size);
	vec2 to_next = to_screen(to_clip * vec4(CUSTOM1.xyz, 1.0), half_size) - s;
	bool start = length(to_prev) < 0.0001;
	bool end = length(to_next) < 0.0001;
	vec2 dir_in = start ? to_next : to_prev;
	vec2 dir_out = end ? to_prev : to_next;
	dir_in = length(dir_in) > 0.0001 ? normalize(dir_in) : vec2(1.0, 0.0);
	dir_out = length(dir_out) > 0.0001 ? normalize(dir_out) : dir_in;
	vec2 tangent = dir_in + dir_out;
	tangent = length(tangent) > 0.0001 ? normalize(tangent) : dir_in;
	vec2 miter = vec2(-tangent.y, tangent.x);
	float half_w = width_px * 0.5;
	float outer = half_w + 1.0;
	// Miter length: keeps the width across both segments; capped at a sharp turn.
	float stretch = 1.0 / max(dot(miter, vec2(-dir_in.y, dir_in.x)), 0.35);
	vec2 offset = miter * UV.x * outer * stretch;
	if (start) {
		offset -= dir_out * half_w;
	}
	if (end) {
		offset += dir_in * half_w;
	}
	across = UV.x * outer;
	POSITION = here + vec4(offset / half_size * here.w, 0.0, 0.0);
}

void fragment() {
	float half_w = width_px * 0.5;
	float coverage = clamp(half_w + 0.5 - abs(across), 0.0, 1.0);
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * opacity * coverage;
}
