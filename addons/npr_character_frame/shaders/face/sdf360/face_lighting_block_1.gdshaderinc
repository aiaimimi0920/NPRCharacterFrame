
group_uniforms u_nose_line_params;
	uniform float u_nose_line_power = 3.0; // _35._m359
	uniform vec3 u_nose_line_color = vec3(0.70776, 0.1224, 0.1224); // _35._m360
group_uniforms;

float calculate_nose_line_factor(vec3 normal_ws, vec3 view_dir_ws, float area_mask) {
	vec3 modified_view_dir_ws = view_dir_ws;
	modified_view_dir_ws.y *= 0.5;
	float modified_NdotV = dot(normal_ws, modified_view_dir_ws);
	modified_NdotV = max(modified_NdotV, 0.001);

	float nose_sp = max(u_nose_line_power * 8.0, 0.1);
	float nose_power = pow(modified_NdotV, nose_sp);
	float specular = min(nose_power, 1.0) * area_mask;
	float nose_line_mask = (specular > 0.1) ? 1.0 : 0.0;
	return nose_line_mask;
}

// 在您的着色器代码顶部，可以添加以下uniforms来对应汇编中的参数
group_uniforms u_lip_line_fix_params;
	uniform float u_lip_line_start = 0.6; // _35._m292
	uniform float u_lip_line_end = 2.0; // _35._m293

	uniform float u_lip_line_fix_curve_shape = 0.0; //_35._m295 // 控制曲线平缓度，越高越陡峭
	uniform float u_lip_line_fix_curve_gain = 1.0;//_35._m294 // 强化效果
	uniform float u_lip_line_fix_curve_intensity = 0.6;//_35._m291 // 最终强度
	uniform vec3 u_lip_line_fix_color = vec3(0.5152, 0.17931, 0.17931);//_35._m290
group_uniforms;

/**
 * @brief 基于摄像机距离修复唇线
 */
float calculate_lip_line_fix_factor(float dist_to_cam, float vertex_color_g) {
	float fade_range = max(u_lip_line_end - u_lip_line_start, 0.01);
	float factor1 = (dist_to_cam < 2.0) ? 1.2 : 1.0;
	float factor2 = (dist_to_cam > 5.0) ? 0.8 : 1.0;

	bool is_before_fade = dist_to_cam < u_lip_line_start;
	float distance_factor  = clamp((dist_to_cam - u_lip_line_start) / fade_range, 0.0, 1.0);
	float raw_fade_factor  = is_before_fade ? 0.0 : distance_factor;

	float hardcoded_dist_mod  = (factor1 * factor2);
	float artist_tuned_strength  = (hardcoded_dist_mod - 1.0) * u_lip_line_fix_curve_shape  + 1.0;
	artist_tuned_strength  *= u_lip_line_fix_curve_gain;
	artist_tuned_strength  = max(artist_tuned_strength , 0.01);
	artist_tuned_strength  *= u_lip_line_fix_curve_intensity;
	artist_tuned_strength  = clamp(artist_tuned_strength , 0.0, 1.0);

	float effect_strength_factor = mix(0.04, artist_tuned_strength , raw_fade_factor);

	float artist_mask = (vertex_color_g < 0.95) ? vertex_color_g : 0.0;

	// 比较“效果强度”和一个随距离动态变化的“激活门槛”
	float activation_threshold  = artist_mask - (1.0 - raw_fade_factor);

	return (effect_strength_factor  < activation_threshold) ? 0.0 : 1.0;
}

group_uniforms u_eye;
	uniform vec3 u_eye_base_shadow_color =vec3(1.0,1.0,1.0); // _35._m281
	uniform vec3 u_eye_blend_tint=vec3(1.0,1.0,1.0); // _35._m19
group_uniforms;

group_uniforms u_emission_params;
	uniform float u_emission_threshold = 0.8; // _35._m30
	uniform float u_emission_intensity = 0.6; // _35._m31


	uniform bool u_use_global_interior_line_darken_factor = false;
	global uniform float g_u_interior_line_darken_factor = 0.0;
group_uniforms;

/**
 * @brief 计算自发光效果强度
 */
float calculate_emission_factor(float color_a) {
	bool is_above_threshold = color_a > u_emission_threshold;
	float emission_threshold_inv = max(1.0 - u_emission_threshold, 0.001);
	float emission_factor = (color_a - u_emission_threshold) / emission_threshold_inv;
	emission_factor = mix(0.0, emission_factor, float(is_above_threshold)); // _150
	return emission_factor * u_emission_intensity;
}

