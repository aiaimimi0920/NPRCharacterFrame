shader_type spatial;
render_mode unshaded;
#include "res://addons/npr_character_frame/shaders/eye/eye_profile.gdshaderinc"

uniform vec4 eye_color : source_color = vec4(1.0);
uniform sampler2D iris_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool textured = false;
uniform vec2 focus_offset = vec2(0.0);
uniform float pupil_scale = 1.0;
uniform float upper_shade : hint_range(0.0, 1.0) = 0.18;
uniform vec2 aperture_size = vec2(0.0345, 0.019);
uniform float aperture_slope = 0.08;
varying vec2 aperture_position;

void vertex() {
	aperture_position = VERTEX.xy * pupil_scale + focus_offset;
	VERTEX.z = npr_eye_depth(aperture_position);
}

void fragment() {
	// Iris/pupil movement stays inside the authored, sloped eye aperture.
	vec2 aperture = vec2(aperture_position.x,
		aperture_position.y - aperture_slope * aperture_position.x) / aperture_size;
	if (!npr_eye_aperture(aperture_position)) {
		discard;
	}
	vec3 base = eye_color.rgb;
	if (textured) {
		base *= texture(iris_texture, UV).rgb;
	}
	float shade = 1.0 - upper_shade * smoothstep(-0.4, 0.75, aperture.y);
	ALBEDO = base * shade;
}
