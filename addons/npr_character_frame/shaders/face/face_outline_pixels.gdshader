shader_type spatial;
#include "res://addons/npr_character_frame/shaders/face/symbol_calibration.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_diagnostics.gdshaderinc"
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

// Pixel width, independent of the source FBX units and undocumented vertex colors.
uniform float outline_width_pixels : hint_range(0.0, 4.0, 0.1) = 1.2;
uniform vec4 outline_color : source_color = vec4(0.22, 0.09, 0.13, 1.0);
uniform ivec3 geometry_mask = ivec3(255, 0, 0);
uniform int u_npr_outline_role : hint_range(0, 2) = 0;
uniform bool u_npr_outline_regions_enabled = false;
uniform sampler2D u_npr_outline_region_map : filter_linear_mipmap, repeat_enable;
uniform vec4 u_npr_outline_colors[8];
uniform int u_npr_outline_smooth_normal_source : hint_range(0, 2) = 0;
uniform bool u_npr_outline_lip_fix_enabled = false;
uniform sampler2D u_npr_outline_face_map : filter_linear_mipmap, repeat_enable;
uniform bool u_npr_outline_control_enabled = false;
uniform sampler2D u_npr_outline_control : filter_linear_mipmap, repeat_enable;
uniform float u_npr_outline_lip_width_scale : hint_range(0.0, 1.0) = 0.35;
uniform float u_npr_outline_lip_width_pixels : hint_range(0.0, 4.0, 0.1) = 0.7;
uniform bool u_npr_symbolic_mouth = false;
uniform bool u_npr_symbolic_eyes = false;
varying float npr_symbol_lash;
varying vec4 npr_symbol_canvas;
varying flat float v_npr_outline_slot;
varying vec2 v_npr_outline_uv;
varying vec3 v_npr_outline_position_ws;

void vertex() {
	npr_symbol_lash = CUSTOM0.w;
	npr_symbol_canvas = CUSTOM1;
	vec2 authored_uv = vec2(UV.x, 1.0 - UV.y);
	v_npr_outline_uv = authored_uv;
	v_npr_outline_position_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_npr_outline_slot = 0.0;
	if (u_npr_outline_regions_enabled && u_npr_outline_role != 1) {
		v_npr_outline_slot = npr_material_slot(textureLod(u_npr_outline_region_map, authored_uv, 0.0).a);
	}
	vec3 outline_normal = NORMAL;
	if (u_npr_outline_smooth_normal_source == 1) {
		outline_normal = TANGENT;
	} else if (u_npr_outline_smooth_normal_source == 2) {
		outline_normal = npr_oct_decode(UV2 * 2.0 - 1.0);
	}
	vec4 clip = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);
	vec3 normal_view = MODELVIEW_NORMAL_MATRIX * outline_normal;
	vec4 normal_clip = PROJECTION_MATRIX * vec4(normal_view, 0.0);
	// Quotient derivative of clip.xy / clip.w, normalized in pixel rather than NDC space.
	vec2 pixel_direction = (normal_clip.xy * clip.w - clip.xy * normal_clip.w) * VIEWPORT_SIZE;
		float direction_length = length(pixel_direction);
		if (direction_length > 0.00001 && clip.w > 0.00001) {
			float width_scale = 1.0;
			float resolved_width = outline_width_pixels;
			if (u_npr_outline_lip_fix_enabled && u_npr_outline_role == 1) {
				if (u_npr_outline_control_enabled) {
					vec3 control = textureLod(u_npr_outline_control, authored_uv, 0.0).rgb;
					float lip = max(control.r, control.g);
					resolved_width = mix(
						outline_width_pixels,
						u_npr_outline_lip_width_pixels,
						lip
					);
					resolved_width *= 1.0 - control.b;
				} else {
					float lip = textureLod(u_npr_outline_face_map, authored_uv, 0.0).g;
					width_scale = mix(1.0, u_npr_outline_lip_width_scale, lip);
				}
			}
			clip.xy += pixel_direction / direction_length
				* (2.0 * resolved_width * width_scale / VIEWPORT_SIZE) * clip.w;
	}
	// Do not change Z or W: preserve the engine's Reverse-Z depth convention.
	POSITION = clip;
	if (!npr_part_visible(COLOR, geometry_mask.x, geometry_mask.y != 0, geometry_mask.z != 0)) {
		POSITION = vec4(-99.0, -99.0, -99.0, 1.0);
	}
}

void fragment() {
	if (u_npr_diagnostic_mode != 0 && u_npr_diagnostic_mode != 8) { discard; }
	if (npr_symbol_canvas.w > 2.5) { discard; }
	if (u_npr_symbolic_eyes) {
		if (abs(npr_symbol_canvas.w - 1.0) < 0.1) { discard; }
		vec2 l = (npr_symbol_canvas.xy - u_npr_symbol_outline_eye_left) / u_npr_symbol_outline_eye_radius;
		vec2 r = (npr_symbol_canvas.xy - u_npr_symbol_outline_eye_right) / u_npr_symbol_outline_eye_radius;
		if (abs(npr_symbol_canvas.w - 2.0) < 0.1 && min(length(l), length(r)) < 1.0) { discard; }
	}
	if (u_npr_symbolic_eyes && abs(npr_symbol_lash - 1.0) < 0.1) { discard; }
	if (u_npr_symbolic_mouth && abs(npr_symbol_lash - 2.0) < 0.1) { discard; }
	vec4 surface_fx = npr_surface_effects(v_npr_outline_uv);
	if (!npr_visibility_keep(FRAGCOORD.xy)) {
		discard;
	}
	if (npr_dissolve_signed_distance(v_npr_outline_uv, v_npr_outline_position_ws,
			surface_fx.a) < 0.0) {
		discard;
	}
	int slot = clamp(int(v_npr_outline_slot), 0, 7);
	ALBEDO = u_npr_outline_regions_enabled ? u_npr_outline_colors[slot].rgb : outline_color.rgb;
	if (u_npr_diagnostic_mode == 8) { ALBEDO = vec3(0.0); }
}
