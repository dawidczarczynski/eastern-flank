#[compute]
#version 450

// The full 3D trees of the real-scale forest, compacted on the GPU (TASK-221 follow-up, ADR 0027
// amendment 2): every frame one thread per fill cell of a square window around the camera derives
// the cell's tree exactly as ForestFill.cell_tree / forest_impostor.gdshader do (forest_hash,
// the lattice, the stand mask), and a tree that is inside its species' full range appends its
// transform and variation to the list of its model (species x variant). The lists are the
// MultiMesh buffers of the models (ForestFullTrees copies them over), so a tree costs the
// vertices of its own model only – not those of all 15 models, as when the vertex shader derived
// the tree from an identity instance (ADR 0027 decision 4).
// A tree is a full tree up to its own point of the hand-over band around its species' range
// (capped by `full_cap`), judged by the distance of the impostor's base: the very expression of
// tree_impostor_view.gdshaderinc impostor_in_band, so exactly one of the two draws every tree.
// The twin in GDScript: ForestField.full_trees_around (the reference tests compare).

#include "res://assets/shaders/forest_hash.gdshaderinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

const int MODELS = 15;
const int VARIANTS = 3;
const int MAX_BURNS = 128;

layout(set = 0, binding = 0) uniform sampler2D forest_mask;
layout(set = 0, binding = 1) uniform sampler2D parcels;
layout(set = 0, binding = 2) uniform sampler2D heights;
layout(set = 0, binding = 3) uniform sampler2D near_heights;

layout(set = 0, binding = 4, std430) restrict readonly buffer Params {
	// x: forest seed, y: use_parcels, z: use_near, w: burn count
	uvec4 flags;
	// First cell (x, z) and cell counts (x, z) of the window.
	ivec4 window;
	// height_cells (x, z)
	ivec4 height_cells;
	// camera position, spacing
	vec4 camera;
	vec4 fill_area;
	// min_ground, high_ground, water_surface, metres_per_unit
	vec4 ground;
	// conifer_chance (x, y), autumn_share, mask_per_unit
	vec4 conifer;
	// Cumulative shares: pine (of the conifers), birch, birch + oak, all (of the deciduous trees).
	vec4 shares;
	// height_origin (x, z), height_step, hand_over_sink
	vec4 height;
	// near_origin (x, z), near_step, sink
	vec4 near;
	// parcel_origin_m (x, z), parcel_metres_per_pixel, band_share
	vec4 parcel;
	// full_cap
	vec4 cap;
	// Per species the centre of its full band (camera distance, world units).
	vec4 centres[2];
	// Per model (species * 3 + variant): the model-to-world scale (x, z: width, y: height) at
	// tree scale 1; two models a vec4.
	vec4 scales[8];
	// Per model the capacity of its list and its first instance in the output.
	uvec4 capacity[4];
	uvec4 first[4];
	// Burnt circles (x, z, radius, 0).
	vec4 burns[MAX_BURNS];
} P;

layout(set = 0, binding = 5, std430) restrict buffer Counts {
	uint count[16];
} counts;

// 16 floats an instance: the MultiMesh buffer of a 3D transform with custom data (three rows of
// basis x, y, z and origin, then the custom data).
layout(set = 0, binding = 6, std430) restrict writeonly buffer Instances {
	vec4 data[];
} instances;

// TerrainLattice.mesh_height_at
float lattice_height(vec2 p) {
	float fx = clamp((p.x - P.height.x) / P.height.z, 0.0, float(P.height_cells.x));
	float fz = clamp((p.y - P.height.y) / P.height.z, 0.0, float(P.height_cells.y));
	int i = min(int(floor(fx)), P.height_cells.x - 1);
	int j = min(int(floor(fz)), P.height_cells.y - 1);
	float u = fx - float(i);
	float v = fz - float(j);
	float ha = texelFetch(heights, ivec2(i, j), 0).r;
	float hb = texelFetch(heights, ivec2(i + 1, j), 0).r;
	float hc = texelFetch(heights, ivec2(i, j + 1), 0).r;
	float h;
	if (u + v <= 1.0) {
		h = ha + u * (hb - ha) + v * (hc - ha);
	} else {
		float hd = texelFetch(heights, ivec2(i + 1, j + 1), 0).r;
		h = hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd);
	}
	return max(h, P.ground.z);
}

