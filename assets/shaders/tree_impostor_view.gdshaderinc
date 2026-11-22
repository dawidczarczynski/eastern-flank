// The picture side of the tree impostors (TASK-135, TreeImpostors), shared by
// tree_impostor.gdshader (per-instance data) and forest_impostor.gdshader (GPU-placed forest,
// TASK-189): a quad per tree, turned to the camera about the vertical, showing a baked picture of
// the real tree model. The atlas has one row per species x variant and one column per view around
// the tree; the two views nearest to the camera's direction (relative to the tree's own yaw) are
// blended. Opaque with discard (no alpha pass).

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

// Whether a tree at `camera_distance` is drawn as an impostor: between its full band (capped by
// the full-tree budget) and its impostor band, at its own point of the bands (`phase`).
bool impostor_in_band(float camera_distance, float full_centre, float out_centre, float phase) {
	float lod_from = min(
		mix(full_centre * (1.0 - band_share), full_centre * (1.0 + band_share), phase),
		full_reach
	);
	float lod_to = mix(out_centre * (1.0 - band_share), out_centre * (1.0 + band_share), phase);
	return camera_distance >= lod_from && camera_distance < lod_to;
}

// The world position of a quad corner (`uv`) of a tree at `origin`; `view` is the view_position
// for the fragment: the view whose rotation of the tree shows the camera's side (the tree's yaw
// minus the camera's azimuth, both from +z towards +x, in turns of the views).
vec3 impostor_corner(
	vec3 origin, vec3 cam, float width, float height, float yaw, vec2 uv, out float view
) {
	vec3 to_camera = cam - origin;
	to_camera.y = 0.0;
	float flat_length = length(to_camera);
	to_camera = flat_length > 1.0e-6 ? to_camera / flat_length : vec3(0.0, 0.0, 1.0);
	vec3 right = vec3(to_camera.z, 0.0, -to_camera.x);
	float up = mix(-below_base, vertical_span - below_base, 1.0 - uv.y);
	float azimuth = atan(to_camera.x, to_camera.z);
	view = mod((yaw - azimuth) / 6.2831853 * views, views);
	return origin + right * ((uv.x - 0.5) * width) + vec3(0.0, up * height, 0.0);
}

// The tinted picture colour at `uv` (rgb) and its coverage (a: discard below 0.5).
vec4 impostor_color(vec2 uv) {
	float i0 = floor(view_position);
	float f = view_position - i0;
	vec4 a = texture(atlas, vec2((mod(i0, views) + uv.x) / views, (row + uv.y) / rows));
	vec4 b = texture(atlas, vec2((mod(i0 + 1.0, views) + uv.x) / views, (row + uv.y) / rows));
	float alpha = a.a * (1.0 - f) + b.a * f;
	vec3 color = (a.rgb * (1.0 - f) + b.rgb * f) / max(alpha, 1.0e-3);
	return vec4(color * tint * exposure, alpha);
}
