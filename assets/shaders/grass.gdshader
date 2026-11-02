shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Grass clumps (TASK-057): alpha-scissored crossed cards, wind sway. The card is a neutral grey;
// the hue is the per-instance colour (linear), the root darkening happens only here.

#include "res://assets/shaders/wind.gdshaderinc"

uniform sampler2D card : source_color, filter_linear_mipmap, repeat_disable;
uniform float root_darkening = 0.55;
// Flower mode (TASK-070): the card is R = shade, G = blossom mask; COLOR is the blossom colour.
uniform bool flower_mode = false;
// Reed mode (TASK-108e): blades are grey and tinted by COLOR; seed heads (R > B in the card) keep
// their own brown.
uniform bool reed_mode = false;
uniform vec3 stem_color : source_color = vec3(0.1, 0.16, 0.04);

varying float height_k;

void vertex() {
	height_k = 1.0 - UV.y;
	vec3 instance_pos = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(instance_pos.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 offset = wind_offset(world_vertex, height_k, phase);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset;
}

void fragment() {
	vec4 texel = texture(card, UV);
	if (texel.a < 0.5) {
		discard;
	}
	if (flower_mode) {
		vec3 stem = stem_color * mix(root_darkening, 1.0, height_k);
		ALBEDO = mix(stem, COLOR.rgb, texel.g) * texel.r;
	} else if (reed_mode) {
		float head = clamp((texel.r - texel.b) * 8.0, 0.0, 1.0);
		vec3 blade = texel.rgb * COLOR.rgb;
		ALBEDO = mix(blade, texel.rgb, head) * mix(root_darkening, 1.0, height_k);
	} else {
		ALBEDO = texel.rgb * COLOR.rgb * mix(root_darkening, 1.0, height_k);
	}
	ROUGHNESS = 0.9;
	// Ground-like lighting on both faces: always the up normal (view space), whatever the face.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
