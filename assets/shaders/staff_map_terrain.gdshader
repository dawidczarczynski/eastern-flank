// Staff map terrain from real geography (TASK-126): one surface over the displaced relief mesh
// that combines the map's graphic layers – water mask (linear), land cover classes (nearest,
// blended by hand) and hillshade (linear) – into the palette's colours. Edges are the 0.5 contour
// of the tent-filtered masks, smoothed over at least one screen pixel (fwidth), so coasts,
// lakes, forests and towns are soft natural shapes that do not follow hex edges. The hex terrain
// is never read. Same sRGB blending, soft-light hillshade and marsh hatch as
// staff_map_ground.gdshader (the v0 hex look).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D water_tex : filter_linear, repeat_disable;
uniform sampler2D cover_tex : filter_nearest, repeat_disable;
uniform sampler2D relief_tex : filter_linear, repeat_disable;
// World rectangles (x, z origin; width, depth) covered by the water / cover and the relief pixels.
uniform vec4 layer_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 relief_rect = vec4(0.0, 0.0, 1.0, 1.0);

// Palette, sRGB (not converted: the blend runs in sRGB like the reference's CSS).
uniform vec4 land_color = vec4(0.114, 0.129, 0.110, 1.0);
uniform vec4 forest_color = vec4(0.133, 0.188, 0.165, 1.0);
uniform vec4 forest_edge_color = vec4(0.169, 0.239, 0.192, 1.0);
uniform vec4 urban_color = vec4(0.212, 0.224, 0.192, 1.0);
uniform vec4 urban_edge_color = vec4(0.294, 0.306, 0.271, 1.0);
uniform vec4 water_color = vec4(0.075, 0.125, 0.161, 1.0);
uniform vec4 shore_color = vec4(0.169, 0.267, 0.329, 1.0);
uniform vec4 marsh_color = vec4(0.275, 0.404, 0.478, 1.0);
// Cover class values (ImportedMap.COVER_*).
uniform int cover_urban = 3;
uniform int cover_forest = 4;
uniform int cover_marsh = 5;
// Hillshade value on flat ground (ImportedMap.RELIEF_FLAT / 255) and its gain into the offset
// (the layer's shading is computed with a milder slope exaggeration than the v0 per-hex one).
uniform float relief_flat = 0.70588;
uniform float relief_gain = 2.5;
uniform float shade_strength = 0.8;
uniform float shade_gain = 1.0;
// Edge lines (forest, town, shore) in screen pixels; 0 hides them. The land-cover edges are
// fainter than the shore (many small patches).
uniform float edge_px = 1.0;
uniform float cover_edge_alpha = 0.85;
uniform vec2 hatch_tile_px = vec2(7.0, 5.0);
uniform vec2 hatch_tile_world = vec2(0.35, 0.25);

varying vec2 ground;

void vertex() {
	ground = VERTEX.xz;
}

vec3 soft_light(vec3 a, float b) {
	vec3 d = mix(sqrt(a), ((16.0 * a - 12.0) * a + 4.0) * a, step(a, vec3(0.25)));
	return b <= 0.5 ? a - (1.0 - 2.0 * b) * a * (1.0 - a) : a + (2.0 * b - 1.0) * (d - a);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

// One-hot (forest, urban, marsh) of a cover texel.
vec3 cover_classes(ivec2 texel, ivec2 size) {
	int value = int(round(texelFetch(cover_tex, clamp(texel, ivec2(0), size - 1), 0).r * 255.0));
	return vec3(
		float(value == cover_forest), float(value == cover_urban), float(value == cover_marsh)
	);
}

// Coverage of a bilinear mask value: its 0.5 contour, antialiased over >= 1 screen pixel.
float coverage(float mask) {
	float w = max(fwidth(mask), 0.0001);
	return smoothstep(0.5 - w, 0.5 + w, mask);
}

// 1 on a `px`-wide line along the mask's 0.5 contour, 0 elsewhere (antialiased).
float contour(float mask, float px) {
	float w = max(fwidth(mask), 0.0001);
	float d = abs(mask - 0.5) / w;  // distance from the contour in screen pixels (approx.)
	return 1.0 - smoothstep(px * 0.5, px * 0.5 + 1.0, d);
}

// Bilinear (forest, urban, marsh) at texel-space point `p` (class indices must not be filtered).
vec3 cover_bilinear(vec2 p, ivec2 size) {
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	return mix(
		mix(cover_classes(i, size), cover_classes(i + ivec2(1, 0), size), f.x),
		mix(cover_classes(i + ivec2(0, 1), size), cover_classes(i + ivec2(1, 1), size), f.x),
		f.y
	);
}

void fragment() {
	vec2 uv = (ground - layer_rect.xy) / layer_rect.zw;
	// Four bilinear taps half a pixel apart: a tent filter two pixels wide, so the 0.5 contours
	// are rounded curves instead of the chamfered steps of a single bilinear sample.
	vec2 o = vec2(0.5) / vec2(textureSize(water_tex, 0));
	float water = 0.25 * (
		texture(water_tex, uv + vec2(-o.x, -o.y)).r + texture(water_tex, uv + vec2(o.x, -o.y)).r
		+ texture(water_tex, uv + vec2(-o.x, o.y)).r + texture(water_tex, uv + vec2(o.x, o.y)).r
	);
	ivec2 size = textureSize(cover_tex, 0);
	vec2 p = uv * vec2(size) - 0.5;
	vec3 classes = 0.25 * (
		cover_bilinear(p + vec2(-0.5, -0.5), size) + cover_bilinear(p + vec2(0.5, -0.5), size)
		+ cover_bilinear(p + vec2(-0.5, 0.5), size) + cover_bilinear(p + vec2(0.5, 0.5), size)
	);
	float forest = coverage(classes.x);
	float urban = coverage(classes.y);
	float marsh = coverage(classes.z);
	float wet = coverage(water);

	vec3 colour = land_color.rgb;
	colour = mix(colour, forest_color.rgb, forest);
	colour = mix(colour, urban_color.rgb, urban);
	float forest_edge = contour(classes.x, edge_px) * forest_edge_color.a * cover_edge_alpha;
	float urban_edge = contour(classes.y, edge_px) * urban_edge_color.a * cover_edge_alpha;
	colour = mix(colour, forest_edge_color.rgb, forest_edge);
	colour = mix(colour, urban_edge_color.rgb, urban_edge);

	vec2 ruv = (ground - relief_rect.xy) / relief_rect.zw;
	float offset = (texture(relief_tex, ruv).r - relief_flat) * relief_gain;
	float layer = clamp(0.5 + offset * shade_gain, 0.0, 1.0);
	colour = mix(colour, soft_light(colour, layer), shade_strength * (1.0 - wet));

	if (marsh > 0.001) {
		vec2 cell = ground / hatch_tile_world;
		cell.x += floor(cell.y) * 0.5;  // stagger the rows
		vec2 px = fract(cell) * hatch_tile_px;
		float row = 1.0 - smoothstep(0.5, 1.0, abs(px.y - hatch_tile_px.y * 0.5));
		float dash = smoothstep(0.0, 0.8, px.x) * (1.0 - smoothstep(3.6, 4.4, px.x));
		colour = mix(colour, marsh_color.rgb, row * dash * 0.85 * marsh);
	}
	colour = mix(colour, water_color.rgb, wet);
	colour = mix(colour, shore_color.rgb, contour(water, edge_px) * shore_color.a);
	ALBEDO = colour;
}
