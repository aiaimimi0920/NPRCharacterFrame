
float npr_mouth_ink(vec2 position) {
	vec2 p = position / u_npr_mouth_symbol_size;
	float d = 1.0;
	if (u_npr_mouth_symbol == 1) {
		for (int i = 0; i < 24; i++) {
			float x = -0.8 + float(i) * 1.6 / 24.0;
			float x2 = x + 1.6 / 24.0;
			d = min(d, npr_symbol_segment(p, vec2(x, 0.25 * sin(x * 8.0)), vec2(x2, 0.25 * sin(x2 * 8.0))));
		}
	} else if (u_npr_mouth_symbol == 2) {
		d = abs(length(p) - 0.5);
	} else if (u_npr_mouth_symbol == 3) {
		d = npr_symbol_segment(p, vec2(-0.75, 0.0), vec2(0.75, 0.0));
	}
	float aa = max(fwidth(d), 0.006);
	return 1.0 - smoothstep(u_npr_mouth_symbol_stroke - aa, u_npr_mouth_symbol_stroke + aa, d);
}

