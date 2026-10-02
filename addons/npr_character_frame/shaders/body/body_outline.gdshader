shader_type spatial;
#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"

// 渲染模式
render_mode skip_vertex_transform, depth_draw_always, cull_front, unshaded, shadows_disabled, ambient_light_disabled;

stencil_mode read, compare_not_equal, 0x10;


// --- 功能开关 ---
//#define ENABLE_TWO_PART_HIDE

// ===================================================================
// >> Uniforms & Varyings <<
// ===================================================================
// --- Vertex ---

const vec4 C_POSITION_CLIPPED = vec4(-99.0, -99.0, -99.0, 1.0);

group_uniforms u_vertex_base;
	// 位掩码，用于按位与顶点色中的ID，决定显示哪些部件 (例如，值为3 (二进制11) 将显示ID为1和2的部件)
	instance uniform int u_show_part_id : hint_range(0, 255) = 255;
	// 是否隐藏角色部件 (对应顶点色 G 通道)
	instance uniform bool u_hide_character_parts = false;
#ifdef ENABLE_TWO_PART_HIDE
	// 是否隐藏NPC部件 (对应顶点色 R 通道, 仅当 ENABLE_TWO_PART_HIDE 开启时有效)
	uniform bool u_hide_npc_parts = false;
#endif
	// 主UV的缩放
	uniform vec3 u_uv1_scale = vec3(1.0,1.0,1.0);
	// 主UV的偏移
	uniform vec3 u_uv1_offset = vec3(0.0,0.0,0.0);

	// 全局的特殊矩阵，可能用于类似直播小框的计算
	global uniform mat4 g_u_special_ws_to_vs;
	// 指示当前是否使用特殊矩阵计算cs
	instance uniform bool u_use_special_transform = false; // _20._m13

	uniform bool u_sdf_on_uv2 = true;
	instance uniform bool u_is_monster : instance_index(3) = false;

	// --- 描边参数 ---
	global uniform float g_u_outline_intensity = 0.015;
	uniform float u_outline_intensity = 0.035;

	// --- 描边宽度控制 ---
	global uniform bool g_u_use_global_outline_width;
	global uniform float g_u_global_outline_width;
	uniform float u_initial_fade_factor = 0.0;

	uniform float u_outline_weight = 1.0;
	uniform float u_distance_fade_start;
	uniform float u_distance_fade_end;

	// --- 变换与坐标 ---
	global uniform mat4 g_u_jittered_projection;
group_uniforms;

group_uniforms u_vertex_light;
	global uniform bool g_u_character_disable_main_light = false;
	instance uniform bool u_character_disable_local_main_light : instance_index(5) = false;
	instance uniform vec4 u_character_local_main_light_position : instance_index(6) = vec4(-0.73723, 0.43589, -0.51623, 0.00);
	global uniform vec4 g_u_character_main_light_position = vec4(-0.73723, 0.43589, -0.51623, 0.00);
	instance uniform vec4 u_custom_main_light_dir : instance_index(4) = vec4(1.00, 1.00, 1.00, 0.00);
	global uniform vec4 g_u_monster_main_light_dir = vec4(0.2706, 0.70711, 0.65328, 0.0);
	instance uniform vec4 u_accent_light_dir : instance_index(7) = vec4( 0.00, 0.00, 0.00, 0.00);
		instance uniform vec4 u_character_local_main_light_color : source_color, instance_index(8) = vec4(1.0,1.0,1.0,1.0);
	global uniform vec4 g_u_character_main_light_color:source_color = vec4(1.0,1.0,1.0,1.0);
group_uniforms;

// --- Varyings ---

// NDC坐标和裁剪空间Z/W
varying vec4 v_position_ndc;
varying vec3 v_position_ws;
// 世界空间法线
varying vec3 v_tangent_ws;

// ===================================================================
// >> Vertex Shader <<
// ===================================================================

// 顶点着色器 - 部件显隐与掩码处理
bool get_render_condition(vec4 color) {
#ifdef ENABLE_TWO_PART_HIDE
	uvec2 part_id_mask = uvec2(color.gr * 256.0);
	part_id_mask = uvec2(part_id_mask & uvec2(uint(u_show_part_id)));
	return (u_hide_character_parts ? float(part_id_mask.x) :
			(u_hide_npc_parts ? float(part_id_mask.y) : 1.0)) > 0.0;
#else
	int part_id_mask = int(color.g * 256.0);
	//part_id_mask = 0;
	part_id_mask = int(uint(part_id_mask) & uint(u_show_part_id));
	part_id_mask = part_id_mask>0?-1:0;
	return (u_hide_character_parts ? part_id_mask : -1) != 0;
#endif
}

