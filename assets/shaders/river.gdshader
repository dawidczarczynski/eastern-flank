shader_type spatial;
render_mode blend_mix, cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;
// River ribbon (TASK-108c): flowing water with muddy banks. Replaces the plain river material.
// Vertex attributes: UV.x = metres of arc length from the upstream end, UV.y = across (0 on the
// centreline, +-1 on the bank's outer edge), COLOR.r = the across value where the water ends and
// the bank starts (per side), COLOR.g = opacity factor (0 where the water ends in a source or a
// tributary merges into the through river, 1 elsewhere), CUSTOM0.xy = world XZ direction a vertex moves
// outwards, TANGENT = +x (normal mapping without mesh tangents).
// Water: deep colour in the middle to shallow at the water edge, ripples from water.gdshader's
// normal map in (along, across) metres scrolling downstream. Bank: the mud ground layer, fading
// out at the outer edge. `flow_speed` 0 (GraphicsQuality `river_flow` off) keeps the ripples
// still. Uses only what the Compatibility renderer has (sampler2DArray, no screen reads).

#include "res://assets/shaders/cloud_shadow.gdshaderinc"

uniform sampler2DArray albedo_height : source_color, filter_linear_mipmap, repeat_enable;
// Same layer indices, repeat and tints as terrain.gdshader (TerrainGround).
uniform float layer_repeat[6];
uniform vec3 layer_tint[6];
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// World units per metre and the bank width in metres. The water half width of a vertex (it varies
// per river, TASK-216) follows from COLOR.r and the bank band: outer = bank / (1 - edge), water =
// edge * outer; the minimum on-screen width widens the ribbon from that.
uniform float units_per_m = 0.0069;
uniform float bank_m = 3.0;
// The bank band grows with the water: bank = bank_m + bank_k * water (metres), see half_m below.
uniform float bank_k = 0.12;
// Sandy shore: wet sand at the waterline, dry sand further out, the mud texture gives the detail.
uniform vec4 wet_sand : source_color = vec4(0.36, 0.31, 0.22, 1.0);
uniform vec4 dry_sand : source_color = vec4(0.62, 0.55, 0.40, 1.0);
uniform float min_px = 1.5;
// Depth pull towards the camera along the view ray (world units): a base plus a share of the
// distance. The ribbon lies on the exact ground, the coarse far terrain mesh can be above it.
uniform float pull_base = 0.003;
uniform float pull_per_distance = 0.004;

uniform vec4 shallow_color : source_color = vec4(0.2980, 0.4157, 0.3843, 1.0); // #4c6a62
uniform vec4 deep_color : source_color = vec4(0.1804, 0.2902, 0.3216, 1.0); // #2e4a52
uniform float shallow_alpha = 0.7;
uniform float deep_alpha = 0.95;

// Ripple layers: metres per normal-map repeat and downstream speed in metres per second.
uniform vec2 ripple_m = vec2(11.0, 6.5);
uniform float flow_speed = 0.4;
uniform float normal_scale = 0.3;
uniform float roughness = 0.06;

const int MUD = 3;

varying vec3 world_pos;
varying vec3 river; // along (m), across, water edge
varying float half_m;
varying float end_fade; // half width of the ribbon here, metres

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float pixels_per_unit = PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5 / max(-view.z, 0.01);
	float wanted = 0.5 * min_px / pixels_per_unit;
	half_m = bank_m / max(1.0 - (1.0 + bank_k) * COLOR.r, 0.005);
	float water_half = COLOR.r * half_m * units_per_m;
	float widen = max(1.0, wanted / max(water_half, 1e-5));
	VERTEX.xz += CUSTOM0.xy * abs(UV.y) * half_m * units_per_m * (widen - 1.0);
	river = vec3(UV.x, UV.y, COLOR.r);
	end_fade = COLOR.g;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pull towards the camera along the view ray: same screen position, nearer depth.
	vec4 pulled = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(pulled.xyz);
	pulled.xyz -= pulled.xyz / max(dist, 0.001) * (pull_base + pull_per_distance * dist);
	POSITION = PROJECTION_MATRIX * pulled;
}

vec3 ground(int layer, vec2 xz) {
	return texture(albedo_height, vec3(xz / layer_repeat[layer], float(layer))).rgb * layer_tint[layer];
}

void fragment() {
	float a = abs(river.y);
	float edge = river.z;
	float t = clamp(a / max(edge, 0.01), 0.0, 1.0);
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.0, 1.0, t));
	float water_a = mix(deep_alpha, shallow_alpha, t);
	// Wet mud: the mud layer, darkened.
	float shore = smoothstep(edge, 1.0, a);
	float detail = dot(ground(MUD, world_pos.xz), vec3(0.333)) * 1.6 + 0.35;
	vec3 mud = mix(wet_sand.rgb, dry_sand.rgb, smoothstep(0.0, 0.7, shore)) * detail;
	float bank_a = 1.0 - smoothstep(edge, 1.0, a);
	float in_water = 1.0 - smoothstep(edge - 0.04, edge + 0.02, a);
	vec3 colour = mix(mud * cloud_shadow_factor(world_pos.xz), water, in_water);
	ALBEDO = colour;
	ALPHA = mix(bank_a, water_a, in_water) * smoothstep(0.0, 1.0, end_fade);

	// Ripples in (along, across) metres, drifting downstream (towards larger along).
	vec2 uv = vec2(river.x, river.y * half_m);
	vec2 uv_a = vec2(uv.x - flow_speed * TIME, uv.y) / ripple_m.x;
	vec2 uv_b = vec2(uv.x - flow_speed * 0.7 * TIME, uv.y * 0.8) / ripple_m.y;
	NORMAL_MAP = (texture(normal_map, uv_a).rgb + texture(normal_map, uv_b).rgb) * 0.5;
	NORMAL_MAP_DEPTH = normal_scale * in_water;
	ROUGHNESS = mix(1.0, roughness, in_water);
	METALLIC = 0.0;
	SPECULAR = mix(0.2, 0.354, in_water);
}
