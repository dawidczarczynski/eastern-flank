// Body of the tree shaders (TASK-060): foliage.gdshader (LOD0: bark + alpha-scissor leaf cards) and
// foliage_solid.gdshader (LOD1 / LOD2: bark + a closed solid crown, #define SOLID_CROWN, fully
// opaque). One material per species and LOD on the one surface of a TreeMeshes mesh (bark and
// leaves merged, TASK-108 performance). Vertex colour b = 1 marks leaves, 0 the bark; r is the
// baked ambient occlusion, g the per-card flutter phase. The card texture is a neutral grey: the
// hue is the species leaf colour shifted by the per-instance variation (INSTANCE_CUSTOM: r hue
// shift, g value factor, b saturation factor, a wind phase).

#include "res://assets/shaders/wind.gdshaderinc"

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 leaf_color : source_color = vec3(0.3, 0.42, 0.2);
uniform vec3 bark_color : source_color = vec3(0.29, 0.23, 0.16);
// Birch bark: light with dark horizontal marks.
uniform bool birch_bark = false;
// Solid crowns (foliage_solid.gdshader, LOD1 / LOD2): the albedo is the cards' mean luminance.
uniform float solid_luminance = 0.8;
// Model-space reference height (TreeMeshes.TREE_HEIGHT): the sway grows with y / tree_height.
uniform float tree_height = 0.3;
uniform float backlight_strength = 0.35;
// Wind only moves trees near the camera: full strength up to wind_distance - wind_fade, none from
// wind_distance on (the sway is a fraction of a tile, invisible from afar). The solid crowns skip
// it altogether.
uniform float wind_distance = 24.0;
uniform float wind_fade = 8.0;
// LOD switch per tree (TreeField): the tree is drawn from a distance inside lod_in (begin, end:
// distance of its base from the camera) up to one inside lod_out. Where exactly inside the band is
// the tree's own random value (INSTANCE_CUSTOM.a), the same in every LOD, so neighbouring LODs
// hand over tree by tree across the band and exactly one of them draws each tree. Done here, in
// the vertex shader, and not with VISIBILITY_RANGE_FADE_SELF: Godot draws a fading instance
// alpha-blended, without the depth prepass, which shaded every layer of every tree in the band
// (~5 ms on the target GPU); a dithered discard keeps the prepass but costs the early depth test.
uniform vec2 lod_in = vec2(-2.0, -1.0);
uniform vec2 lod_out = vec2(1.0e8, 1.0e9);

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
	// The viewport's camera also in the shadow passes (CAMERA_POSITION_WORLD is the light there).
	float camera_distance = distance(origin, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	float h = clamp(VERTEX.y / tree_height, 0.0, 1.2);
#ifndef SOLID_CROWN
	float wind_mask = clamp((wind_distance - camera_distance) / wind_fade, 0.0, 1.0);
	if (wind_mask > 0.0) {
		vec3 offset = wind_offset(origin, h, INSTANCE_CUSTOM.a * 6.2831853);
		offset += wind_flutter(origin, COLOR.g + INSTANCE_CUSTOM.a) * leaf;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * offset * wind_mask;
	}
#endif
	float lod_from = mix(lod_in.x, lod_in.y, INSTANCE_CUSTOM.a);
	float lod_to = mix(lod_out.x, lod_out.y, INSTANCE_CUSTOM.a);
	if (camera_distance < lod_from || camera_distance >= lod_to) {
		// Another LOD draws this tree: collapse it to a point (no pixels).
		VERTEX = vec3(0.0);
	}
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Procedural bark: vertical streaks (u around, v along the height), birch: light bark with dark
// horizontal marks.
vec3 bark_albedo(vec2 uv) {
	float streak = hash12(vec2(floor(uv.x * 14.0), floor(uv.y * 1.5)));
	vec3 bark = bark_color * (0.8 + 0.3 * streak);
	if (birch_bark) {
		float mark = step(0.72, hash12(vec2(floor(uv.x * 5.0), floor(uv.y * 6.0))));
		bark = mix(bark, vec3(0.06, 0.05, 0.045), mark * 0.85);
	}
	return bark;
}

void fragment() {
#ifdef SOLID_CROWN
	// Opaque: no ALPHA anywhere, so the mesh stays in the opaque pass (depth prepass, early z,
	// no alpha-tested shadow pass).
	if (leaf > 0.5) {
		ALBEDO = tint * solid_luminance * ao;
		ROUGHNESS = 0.85;
		BACKLIGHT = tint * backlight_strength * ao;
	} else {
		ALBEDO = bark_albedo(UV) * ao;
		ROUGHNESS = 0.95;
	}
#else
	// The bent normals hold for both faces of a card (no flip on back faces).
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	if (leaf > 0.5) {
		vec4 texel = texture(leaf_texture, UV);
		ALBEDO = tint * texel.rgb * ao;
		ALPHA = texel.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		ROUGHNESS = 0.85;
		BACKLIGHT = tint * backlight_strength * ao;
	} else {
		ALBEDO = bark_albedo(UV) * ao;
		ALPHA = 1.0;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		ROUGHNESS = 0.95;
	}
#endif
}
