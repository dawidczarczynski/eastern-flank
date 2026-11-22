shader_type spatial;
render_mode world_vertex_coords, unshaded, cull_disabled;
// The GPU-placed impostors of the real-scale forest (TASK-189, ADR 0027). A chunk is a MultiMesh of
// the TreeImpostors quad with one instance per fill grid cell and no per-instance data: the cell
// comes from INSTANCE_ID and the chunk's `cells` (instance uniform), and everything else from the
// same formulas as ForestFill.cell_tree (forest_hash.gdshaderinc) and the map textures ForestFill /
// ForestField bind once per map – the stand mask (ForestMaskSource), the parcels, the drawn
// lattice heights. A cell that holds no tree (or whose tree is outside the impostor
// bands, or burnt) collapses to a point. The picture: tree_impostor_view.gdshaderinc.

#include "res://assets/shaders/forest_hash.gdshaderinc"
#include "res://assets/shaders/tree_impostor_view.gdshaderinc"

// TreeSpecies.all(): pine, spruce (conifers), birch, oak, alder.
const int FOREST_SPECIES = 5;

// First cell (x, z) and cell counts (x, z) of the chunk.
instance uniform vec4 cells;

// Every uniform below is set by ForestFill.bind / ForestField._setup_impostors.
uniform uint forest_seed;
uniform float spacing;
uniform float min_ground;
uniform float high_ground;
// ScatterPlanner's conifer chance above / below high_ground.
uniform vec2 conifer_chance;
// Cumulative shares: pine (of the conifers), birch, birch + oak, all (of the deciduous trees).
uniform vec4 shares;
uniform float autumn_share;
// The fill area (x0, z0, x1, z1), end exclusive.
uniform vec4 fill_area;
// Where a tree may stand (ForestFill's stand mask from a ForestMaskSource: forest land cover minus
// the tile-centre clearing, roads and rivers), mask_per_unit texels per unit from fill_area.xy.
uniform sampler2D forest_mask : filter_nearest, repeat_disable;
uniform float mask_per_unit;
uniform bool use_parcels;
uniform sampler2D parcels : filter_nearest, repeat_disable;
uniform vec2 parcel_origin_m;
uniform float parcel_metres_per_pixel;
uniform float metres_per_unit;
// The lattice: heights of (height_cells + 1)^2 vertices from height_origin, height_step apart.
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform vec2 height_origin;
uniform float height_step;
uniform ivec2 height_cells;
uniform float water_surface;
// The impostor base sits this far below the lattice height.
uniform float sink;
// Per species: (full range centre, impostor range centre); per species x variant: (quad width per
// unit of tree scale, height per unit of height scale, atlas row); linear leaf colour per species.
uniform vec2 species_ranges[FOREST_SPECIES];
uniform vec3 variant_sizes[FOREST_SPECIES * FOREST_VARIANTS];
uniform vec3 leaf_colors[FOREST_SPECIES];
// Camera distances outside every species' bands (nearest start, farthest end): skipped early.
uniform vec2 cull;
// Beyond this camera distance every other cell (a checkerboard) is left out, each tree at its own
// point of the band, and the rest widen to thin_widen (far trees are a few pixels: half the
// vertex and fill work, the same look).
uniform float thin_from;
uniform float thin_widen;
// Burnt circles (x, z, radius): no tree inside (ForestField.MAX_BURNS).
uniform vec4 burns[128];
uniform int burn_count;

// TerrainLattice.mesh_height_at
float lattice_height(vec2 p) {
	float fx = clamp((p.x - height_origin.x) / height_step, 0.0, float(height_cells.x));
	float fz = clamp((p.y - height_origin.y) / height_step, 0.0, float(height_cells.y));
	int i = min(int(floor(fx)), height_cells.x - 1);
	int j = min(int(floor(fz)), height_cells.y - 1);
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
	return max(h, water_surface);
}