group_uniforms u_rim_light_params;
	uniform vec3 u_rim_light_color = vec3(0.0,0.0,0.0); //_35._m75
	uniform float u_rim_light_color_intensity = 1.0; //_35._m77
	uniform float u_rim_light_threshold = 1.0;//_35._m76.x // 从哪里开始出现边缘光，越大说明视角越倾斜才会有边缘光
	uniform float u_rim_light_feather = 1.0;//_35._m76.y // 边缘光过度区域的范围
group_uniforms;

/**
 * @brief 计算边缘光颜色
 */
vec3 calculate_rim_light_color(float NdotV) {
	float rim_light_factor = 1.0 - abs(NdotV);
	rim_light_factor = (rim_light_factor - u_rim_light_threshold) / u_rim_light_feather;
	rim_light_factor = clamp(rim_light_factor, 0.0, 1.0);

	// 3. 计算最终颜色
	vec3 final_rim_right_color = u_rim_light_color.rgb * u_rim_light_color_intensity * rim_light_factor;
	final_rim_right_color = max(final_rim_right_color, vec3(0.0));
	return final_rim_right_color;
}

/**
 * @brief 面部彩妆与色调混合
 */
group_uniforms u_face_makeup_params;
	uniform float u_face_blush_threshold = 0.8; //_35._m270
	uniform float u_face_blush_intensity_1 = 2.0; //_35._m271
	uniform float u_face_blush_intensity_2 = 0.0; //_35._m272
	uniform vec3 u_face_color_adjust_base = vec3(0.00246, 0.00553, 0.13024); // _35._m277
	uniform vec3 u_face_color_adjust_overlay = vec3(0.22195, 0.22934, 0.26033); // _35._m278
	uniform vec3 u_face_base_makeup_color = vec3(0.95761, 0.43328, 0.43328); // _35._m275
	uniform float u_face_lip_intensity = 0.0; //_35._m273
	uniform vec3 u_face_lip_color = vec3(0.00246, 0.00553, 0.13024); // _35._m276
	uniform float u_face_gradient_intensity = 0.0; //_35._m274
group_uniforms;

vec3 calculate_face_makeup_and_tone(vec3 face_mask, float baked_mask) {
	float blush_boost_factor = 0.0;
	bool has_blush = face_mask.r > u_face_blush_threshold;

	float above_threshold_range = max(1.0 - u_face_blush_threshold, 0.001);
	float normalized_blush_value = (face_mask.r - u_face_blush_threshold) / above_threshold_range;
	blush_boost_factor = normalized_blush_value * u_face_blush_intensity_1 * u_face_blush_intensity_2;
	blush_boost_factor = has_blush?blush_boost_factor:0.0; // 这是有腮红的区域的比例

	bool baked_mask_switch = baked_mask > 0.0;
	vec3 base_tone_color = mix(u_face_color_adjust_base, u_face_color_adjust_overlay, float(baked_mask_switch));

	float below_threshold_blush_ramp = has_blush?1.0:face_mask.r/max(u_face_blush_threshold, 0.001); // 这是没腮红的线色区域

	below_threshold_blush_ramp *= u_face_blush_intensity_2;
	vec3 makeup_color = mix(vec3(1.0), u_face_base_makeup_color, below_threshold_blush_ramp);

	// 混合唇色
	float lip_factor = face_mask.g * u_face_lip_intensity;
	makeup_color = mix(makeup_color, u_face_lip_color, lip_factor);

	// 混合全脸渐变
	float gradient_factor = face_mask.b * u_face_gradient_intensity;
	vec3 final_blended_color = mix(makeup_color, base_tone_color, gradient_factor);

	final_blended_color += blush_boost_factor;
	return final_blended_color;
}

group_uniforms u_sdf_params;
	uniform bool u_sdf_invert = false; //_35._m279 // 翻转sdf的黑白定义
	uniform float u_sdf_feather_radius = 0.0001; // _35._m307
group_uniforms;

float calculate_sdf_factor(float sdf_value_from_lut, float angle) {
	return npr_threshold(sdf_value_from_lut, angle, u_sdf_feather_radius);
}

group_uniforms u_light_control_params;
	uniform float u_top_light_remap_min = 0.85; // _35._m282
	uniform float u_top_light_remap_max = 1.0; // _35._m283
	uniform vec3 u_tint_lighting_color_A = vec3(0.89603, 0.72296, 0.67471); // _35._m280
	uniform vec3 u_tint_lighting_color_B = vec3(0.89603, 0.77638, 0.85874); // _35._m357
	uniform vec3 u_tint_lighting_weight_color = vec3(0.0,0.0,0.0); //_23._m5
	uniform float u_tint_lighting_weight_factor = 0.0; // _23._m8.z
