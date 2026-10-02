#ifndef NPR_MATH_INCLUDED
#define NPR_MATH_INCLUDED

// Degenerate ranges stay finite; preserve intentionally reversed ranges.
float npr_nonzero(float value) {
	return value < 0.0 ? min(value, -0.0001) : max(value, 0.0001);
}

float npr_threshold(float value, float center, float radius) {
	float width = max(radius, 0.0);
	float low = max(center - width, 0.0001);
	float high = min(center + width, 0.9999);
	if (high <= low) {
		return step(center, value);
	}
	return smoothstep(0.0, 1.0, (value - low) / (high - low));
}

// Packed PNG LUT: numeric rows stay raw; only color rows use this conversion.
vec3 npr_srgb_to_linear(vec3 value) {
	return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)),
		greaterThan(value, vec3(0.04045)));
}

// Same 2x2 lookup as vec4(-3, 1, 3, -1) / 256 indexed by (x&1)*2+(y&1).
// Static selects avoid re-spirv's unsupported OpVectorExtractDynamic fallback.
float npr_dither_value(vec2 pixel) {
	bool odd_x = (uint(pixel.x) & 1u) != 0u;
	bool odd_y = (uint(pixel.y) & 1u) != 0u;
	return odd_x ? (odd_y ? -0.00390625 : 0.01171875)
		: (odd_y ? 0.00390625 : -0.01171875);
}

// Captured MRT quantization is NOT permission to quantize Godot's depth buffer.
// Preserve the existing low two bits; higher bits belonged to custom attachments.
vec3 npr_dither_color(vec3 color, int mask, vec2 pixel) {
	int mode = mask & 3;
	if (mode == 0) {
		return color;
	}
	float dither = npr_dither_value(pixel);
	vec3 offset = vec3(dither);
	vec3 levels = vec3(31.0);
	if (mode == 1) {
		offset *= 2.0;
		levels = vec3(15.0);
	} else if (mode == 3) {
		offset.y *= 0.5;
		levels.y = 63.0;
	}
	return round((color + offset) * levels) / levels;
}

float npr_material_slot(float encoded) {
	return fract(floor(encoded * 8.0) / 8.0) * 8.0;
}

vec3 npr_hue_rotate(vec3 color, float turns) {
	float angle = turns * 2.0 * PI;
	float cosine = cos(angle);
	float sine = sin(angle);
	vec3 axis = normalize(vec3(1.0));
	return color * cosine + cross(axis, color) * sine
		+ axis * dot(axis, color) * (1.0 - cosine);
}

vec2 npr_matcap_uv(vec3 normal_vs) {
	return normalize(normal_vs).xy * 0.5 + 0.5;
}

vec3 npr_oct_decode(vec2 encoded) {
	vec3 normal = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
	if (normal.z < 0.0) {
		normal.xy = (1.0 - abs(normal.yx)) * sign(normal.xy);
	}
	return normalize(normal);
}
#endif
