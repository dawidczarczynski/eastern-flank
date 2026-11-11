shader_type canvas_item;
// Colour grade of the main menu backdrops (src/presentation/ui/menu_backdrop.gd): the staff map is
// dimmed and desaturated, the tactical shard is pushed (contrast, saturation, warm highlights).

uniform float brightness = 1.0;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform vec3 tint = vec3(1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = mix(vec3(luma), c.rgb, saturation);
	rgb = (rgb - 0.5) * contrast + 0.5;
	COLOR = vec4(max(rgb * tint * brightness, vec3(0.0)), c.a);
}
