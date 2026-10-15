
group_uniforms u_sheen_params;
	uniform vec3 u_sheen_light_position = vec3(0.0,0.0,0.0); //_23._m7
	uniform vec3 u_sheen_light_direction = vec3(0.0,0.0,0.0); // _23._m6
	uniform float u_sheen_blend_factor = 0.0; //_23._m2.w // 为0则偏向sdf，反之偏向传统
	uniform vec2 u_shading_sheen_factor = vec2(0.0,0.0); //_23._m8.xy
group_uniforms;

/**
 * @brief 计算由SDF驱动的光泽
 */
float calculate_sdf_sheen_factor(float sdf_sample_value, float accent_sdf_angle, vec3 world_pos) {
	// --- 光照模型A: 纯粹的、风格化的SDF光泽 ---
	vec2 remap_bounds = clamp(vec2(accent_sdf_angle - 0.1, accent_sdf_angle + 0.1), 0.0, 1.0);
	float sdf_range = remap_bounds.y - remap_bounds.x;
	float remapped_sdf = (sdf_sample_value - remap_bounds.x) / sdf_range;
	float stylized_sheen_factor = smoothstep(0.0, 1.0, remapped_sdf);

	// --- 光照模型B: 基于主光源的传统光照贡献 ---
	// 计算一个用于点积的方向向量
	vec3 dir_from_light_to_frag  = normalize(world_pos - u_sheen_light_position.xyz);
	float dot_product  = dot(dir_from_light_to_frag, u_sheen_light_direction.xyz);
	float spotlight_factor = dot_product  * 0.5 + 0.5;

	float term_A = stylized_sheen_factor * (1.0 - u_sheen_blend_factor) *0.95;
	float term_B = spotlight_factor * u_sheen_blend_factor;
	float final_sheen_factor = term_A + term_B;
	return final_sheen_factor;
}

group_uniforms u_contrast_params;
	uniform vec3 u_contrast_color = vec3(0.0,0.0,0.0); // _23._m2.xyz
group_uniforms;

/**
 * @brief 对比度调节
 */
vec3 apply_contrast_adjustment(
	vec3 base_color,
	vec2 final_sdf_sheen_factor,
	vec2 sdf_blend_switch
) {
	bvec3 is_dark = lessThan(base_color, vec3(0.5));
	vec3 dark_path_color  = base_color * 2.0 * u_contrast_color.rgb;
	vec3 bright_path_color   = vec3(1.0) - (1.0 - base_color) * 2.0 * (vec3(1.0) - u_contrast_color.rgb);

	vec3 contrast_enhanced_color;
	contrast_enhanced_color.r = is_dark.r ? dark_path_color.r : bright_path_color.r;
	contrast_enhanced_color.g = is_dark.g ? dark_path_color.g : bright_path_color.g;
	contrast_enhanced_color.b = is_dark.b ? dark_path_color.b : bright_path_color.b;

	// 对比度混合
	vec3 blended_color = mix(base_color, contrast_enhanced_color, final_sdf_sheen_factor.x);
	return blended_color;
}

group_uniforms u_sdf_add_color_params;
	uniform vec3 u_sdf_add_color = vec3(0.0,0.0,0.0); // _23._m3
group_uniforms;
////
////
group_uniforms u_rim_shadow_light_params;
	// Face
	uniform float u_rim_shadow_face_width = 0.00; // _35._m64
	uniform float u_rim_shadow_face_feather = 0.99; // _35._m65
	uniform vec3 u_rim_shadow_mask =  vec3(0.0,0.0,0.0); // _35._m63

	// Common
	uniform vec3 u_rim_shadow_offset = vec3(0.3,0.3,0.2); // 35._m82
	uniform float u_rim_shadow_ct = 1.0; // _35._m79
	uniform float u_rim_shadow_intensity = 1.0; // _35._m80
group_uniforms;


vec3 calculate_rim_shadow_light(vec3 view_dir_vs, vec3 normal_vs, vec2 frag_uv) {
	vec3 view_dir_vs_offset = normalize(view_dir_vs - u_rim_shadow_offset.xyz);
	float rim = dot(normal_vs, view_dir_vs_offset);
	rim = clamp(rim, 0.0, 1.0);

	vec2 mirrored_uv = frag_uv;
	mirrored_uv.x = mirrored_uv.x > 0.5?(1.0 - mirrored_uv.x):mirrored_uv.x;
	float rim_shadow_color = texture(u_texture_ilm_map, mirrored_uv).w;

	float rim_shadow = clamp(pow(max(1.0 - rim, 0.001), u_rim_shadow_ct) * u_rim_shadow_face_width, 0.0, 1.0);
	rim_shadow = smoothstep(u_rim_shadow_face_feather, 1.0, rim_shadow);

	vec3 rim_shadow_factor = rim_shadow * (vec3(1.0) - u_rim_shadow_mask.rgb) * u_rim_shadow_intensity;
	return mix(vec3(1.0), vec3(rim_shadow_color), rim_shadow_factor);
}