void vertex() {
	// 模型空间 -> 世界空间 (传递给FS)
	v_position_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float intensity_mask = COLOR.b<0.99?COLOR.b:0.0;
	float cur_outline_weight = u_outline_weight * intensity_mask;

	float final_outline_weight = g_u_outline_intensity * u_outline_intensity*COLOR.a; // 全局描边亮度*模型描边强度

	vec4 position_vs = MODELVIEW_MATRIX*vec4(VERTEX,1.0);
	vec4 special_vs  = g_u_special_ws_to_vs*vec4(v_position_ws, 1.0);
	vec4 base_position_vs = mix(position_vs, special_vs, bvec4(u_use_special_transform)); // _48
	base_position_vs.z = (base_position_vs.z - 0.01 * cur_outline_weight);

	float screen_scale = base_position_vs.z/PROJECTION_MATRIX[1][1];
	float outline_width = sqrt(abs(screen_scale) / g_u_outline_intensity);
	outline_width = g_u_use_global_outline_width ? g_u_global_outline_width : outline_width; // _52.x
	outline_width = final_outline_weight * outline_width * (1.0 - u_initial_fade_factor);

	float dist_to_cam = length(v_position_ws - CAMERA_POSITION_WORLD);
	float fade_range = u_distance_fade_end - u_distance_fade_start;
	float distance_in_range = dist_to_cam - u_distance_fade_start;

	float fade_ratio = 0.0;
	if (fade_range > 0.0001) {
		fade_ratio = min(smoothstep(0.0, 1.0, distance_in_range / fade_range), 0.5);
	}
	fade_ratio += 1.0;
	float last_factor = final_outline_weight * fade_ratio;

	vec3 normal_vs = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec3 extrusion_dir = normalize(vec3(normal_vs.xy, -0.1));

	vec4 extruded_position_vs  = vec4(extrusion_dir * last_factor + base_position_vs.xyz,1.0);

	//vec4 final_position_cs = g_u_jittered_projection*extruded_position_vs; // 注意这里可能使用的是抖动投影矩阵，并不是完全的投影矩阵,TODO:这个是正确版本，但是调试期间使用下面这个版本，要不主视图不显示
	vec4 final_position_cs = PROJECTION_MATRIX*extruded_position_vs;
	// 部件显隐与顶点掩码处理
	bool render_condition = get_render_condition(COLOR);
	POSITION = mix(C_POSITION_CLIPPED, final_position_cs, float(render_condition)); // _46 = position_cs

	v_position_ndc.xy = (final_position_cs.xy + final_position_cs.w) * 0.5;
	v_position_ndc.zw = final_position_cs.zw; // face_npr_outline 不同

	UV = vec2(UV.x, UV.y);
	UV2 = vec2(0.0, 0.0);
	COLOR = vec4(COLOR.rgb,0.0);
	v_tangent_ws = normalize(MODEL_NORMAL_MATRIX * TANGENT);
}

///////// fragment函数 /////////

uniform int u_view_flip_index = 0;// 这个变量可能是指定平台的
// 这一段很可能是给不同的平台做适配
const vec2 c_flip_modes[8] = vec2[](
	vec2(1.0, 1.0),    // 原始
	vec2(1.0, 1.0),    // 重复未使用
	vec2(-1.0, 1.0),   // 水平翻转
	vec2(-1.0, -1.0),  // 水平 + 垂直翻转
	vec2(1.0, -1.0),   // 垂直翻转
	vec2(1.0, 1.0),    // 再次原始
	vec2(-1.0, 1.0),   // 水平翻转
	vec2(-1.0, -1.0)   // 全翻转
);

//#define TOON_BACK_COLOR // 包含背面的模型，部分模型只有正面贴图
//#define TOON_HAIR
#define USE_MATERIAL_VALUES_LUT

