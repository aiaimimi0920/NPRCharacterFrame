shader_type canvas_item;
render_mode unshaded, blend_add, skip_vertex_transform;

uniform sampler2D particle_state : filter_nearest, repeat_disable;
uniform sampler2D chart_map : filter_nearest, repeat_disable;
uniform vec2 atlas_size;
uniform float display_time;
uniform float deposit_delta;
uniform bool trail_pass = false;
varying vec2 footprint;
varying float chart_id;
varying float strength;

void vertex() {
	int bead_index = int(INSTANCE_CUSTOM.r);
	int slot = bead_index / 2;
	bool second = (bead_index % 2) == 1;
	vec4 a = texelFetch(particle_state, ivec2(0, slot), 0);
	vec4 b = texelFetch(particle_state, ivec2(1, slot), 0);
	vec4 timing = texelFetch(particle_state, ivec2(2, slot), 0);
	float t = clamp((display_time - timing.x) / max(timing.y, 0.0001), 0.0, 1.0);
	bool seam = timing.z != timing.w;
	vec2 center = seam ? (second ? b.xy : a.xy) : mix(a.xy, b.xy, t);
	float radius = mix(a.z, b.z, t);
	float opacity = mix(a.w, b.w, t);
	strength = opacity * (seam ? (second ? t : 1.0 - t) : (second ? 0.0 : 1.0));
	chart_id = second ? timing.w : timing.z;
	// A finite pixel footprint prevents sub-texel specular on/off aliasing.
	float filtered_radius = max(radius, 1.25);
	strength *= min(1.0, radius * radius / (filtered_radius * filtered_radius));
	footprint = VERTEX * 2.0;
	VERTEX = center + footprint * filtered_radius * (trail_pass ? 1.5 : 1.0);
}

void fragment() {
	vec2 code = texture(chart_map, FRAGCOORD.xy / atlas_size).rg;
	float owner = round(code.r * 255.0) + round(code.g * 255.0) * 256.0;
	float mask = float(owner == chart_id && chart_id > 0.0);
	float value = exp(-dot(footprint, footprint) * 2.0) * strength * mask;
	COLOR = trail_pass ? vec4(value * deposit_delta * 1.8, 0.0, 0.0, 1.0)
		: vec4(0.0, value, 0.0, 1.0);
}
