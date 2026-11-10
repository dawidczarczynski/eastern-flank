shader_type spatial;
render_mode cull_disabled, specular_disabled, shadows_disabled;
// Road ribbon (TASK-108b): a gravel carriageway with two darker wheel ruts and worn verges that
// fade into the terrain. `UV.y` is the across value (-1 / +1 on the outer verge edges, 0 on the
// centreline, 0.5 at the carriageway edge) and `CUSTOM0.xy` the world XZ direction a vertex moves
// outwards. The vertex shader widens the ribbon so the carriageway is never narrower than
// `min_px` pixels on screen (a 5 m road is below one pixel zoomed out and would shimmer).
// Uses only what the Compatibility renderer has (sampler2DArray, no compute, no screen reads).

uniform sampler2DArray albedo_height : source_color, filter_linear_mipmap, repeat_enable;
// Same layer indices, repeat and tints as terrain.gdshader (TerrainGround).
uniform float layer_repeat[6];
uniform vec3 layer_tint[6];
// Half width of the whole ribbon (world units) and the carriageway's share of it.
uniform float half_width = 0.035;
uniform float carriageway = 0.5;
uniform float min_px = 1.5;
uniform float rut_across = 0.25;
uniform float rut_width = 0.09;
uniform float rut_darkening = 0.45;
uniform vec2 verge_fade = vec2(0.6, 1.0);

const int DIRT = 2;
const int GRAVEL = 4;
const int DRY_GRASS = 1;

varying vec3 world_pos;
varying float across;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float pixels_per_unit = PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5 / max(-view.z, 0.01);
	float wanted = 0.5 * min_px / pixels_per_unit;
	float widen = max(1.0, wanted / (half_width * carriageway));
	VERTEX.xz += CUSTOM0.xy * abs(UV.y) * half_width * (widen - 1.0);
	across = UV.y;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 ground(int layer, vec2 xz) {
	return texture(albedo_height, vec3(xz / layer_repeat[layer], float(layer))).rgb * layer_tint[layer];
}

void fragment() {
	float a = abs(across);
	vec2 xz = world_pos.xz;
	vec3 gravel = ground(GRAVEL, xz);
	vec3 dirt = ground(DIRT, xz);
	vec3 dry = ground(DRY_GRASS, xz);
	float rut = exp(-pow((a - rut_across) / rut_width, 2.0));
	vec3 road = mix(gravel, gravel * dirt * 2.0, rut * rut_darkening * 2.0);
	vec3 verge = mix(dirt, dry, 0.45);
	float edge = smoothstep(carriageway - 0.04, carriageway + 0.04, a);
	ALBEDO = mix(road, verge, edge);
	ROUGHNESS = 1.0;
	ALPHA = 1.0 - smoothstep(verge_fade.x, verge_fade.y, a);
}
