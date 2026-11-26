shader_type spatial;
render_mode cull_disabled, specular_disabled;
// The GPU-placed full 3D trees of the real-scale forest (TASK-221, ADR 0027 amendment): the LOD0
// model (bark + alpha-scissor leaf cards, foliage_body.gdshaderinc under PLACED_VEGETATION) of a
// fill tree, derived from its grid cell exactly as the impostors do (forest_impostor.gdshader,
// ForestFill.cell_tree): the same point, species, variant, size, yaw and colour, so a tree and its
// impostor are the one tree. A chunk is a MultiMesh of identity instances, one per cell; the mesh
// has one surface per species (this material is one of them, `placed_species`) holding the three
// variant models, the variant of each vertex in its colour's alpha (ForestField._species_mesh). A
// cell's tree is drawn by the vertices of its own species and variant and collapsed by every
// other: the cheap hash tests come first (variant, species, distance), the map lookups only for
// the few vertices that survive them.
// The base stands on the drawn near surface (NearHeightCache, near_height.gdshaderinc) sunk
// `sink`. Each tree is drawn up to its own point of the hand-over band around `full_centre` (capped
// by `full_reach`, the nearest full chunk that is not built); the impostors take it from there. The
// distance the band is judged by is the impostor's own (the lattice height under the impostor's
// sink: forest_impostor.gdshader), so exactly one of the two draws every tree.

#define PLACED_VEGETATION
#define PLACED_LEAF_COLOR
// The shared cell hash first: its functions take a `spacing` parameter, the fill declares the uniform.
#include "res://assets/shaders/vegetation_hash.gdshaderinc"
#include "res://assets/shaders/forest_cell.gdshaderinc"
#include "res://assets/shaders/near_height.gdshaderinc"

// First cell (x, z) and cell counts (x, z) of the chunk.
instance uniform vec4 cells;

// Set by ForestField: which species this surface draws (TreeSpecies.all() index), per variant the
// model-to-world scale (x and z: tree_size * the crown's narrowing, y: tree_size) at tree scale 1,
// the base sink, the centre of the hand-over band and its half width (camera distance, world
// units; share of the centre), the range cap of the GPU trees (a band around it of the same share,
// `full_cap`), the impostor's base sink (for the distance), the nearest distance at which a full
// chunk is missing (no full tree from there on), the burnt circles.
uniform int placed_species = 0;
uniform vec2 variant_scale[FOREST_VARIANTS];
uniform float sink = 0.0;
uniform float full_centre = 1.0e8;
uniform float band_share = 0.08;
uniform float hand_over_sink = 0.0;
uniform float full_reach = 1.0e9;
uniform float full_cap = 1.0e9;
uniform vec4 burns[128];
uniform int burn_count;

