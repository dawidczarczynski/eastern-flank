shader_type spatial;
render_mode cull_disabled, specular_disabled, alpha_to_coverage_and_one;
// Trees (TASK-060): one material per species and LOD, drawn on the two surfaces of a TreeMeshes
// mesh. Vertex colour b = 1 marks leaves (alpha-scissor cards on LOD0, a solid crown on LOD1),
// 0 the bark; r is the baked ambient occlusion, g the per-card flutter phase. The card texture is
// a neutral grey: the hue is the species leaf colour shifted by the per-instance variation
// (INSTANCE_CUSTOM: r hue shift, g value factor, b saturation factor, a wind phase).

#include "res://assets/shaders/wind.gdshaderinc"

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 leaf_color : source_color = vec3(0.3, 0.42, 0.2);
uniform vec3 bark_color : source_color = vec3(0.29, 0.23, 0.16);
// Birch bark: light with dark horizontal marks.
uniform bool birch_bark = false;
// LOD1: the crown is a closed solid, not alpha cards; its albedo is the cards' mean luminance.
uniform bool solid_crown = false;
uniform float solid_luminance = 0.8;
// Model-space reference height (TreeMeshes.TREE_HEIGHT): the sway grows with y / tree_height.
uniform float tree_height = 0.3;
uniform float backlight_strength = 0.35;
// Wind only moves trees near the camera: full strength up to wind_distance - wind_fade, none from
// wind_distance on (the sway is a fraction of a tile, invisible from afar). The solid LOD1 crowns
// skip it altogether.
uniform float wind_distance = 24.0;
uniform float wind_fade = 8.0;

varying vec3 tint;
varying float ao;
varying float leaf;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	leaf = COLOR.b;
	ao = COLOR.r;
	// Hue shift / value / saturation in sRGB-like HSV of the (linear) species colour.
	vec3 hsv = rgb_to_hsv(leaf_color);
	hsv.x = fract(hsv.x - INSTANCE_CUSTOM.r);
	hsv.y = clamp(hsv.y * INSTANCE_CUSTOM.b, 0.0, 1.0);
	hsv.z *= INSTANCE_CUSTOM.g;
	tint = hsv_to_rgb(hsv);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp(VERTEX.y / tree_height, 0.0, 1.2);
	float wind_mask = 0.0;
	if (!solid_crown) {
		wind_mask = clamp((wind_distance - distance(origin, CAMERA_POSITION_WORLD)) / wind_fade, 0.0, 1.0);
	}
	if (wind_mask > 0.0) {
		vec3 offset = wind_offset(origin, h, INSTANCE_CUSTOM.a * 6.2831853);
		offset += wind_flutter(origin, COLOR.g + INSTANCE_CUSTOM.a) * leaf;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * offset * wind_mask;
	}
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// The bent normals hold for both faces of a card (no flip on back faces).
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	if (leaf > 0.5) {
		float alpha = 1.0;
		vec3 luminance = vec3(solid_luminance);
		if (!solid_crown) {
			vec4 texel = texture(leaf_texture, UV);
			luminance = texel.rgb;
			alpha = texel.a;
		}
		ALBEDO = tint * luminance * ao;
		ALPHA = alpha;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		// Softer card edges with MSAA (alpha to coverage); no effect without MSAA.
		ALPHA_ANTIALIASING_EDGE = 0.3;
		ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_texture, 0));
		ROUGHNESS = 0.85;
		BACKLIGHT = tint * backlight_strength * ao;
	} else {
		// Procedural bark: vertical streaks (u around, v along the height), birch: light bark
		// with dark horizontal marks.
		float streak = hash12(vec2(floor(UV.x * 14.0), floor(UV.y * 1.5)));
		vec3 bark = bark_color * (0.8 + 0.3 * streak);
		if (birch_bark) {
			float mark = step(0.72, hash12(vec2(floor(UV.x * 5.0), floor(UV.y * 6.0))));
			bark = mix(bark, vec3(0.06, 0.05, 0.045), mark * 0.85);
		}
		ALBEDO = bark * ao;
		ALPHA = 1.0;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		ROUGHNESS = 0.95;
	}
}
