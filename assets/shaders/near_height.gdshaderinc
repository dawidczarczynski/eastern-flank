// The drawn near terrain around the camera target as the shaders read it (NearHeightCache, TASK-217a;
// shared by the shrubs, the grass and the full forest trees, TASK-221).

// The drawn near terrain around the camera target (NearHeightCache): heights of the near mesh's
// vertices, near_step apart from near_origin; MISSING (< -1e5) where no near chunk is built.
uniform bool use_near = false;
uniform sampler2D near_heights : filter_nearest, repeat_disable;
uniform vec2 near_origin;
uniform float near_step = 1.0;

// The drawn ground under p (NearHeightCache.height_at): the near mesh's triangles where a near
// chunk is built, else `lattice` (the lattice height, what is drawn there). Drawing only: the
// placement decisions read the lattice.
float near_drawn_ground(vec2 p, float lattice) {
	if (!use_near) {
		return lattice;
	}
	vec2 f = (p - near_origin) / near_step;
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
