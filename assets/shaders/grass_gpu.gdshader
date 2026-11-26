shader_type spatial;
render_mode cull_disabled, specular_disabled;
// The GPU-placed near grass (TASK-217b, ADR 0033; GpuGrassField): crossed clump cards like
// grass.gdshader (same cards, wind, root darkening), but every clump is derived from its grid cell
// (grass_rules.gdshaderinc) in the vertex shader: a chunk is a MultiMesh of identity instances,
// one per cell, with one surface per card kind (this material is one of them, `mode`: 0 grass,
// 1 flowers, 2 reeds), so a cell's clump is drawn by the surface of its kind and collapsed by the
// others. The colour is the ground's (the terrain's grass layers, tinted by the satellite layer
// like the near ground) pulled towards the kind's colour; beyond `fade_from` x the ring the clumps
// thin out (a per-clump roll) until none is left at `grass_reach`, where the terrain's own
// grass tone (terrain.gdshader) carries the ground.

#include "res://assets/shaders/grass_rules.gdshaderinc"
#include "res://assets/shaders/satellite_colour.gdshaderinc"
#include "res://assets/shaders/wind.gdshaderinc"
#include "res://assets/shaders/cloud_shadow.gdshaderinc"

// First cell (x, z) and cell counts (x, z) of the chunk.
instance uniform vec4 cells;

uniform sampler2D card : source_color, filter_linear_mipmap, repeat_disable;
uniform int mode = 0;
uniform float root_darkening = 0.55;
uniform vec3 stem_color : source_color = vec3(0.1, 0.16, 0.04);
// Linear ground colours of the grass and dry-grass layers (TerrainTextures average colours).
uniform vec3 ground_grass = vec3(0.12, 0.2, 0.05);
uniform vec3 ground_dry = vec3(0.3, 0.27, 0.1);
// The draw range (world units, from the camera) and the share where the thinning starts.
uniform float grass_reach = 1.0;
uniform float fade_from = 0.6;
// Mip level of the satellite layer read for the clump colour.
uniform float satellite_lod = 2.0;
uniform vec4 burns[128];
uniform int burn_count;

varying float height_k;

// The linear colour of a clump: the ground (grass towards dry by the dry share, per-clump tint,
// the satellite hue of the near ground) pulled towards the kind's colour.
vec3 grass_colour(vec2 p, int kind, float tint, float dry) {
	vec3 base = mix(ground_grass, ground_dry, GRASS_DRY_MAX * dry);
	if (satellite_on) {
		vec2 uv = (p - satellite_rect.xy) * satellite_rect.zw;
		vec2 inside = min(uv, 1.0 - uv) / satellite_edge;
		float coverage = clamp(min(inside.x, inside.y), 0.0, 1.0);
		vec3 layer = textureLod(satellite_map, clamp(uv, vec2(0.0), vec2(1.0)), satellite_lod).rgb;
		layer = mix(vec3(dot(layer, SATELLITE_LUMA)), layer, satellite_saturation) * satellite_gain;
		base = mix(base, satellite_hue(base, layer), satellite_near_tint * coverage);
	}
	base *= mix(0.85, 1.1, tint);
	vec3 target = kind_target[kind];
	if (kind == GRASS_REED) {
		target = mix(target, reed_dry, dry);
	}
	return mix(base, target, kind_mix[kind]);
}

void vertex() {
	height_k = 1.0 - UV.y;
	ivec2 cell;
	bool alive = veg_instance_cell(INSTANCE_ID, cells, cell);
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	vec2 p = grass_point(cell);
	// Beyond the ring on the ground plane already: no texture reads.
	alive = alive && distance(p, cam.xz) < grass_reach;
	float ground = 0.0;
	int kind = 0;
	float height = 1.0;
	float scale = 1.0;
	float yaw = 0.0;
	float tint = 0.5;
	float dry = 0.0;
	float phase = 0.0;
	float fade = 0.0;
	vec3 flower_colour = vec3(1.0);
	if (alive) {
		alive = grass_at(cell, p, ground, kind, height, scale, yaw, tint, dry, phase, fade, flower_colour);
	}
	int kind_mode = kind == GRASS_FLOWER ? 1 : (kind == GRASS_REED ? 2 : 0);
	alive = alive && kind_mode == mode;
	for (int b = 0; b < burn_count && alive; b++) {
		alive = distance(p, burns[b].xy) > burns[b].z;
	}
	vec3 origin = vec3(p.x, shrub_drawn_ground(p, ground), p.y);
	if (alive) {
		float d = distance(origin, cam);
		alive = d < grass_reach && fade < 1.0 - smoothstep(fade_from * grass_reach, grass_reach, d);
	}
	if (!alive) {
		VERTEX = vec3(0.0);
	} else {
		float c = cos(yaw);
		float s = sin(yaw);
		vec3 v = VERTEX * vec3(scale, scale * height, scale);
		// Basis(Vector3.UP, yaw) applied to the scaled vertex.
		vec3 world = origin + vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
		world += wind_offset(world, height_k, phase * 6.2831853);
		VERTEX = world - NODE_POSITION_WORLD;
		COLOR = vec4(mode == 1 ? flower_colour : grass_colour(p, kind, tint, dry), 1.0);
	}
}

void fragment() {
	vec4 texel = texture(card, UV);
	if (texel.a < 0.5) {
		discard;
	}
	if (mode == 1) {
		vec3 stem = stem_color * mix(root_darkening, 1.0, height_k);
		ALBEDO = mix(stem, COLOR.rgb, texel.g) * texel.r;
	} else if (mode == 2) {
		float head = clamp((texel.r - texel.b) * 8.0, 0.0, 1.0);
		vec3 blade = texel.rgb * COLOR.rgb;
		ALBEDO = mix(blade, texel.rgb, head) * mix(root_darkening, 1.0, height_k);
	} else {
		ALBEDO = texel.rgb * COLOR.rgb * mix(root_darkening, 1.0, height_k);
	}
	ALBEDO *= cloud_shadow_factor((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz);
	ROUGHNESS = 0.9;
	// Ground-like lighting on both faces: always the up normal (view space), whatever the face.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
