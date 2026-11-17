// Optional authored nose line in Face mesh-local coordinates, after morphing.
// Disabled leaves the historical view/ILM nose calculation unchanged.
group_uniforms u_npr_nose_local;
uniform bool u_npr_nose_local_enabled = false;
// center Y, parabola curvature, X scale, Gaussian Y width (mesh units).
uniform vec4 u_npr_nose_local_curve = vec4(0.0, 0.0, 1.0, 0.001);
// absolute X inner/outer fade; local Z lower/upper fade (mesh units).
uniform vec4 u_npr_nose_local_domain = vec4(0.0, 0.001, 0.0, 0.001);
uniform vec4 u_npr_nose_local_color : source_color = vec4(0.55, 0.34, 0.30, 0.18);
group_uniforms;
varying vec3 npr_nose_local_position;

vec3 npr_nose_local_albedo(vec3 base, vec3 position) {
	float nx = position.x;
	float scale = max(abs(u_npr_nose_local_curve.z), 0.000001);
	float width = max(abs(u_npr_nose_local_curve.w), 0.000001);
	float normalized_x = nx / scale;
	float center_y = u_npr_nose_local_curve.x + u_npr_nose_local_curve.y * normalized_x * normalized_x;
	float normalized_y = (position.y - center_y) / width;
	float mask = exp(-(normalized_y * normalized_y));
	float x_outer = max(u_npr_nose_local_domain.y, u_npr_nose_local_domain.x + 0.000001);
	float z_upper = max(u_npr_nose_local_domain.w, u_npr_nose_local_domain.z + 0.000001);
	mask *= 1.0 - smoothstep(u_npr_nose_local_domain.x, x_outer, abs(nx));
	mask *= smoothstep(u_npr_nose_local_domain.z, z_upper, position.z);
	return mix(base, u_npr_nose_local_color.rgb, mask * clamp(u_npr_nose_local_color.a, 0.0, 1.0));
}