group_uniforms u_base_map;
uniform vec4 u_base_color : source_color = vec4(1.0,1.0,1.0,1.0); // 已核对数据
uniform vec4 u_back_color : source_color = vec4(1.0,1.0,1.0,1.0); // 已核对数据
uniform sampler2D u_texture_base_map : source_color, filter_linear_mipmap, repeat_enable;
group_uniforms;

group_uniforms u_light_map;
uniform sampler2D u_texture_light_map : source_color, filter_linear_mipmap, repeat_enable;
group_uniforms;


uniform sampler2D u_material_values_pack_lut : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms u_textures;
	uniform sampler2D u_texture_lut_map : source_color, filter_linear_mipmap, repeat_enable;
group_uniforms;

group_uniforms u_distance_lut_params;
	global uniform float g_u_distance_remap_min_A = -50.0;
	global uniform float g_u_distance_remap_max_A = 1000.0;
	global uniform float g_u_distance_remap_min_B = -100.0;
	global uniform float g_u_distance_remap_max_B = 351.2;
	global uniform float g_u_distance_range_blend_factor = 0.1;
	global uniform vec2 g_u_cam_dist_intensities = vec2(0.8, 0.7);
	global uniform float g_u_plane_dist = 255.0;
	global uniform float g_u_plane_dist_center = 5.0;
	global uniform float g_u_lut_y_param1 = 0.0;
	global uniform float g_u_lut_y_param2 = 0.0;
	global uniform float g_u_lut_y_offset1 = 0.5625;
	global uniform float g_u_lut_y_offset2 = 0.8125;
	global uniform vec4 g_u_world_plane = vec4(0.0,1.0,0.0,0.0);
	uniform float u_distance_lut_grading_intensity = 1.0;
	uniform vec3 u_outline_color = vec3(0.5,0.3,0.2);
group_uniforms;




/**
 * @brief 基于距离的LUT颜色渐变
 */
vec3 apply_distance_lut_grading(float dist_to_cam, vec3 current_color, vec3 world_pos) {
	vec2 remap_min_params = vec2(g_u_distance_remap_min_A, g_u_distance_remap_min_B);
	vec2 remap_max_params = vec2(g_u_distance_remap_max_A, g_u_distance_remap_max_B);
	vec2 remap_full_ranges = remap_max_params - remap_min_params;
	vec2 final_remap_min = g_u_distance_range_blend_factor * remap_full_ranges + remap_min_params;
	vec2 final_remap_max = remap_max_params;

	// TODO:这里是测试代码，因为距离过长或者摄像机位置不对，所以会出问题
	dist_to_cam = dist_to_cam*0.1;

	vec2 value_in_range = vec2(dist_to_cam) - final_remap_min;
	vec2 final_range = final_remap_max - final_remap_min;
	vec2 t_values = clamp(value_in_range / final_range, vec2(0.0), vec2(1.0));
	t_values = t_values * g_u_cam_dist_intensities.xy;

	vec2 t_sq = t_values * t_values;
	vec2 curved_dist_factors  = t_values * (t_values - t_sq) + t_values;

	//curved_dist_factors.x = 0.7;
	//curved_dist_factors.y = 0.1;

	// 计算平面距离因子
	float dist_to_plane = dot(world_pos, g_u_world_plane.xyz) - g_u_world_plane.w;

	float processed_plane_dist = (g_u_plane_dist>0.0) ? (dist_to_plane - g_u_plane_dist_center) : (g_u_plane_dist_center - dist_to_plane);

	float plane_range = abs(g_u_plane_dist) + 1.0;
	float remapped_plane_dist_raw = min(max(processed_plane_dist, 0.0) / plane_range, 1.0);

	float final_plane_factor = 1.0 - remapped_plane_dist_raw;

	float blend_target_4_weight =clamp(final_plane_factor * g_u_cam_dist_intensities.y -1.0, 0.0,1.0);

	// --- LUT采样与链式混合
	float y_coord_base = (1.0 - g_u_lut_y_param1) * g_u_lut_y_param2 * 0.125;
	float lut_uv_y_1 = y_coord_base + g_u_lut_y_offset1;
	float lut_uv_y_2 = y_coord_base + g_u_lut_y_offset2;

	// 第一次采样、混合
	vec3 color_from_lut1 = textureLod(u_texture_lut_map, vec2(curved_dist_factors.x, lut_uv_y_1), 0.0).rgb;
	float blend_factor_B  = clamp(g_u_cam_dist_intensities.x-1.0,0.0,1.0);

	vec2 distance_blend_factors  = clamp(curved_dist_factors, vec2(0.0), vec2(1.0));
	vec3 blend_target_1 = distance_blend_factors.x * color_from_lut1;
	vec3 color_after_ramp1_mix = mix(current_color, blend_target_1, distance_blend_factors.x);

	// 第二次混合
	vec3 blend_target_2 = distance_blend_factors.x * color_from_lut1 + color_after_ramp1_mix;

	vec3 color_after_uniform_mix = blend_target_2 * blend_factor_B + color_after_ramp1_mix;

	// 第三次采样和混合
	vec3 color_from_lut2 = textureLod(u_texture_lut_map, vec2(curved_dist_factors.y, lut_uv_y_2), 0.0).rgb;
	vec3 scaled_lut2_color  = final_plane_factor * color_from_lut2;
	vec3 color_after_ramp2_mix = mix(color_after_uniform_mix, scaled_lut2_color  * distance_blend_factors.y,  distance_blend_factors.y);

	// 第四次混合
	vec3 blend_target_4 = (scaled_lut2_color * distance_blend_factors.y) + color_after_ramp2_mix ;

	vec3 color_after_plane_mix = blend_target_4*blend_target_4_weight + color_after_ramp2_mix;

	float lut2_luminance  = max(max(color_from_lut2.x, color_from_lut2.y),color_from_lut2.z);

	vec3 grading_target_color = final_plane_factor*color_after_plane_mix * distance_blend_factors.y + color_after_uniform_mix;

	vec3 grading_base_color = mix(color_after_uniform_mix, color_after_plane_mix , final_plane_factor);

	float luminance_blend_factor = mix(lut2_luminance, 0.0, u_distance_lut_grading_intensity);

	vec3 final_graded_color = mix(grading_base_color, grading_target_color, luminance_blend_factor);

	return final_graded_color;
}



