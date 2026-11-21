shader_type spatial;
render_mode world_vertex_coords, unshaded, cull_disabled;
// Tree impostors (TASK-135, TreeImpostors): a quad per tree, turned to the camera about the
// vertical, showing a baked picture of the real tree model. The atlas has one row per species x
// variant and one column per view around the tree; the two views nearest to the camera's direction
// (relative to the tree's own random yaw) are blended. Opaque with discard (no alpha pass).
// Instance data (TreeImpostors): transform = base + scale (x quad width, y tree height), COLOR =
// tint relative to the baked colour, CUSTOM = (full range centre, impostor range centre, atlas
// row, phase). The impostor draws a tree whose base is between its full band (where the full tree
// hands over, capped by the full-tree budget's `full_reach`) and its impostor band (where the
// canopy shell takes over), each tree at its own point of the bands like foliage_body.gdshaderinc.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float rows = 1.0;
uniform float views = 8.0;
uniform float band_share = 0.08;
// The full-tree budget's reach (ForestField): from here on no full tree is drawn.
uniform float full_reach = 1.0e9;
// The picture spans `vertical_span` tree heights from `below_base` of a height below the base.
uniform float below_base = 0.12;
uniform float vertical_span = 1.25;
// Brightness of the baked light against the scene's.
uniform float exposure = 1.0;

varying vec3 tint;
varying float row;
varying float view_position;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float camera_distance = distance(origin, cam);
	float phase = INSTANCE_CUSTOM.a;
	float full_centre = INSTANCE_CUSTOM.r;
	float out_centre = INSTANCE_CUSTOM.g;
	float lod_from = min(
		mix(full_centre * (1.0 - band_share), full_centre * (1.0 + band_share), phase),
		full_reach
	);
	float lod_to = mix(out_centre * (1.0 - band_share), out_centre * (1.0 + band_share), phase);
	tint = COLOR.rgb;
	row = INSTANCE_CUSTOM.b;
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 to_camera = cam - origin;
	to_camera.y = 0.0;
	float flat_length = length(to_camera);
	to_camera = flat_length > 1.0e-6 ? to_camera / flat_length : vec3(0.0, 0.0, 1.0);
	vec3 right = vec3(to_camera.z, 0.0, -to_camera.x);
	float up = mix(-below_base, vertical_span - below_base, 1.0 - UV.y);
	// The view whose rotation of the tree shows the camera's side: yaw of the tree minus the
	// camera's azimuth (both from +z towards +x), in turns of the views.
	float yaw = fract(phase * 7.31 + origin.x * 3.17 + origin.z * 1.93) * 6.2831853;
	float azimuth = atan(to_camera.x, to_camera.z);
	view_position = (yaw - azimuth) / 6.2831853 * views;
	view_position = mod(view_position, views);
	VERTEX = origin + right * ((UV.x - 0.5) * width) + vec3(0.0, up * height, 0.0);
	if (camera_distance < lod_from || camera_distance >= lod_to) {
		VERTEX = origin;
	}
}

void fragment() {
	float i0 = floor(view_position);
	float f = view_position - i0;
	vec2 uv = UV;
	vec4 a = texture(atlas, vec2((mod(i0, views) + uv.x) / views, (row + uv.y) / rows));
	vec4 b = texture(atlas, vec2((mod(i0 + 1.0, views) + uv.x) / views, (row + uv.y) / rows));
	float wa = a.a * (1.0 - f);
	float wb = b.a * f;
	float alpha = wa + wb;
	if (alpha < 0.5) {
		discard;
	}
	vec3 color = (a.rgb * (1.0 - f) + b.rgb * f) / max(alpha, 1.0e-3);
	ALBEDO = color * tint * exposure;
}
