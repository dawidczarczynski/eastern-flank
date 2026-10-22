shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Grass clumps (TASK-057): alpha-scissored crossed cards, wind sway. The card is a neutral grey;
// the hue is the per-instance colour (linear), the root darkening happens only here.

#include "res://assets/shaders/wind.gdshaderinc"

uniform sampler2D card : source_color, filter_linear_mipmap, repeat_disable;
uniform float root_darkening = 0.55;

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
	ALBEDO = texel.rgb * COLOR.rgb * mix(root_darkening, 1.0, height_k);
	ROUGHNESS = 0.9;
	// Ground-like lighting on both faces: always the up normal (view space), whatever the face.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
