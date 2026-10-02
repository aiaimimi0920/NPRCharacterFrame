// All coplanar color/stencil/shadow passes must use the SAME operation order.
// P*V*M*v and (P*MV)*v are mathematically equivalent, but round differently on
// the GPU. A depth-tested overlay then flickers as triangles win/lose depth.
// Match Godot's default vertex pipeline: model -> view, then view -> clip.
vec4 npr_clip_position(mat4 projection, mat4 modelview, vec3 vertex_model) {
	vec3 vertex_view = (modelview * vec4(vertex_model, 1.0)).xyz;
	return projection * vec4(vertex_view, 1.0);
}

// In hide/filter mode, intersecting bits are KEPT, despite the historical names.
bool npr_part_visible(vec4 color, int mask, bool character_filter, bool npc_filter) {
	uvec2 selected = uvec2(color.gr * 256.0) & uvec2(uint(mask));
	return character_filter ? selected.x > 0u : (npc_filter ? selected.y > 0u : true);
}