group_uniforms u_bloom_params;
	uniform float u_bloom_no_mid_baked_mask_intensity = 0.02; // _35._m240
	global uniform vec4 g_u_bloom_add_color = vec4(0.0,0.0,0.0,1.0); // _39._m60
group_uniforms;

vec3 apply_bloom_blend(
	vec3 blender_color,
	vec3 bloom_blend_color,
	float bloom_factor_2
) {
	bool is_above_threshold = u_emission_intensity < bloom_factor_2;
	float range = max(1.0 - u_emission_intensity, 0.001);
	float remapped_factor  = (bloom_factor_2 - u_emission_intensity) / range;
	remapped_factor = clamp(remapped_factor, 0.0, 1.0);
	float final_bloom_blend_factor = is_above_threshold ? remapped_factor : 0.0;

	vec3 target_bloom_color  = bloom_blend_color * u_emission_intensity;
	vec3 final_color = mix(blender_color, target_bloom_color, final_bloom_blend_factor);
	return final_color;
}

group_uniforms u_height_lerp_params;
	instance uniform vec3 u_character_world_space_offset : instance_index(9) = vec3(0.0,0.0,0.0); // _35._m0
	global uniform vec4 g_u_height_lerp_bottom_color: source_color = vec4(1.0,1.0,1.0,0.5); //_39._m74
	global uniform vec4 g_u_height_lerp_middle_color: source_color = vec4(1.0,1.0,1.0,0.5); //_39._m73
	global uniform vec4 g_u_height_lerp_top_color: source_color = vec4(1.0,1.0,1.0,0.5); //_39._m72
	global uniform float g_u_height_lerp_bottom = 0.0; //_39._m71
	global uniform float g_u_height_lerp_top = 0.0; //_39._m70
group_uniforms;
/**
 * @brief 高度渐变
 */
vec3 apply_height_gradient(float world_height, vec3 current_color) {
	if (u_npr_studio_enabled) {
		return current_color;
	}

	float relative_height = world_height - u_character_world_space_offset.y;
	float lerp01 = 1.0 - smoothstep(0.0, 1.0, relative_height / max(g_u_height_lerp_bottom, 0.001));

	float lerp10 = smoothstep(0.0, 1.0, (relative_height - g_u_height_lerp_top) * 2.0);
	float mask = clamp(1.0 - lerp01 - lerp10, 0.0, 1.0);

	vec3 bottom_c = lerp01 * g_u_height_lerp_bottom_color.rgb * g_u_height_lerp_bottom_color.a;
	vec3 middle_c = mask * g_u_height_lerp_middle_color.rgb * g_u_height_lerp_middle_color.a;
	vec3 top_c = lerp10 * g_u_height_lerp_top_color.rgb * g_u_height_lerp_top_color.a;

	return current_color * clamp(bottom_c + middle_c + top_c, 0.0, 1.0) * 2.0;
}

group_uniforms u_distance_lut_params;
	global uniform float g_u_distance_remap_min_A = -50.0; //_39._m138
	global uniform float g_u_distance_remap_max_A = 1000.0; //_39._m139
	global uniform float g_u_distance_remap_min_B = -100.0; // _39._m146
	global uniform float g_u_distance_remap_max_B = 351.2; // _39._m147
	global uniform float g_u_distance_range_blend_factor = 0.1; //_39._m150
	global uniform vec2 g_u_cam_dist_intensities = vec2(0.8, 0.7); // _39._m137 _39._m145
	global uniform float g_u_plane_dist = 255.0; // _39._m144
	global uniform float g_u_plane_dist_center = 5.0; // _39._m143
	global uniform float g_u_lut_y_param1 = 0.0; // _39._m163
	global uniform float g_u_lut_y_param2 = 0.0; // _39._m19
	global uniform float g_u_lut_y_offset1 = 0.5625; // _39._m136
	global uniform float g_u_lut_y_offset2 = 0.8125; // _39._m142
	global uniform vec4 g_u_world_plane = vec4(0.0,1.0,0.0,0.0); // _39._m33[3u]
		uniform float u_distance_lut_grading_intensity = 1.0; // _39._m151
		// Project calibration: keep the imported distance domain explicit and tunable.
		uniform float u_distance_lut_distance_scale : hint_range(0.0001, 4.0, 0.0001) = 0.05;
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

	// Silver Wolf's imported distance domain is calibrated to a compact LUT range.
	dist_to_cam *= u_distance_lut_distance_scale;

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
	vec3 color_from_lut1 = textureLod(u_texture_diffuse_ramp, vec2(curved_dist_factors.x, lut_uv_y_1), 0.0).rgb;
	float blend_factor_B  = clamp(g_u_cam_dist_intensities.x-1.0,0.0,1.0);

	vec2 distance_blend_factors  = clamp(curved_dist_factors, vec2(0.0), vec2(1.0));
	vec3 blend_target_1 = distance_blend_factors.x * color_from_lut1;
	vec3 color_after_ramp1_mix = mix(current_color, blend_target_1, distance_blend_factors.x);

	// 第二次混合
	vec3 blend_target_2 = distance_blend_factors.x * color_from_lut1 + color_after_ramp1_mix;

	vec3 color_after_uniform_mix = blend_target_2 * blend_factor_B + color_after_ramp1_mix;

	// 第三次采样和混合
	vec3 color_from_lut2 = textureLod(u_texture_diffuse_ramp, vec2(curved_dist_factors.y, lut_uv_y_2), 0.0).rgb;
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
	uniform mat4 g_u_fog_matrix = mat4(vec4(0.47635, 0.0, 0.0, 0.0), vec4(0.00, 0.26795, 0.0, -0.29739), vec4(0.0, 7.89598e-09, 0.00, 0.14703), vec4(0.0, -7.89598E-09, -1.00, -0.14703)); // _15._m7
	global uniform float g_u_fog_linear_scale=1.0; // _32._m13.x
	global uniform float g_u_fog_linear_offset=0.0; // _32._m13.y
	global uniform float g_u_fog_log_scale= 1.0; // _32._m13.z
	global uniform float g_u_fog_intensity = 0.0; // _32._m2
	uniform sampler3D u_texture_fog_map : source_color, filter_linear_mipmap, repeat_enable;
	uniform bool u_npr_capture_fog_enabled = true;
