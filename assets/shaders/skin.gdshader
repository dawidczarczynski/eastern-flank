shader_type spatial;
// Soldiers' skin (TASK-085). Reads the MeshKit vertex mask (ADR 0012): COLOR.g = openness (baked
// ambient occlusion – dark under the helmet rim, in the eye sockets, at the sides of the face),
// a little redder where occluded (thin skin over blood) and used as AO for the ambient and most of
// the direct light; COLOR.b = per-part tint seed.
// No subsurface scattering: SSS_STRENGTH switches on a full-screen scattering pass (0.9 ms a frame
// on the target GPU) for faces a few pixels tall; unit materials must not need one
// (UnitRenderRules, ADR 0023).

uniform vec4 albedo : source_color = vec4(0.55, 0.43, 0.35, 1.0);
uniform float roughness = 0.6;
// Set per MeshInstance3D by ModelParts (see camo.gdshader): the part's place in the model and the
// unit's seed – each soldier's and each unit's skin tone differs a little.
instance uniform vec3 part_origin = vec3(0.0);
instance uniform float wear_seed = 0.0;

void fragment() {
	float person = fract(sin(dot(part_origin, vec3(12.9898, 78.233, 37.719)) + wear_seed * 7.13) * 43758.5453);
	vec3 col = albedo.rgb * (0.9 + 0.2 * person) * (1.0 + (COLOR.b - 0.5) * 0.08);
	col *= mix(vec3(0.45, 0.37, 0.35), vec3(1.0), COLOR.g * COLOR.g);
	ALBEDO = col;
	// The occlusion also dims the direct light (the sun's shadow of a helmet brim is finer than
	// the shadow map resolves).
	AO = COLOR.g;
	AO_LIGHT_AFFECT = 0.75;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}