group_uniforms;
float calculate_lighting_control_factor(float baked_mask, float top_light_factor, vec2 baked_mask_switch) {
	bool is_in_mid_baked = baked_mask > 0.1 && baked_mask < 0.8;
	vec3 mid_range_constants = mix(vec3(0.0), vec3(1.0, -1.0, 0.5), bvec3(is_in_mid_baked));
	float baked_mask_combo_factor = baked_mask_switch.x + mid_range_constants.y + mid_range_constants.z;

	float remap_min = u_top_light_remap_min - 0.36;
	float remap_range = u_top_light_remap_max - remap_min;
	float value_in_range = top_light_factor - remap_min;

	float t = value_in_range / npr_nonzero(remap_range);
	float remapped_top_light_factor = smoothstep(0.0,1.0,t);

	float temp_mix  = (baked_mask_combo_factor  * remapped_top_light_factor) - 1.0;
	float final_factor   = (baked_mask_combo_factor  * temp_mix) + 1.0;
	return final_factor;
}

vec3 calculate_lighting_control_color(float light_factor, float light_control_factor, vec2 baked_mask_switch) {
	vec3 base_tint_color = mix(u_tint_lighting_color_A, u_tint_lighting_color_B, baked_mask_switch.x);
	vec3 weight_color = mix(vec3(1.0), u_tint_lighting_weight_color, u_tint_lighting_weight_factor);
	vec3 final_base_tint = base_tint_color * weight_color;
	final_base_tint = mix(final_base_tint, vec3(1.0), light_factor * light_control_factor);
	return final_base_tint;
}

// 渐变调整光的颜色
group_uniforms u_light_grading_params;
	global uniform bool g_u_light_grading_enable = true; // 开启光渐变功能
	global uniform vec4 g_u_light_grading_highlight_color = vec4(1.0,1.0,1.0,0.5);//_39._m82
	global uniform vec4 g_u_light_grading_shadow_color = vec4(1.0,1.0,1.0,0.5);//_39._m83
	global uniform float g_u_light_grading_intensity = 0.0; // _39._m86

	global uniform float g_u_light_grading_remap_max = 1.0; //_39._m89
	global uniform float g_u_light_grading_remap_mid = 0.55; //_39._m88
	global uniform float g_u_light_grading_remap_min = 0.0;//_39._m87
group_uniforms;

vec3 apply_lighting_color_grading(
	float light_factor, float light_control_factor, vec2 sdf_blend_switch, vec3 light_control_color
) {
	vec3 curve_highlight_color = g_u_light_grading_highlight_color.rgb * g_u_light_grading_highlight_color.a;
	vec3 curve_highlight_color_doubled = curve_highlight_color * 2.0;
	vec3 curve_shadow_color = g_u_light_grading_shadow_color.rgb * g_u_light_grading_shadow_color.a;
	vec3 curve_shadow_color_doubled = curve_shadow_color * 2.0;

	vec3 mixed_curve_colors = mix(curve_shadow_color_doubled, curve_highlight_color_doubled, light_control_factor);
	vec3 curve_base = mix(vec3(1.0), mixed_curve_colors, g_u_light_grading_intensity);

	// 是否是亮部
	bool is_lit = light_factor>=max(u_character_local_main_light_position.w, 0.01);

	// 亮部颜色
	float remap_range_A = g_u_light_grading_remap_max - g_u_light_grading_remap_mid;
	vec3 remapped_bright = (light_control_color - g_u_light_grading_remap_mid) / npr_nonzero(remap_range_A);
	remapped_bright = remapped_bright*0.5 + 0.5;
	remapped_bright = clamp(remapped_bright, 0.0, 1.0);
	vec3 final_curve_bright = mix(curve_highlight_color_doubled, curve_base, sdf_blend_switch.x);
	vec3 graded_bright = remapped_bright * final_curve_bright;

	float remap_range_B = g_u_light_grading_remap_mid - g_u_light_grading_remap_min;
	vec3 remapped_dark = (g_u_light_grading_remap_mid - light_control_color) / npr_nonzero(remap_range_B);
	remapped_dark =  0.5 - remapped_dark*0.5;
	remapped_dark = clamp(remapped_dark, 0.0, 1.0);
	vec3 final_curve_dark = mix(curve_shadow_color_doubled, curve_base, sdf_blend_switch.x);
	vec3 graded_dark = remapped_dark * final_curve_dark;

	vec3 graded_color = mix(graded_dark, graded_bright, float(is_lit));

	graded_color = mix(light_control_color, graded_color, float(g_u_light_grading_enable && !u_npr_studio_enabled));
	return graded_color;
}

group_uniforms u_luminance_grading_params;
	uniform float u_eyeball_effect_intensity = 0.0; // _35._m352
	uniform vec3 u_eyeball_effect_tint = vec3(1.0,1.0,1.0); // _35._m354
group_uniforms;

/**
 * @brief 根据亮度调整眼球颜色
 */
