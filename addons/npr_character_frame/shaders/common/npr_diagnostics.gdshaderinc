// Debug output is evaluated in the same fragment as production shading.
// 0 keeps the original arithmetic and coverage; no replacement debug material.
uniform int u_npr_diagnostic_mode = 0;

vec3 npr_diagnostic_color(int role, int slot, vec3 normal_ws, vec2 uv,
		vec3 base, float shadow, float eye_mask, int face_domain) {
	if (u_npr_diagnostic_mode == 1) {
		if (role != 1) { return vec3(0.18); }
		if (face_domain == 1) { return vec3(0.04, 0.85, 0.16); }
		if (face_domain == 2) { return vec3(0.02, 0.75, 0.85); }
		if (face_domain == 3) { return vec3(0.95, 0.035, 0.025); }
		return vec3(0.035, 0.20, 0.85);
	}
	if (u_npr_diagnostic_mode == 2) { return normalize(normal_ws) * 0.5 + 0.5; }
	if (u_npr_diagnostic_mode == 3) { return vec3(fract(uv), 0.0); }
	if (u_npr_diagnostic_mode == 4) { return role == 1 ? vec3(shadow) : vec3(0.18); }
	if (u_npr_diagnostic_mode == 5) {
		float id = float(role * 8 + slot);
		return 0.5 + 0.45 * cos(vec3(0.0, 2.0944, 4.1888) + id * 2.39996);
	}
	if (u_npr_diagnostic_mode == 6) { return base; }
	if (u_npr_diagnostic_mode == 7) { return vec3(shadow); }
	if (u_npr_diagnostic_mode == 8) { return vec3(0.95); }
	if (u_npr_diagnostic_mode == 9) { return vec3(eye_mask); }
	return base;
}
