shader_type spatial;
// Procedural three-tone camouflage with grain and mud near the ground (TASK-029).
// Port of GLSL_NOISE / camo() in docs/design/v2/game_screen.scene.js.
// Pattern mode 0 = blotches, 1 = digital (pixel squares, e.g. Russian EMR).

uniform vec4 color_a : source_color = vec4(0.30, 0.34, 0.20, 1.0);
uniform vec4 color_b : source_color = vec4(0.23, 0.20, 0.15, 1.0);
uniform vec4 color_c : source_color = vec4(0.13, 0.15, 0.11, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.357, 0.290, 0.208, 1.0);
uniform float pattern_scale = 9.0;
uniform float dirt_height = 0.12;
uniform float base_roughness = 0.8;
uniform float metallic = 0.12;
uniform int pattern_mode = 0;
uniform float digital_cells = 6.0;
// Offset of this part inside the model (set per MeshInstance3D by UnitModels) so the pattern
// and the mud line are continuous across the separate primitives of one model.
instance uniform vec3 part_origin = vec3(0.0);

varying vec3 obj_pos;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(h3(i), h3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(h3(i + vec3(0.0, 1.0, 0.0)), h3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(h3(i + vec3(0.0, 0.0, 1.0)), h3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(h3(i + vec3(0.0, 1.0, 1.0)), h3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fb(vec3 p) {
	return n3(p) * 0.55 + n3(p * 2.07) * 0.3 + n3(p * 4.3) * 0.15;
}

void vertex() {
	obj_pos = VERTEX + part_origin;
}

void fragment() {
	vec3 q = obj_pos * pattern_scale;
	if (pattern_mode == 1) {
		q = floor(q * digital_cells) / digital_cells;
	}
	float ca = fb(q);
	float cb = fb(q * 1.27 + vec3(17.0, 3.0, 9.0));
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.52, 0.55, ca));
	col = mix(col, color_c.rgb, smoothstep(0.6, 0.63, cb));
	float gr = n3(obj_pos * pattern_scale * 18.0);
	col *= 0.88 + 0.24 * gr;
	float dirt = smoothstep(dirt_height, 0.0, obj_pos.y)
		* (0.45 + 0.55 * n3(obj_pos * pattern_scale * 5.0));
	col = mix(col, dirt_color.rgb, dirt * 0.85);
	ALBEDO = col;
	ROUGHNESS = clamp(base_roughness + (gr - 0.5) * 0.25 + dirt * 0.1, 0.0, 1.0);
	METALLIC = metallic;
}
