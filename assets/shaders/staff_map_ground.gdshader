// Staff map ground (TASK-125): the displaced relief mesh with flat land-cover colours per vertex
// (sRGB values in COLOR), the baked hillshade (UV.x = shade offset, 0 on flat ground) blended
// soft-light, and the marsh hatch (UV.y = 1 on marsh) as a screen-constant 7 x 5 px tile anchored
// to the ground. Unshaded: the colours are the palette's, no scene lights.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// sRGB, not converted: the blend runs in sRGB like the reference's CSS soft-light.
uniform vec4 marsh_color = vec4(0.275, 0.404, 0.478, 1.0);
uniform float shade_strength = 0.8;
// Shade offset -> soft-light layer: 0.5 + offset * shade_gain (x 1.4 at the far zoom).
uniform float shade_gain = 1.0;
// Hatch tile in screen pixels and in world units (pixels / scale, depth also / cos pitch).
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

void fragment() {
	vec3 base = COLOR.rgb;
	float layer = clamp(0.5 + UV.x * shade_gain, 0.0, 1.0);
	vec3 colour = mix(base, soft_light(base, layer), shade_strength);
	if (UV.y > 0.5) {
		vec2 cell = ground / hatch_tile_world;
		cell.x += floor(cell.y) * 0.5;  // stagger the rows
		vec2 px = fract(cell) * hatch_tile_px;
		float row = 1.0 - smoothstep(0.5, 1.0, abs(px.y - hatch_tile_px.y * 0.5));
		float dash = smoothstep(0.0, 0.8, px.x) * (1.0 - smoothstep(3.6, 4.4, px.x));
		colour = mix(colour, marsh_color.rgb, row * dash * 0.85);
	}
	ALBEDO = to_linear(colour);
}
