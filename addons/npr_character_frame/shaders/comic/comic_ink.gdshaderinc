uniform int kind = 0;
uniform float opacity = 1.0;
uniform vec4 ink_tint : source_color = vec4(1.0);

float comic_segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, -2.0);
	float d = 2.0;
	float width = 0.065;
	vec3 color = vec3(0.20, 0.035, 0.06);
	if (kind <= 1) {
		// Pointed upper half and round lower half share the same boundary width.
		d = p.y > 0.0 ? max(abs(p.x) - (0.8 - p.y) * 0.5, p.y - 0.8)
			: length(p) - 0.4;
		color = mix(vec3(0.06, 0.28, 0.5), vec3(0.36, 0.78, 0.96), 1.0 - smoothstep(-0.09, -0.03, d));
		color = mix(color, vec3(0.9, 0.98, 1.0), 1.0 - smoothstep(0.065, 0.095, length(p - vec2(-0.13, -0.10))));
		width = 0.0;
	} else if (kind == 2) {
		vec2 q = abs(p);
		d = min(comic_segment(q, vec2(0.12, 0.72), vec2(0.18, 0.28)),
			comic_segment(q, vec2(0.18, 0.28), vec2(0.62, 0.18)));
		color = vec3(0.85, 0.035, 0.06);
	} else if (kind == 3) {
		d = min(comic_segment(p, vec2(0.0, -0.2), vec2(0.0, 0.83)),
			min(comic_segment(p, vec2(-0.45, -0.2), vec2(-0.78, 0.65)),
			comic_segment(p, vec2(0.45, -0.2), vec2(0.78, 0.65))));
		d = min(d, length(p - vec2(0.0, -0.60)) - 0.04);
		color = vec3(0.95, 0.61, 0.035);
	} else {
		for (int i = 0; i < 6; i++) {
			float x = -0.75 + float(i) * 0.26;
			d = min(d, comic_segment(p, vec2(x, -0.52), vec2(x + 0.30, 0.52)));
		}
		d = max(d - width, length(p * vec2(0.9, 0.7)) - 0.85);
		width = 0.0;
	}
	float aa = max(fwidth(d), 0.003);
	float coverage = 1.0 - smoothstep(width - aa, width + aa, d);
	if (coverage < 0.005) { discard; }
	ALBEDO = color * ink_tint.rgb;
	ALPHA = coverage * opacity * ink_tint.a;
}
