shader_type spatial;
// Procedural camouflage with used-steel weathering (TASK-029, TASK-062). Port of GLSL_NOISE /
// camo() in docs/design/v2/game_screen.scene.js and of the paint of the model detail study
// (docs/design/showcase/showcase_paint.gdshader.txt).
// Pattern mode 0 = hard-edged blotches, 1 = digital (pixel squares, e.g. Russian EMR).
//
// The weathering reads the vertex mask the mesh helpers write (ADR 0012): COLOR.r = chamfer / edge
// (paint wear), COLOR.g = openness (1 open, towards 0 in cavities), COLOR.b = per-part tint seed.
// Every mesh using this shader must carry colours (ModelParts helpers always write them; Godot
// would give a mesh without ARRAY_COLOR white = fully worn). Without masks a part would be
// r = 0, g = 1, b = 0.5 (ModelParts.PLAIN_MASK).
// All noise terms fade to their mean once a cell is smaller than ~1 px (see n3l), so the fine
// wear and grain do not shimmer at battle distance.

uniform vec4 color_a : source_color = vec4(0.30, 0.34, 0.20, 1.0);
uniform vec4 color_b : source_color = vec4(0.23, 0.20, 0.15, 1.0);
uniform vec4 color_c : source_color = vec4(0.13, 0.15, 0.11, 1.0);
uniform float pattern_scale = 9.0;
uniform float base_roughness = 0.8;
uniform float metallic = 0.12;
uniform int pattern_mode = 0;
// Blotch contrast: 1 = the faction colours as they are, lower pulls them towards their mean
// (printed uniform fabric, TASK-085).
uniform float pattern_contrast = 1.0;
uniform float digital_cells = 6.0;
// Paint wear on edges (COLOR.r): chipped to the bare, slightly metallic steel colour.
uniform vec4 wear_color : source_color = vec4(0.38, 0.36, 0.32, 1.0);
uniform float wear_amount = 0.7;
// Per-part brightness variation (COLOR.b).
uniform float tint_amount = 0.1;
// Dust on up-facing surfaces (object-space normal.y).
uniform vec4 dust_color : source_color = vec4(0.56, 0.51, 0.42, 1.0);
uniform float dust_amount = 0.5;
// Mud on the lower part of the model (object-space height; replaces the old dirt_*).
uniform vec4 mud_color : source_color = vec4(0.357, 0.290, 0.208, 1.0);
uniform float mud_height = 0.12;
uniform float mud_amount = 0.8;
// Darkening of the paint just above the ground.
uniform float ground_ao_height = 0.03;
// Rain streaks on vertical faces, sun-faded (desaturated) paint.
uniform float streak_amount = 0.12;
uniform float fade = 0.15;
// Fabric (soldiers' uniforms, TASK-085): 0 = paint; 1 = cloth – creases across the limbs and a
// fine rip-stop weave bumped into the normal (both fade out below ~1 px like the other noises)
// and a soft sheen at grazing angles. `fabric_relief` = crease depth in model units.
uniform float fabric = 0.0;
uniform float fabric_relief = 0.00025;
// Baked occlusion (COLOR.g) as the AO output too (soldiers, TASK-085): 0 = albedo darkening only
// (vehicles), 1 = the ambient light and part of the direct light follow it as well. The two stack
// on purpose: the albedo term keeps creases dark in full sun, the AO term shades the ambient light
// the sky would not reach (armpits, under a brim); the soldier renders were tuned with both.
uniform float mask_ao = 0.0;
// Offset of this part inside the model (set per MeshInstance3D by ModelParts) so the pattern
// and the mud line are continuous across the separate primitives of one model.
instance uniform vec3 part_origin = vec3(0.0);
// Offsets the weathering noises so every unit looks different (set by UnitModels from the unit
// id; the camo pattern itself is the same for all units of a faction).
instance uniform float wear_seed = 0.0;
// Burnt-out wreck (TASK-065): 0 = intact paint, 1 = charred black hull with rusty patches. Set per
// MeshInstance3D while a destroyed vehicle plays its death (the material itself is shared).
instance uniform float burnt = 0.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(h3(i), h3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(h3(i + vec3(0.0, 1.0, 0.0)), h3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(h3(i + vec3(0.0, 0.0, 1.0)), h3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(h3(i + vec3(0.0, 1.0, 1.0)), h3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// Value noise that fades to 0.5 as its cell size (1 / frequency) approaches the pixel size;
// `px` = change of the scaled coordinate per screen pixel.
// Cells below a pixel skip the noise entirely (the cost drops with distance).
float n3l(vec3 q, float px) {
	float w = 1.0 - smoothstep(0.3, 0.9, px);
	if (w <= 0.0) {
		return 0.5;
	}
	return mix(0.5, n3(q), w);
}

float fb(vec3 p) {
	return n3(p) * 0.55 + n3(p * 2.07) * 0.3 + n3(p * 4.3) * 0.15;
}

float fbl(vec3 q, float px) {
	return n3l(q, px) * 0.55 + n3l(q * 2.07, px * 2.07) * 0.3 + n3l(q * 4.3, px * 4.3) * 0.15;
}

void vertex() {
	obj_pos = VERTEX + part_origin;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 p = obj_pos;
	vec3 fw = fwidth(p);
	float px = max(max(fw.x, fw.y), fw.z);
	vec3 col = color_a.rgb;
	float gr;
	if (pattern_mode == 1) {
		vec3 q = floor(p * pattern_scale * digital_cells) / digital_cells;
		float ca = fb(q);
		float cb = fb(q * 1.27 + vec3(17.0, 3.0, 9.0));
		col = mix(col, color_b.rgb, smoothstep(0.52, 0.55, ca));
		col = mix(col, color_c.rgb, smoothstep(0.6, 0.63, cb));
	} else {
		vec3 q = p * pattern_scale;
		float pq = px * pattern_scale;
		vec3 warp = vec3(fbl(q * 0.8 + 3.1, pq * 0.8), fbl(q * 0.8 + 7.7, pq * 0.8), fbl(q * 0.8 + 1.3, pq * 0.8)) - 0.5;
		q += warp * 1.1;
		float na = fbl(q, pq);
		float nb = fbl(q * 1.15 + vec3(11.0, 5.0, 23.0), pq * 1.15);
		float aa = fwidth(na) * 0.75 + 0.002;
		float ab = fwidth(nb) * 0.75 + 0.002;
		col = mix(col, color_b.rgb, smoothstep(0.52 - aa, 0.52 + aa, na));
		col = mix(col, color_c.rgb, smoothstep(0.585 - ab, 0.585 + ab, nb));
	}
	col = mix((color_a.rgb + color_b.rgb + color_c.rgb) / 3.0, col, pattern_contrast);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))), fade);
	col *= 1.0 + (COLOR.b - 0.5) * tint_amount;

	// Weathering noises are offset per unit.
	vec3 s = p + vec3(7.13, 3.71, 11.3) * wear_seed;
	float grain = n3l(s * 260.0, px * 260.0);
	col *= (0.92 + 0.16 * fbl(s * 22.0, px * 22.0)) * (0.98 + 0.04 * grain);

	float vertical = 1.0 - abs(obj_nrm.y);
	float streak = n3l(vec3(s.x * 180.0, s.y * 12.0, s.z * 180.0), px * 180.0);
	col *= 1.0 - vertical * smoothstep(0.55, 0.85, streak) * streak_amount;

	// Edge wear: chips on the chamfer bands. Far away the chips average out to a lighter edge.
	float chip = n3l(s * 320.0, px * 320.0) * 0.6 + n3l(s * 900.0, px * 900.0) * 0.4;
	float chipped = smoothstep(0.73 - wear_amount * 0.12, 0.77 - wear_amount * 0.1, chip);
	float near = 1.0 - smoothstep(0.3, 0.9, px * 320.0);
	float worn = clamp(wear_amount * 4.0, 0.0, 1.0);
	col *= 1.0 + COLOR.r * worn * 0.12 * (0.5 + n3l(s * 120.0, px * 120.0));
	float wear = COLOR.r * mix(0.3, chipped, near) * worn;
	col = mix(col, wear_color.rgb, wear * 0.75);

	col *= mix(0.42, 1.0, COLOR.g);
	col *= mix(0.72, 1.0, smoothstep(0.0, ground_ao_height, p.y));

	float up = smoothstep(0.45, 0.95, obj_nrm.y);
	float dust = up * smoothstep(0.3, 0.8, fbl(s * 25.0, px * 25.0) * 0.7 + fbl(s * 90.0, px * 90.0) * 0.3) * dust_amount;
	col = mix(col, dust_color.rgb, dust * 0.45);
	float mud = clamp(smoothstep(mud_height, 0.0, p.y) * (0.35 + 0.65 * fbl(s * 80.0, px * 80.0)) * mud_amount, 0.0, 1.0);
	col = mix(col, mud_color.rgb, mud * 0.85);

	float rough = clamp(base_roughness + (grain - 0.5) * 0.2 - wear * 0.25 + dust * 0.15 + mud * 0.1, 0.05, 1.0);
	float metal = mix(metallic, 0.55, wear * 0.5);
	if (burnt > 0.0) {
		// Charred black with noisy rusty-brown patches; the camo pattern stays faintly visible (10 %).
		float patches = smoothstep(0.6, 0.8, fbl(s * 14.0, px * 14.0));
		vec3 char_col = mix(vec3(0.0123, 0.0109, 0.0097), vec3(0.0685, 0.0273, 0.0130), patches);
		col = mix(col, char_col + col * 0.1, burnt * 0.9);
		rough = mix(rough, 0.95, burnt);
		metal = mix(metal, 0.05, burnt);
	}

	if (fabric > 0.0) {
		// Bump from a height field in model units (Mikkelsen's surface-gradient bump mapping, no
		// tangents needed): creases ~3 cm apart across the limbs, the weave at ~5 mm.
		vec3 m = p * 10.0;
		float pm = px * 10.0;
		float crease = fbl(vec3(m.x * 14.0, m.y * 34.0, m.z * 14.0), pm * 34.0);
		float weave = n3l(m * 190.0, pm * 190.0);
		float h = crease * 0.75 + weave * 0.25;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float to_view = length(dpdx) / max(length(dFdx(obj_pos)), 1e-9);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2) * fabric_relief * to_view;
		NORMAL = normalize(abs(det) * NORMAL - fabric * grad);
		RIM = 0.3 * fabric;
		RIM_TINT = 0.6;
		rough = min(rough + 0.03, 1.0);
	}
	if (mask_ao > 0.0) {
		AO = mix(1.0, COLOR.g, mask_ao);
		AO_LIGHT_AFFECT = 0.5 * mask_ao;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