// ForestFill._stands: on the stand mask and off the parcels.
bool stands(vec2 p) {
	ivec2 t = ivec2(floor((p - fill_area.xy) * mask_per_unit));
	ivec2 size = textureSize(forest_mask, 0);
	if (t.x < 0 || t.y < 0 || t.x >= size.x || t.y >= size.y || texelFetch(forest_mask, t, 0).r < 0.5) {
		return false;
	}
	if (!use_parcels) {
		return true;
	}
	// ParcelMap.blocks_standing: every kind but none (0) and the balk (8).
	ivec2 q = ivec2(floor((p * metres_per_unit - parcel_origin_m) / parcel_metres_per_pixel));
	ivec2 parcel_size = textureSize(parcels, 0);
	if (q.x < 0 || q.y < 0 || q.x >= parcel_size.x || q.y >= parcel_size.y) {
		return true;
	}
	int kind = int(round(texelFetch(parcels, q, 0).r * 255.0));
	return kind == 0 || kind == 8;
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// TreeImpostors.tint: the species colour shifted by the tree's variation, over the unshifted one.
vec3 tree_tint(vec3 leaf, float hue, float value, float saturation) {
	vec3 hsv = rgb_to_hsv(leaf);
	vec3 shifted = hsv_to_rgb(
		vec3(fract(hsv.x - hue), clamp(hsv.y * saturation, 0.0, 1.0), hsv.z * value)
	);
	return clamp(shifted / max(leaf, vec3(0.02)), vec3(0.4), vec3(1.8));
}

void vertex() {
	int nx = max(int(cells.z), 1);
	ivec2 cell = ivec2(int(cells.x) + INSTANCE_ID % nx, int(cells.y) + INSTANCE_ID / nx);
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	uint point_hash = forest_tile_seed(forest_seed, cell, FOREST_POINT_SALT);
	vec2 p = forest_point(point_hash, cell, spacing);
	bool alive = INSTANCE_ID < nx * int(cells.w);
	alive = alive && p.x >= fill_area.x && p.y >= fill_area.y && p.x < fill_area.z && p.y < fill_area.w;
	float ground = 0.0;
	vec3 origin = vec3(p.x, 0.0, p.y);
	float camera_distance = 0.0;
	// Farther than every band already on the ground plane: no height lookups.
	alive = alive && distance(p, cam.xz) < cull.y;
	if (alive) {
		ground = lattice_height(p);
		origin.y = ground - sink;
		camera_distance = distance(origin, cam);
		// The budget's reach may start impostors nearer than any species' full band.
		float near_cull = min(cull.x, full_reach);
		alive = camera_distance >= near_cull && camera_distance < cull.y && ground >= min_ground;
	}
	float thin_phase = float((point_hash * FOREST_UNIT_MULTIPLIER) >> 24u) / 256.0;
	float thin_at = thin_from * mix(1.0 - band_share, 1.0 + band_share, thin_phase);
	if (((cell.x + cell.y) & 1) != 0 && camera_distance >= thin_at) {
		alive = false;
	}
	if (alive) {
		alive = stands(p);
	}
	for (int b = 0; b < burn_count && alive; b++) {
		alive = distance(p, burns[b].xy) > burns[b].z;
	}
	tint = vec3(1.0);
	row = 0.0;
	view_position = 0.0;
	VERTEX = origin;
	if (alive) {
		uint values_hash = forest_tile_seed(forest_seed, cell, FOREST_VALUE_SALT);
		float s = FOREST_SCALE_MIN + FOREST_SCALE_RANGE * float(values_hash & 1023u) / 1024.0;
		float k = float((values_hash >> 10u) & 1023u) / 1024.0;
		float conifer_roll = float((values_hash >> 20u) & 1023u) / 1024.0;
		bool conifer = conifer_roll < (ground > high_ground ? conifer_chance.x : conifer_chance.y);
		uint h = forest_tile_seed(forest_seed, cell, FOREST_PICK_SALT);
		float roll = forest_unit(h, FOREST_PART_SPECIES);
		int species;
		if (conifer) {
			species = roll < shares.x ? 0 : 1;
		} else {
			species = roll < shares.y ? 2 : (roll < shares.z ? 3 : 4);
		}
		int variant = min(int(forest_unit(h, FOREST_PART_VARIANT) * float(FOREST_VARIANTS)), FOREST_VARIANTS - 1);
		float hue = (forest_unit(h, FOREST_PART_HUE) * 2.0 - 1.0) * FOREST_HUE_SHIFT;
		if (!conifer && forest_unit(h, FOREST_PART_AUTUMN) < autumn_share) {
			hue = mix(FOREST_AUTUMN_HUE_MIN, FOREST_AUTUMN_HUE_MAX, forest_unit(h, FOREST_PART_AUTUMN_HUE));
		}
		float value = mix(FOREST_VALUE_MIN, FOREST_VALUE_MAX, forest_unit(h, FOREST_PART_VALUE));
		float saturation = mix(
			FOREST_SATURATION_MIN, FOREST_SATURATION_MAX, forest_unit(h, FOREST_PART_SATURATION)
		);
		float phase = forest_unit(h, FOREST_PART_PHASE);
		vec2 ranges = species_ranges[species];
		if (impostor_in_band(camera_distance, ranges.x, ranges.y, phase)) {
			vec3 size = variant_sizes[species * FOREST_VARIANTS + variant];
			float height_scale = s * (0.9 + k * 0.3);
			row = size.z;
			tint = tree_tint(leaf_colors[species], hue, value, saturation);
			float view;
			float widen = mix(
				1.0,
				thin_widen,
				smoothstep(thin_from * (1.0 - band_share), thin_from * (1.0 + band_share), camera_distance)
			);
			VERTEX = impostor_corner(
				origin, cam, size.x * s * widen, size.y * height_scale, k * 6.0, UV, view
			);
			view_position = view;
		}
	}
}

void fragment() {
	vec4 color = impostor_color(UV);
	if (color.a < 0.5) {
		discard;
	}
	ALBEDO = color.rgb;
}
