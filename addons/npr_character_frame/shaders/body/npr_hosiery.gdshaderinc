#ifndef NPR_HOSIERY_INCLUDED
#define NPR_HOSIERY_INCLUDED

// Art-directed thin fabric, composited over opaque skin. See the research note.
group_uniforms u_wardrobe_hosiery;
uniform vec4 u_npr_hosiery_fabric_color : source_color = vec4(0.12, 0.105, 0.145, 1.0);
uniform vec4 u_npr_hosiery_sheen_color : source_color = vec4(0.74, 0.68, 0.68, 1.0);
uniform float u_npr_hosiery_sheen_strength : hint_range(0.0, 0.5) = 0.20;
uniform float u_npr_hosiery_angle_strength : hint_range(0.0, 1.0) = 1.0;
uniform float u_npr_hosiery_weave_strength : hint_range(0.0, 0.1) = 0.035;
uniform float u_npr_hosiery_weave_scale : hint_range(128.0, 2048.0) = 1024.0;
uniform float u_npr_hosiery_roughness : hint_range(0.18, 0.6) = 0.27;
// Bounded visual approximation for hosiery pressure at the garment edge.
uniform float u_npr_hosiery_compression_strength : hint_range(0.0, 1.0) = 0.0;
// Separate linear masks keep tulle coverage and seam/stitch authoring out of
// the RGB dye channels in garment_mask.png.
uniform sampler2D u_npr_tulle_mask : filter_linear, repeat_disable;
uniform sampler2D u_npr_stitch_mask : filter_linear, repeat_disable;
uniform float u_npr_tulle_strength : hint_range(0.0, 1.0) = 0.0;
uniform float u_npr_stitch_strength : hint_range(0.0, 1.0) = 0.0;
// Opt-in authored rest coordinates: independent of UV island splits/overlap.
uniform bool u_npr_hosiery_metric_seams = false;
uniform float u_npr_hosiery_height : hint_range(0.5, 1.55) = 1.34;
uniform float u_npr_hosiery_cuff_band_width = 0.016;
uniform float u_npr_hosiery_cuff_stitch_offset = 0.012;
uniform float u_npr_hosiery_cuff_stitch_width = 0.0012;
uniform float u_npr_hosiery_textile_period_m = 0.0025;
uniform float u_npr_hosiery_textile_repeats = 8.0;
uniform float u_npr_hosiery_shell_offset_m = 0.00025;
uniform vec4 u_npr_stitch_color : source_color = vec4(0.20, 0.16, 0.24, 1.0);
group_uniforms;

// Density and two tangent-space slopes of a stylized loop-knit signal.
// Wardrobe rest coordinates are continuous across the source UV islands.
// At the default scale, wales repeat every 2.5 mm; keep the knit's 1.35 course ratio.
vec2 npr_hosiery_weave_coordinates(vec2 uv, vec3 rest) {
	return u_npr_hosiery_metric_seams
		? rest.xy * ((1.0 / u_npr_hosiery_textile_period_m) / 1024.0) : uv;
}

vec3 npr_hosiery_weave(vec2 uv) {
	vec2 thread_uv = uv * max(u_npr_hosiery_weave_scale, 1.0) * vec2(1.0, 1.35);
	vec2 footprint = fwidth(thread_uv);
	// The phase modulation has harmonics: fade well before the Nyquist limit.
	float resolved = 1.0 - smoothstep(0.12, 0.38, max(footprint.x, footprint.y));
	vec2 phase = thread_uv * 6.2831853;
	float bend = 0.85 * sin(phase.y);
	float left = phase.x + bend;
	float right = phase.x - bend;
	float loops = 0.5 * (cos(left) + cos(right));
	float courses = cos(phase.y);
	float density = loops * (0.25 + 0.75 * courses);
	float dx = -0.5 * (sin(left) + sin(right)) * (0.25 + 0.75 * courses);
	float dy = 0.425 * courses * (sin(right) - sin(left)) * (0.25 + 0.75 * courses)
		- 0.75 * loops * sin(phase.y);
	return vec3(density, dx, dy) * resolved * u_npr_hosiery_weave_strength;
}

