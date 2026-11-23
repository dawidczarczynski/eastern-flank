// Satellite colour layer (TASK-192b, ADR 0031; SatelliteColour): the Sentinel-2 summer composite of
// the battle's map as one sRGB texture in world space. Included by terrain.gdshader (the far ground
// takes the layer's colour, the near ground a luminance-preserving tint of it) and
// canopy.gdshader (the forest shells take its hue). Off (`satellite_on` false, the default) the
// shaders skip it entirely: the `balanced` look and maps without a layer render as before.
// SatelliteColour has the GDScript twins of these functions (tests/unit/test_satellite_colour.gd).

uniform bool satellite_on = false;
uniform sampler2D satellite_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable, hint_default_black;
// World x, z of the raster's outer north-west corner and 1 / its world width, height.
uniform vec4 satellite_rect = vec4(0.0, 0.0, 1.0, 1.0);
// The layer fades out over this width inside the raster's edge (in raster uv, x and z).
uniform vec2 satellite_edge = vec2(0.01);
// Near tint share and the view distance band (world units) over which the layer takes over.
uniform float satellite_near_tint = 0.25;
uniform vec2 satellite_blend = vec2(2.0, 10.0);
uniform float satellite_gain = 1.0;
uniform float satellite_saturation = 1.0;

const vec3 SATELLITE_LUMA = vec3(0.2126, 0.7152, 0.0722);

// The layer's linear colour at world (x, z) in rgb, its coverage (0 outside, 1 inside the edge
// band) in a. Call it in uniform control flow (mipmapped sample).
vec4 satellite_sample(vec2 xz) {
	vec2 uv = (xz - satellite_rect.xy) * satellite_rect.zw;
	vec2 inside = min(uv, 1.0 - uv) / satellite_edge;
	float coverage = clamp(min(inside.x, inside.y), 0.0, 1.0);
	vec3 c = texture(satellite_map, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
	c = mix(vec3(dot(c, SATELLITE_LUMA)), c, satellite_saturation) * satellite_gain;
	return vec4(c, coverage);
}

// How far the layer has taken over at view distance `d`: 0 up to the blend start, 1 beyond its end.
float satellite_far(float d) {
	return smoothstep(satellite_blend.x, satellite_blend.y, d);
}

// The layer's weight at view distance `d`: the near tint up to the blend start, 1 beyond its end.
float satellite_weight(float d) {
	return mix(satellite_near_tint, 1.0, satellite_far(d));
}

// `layer`'s hue and saturation at `base`'s luminance.
vec3 satellite_hue(vec3 base, vec3 layer) {
	return layer * (dot(base, SATELLITE_LUMA) / max(dot(layer, SATELLITE_LUMA), 1e-4));
}

// The ground colour at view distance `d`: near, `base` tinted towards the layer's hue at its own
// luminance (the splat detail stays); far, the layer's colour itself.
vec3 satellite_ground(vec3 base, vec4 layer, float d) {
	float far = satellite_far(d);
	vec3 target = mix(satellite_hue(base, layer.rgb), layer.rgb, far);
	return mix(base, target, mix(satellite_near_tint, 1.0, far) * layer.a);
}
