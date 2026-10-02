shader_type spatial;
render_mode skip_vertex_transform, depth_draw_always, cull_back, specular_disabled, ambient_light_disabled;
stencil_mode read, compare_not_equal, 0x11;

// Shared shading; this pass excludes the eye stencil.
#include "res://addons/npr_character_frame/shaders/hair/hair_base_common.gdshaderinc"