float npr_hosiery_coverage(float opacity, float facing, float domain, float weave) {
	float no_v = clamp(abs(facing), 0.0, 1.0);
	// A bounded optical path preserves both slider endpoints at grazing angles.
	float path = 1.65 * mix(1.0, sqrt(1.16 / (no_v * no_v + 0.16)),
		clamp(u_npr_hosiery_angle_strength, 0.0, 1.0));
	// Threads modulate the skin's transmission, not just the nearly black dye.
	path *= max(1.0 + 1.5 * weave, 0.1);
	float transmission = pow(1.0 - clamp(opacity, 0.0, 1.0), path);
	return clamp(domain, 0.0, 1.0) * (1.0 - transmission);
}

float npr_hosiery_compression(float coverage) {
	float edge = clamp(fwidth(coverage) * 36.0, 0.0, 1.0);
	float interior = smoothstep(0.08, 0.42, coverage);
	return edge * interior * clamp(u_npr_hosiery_compression_strength, 0.0, 1.0);
}

vec3 npr_hosiery_authored_layers(vec2 uv) {
	float tulle = texture(u_npr_tulle_mask, uv).r * clamp(u_npr_tulle_strength, 0.0, 1.0);
	float stitch = texture(u_npr_stitch_mask, uv).r * clamp(u_npr_stitch_strength, 0.0, 1.0);
	return vec3(tulle, stitch, max(tulle, stitch));
}

float npr_hosiery_metric_line(float distance_to_line, float width) {
	float pixel_width = max(fwidth(distance_to_line), 0.00001);
	return clamp((0.5 * width + 0.5 * pixel_width - abs(distance_to_line))
		/ pixel_width, 0.0, 1.0);
}

float npr_hosiery_metric_stitch(vec3 rest) {
	// A folded hem belongs INSIDE the coverage boundary on the skinned surface.
	// No detached rings or arbitrary world-space longitudinal stripe.
	float below = u_npr_hosiery_height - rest.y;
	float aa = max(fwidth(rest.y), 0.0001);
	float band = 1.0 - smoothstep(u_npr_hosiery_cuff_band_width - aa,
		u_npr_hosiery_cuff_band_width + aa, below);
	float stitch = npr_hosiery_metric_line(below - u_npr_hosiery_cuff_stitch_offset,
		u_npr_hosiery_cuff_stitch_width);
	return max(0.35 * band, 0.65 * stitch);
}

float npr_hosiery_height_coverage(vec3 rest) {
	float aa = max(fwidth(rest.y), 0.0001);
	// One-sided AA guarantees zero hosiery above the selected height.
	return 1.0 - smoothstep(u_npr_hosiery_height - aa, u_npr_hosiery_height, rest.y);
}

vec3 npr_hosiery_sheen(vec3 normal, vec3 half_dir, vec3 axis_hint, vec3 across_hint,
		float no_v, float no_l, vec3 weave) {
	vec3 axis = axis_hint - normal * dot(axis_hint, normal);
	if (dot(axis, axis) < 0.0001) {
		vec3 fallback = abs(normal.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		axis = fallback - normal * dot(fallback, normal);
	}
	axis = normalize(axis);
	vec3 across = normalize(cross(normal, axis));
	float handedness = dot(across, across_hint) < 0.0 ? -1.0 : 1.0;
	across *= handedness;
	vec3 fiber_normal = normalize(normal - 0.22 * (across * weave.y + axis * weave.z));
	axis = normalize(axis - fiber_normal * dot(axis, fiber_normal));
	across = normalize(cross(fiber_normal, axis)) * handedness;
	float no_h = max(dot(fiber_normal, half_dir), 0.0);
	// Broaden the fiber highlight when the surface normal varies within a pixel.
	vec3 normal_dx = dFdx(normal);
	vec3 normal_dy = dFdy(normal);
	float variance = min(dot(normal_dx, normal_dx) + dot(normal_dy, normal_dy), 0.18);
	float roughness = clamp(u_npr_hosiery_roughness, 0.18, 0.6);
	vec2 width = sqrt(vec2(0.64, roughness * roughness) + vec2(variance));
	vec2 slope = vec2(dot(axis, half_dir), dot(across, half_dir)) / width;
	float ribbon = exp2(-dot(slope, slope) / max(no_h * no_h, 0.15));
	float fiber = exp2(-dot(slope, slope) * 2.8 / max(no_h * no_h, 0.15));
	float facing_lobe = pow(clamp(abs(no_v), 0.0, 1.0), 4.0);
	float shape = (0.68 * ribbon + 0.16 * fiber + 0.16 * facing_lobe)
		* smoothstep(-0.1, 0.6, no_l);
	return u_npr_hosiery_sheen_color.rgb * u_npr_hosiery_sheen_strength * shape * (1.0 + weave.x);
}

#endif