/**
 * @brief 雾效
 */
group_uniforms u_fog_params;
	uniform mat4 g_u_fog_matrix = mat4(vec4(0.47635, 0.0, 0.0, 0.0), vec4(0.00, 0.26795, 0.0, -0.29739), vec4(0.0, 7.89598e-09, 0.00, 0.14703), vec4(0.0, -7.89598E-09, -1.00, -0.14703));
	global uniform float g_u_fog_linear_scale=1.0;
	global uniform float g_u_fog_linear_offset=0.0;
	global uniform float g_u_fog_log_scale= 1.0;
	global uniform float g_u_fog_intensity = 0.0;
	uniform sampler3D u_texture_fog_map : source_color, filter_linear_mipmap, repeat_enable;
group_uniforms;

vec3 apply_fog_effect(vec3 current_color, vec4 position_ndc, float frag_depth) {
	vec2 screen_uv = position_ndc.xy / position_ndc.w;
	vec2 ndc = screen_uv * 2.0 - 1.0;

	// 自定义变换
	float linear_depth = frag_depth * 2.0 - 1.0;
	vec2 fog_clip_zw = (ndc.yy * g_u_fog_matrix[1].zw)
						   + (ndc.xx * g_u_fog_matrix[0].zw)
						   + (vec2(linear_depth) * g_u_fog_matrix[2].zw)
						   + g_u_fog_matrix[3].zw;

	// 透视除法
	float fog_depth_remapped = -fog_clip_zw.x / fog_clip_zw.y;
	// 线性重映射
	fog_depth_remapped = fog_depth_remapped * g_u_fog_linear_scale + g_u_fog_linear_offset;
	fog_depth_remapped = max(fog_depth_remapped, 0.0001);

	// 对数深度
	float final_fog_depth = log2(fog_depth_remapped) * g_u_fog_log_scale;

	// 最终的3D采样坐标
	vec3 lut_coord = vec3(screen_uv, final_fog_depth);

	vec4 fog_sample = textureLod(u_texture_fog_map, lut_coord, 0.0);

	vec3 blended_color =  fog_sample.rgb + (fog_sample.a-1.0)*current_color;

	vec3 fog_blender_color = float(g_u_fog_intensity) * blended_color + current_color;
	return fog_blender_color;
}

/**
 * @brief 最终的抖动和量化
 */
group_uniforms u_dither_params;
	uniform int u_dither_mask = 0;
	// uniform int u_color_mode = 0;
	const vec4 c_dither_values = vec4(-0.01171875, 0.00390625, 0.01171875, -0.00390625);