vec3 apply_eyeball_effect(vec3 shaded_color, float baked_mask) {
	// Disabled on the shipped face material. The original final clamp still applies.
	if (u_eyeball_effect_intensity <= 0.0) {
		return clamp(shaded_color, vec3(0.0), vec3(1.0));
	}
	// 1. 计算输入颜色的亮度
	float luminance = dot(shaded_color, vec3(0.3, 0.59, 0.11));
	bool is_eyeball_area  = baked_mask > 0.1 && baked_mask < 0.8;
	float eyeball_effect_factor = float(is_eyeball_area ) * u_eyeball_effect_intensity;
	eyeball_effect_factor = clamp(eyeball_effect_factor, 0.0, 1.0);

	vec3 lum_tint = luminance * u_eyeball_effect_tint.rgb;
	vec3 color_a = mix(shaded_color, lum_tint, eyeball_effect_factor);
	vec3 color_b = lum_tint * luminance + color_a;
	float lum_mult = luminance * 0.5 + 1.0;
	vec3 color_c = color_b * lum_mult - shaded_color;
	vec3 last_color = mix(shaded_color, shaded_color + color_c, eyeball_effect_factor);
	last_color = clamp(last_color, vec3(0.0), vec3(1.0));
	return last_color;
}

/**
 * @brief 眼球视觉特效 (VFX)
 */
group_uniforms u_eyeball_vfx_params;
	uniform bool u_procedural_fx_enable = false; // _35._m284
	uniform sampler2D u_eyeball_vfx_pattern_texture: source_color, filter_linear_mipmap, repeat_enable;
	// 特效图案的UV变换 (缩放与偏移)
	uniform vec4 u_eyeball_vfx_uv_transform  = vec4(1.0,1.0,0.0,0.0); // _35._m285
	// 特效动画参数 (xy:旋转中心, zw:旋转速度)
	uniform vec4 u_eyeball_vfx_anim_params  = vec4(0.0,0.0,0.0,0.0); // _35._m286
	// 特效混合的目标颜色 A
	uniform vec4 u_eyeball_vfx_color_a  = vec4(1.0,1.0,1.0,1.0); // _35._m287
	// 特效混合的目标颜色 B
	uniform vec4 u_eyeball_vfx_color_b  = vec4(1.0,1.0,1.0,1.0); // _35._m288
	uniform float u_eyeball_vfx_intensity  = 1.0; // _35._m289
group_uniforms;

// 为眼球颜色叠加一层动态的、由贴图驱动的视觉特效
vec3 apply_eyeball_vfx(vec3 base_color, vec2 uv, float time, float baked_mask, vec2 sdf_blend_switch) {
	if (!u_procedural_fx_enable) {
		return base_color;
	}
	bool is_eyeball_area = baked_mask > 0.1 && baked_mask < 0.8;
	float eyeball_area_factor   = float(is_eyeball_area);

	// 1. 生成两套动态UV，用作采样“种子”
	vec2 transformed_base_uv = uv.yx * u_eyeball_vfx_uv_transform.yx + u_eyeball_vfx_uv_transform.wz;
	vec2 angles = time * u_eyeball_vfx_anim_params.zw;

	vec2 center_offset = transformed_base_uv - u_eyeball_vfx_anim_params.yx;

	mat2 rot_A = mat2(vec2(cos(angles.x), -sin(angles.x)), vec2(sin(angles.x), cos(angles.x)));
	vec2 rotated_uv_A = rot_A * center_offset + u_eyeball_vfx_anim_params.xy;

	mat2 rot_B = mat2(vec2(cos(angles.y), -sin(angles.y)), vec2(sin(angles.y), cos(angles.y)));
	vec2 rotated_uv_B = rot_B * center_offset + u_eyeball_vfx_anim_params.xy;

	float pattern_A_value  = texture(u_eyeball_vfx_pattern_texture, rotated_uv_A).r;
	float pattern_B_value  = texture(u_eyeball_vfx_pattern_texture, rotated_uv_B).g;

	float mix_factor_B  = pattern_B_value * u_eyeball_vfx_color_b.a * eyeball_area_factor;
	vec3 color_with_overlay_B  = mix(base_color, u_eyeball_vfx_color_b.rgb, mix_factor_B );

	float mix_factor_A  = pattern_A_value   * u_eyeball_vfx_color_a.a * eyeball_area_factor;
	vec3 final_color  = mix(color_with_overlay_B , u_eyeball_vfx_color_a.rgb, mix_factor_A );

	float final_fx_intensity_factor  = sdf_blend_switch.x + eyeball_area_factor ;
	final_fx_intensity_factor  = mix(1, u_eyeball_vfx_intensity, final_fx_intensity_factor );
	return final_color * final_fx_intensity_factor ;
}