// NearHeightCache / near_height.gdshaderinc near_drawn_ground
float near_drawn_ground(vec2 p, float lattice) {
	if (P.flags.z == 0u) {
		return lattice;
	}
	vec2 f = (p - P.near.xy) / P.near.z;
	ivec2 i = ivec2(floor(f));
	ivec2 size = textureSize(near_heights, 0);
	if (i.x < 0 || i.y < 0 || i.x + 1 >= size.x || i.y + 1 >= size.y) {
		return lattice;
	}
	float ha = texelFetch(near_heights, i, 0).r;
	float hb = texelFetch(near_heights, i + ivec2(1, 0), 0).r;
	float hc = texelFetch(near_heights, i + ivec2(0, 1), 0).r;
	float hd = texelFetch(near_heights, i + ivec2(1, 1), 0).r;
	if (min(min(ha, hb), min(hc, hd)) < -1.0e5) {
		return lattice;
	}
	float u = f.x - float(i.x);
	float v = f.y - float(i.y);
	if (u + v <= 1.0) {
		return ha + u * (hb - ha) + v * (hc - ha);
	}
	return hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd);
}

// ForestFill._stands: on the stand mask and off the parcels.
bool stands(vec2 p) {
	ivec2 t = ivec2(floor((p - P.fill_area.xy) * P.conifer.w));
	ivec2 size = textureSize(forest_mask, 0);
	if (t.x < 0 || t.y < 0 || t.x >= size.x || t.y >= size.y || texelFetch(forest_mask, t, 0).r < 0.5) {
		return false;
	}
	if (P.flags.y == 0u) {
		return true;
	}
	// ParcelMap.blocks_standing: every kind but none (0) and the balk (8).
	ivec2 q = ivec2(floor((p * P.ground.w - P.parcel.xy) / P.parcel.z));
	ivec2 parcel_size = textureSize(parcels, 0);
	if (q.x < 0 || q.y < 0 || q.x >= parcel_size.x || q.y >= parcel_size.y) {
		return true;
	}
	int kind = int(round(texelFetch(parcels, q, 0).r * 255.0));
	return kind == 0 || kind == 8;
}

float species_centre(int species) {
	return species < 4 ? P.centres[0][species] : P.centres[1].x;
}

