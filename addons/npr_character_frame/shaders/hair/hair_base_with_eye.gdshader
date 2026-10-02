shader_type spatial;
render_mode skip_vertex_transform, depth_draw_always, cull_back, specular_disabled, ambient_light_disabled;
stencil_mode read, compare_equal, 0x11;

// Same shading, but captured 1-tap shadow filtering and view-dependent eye alpha.
#define NPR_HAIR_OVER_EYE
#include "res://addons/npr_character_frame/shaders/hair/hair_base_common.gdshaderinc"