group_uniforms;

vec3 apply_fog_effect(vec3 current_color, vec4 position_ndc, float frag_depth) {
	// Disabled capture fog must not sample an unbound volume or evaluate its matrix.
	if (!u_npr_capture_fog_enabled || g_u_fog_intensity == 0.0) {
		return current_color;
	}
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
 * @brief 八面体法线编码
 */


/**
 * @brief 最终的抖动和量化
 */
group_uniforms u_dither_params;
	uniform int u_dither_mask = 0;
	// uniform int u_color_mode = 0;
	const vec4 c_dither_values = vec4(-0.01171875, 0.00390625, 0.01171875, -0.00390625);
group_uniforms;




float npr_symbol_segment(vec2 p, vec2 a, vec2 b) {
	vec2 line = b - a;
	return length(p - a - line * clamp(dot(p - a, line) / dot(line, line), 0.0, 1.0));
}

float npr_symbol_ink(vec2 position, float side) {
	vec2 p = position / u_npr_eye_symbol_size;
	float d = 1.0;
	if (u_npr_eye_symbol == 1) {
		p.x *= -side;
		d = min(npr_symbol_segment(p, vec2(-0.55, -0.65), vec2(0.45, 0.0)),
			npr_symbol_segment(p, vec2(0.45, 0.0), vec2(-0.55, 0.65)));
	} else if (u_npr_eye_symbol == 2) {
		d = min(npr_symbol_segment(p, vec2(-0.65, -0.35), vec2(0.0, 0.60)),
			npr_symbol_segment(p, vec2(0.0, 0.60), vec2(0.65, -0.35)));
	} else if (u_npr_eye_symbol == 3) {
		d = npr_symbol_segment(p, vec2(-0.7, 0.0), vec2(0.7, 0.0));
		} else if (u_npr_eye_symbol == 4) {
			d = min(npr_symbol_segment(p, vec2(-0.55, -0.60), vec2(0.55, 0.60)),
				npr_symbol_segment(p, vec2(-0.55, 0.60), vec2(0.55, -0.60)));
		} else if (u_npr_eye_symbol == 5) {
			for (int i = 0; i < 10; i++) {
				float a = 1.5707963 + float(i) * 0.6283185;
				float b = a + 0.6283185;
				float r0 = (i % 2 == 0) ? 0.78 : 0.32;
				float r1 = (i % 2 == 0) ? 0.32 : 0.78;
				d = min(d, npr_symbol_segment(p, vec2(cos(a), sin(a)) * r0, vec2(cos(b), sin(b)) * r1));
			}
		} else if (u_npr_eye_symbol == 6) {
			vec2 h = vec2(p.x, p.y + 0.08) / 0.64;
			float k = dot(h, h) - 1.0;
			float heart = k * k * k - h.x * h.x * h.y * h.y * h.y;
			float aa_heart = max(fwidth(heart), 0.015);
			return 1.0 - smoothstep(-aa_heart, aa_heart, heart);
	}
	float aa = max(fwidth(d), 0.006);
	return 1.0 - smoothstep(u_npr_eye_symbol_stroke - aa, u_npr_eye_symbol_stroke + aa, d);
}
