// Face-local marks are composited on original skin: no camera-facing geometry or depth bias.
uniform mat4 u_npr_comic_world_to_anchor;
uniform vec3 u_npr_comic_anchor_origin = vec3(0.0);
uniform float u_npr_comic_tear_opacity = 0.0;
uniform float u_npr_comic_hatching_opacity = 0.0;
uniform vec4 u_npr_comic_tear_left = vec4(0.0);
uniform vec4 u_npr_comic_tear_right = vec4(0.0);
uniform vec4 u_npr_comic_hatching_left = vec4(0.0);
uniform vec4 u_npr_comic_hatching_right = vec4(0.0);
uniform vec4 u_npr_comic_tear_tint : source_color = vec4(1.0);
uniform vec4 u_npr_comic_hatching_tint : source_color = vec4(1.0);

vec4 npr_face_mark(vec2 local_xy, vec4 region, bool tear) {
	vec2 p = (local_xy - region.xy) / max(region.zw * 0.5, vec2(0.0001));
	float d = 2.0;
	vec3 color = vec3(0.20, 0.035, 0.06);
	if (tear) {
		d = p.y > 0.0 ? max(abs(p.x) - (0.8 - p.y) * 0.5, p.y - 0.8)
			: length(p) - 0.4;
		color = mix(vec3(0.06, 0.28, 0.5), vec3(0.36, 0.78, 0.96),
			1.0 - smoothstep(-0.09, -0.03, d));
		color = mix(color, vec3(0.9, 0.98, 1.0),
			1.0 - smoothstep(0.065, 0.095, length(p - vec2(-0.13, -0.10))));
	} else {
		for (int i = 0; i < 6; i++) {
			float x = -0.75 + float(i) * 0.26;
			vec2 a = vec2(x, -0.52);
			vec2 ab = vec2(0.30, 1.04);
			d = min(d, length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0)));
		}
		d = max(d - 0.065, length(p * vec2(0.9, 0.7)) - 0.85);
	}
	float aa = max(fwidth(d), 0.003);
	return vec4(color, 1.0 - smoothstep(-aa, aa, d));
}

vec3 npr_face_comics(vec3 color, vec4 local, vec3 world_position) {
	if (u_npr_comic_tear_opacity <= 0.0 && u_npr_comic_hatching_opacity <= 0.0) { return color; }
	// Original skin, sliding lids and optional fitted lids share head-local space.
	// Their CUSTOM1 encodings differ; current world position gives one continuous domain.
	local = vec4((u_npr_comic_world_to_anchor * vec4(world_position, 1.0)).xyz
		+ u_npr_comic_anchor_origin, 2.0);
	if (local.z <= 0.005) { return color; }
	for (int i = 0; i < 2; i++) {
		if (u_npr_comic_hatching_opacity > 0.0) {
			vec4 ink = npr_face_mark(local.xy,
				i == 0 ? u_npr_comic_hatching_left : u_npr_comic_hatching_right, false);
			color = mix(color, ink.rgb * u_npr_comic_hatching_tint.rgb,
				ink.a * u_npr_comic_hatching_opacity * u_npr_comic_hatching_tint.a);
		}
		if (u_npr_comic_tear_opacity > 0.0) {
			vec4 ink = npr_face_mark(local.xy,
				i == 0 ? u_npr_comic_tear_left : u_npr_comic_tear_right, true);
			color = mix(color, ink.rgb * u_npr_comic_tear_tint.rgb,
				ink.a * u_npr_comic_tear_opacity * u_npr_comic_tear_tint.a);
		}
	}
	return color;
}