vec2 model_scale(int model) {
	vec4 pair = P.scales[model / 2];
	return (model % 2) == 0 ? pair.xy : pair.zw;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= P.window.z || id.y >= P.window.w) {
		return;
	}
	ivec2 cell = P.window.xy + id;
	float spacing = P.camera.w;
	float band = P.parcel.w;
	vec3 cam = P.camera.xyz;
	uint seed = P.flags.x;
	// ForestFill._pick: variant and species roll from the pick hash alone, no map data.
	uint h = forest_tile_seed(seed, cell, FOREST_PICK_SALT);
	int variant = min(int(forest_unit(h, FOREST_PART_VARIANT) * float(FOREST_VARIANTS)), FOREST_VARIANTS - 1);
	float roll = forest_unit(h, FOREST_PART_SPECIES);
	// ForestFill.cell_tree: the point, then the values hash (size, yaw and the conifer roll).
	vec2 p = forest_point(forest_tile_seed(seed, cell, FOREST_POINT_SALT), cell, spacing);
	float outer = min(P.cap.x, 1.0e9) * (1.0 + band);
	if (distance(p, cam.xz) >= outer) {
		return;
	}
	if (p.x < P.fill_area.x || p.y < P.fill_area.y || p.x >= P.fill_area.z || p.y >= P.fill_area.w) {
		return;
	}
	uint values_hash = forest_tile_seed(seed, cell, FOREST_VALUE_SALT);
	float conifer_roll = float((values_hash >> 20u) & 1023u) / 1024.0;
	float ground = lattice_height(p);
	if (ground < P.ground.x) {
		return;
	}
	bool conifer = conifer_roll < (ground > P.ground.y ? P.conifer.x : P.conifer.y);
	if (!stands(p)) {
		return;
	}
	int species;
	if (conifer) {
		species = roll < P.shares.x ? 0 : 1;
	} else {
		species = roll < P.shares.y ? 2 : (roll < P.shares.z ? 3 : 4);
	}
	float phase = forest_unit(h, FOREST_PART_PHASE);
	// The hand-over to the impostors (impostor_in_band, tree_impostor_view.gdshaderinc): this tree
	// up to its own point of the band, by the distance of the impostor's base.
	float centre = species_centre(species);
	float lod_to = min(
		mix(centre * (1.0 - band), centre * (1.0 + band), phase),
		mix(P.cap.x * (1.0 - band), P.cap.x * (1.0 + band), phase)
	);
	if (distance(vec3(p.x, ground - P.height.w, p.y), cam) >= lod_to) {
		return;
	}
	for (uint b = 0u; b < P.flags.w; b++) {
		if (distance(p, P.burns[b].xy) <= P.burns[b].z) {
			return;
		}
	}
	int model = species * FOREST_VARIANTS + variant;
	uint slot = atomicAdd(counts.count[model], 1u);
	if (slot >= P.capacity[model / 4][model % 4]) {
		return;
	}
	vec3 origin = vec3(p.x, near_drawn_ground(p, ground) - P.near.w, p.y);
	float s = FOREST_SCALE_MIN + FOREST_SCALE_RANGE * float(values_hash & 1023u) / 1024.0;
	float k = float((values_hash >> 10u) & 1023u) / 1024.0;
	float hue = (forest_unit(h, FOREST_PART_HUE) * 2.0 - 1.0) * FOREST_HUE_SHIFT;
	if (!conifer && forest_unit(h, FOREST_PART_AUTUMN) < P.conifer.z) {
		hue = mix(FOREST_AUTUMN_HUE_MIN, FOREST_AUTUMN_HUE_MAX, forest_unit(h, FOREST_PART_AUTUMN_HUE));
	}
	float value = mix(FOREST_VALUE_MIN, FOREST_VALUE_MAX, forest_unit(h, FOREST_PART_VALUE));
	float saturation = mix(
		FOREST_SATURATION_MIN, FOREST_SATURATION_MAX, forest_unit(h, FOREST_PART_SATURATION)
	);
	// ForestField._fill_transform: Basis(UP, yaw) * Basis.from_scale(s * w, height_scale * h, s * w).
	vec2 size = model_scale(model);
	float sx = s * size.x;
	float sy = s * (0.9 + k * 0.3) * size.y;
	float yaw = k * 6.0;
	float c = cos(yaw);
	float sn = sin(yaw);
	mat3 rotation = mat3(vec3(c, 0.0, -sn), vec3(0.0, 1.0, 0.0), vec3(sn, 0.0, c));
	mat3 m = rotation * mat3(vec3(sx, 0.0, 0.0), vec3(0.0, sy, 0.0), vec3(0.0, 0.0, sx));
	uint at = (P.first[model / 4][model % 4] + slot) * 4u;
	instances.data[at] = vec4(m[0][0], m[1][0], m[2][0], origin.x);
	instances.data[at + 1u] = vec4(m[0][1], m[1][1], m[2][1], origin.y);
	instances.data[at + 2u] = vec4(m[0][2], m[1][2], m[2][2], origin.z);
	instances.data[at + 3u] = vec4(hue, value, saturation, phase);
}
