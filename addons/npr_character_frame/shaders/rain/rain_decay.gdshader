shader_type canvas_item;
render_mode unshaded, blend_mul;
uniform float retention = 1.0;

void fragment() {
	COLOR = vec4(vec3(retention), 1.0);
}
