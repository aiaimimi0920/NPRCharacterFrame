shader_type canvas_item;
uniform vec4 edge_color : source_color = vec4(0.43, 0.56, 0.67, 1.0);
uniform vec4 center_color : source_color = vec4(0.82, 0.88, 0.91, 1.0);

void fragment() {
	vec2 p = UV - vec2(0.45, 0.42);
	p.x *= 1.2;
	float glow = exp(-dot(p, p) * 7.0);
	vec3 color = mix(edge_color.rgb, center_color.rgb, glow);
	// A quiet arc keeps the navigation separate from the character stage.
	float arc = abs(length((UV - vec2(1.8, 0.5)) * vec2(1.0, 0.6)) - 1.7);
	color += vec3(0.055) * (1.0 - smoothstep(0.0005, 0.0015, arc));
	COLOR = vec4(color, 1.0);
}