bool placed_instance(
	int instance_id, mat4 main_cam, float tag, out vec4 custom, out vec3 base_color, out vec3 origin,
	out mat3 placed, out mat3 placed_normal
) {
	custom = vec4(0.0, 1.0, 1.0, 0.0);
	base_color = vec3(0.0);
	origin = vec3(0.0);
	placed = mat3(1.0);
	placed_normal = mat3(1.0);
	ivec2 cell;
	if (!veg_instance_cell(instance_id, cells, cell)) {
		return false;
	}
	// ForestFill._pick: variant and species from the pick hash alone, no map data.
	uint h = forest_tile_seed(forest_seed, cell, FOREST_PICK_SALT);
	int variant = min(int(forest_unit(h, FOREST_PART_VARIANT) * float(FOREST_VARIANTS)), FOREST_VARIANTS - 1);
	// The vertex's model (ForestField._species_mesh: alpha = variant / 2).
	if (variant != int(tag * 2.0 + 0.5)) {
		return false;
	}
	float roll = forest_unit(h, FOREST_PART_SPECIES);
	bool conifer_surface = placed_species < 2;
	int species;
	if (conifer_surface) {
		species = roll < shares.x ? 0 : 1;
	} else {
		species = roll < shares.y ? 2 : (roll < shares.z ? 3 : 4);
	}
	if (species != placed_species) {
		return false;
	}
	// ForestFill.cell_tree: the point, then the values hash (size, yaw and the conifer roll).
	vec3 cam = main_cam[3].xyz;
	vec2 p = forest_point(forest_tile_seed(forest_seed, cell, FOREST_POINT_SALT), cell, spacing);
	// Beyond the hand-over band on the ground plane already: no more work.
	if (distance(p, cam.xz) >= min(min(full_centre, full_cap) * (1.0 + band_share), full_reach)) {
		return false;
	}
	if (p.x < fill_area.x || p.y < fill_area.y || p.x >= fill_area.z || p.y >= fill_area.w) {
		return false;
	}
	uint values_hash = forest_tile_seed(forest_seed, cell, FOREST_VALUE_SALT);
	float conifer_roll = float((values_hash >> 20u) & 1023u) / 1024.0;
	// The conifer chance depends on the ground (high / low): a roll that fails both is a deciduous
	// tree (or the reverse) whatever the ground, so the lattice is read only for the rest.
	if (conifer_surface ? conifer_roll >= max(conifer_chance.x, conifer_chance.y)
			: conifer_roll < min(conifer_chance.x, conifer_chance.y)) {
		return false;
	}
	float ground = lattice_height(p);
	if (ground < min_ground) {
		return false;
	}
	bool conifer = conifer_roll < (ground > high_ground ? conifer_chance.x : conifer_chance.y);
	if (conifer != conifer_surface || !stands(p)) {
		return false;
	}
	for (int b = 0; b < burn_count; b++) {
		if (distance(p, burns[b].xy) <= burns[b].z) {
			return false;
		}
	}
	float phase = forest_unit(h, FOREST_PART_PHASE);
	// The hand-over to the impostors (impostor_in_band, tree_impostor_view.gdshaderinc): this tree
	// up to its own point of the band, by the distance of the impostor's base.
	float lod_to = min(
		min(
			mix(full_centre * (1.0 - band_share), full_centre * (1.0 + band_share), phase),
			mix(full_cap * (1.0 - band_share), full_cap * (1.0 + band_share), phase)
		),
		full_reach
	);
	if (distance(vec3(p.x, ground - hand_over_sink, p.y), cam) >= lod_to) {
		return false;
	}
	origin = vec3(p.x, near_drawn_ground(p, ground) - sink, p.y);
	float s = FOREST_SCALE_MIN + FOREST_SCALE_RANGE * float(values_hash & 1023u) / 1024.0;
	float k = float((values_hash >> 10u) & 1023u) / 1024.0;
	float hue = (forest_unit(h, FOREST_PART_HUE) * 2.0 - 1.0) * FOREST_HUE_SHIFT;
	if (!conifer && forest_unit(h, FOREST_PART_AUTUMN) < autumn_share) {
		hue = mix(FOREST_AUTUMN_HUE_MIN, FOREST_AUTUMN_HUE_MAX, forest_unit(h, FOREST_PART_AUTUMN_HUE));
	}
	float value = mix(FOREST_VALUE_MIN, FOREST_VALUE_MAX, forest_unit(h, FOREST_PART_VALUE));
	float saturation = mix(
		FOREST_SATURATION_MIN, FOREST_SATURATION_MAX, forest_unit(h, FOREST_PART_SATURATION)
	);
	custom = vec4(hue, value, saturation, phase);
	// ForestField._fill_transform: Basis(UP, yaw) * Basis.from_scale(s * w, height_scale * h, s * w).
	vec2 size = variant_scale[variant];
	float sx = s * size.x;
	float sy = s * (0.9 + k * 0.3) * size.y;
	float yaw = k * 6.0;
	float c = cos(yaw);
	float sn = sin(yaw);
	mat3 rotation = mat3(vec3(c, 0.0, -sn), vec3(0.0, 1.0, 0.0), vec3(sn, 0.0, c));
	placed = rotation * mat3(vec3(sx, 0.0, 0.0), vec3(0.0, sy, 0.0), vec3(0.0, 0.0, sx));
	placed_normal = rotation
		* mat3(vec3(1.0 / sx, 0.0, 0.0), vec3(0.0, 1.0 / sy, 0.0), vec3(0.0, 0.0, 1.0 / sx));
	return true;
}

#include "res://assets/shaders/foliage_body.gdshaderinc"
