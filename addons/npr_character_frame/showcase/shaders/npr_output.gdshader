shader_type canvas_item;
render_mode unshaded;

#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"

// Display-referred output, AFTER the complete 3D viewport and its tonemapper.
// Not a replacement for the material's earlier level/accent/dither stages.
uniform float split_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 split_tint : source_color = vec3(0.48, 0.44, 0.56);
uniform int quantization_mode : hint_range(0, 3) = 0;

void fragment() {
	vec3 source = COLOR.rgb;
	vec3 dark = 2.0 * source * split_tint;
	vec3 bright = vec3(1.0) - 2.0 * (vec3(1.0) - source) * (vec3(1.0) - split_tint);
	vec3 split = mix(bright, dark, lessThan(source, vec3(0.5)));
	vec3 graded = mix(source, split, split_strength);
	// Stable in this texture's own pixel grid, not the window/UI position or TIME.
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	COLOR.rgb = clamp(npr_dither_color(graded, quantization_mode, pixel), vec3(0.0), vec3(1.0));
	// COLOR already includes the viewport texture and modulation. Do not sample it
	// again or change alpha; UI siblings are never inputs to this draw.
}