group_uniforms;


group_uniforms u_outline_group;
	uniform bool u_auto_outline_color = true;
	global uniform float g_interior_line_contrast = 0.5; // 用于控制内描线的对比度。值越大，非线条区域就越暗，线条反衬得就越清晰、越“亮”。
	global uniform vec4 g_u_interior_line_add_color = vec4(0.0,0.0,0.0,0.0);

	uniform bool u_use_global_interior_line_darken_factor = false;
	global uniform float g_u_interior_line_darken_factor = 0.0;
	uniform float u_interior_line_darken_factor = 0.2;


	instance uniform vec4 u_light_position : instance_index(9) = vec4(0.0,0.0,0.0,0.0); // 已核对数据
	instance uniform vec4 u_outline_light_direction : instance_index(10) = vec4(0.0,0.0,0.0,0.0); // 已核对数据 // 虚拟的边缘光基准方向，边缘光：取决于模型表面朝向和“基准方向”的关系。漫反射光：取决于光线飞行方向和“基准方向”的关系。
	uniform vec4 u_dark_area_tint = vec4(0.0,0.0,0.0,0.0); // 已核对数据
	uniform bool u_local_main_light_disabled = true; // 已核对数据
	uniform vec4 u_outline_additive_factor: source_color = vec4(0.0,0.0,0.0,0.0); // 已核对数据
group_uniforms;

void fragment() {
	vec4 debug_color = vec4(-1.0,-1.0,-1.0, -1.0);
	vec4 screen_coord = FRAGCOORD;
	float one_over_w = 1.0 / screen_coord.w;

	// 翻转Y坐标以匹配常见纹理坐标系，原逻辑中没有，需要查看是否需要
	vec2 frag_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 frag_uv2 = vec2(UV2.x, 1.0 - UV2.y);

	vec3 outline_color;
	if(u_auto_outline_color){
		vec4 ilm = texture(u_texture_light_map, frag_uv);
		float ramp_level = floor(ilm.a * 8.0);
		ramp_level = fract(0.125 * ramp_level) * 8.0f;
		outline_color = texelFetch(u_material_values_pack_lut, ivec2(int(ramp_level), 2), 0).xyz;
	}else{
		outline_color = u_outline_color;
	}

	bool use_local_main_light = g_u_character_disable_main_light && !u_character_disable_local_main_light;
	vec3 main_light_dir = use_local_main_light ? u_character_local_main_light_position.xyz : g_u_character_main_light_position.xyz;
	vec3 light_dir_ws = mix(main_light_dir, u_custom_main_light_dir.xyz, u_custom_main_light_dir.w);
	light_dir_ws = u_is_monster? g_u_monster_main_light_dir.xyz : light_dir_ws;
	light_dir_ws = normalize(light_dir_ws);

	float interior_line_intensity = dot(light_dir_ws,v_tangent_ws)*6.6667;
	interior_line_intensity = smoothstep(0.0, 1.0, interior_line_intensity);

	float base_brightness  = 1.0 - g_interior_line_contrast;
	float line_brightness_multiplier = mix(base_brightness , 1.0, interior_line_intensity);
	outline_color = outline_color * line_brightness_multiplier + vec3(interior_line_intensity * g_u_interior_line_add_color.rgb);

	outline_color = (1.0-u_interior_line_darken_factor) *outline_color;
	outline_color = (1.0-float(u_use_global_interior_line_darken_factor)*g_u_interior_line_darken_factor)*outline_color;

	float dist_to_cam = length(v_position_ws - CAMERA_POSITION_WORLD);
	vec3 distance_lut_grading_color = apply_distance_lut_grading(dist_to_cam, outline_color, v_position_ws); // 距离渐变+调色后的颜色
	vec3 fog_blender_color = apply_fog_effect(distance_lut_grading_color, v_position_ndc, FRAGCOORD.z);

	ALBEDO = npr_dither_color(fog_blender_color, u_dither_mask, FRAGCOORD.xy);
	ALPHA = 1.0;
	// Rasterized outline geometry owns depth; no captured MRT data is written to DEPTH.

	if(debug_color.r>=0.0||debug_color.g>=0.0||debug_color.b>=0.0){
		ALBEDO = debug_color.rgb;
	}
}
