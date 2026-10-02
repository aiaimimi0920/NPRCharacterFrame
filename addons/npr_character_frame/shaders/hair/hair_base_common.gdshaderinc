// Shared implementation. Entry shaders own render/stencil state and the eye variant.
#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_style.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_lighting.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_diagnostics.gdshaderinc"

#if defined(HAS_MATERIAL_POST_LIGHT) && !defined(NPR_HAIR_LEGACY_REFERENCE)
#define NPR_HAIR_POST_LIGHT
varying float npr_hair_post_active;
varying vec3 npr_hair_input_ramp;
varying vec4 npr_hair_albedo_skin;
varying float npr_hair_contrast_gain;
varying float npr_hair_soft_attenuation;
varying vec3 npr_hair_normal_ws;
varying vec3 npr_hair_rim_gain;
varying vec3 npr_hair_late_specular;
varying float npr_hair_silhouette;
varying vec3 npr_hair_edge;
#endif

// 启用双通道隐藏部件
// 开启后，在顶点着色器中会根据顶点色的gr两个通道共同判断是否需要隐藏部件，反之只通过g通道判断
#define ENABLE_TWO_PART_HIDE

// 启用各向异性光照，主要是给会反光的比如眼镜使用
//#define ENABLE_ANISOTROPIC

// ===================================================================
// >> Uniforms & Varyings <<
// ===================================================================
// --- Vertex ---

const vec4 C_POSITION_CLIPPED = vec4(-99.0, -99.0, -99.0, 1.0);

group_uniforms u_vertex_params;
	// 位掩码，用于按位与顶点色中的ID，决定显示哪些部件 (例如，值为3 (二进制11) 将显示ID为1和2的部件)
	instance uniform int u_show_part_id : hint_range(0, 255) = 255; // _25._m13
	// 是否隐藏角色部件 (对应顶点色 G 通道)
	instance uniform bool u_hide_character_parts = false; // _25._m12
#ifdef ENABLE_TWO_PART_HIDE
	// 是否隐藏NPC部件 (对应顶点色 R 通道, 仅当 ENABLE_TWO_PART_HIDE 开启时有效)
	uniform bool u_hide_npc_parts = false;
#endif
	// 主UV的缩放
	uniform vec2 u_uv1_scale = vec2(1.0,1.0); // _25._m16.xy
	// 主UV的偏移
	uniform vec2 u_uv1_offset = vec2(0.0,0.0); // _25._m16.zw
	// 顶点色通道掩码，用于在顶点阶段选择性地保留或替换顶点色的RGBA通道
	uniform ivec4 u_channel_mask = ivec4(1); // _25._m14
	// 全局的特殊矩阵，可能用于类似直播小框的计算
	global uniform mat4 g_u_special_ws_to_cs;
	// 指示当前是否使用特殊矩阵计算cs
	instance uniform bool u_use_special_transform = false; // _20._m13
group_uniforms;

group_uniforms u_base_params;
	uniform sampler2D u_texture_base_map : source_color, filter_linear_mipmap, repeat_enable;
	uniform vec4 u_base_color : source_color = vec4(1.0,1.0,1.0,1.0); // _35._m19
	uniform vec4 u_back_color : source_color = vec4(1.0,1.0,1.0,1.0);
	uniform sampler2D u_texture_ilm_map : filter_linear_mipmap, repeat_enable;
	uniform sampler2D u_texture_lut : source_color, filter_linear_mipmap, repeat_enable;
	uniform bool u_is_monster = false; // _35._m1
		instance uniform vec4 u_custom_main_light_dir : instance_index(4) = vec4(0.0,0.0,0.0,0.0); // _35._m18
	global uniform vec4 g_u_monster_main_light_dir = vec4(0.2706, 0.70711, 0.65328, 0.0); // _39._m3
	global uniform vec4 g_u_character_main_light_position = vec4(-0.73723, 0.43589, -0.51623, 0.00); // _23._m0
	global uniform bool g_u_character_disable_main_light = false; // _39._m57
		instance uniform bool u_character_disable_local_main_light : instance_index(5) = false; // _23._m11
		instance uniform vec4 u_character_local_main_light_position : instance_index(6) = vec4(-0.73723, 0.43589, -0.51623, 0.00); // _15._m11
group_uniforms;


// --- Varyings ---
varying vec4 v_position_ndc;
varying vec3 v_position_ws;
varying vec3 v_view_dir_ws;
varying vec3 v_normal_ws;
varying vec3 v_tangent_ws;
varying vec3 v_binormal_ws;
varying float v_hair_sheen_factor;
varying float v_hair_side_factor;
uniform vec3 u_npr_hair_sheen_axis = vec3(0.2759999930858612060546875, 0.961000025272369384765625, 0.0);
uniform vec3 u_npr_hair_side_axis = vec3(1.0, 0.0, 0.0);

// ===================================================================
// >> Vertex Shader <<
// ===================================================================



// 顶点着色器 - 部件显隐与掩码处理
bool get_render_condition(vec4 color) {
#ifdef ENABLE_TWO_PART_HIDE
	return npr_part_visible(color, u_show_part_id, u_hide_character_parts, u_hide_npc_parts);
#else
	return npr_part_visible(color, u_show_part_id, u_hide_character_parts, false);
#endif
}


void vertex() {
	npr_depth_uv_offset = npr_depth_projection_offset(PROJECTION_MATRIX, NPR_DEPTH_PROJECTION);
	npr_depth_view_slot = u_use_special_transform ? 0.0 : npr_select_depth_view(INV_VIEW_MATRIX, NPR_DEPTH_PROJECTION, VIEWPORT_SIZE, CAMERA_VISIBLE_LAYERS);
	// 模型空间 -> 世界空间 (传递给FS)
	v_position_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 模型空间 -> clip空间
	vec4 position_cs = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);

	// 世界空间 -> 特殊裁剪空间（极有可能是使用一个虚拟摄像机将模型直接渲染到合适的位置然后叠加，用途可能是直播小框）
	vec4 special_cs = g_u_special_ws_to_cs * vec4(v_position_ws, 1.0);

	// 根据是否为特殊计算，使用不同的cs
	position_cs = mix(position_cs, special_cs, bvec4(u_use_special_transform));

	// 部件显隐与顶点掩码处理
	bool render_condition = get_render_condition(COLOR);
	POSITION = mix(C_POSITION_CLIPPED, position_cs, float(render_condition));

	UV = UV * u_uv1_scale.xy + u_uv1_offset.xy;
	UV2 = UV2;

	COLOR = COLOR;

	// NDC坐标, 不是常规意义上的ndc：https://zhuanlan.zhihu.com/p/686166007 , 因为是否需要翻转在引擎层已经处理好了，所以这里不做翻转乘积操作
	v_position_ndc.xy = (position_cs.xy + position_cs.w) * 0.5;
	v_position_ndc.zw = position_cs.zw;

	// 计算并传递世界空间的视线向量，顶点到摄像机的方向向量, 其实这里隐含的一个定义是，在渲染时使用原始的模型位置渲染光照，然后通过反射矩阵将其镜像到需要显示的镜面。
	v_view_dir_ws = CAMERA_POSITION_WORLD - v_position_ws;

	v_normal_ws = normalize(MODEL_NORMAL_MATRIX * NORMAL); // model space -> world space

	vec3 view_dir_ms = transpose(MODEL_NORMAL_MATRIX)*v_view_dir_ws;
	vec3 view_ms = normalize(view_dir_ms);

		v_hair_sheen_factor = dot(u_npr_hair_sheen_axis, view_ms);
		v_hair_side_factor = dot(u_npr_hair_side_axis, view_ms);

			vec3 tangent_ms = TANGENT;
			vec3 binormal_ms = BINORMAL;
		NORMAL = normalize(MODEL_NORMAL_MATRIX * NORMAL);
			TANGENT = normalize(MODEL_NORMAL_MATRIX * tangent_ms);
			BINORMAL = normalize(MODEL_NORMAL_MATRIX * binormal_ms);
		v_tangent_ws = TANGENT;
		v_binormal_ws = BINORMAL;
	// POSITION owns rasterization, but skip_vertex_transform also leaves VERTEX
	// in model space. Native CSM and local-light attenuation consume view-space
	// VERTEX independently of POSITION; supplying only clip coordinates is not enough.
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// ===================================================================
// >> Fragment Shader <<
// ===================================================================

group_uniforms u_diffuse_ramp_params;
	uniform sampler2D u_texture_diffuse_ramp : source_color, filter_linear, repeat_disable;
	uniform sampler2D u_texture_diffuse_cool_ramp : source_color, filter_linear, repeat_disable;
	global uniform float g_u_character_toon_ramp_mode = 0.2; // _39._m56
	uniform float u_diffuse_ramp_shadow_strength = 0.1; // _23._m8.z
	uniform vec4 u_diffuse_ramp_skin_shadow_tint:source_color =  vec4(0.0,0.0,0.0,0.0); // _23._m5
	uniform vec4 u_diffuse_ramp_level_shadow_tint:source_color =  vec4(0.0,0.0,0.0,0.0); // _23._m4

	uniform float u_shadow_ramp = 1.0; // _35._m36
group_uniforms;
// diffuse_ramp_uv 计算
vec2 calculate_diffuse_ramp_uv(vec4 ilm, vec4 vertex_color, vec3 normal_ws, vec3 light_dir_ws, float shadow_factor,float softened_light_atten, float ramp_level) {
	vertex_color = vec4(1.0,1.0,1.0,1.0); // 这段代码是因为头发不使用顶点色
	float baked_occlusion_factor = ilm.y * 2.0 * vertex_color.r;
	float raw_ndotl = dot(normal_ws, light_dir_ws);

	float base_light_intensity  = clamp(raw_ndotl*0.5 + 0.5,0.0,1.0);
	base_light_intensity  = 2.0 * base_light_intensity  * baked_occlusion_factor;

	// --- 2. 融合两种不同风味的、经过材质调节的光照因子 ---
	// 首先应用“提亮型”因子，它会更积极地减弱阴影
	float light_after_lifted_atten  = base_light_intensity  * shadow_factor;

	// 然后，与“柔化型”因子比较，并取两者中更暗的结果，以保留最强的阴影表现

	float resolved_light_factor  = min(light_after_lifted_atten, softened_light_atten);

	float resolved_light_factor_2 = max(resolved_light_factor , 0.001);

	float ramp_base_light  = resolved_light_factor_2  * 0.85 + 0.15;

	float baked_light_override  = (shadow_factor < 0.1) ? min(ilm.y * vertex_color.x, 0.8) : 1.0;

	vec2 diffuse_ramp_uv;
	float ramp_u_coord  = (u_shadow_ramp < resolved_light_factor ) ? 0.99 : ramp_base_light ;
	diffuse_ramp_uv.x = ramp_u_coord  * baked_light_override ;
	diffuse_ramp_uv.y = ((ramp_level * 2.0) + 1.0) * 0.0625;
	return diffuse_ramp_uv;
}

// diffuse_ramp 计算，基础色计算
vec3 calculate_diffuse_ramp_color(vec2 diffuse_ramp_uv, bool is_skin, out vec3 sampled_ramp) {
	vec3 ramp = texture(u_texture_diffuse_ramp, diffuse_ramp_uv).rgb;
	vec3 ramp_cool = texture(u_texture_diffuse_cool_ramp, diffuse_ramp_uv).rgb;

	float ramp_mode = npr_ramp_mix(g_u_character_toon_ramp_mode);
	vec3 ramp_color = mix(ramp, ramp_cool, ramp_mode);
	sampled_ramp = ramp_color;

	float diffuse_shadow_mask = (1.0 - smoothstep(0.0, 1.0, (diffuse_ramp_uv.x - 0.8)  * 10.0)) * u_diffuse_ramp_shadow_strength;

	vec3 shaded_skin_color = ramp_color * mix(vec3(1.0), u_diffuse_ramp_skin_shadow_tint.rgb, diffuse_shadow_mask);
	vec3 shaded_level_color = ramp_color * mix(vec3(1.0), u_diffuse_ramp_level_shadow_tint.rgb, diffuse_shadow_mask);
	return mix(shaded_level_color, shaded_skin_color, float(is_skin));
}
//

// 皮肤亮部颜色、皮肤暗部颜色、常规部位的亮部颜色、常规部位的暗部颜色。 通过skinMask插值即可，可以分别对亮部暗部调色。
// 色调调节
group_uniforms u_level_params;
	uniform bool g_u_level_adjust_on = false;
	uniform vec4 u_skin_light_color:source_color =  vec4(1.0,1.0,1.0, 0.5); // _39._m82
	uniform vec4 u_level_light_color:source_color =  vec4(1.0,1.0,1.0, 0.5); // _39._m84
	uniform vec4 u_skin_shadow_color:source_color = vec4(1.0,1.0,1.0, 0.5); // _39._m83
	uniform vec4 u_level_shadow_color:source_color = vec4(1.0,1.0,1.0, 0.5); // _39._m85

	uniform float u_level_white_point = 1.0; // _39._m89
	uniform float u_level_black_point = 0.0; // _39._m87
	uniform float u_level_mid_point = 0.55; // _39._m88
group_uniforms;

// 色阶重映射
vec3 apply_tonal_mapping(vec3 last_color, bool is_skin){
	if (!g_u_level_adjust_on) {
		return last_color;
	}
	float base_color_luminance = dot(last_color, vec3(1.0));
	bool is_overexposed = (base_color_luminance > 2.9);

	vec3 skin_light_color = u_skin_light_color.xyz * u_skin_light_color.w * 2.0; // 皮肤亮部颜色
	vec3 level_light_color = u_level_light_color.xyz * u_level_light_color.w * 2.0; // 常规部位亮部颜色
	vec3 light_color = mix(level_light_color, skin_light_color, bvec3(is_skin)); // 亮部颜色

	vec3 skin_shadow_color = u_skin_shadow_color.xyz * u_skin_shadow_color.w * 2.0; // 皮肤暗部颜色
	vec3 level_shadow_color = u_level_shadow_color.xyz * u_level_shadow_color.w * 2.0; // 常规部位暗部颜色
	vec3 shadow_color = mix(level_shadow_color, skin_shadow_color, bvec3(is_skin)); // 暗部颜色

	vec3 remapped_light = (last_color - u_level_mid_point) / npr_nonzero(u_level_white_point - u_level_mid_point);
	vec3 light_mask = clamp(remapped_light * 0.5 + 0.5, 0.0, 1.0);

	vec3 remapped_shadow = (u_level_mid_point - last_color) / npr_nonzero(u_level_mid_point - u_level_black_point);
	vec3 shadow_mask = clamp(0.5 - remapped_shadow * 0.5, 0.0, 1.0);

	vec3 leveled_light_color = light_color * light_mask;
	vec3 leveled_shadow_color = shadow_color * shadow_mask;

	vec3 leveled_color = is_overexposed ? leveled_light_color : leveled_shadow_color;
	leveled_color = g_u_level_adjust_on?leveled_color:last_color; // 如果没有开启亮度自动调节，则直接使用原色
	return leveled_color;
}
//

// 对比度调节
group_uniforms u_contrast_params;
	uniform bool u_contrast_adjust_on = false; // _35._m37
	uniform float u_contrast_strength = 0.0; // _35._m38
	// Opt-in Godot key-shadow input when the captured CSM atlas is disabled.
	uniform bool u_npr_native_shadow_contrast = false;
group_uniforms;

vec3 apply_local_contrast(vec3 last_color, float shadow_factor, out float color_gain){
	// 对比度
	float contrast_blend_factor  = smoothstep(0.0, 1.0, shadow_factor * 6.666);
	contrast_blend_factor  = mix(u_contrast_strength + 1.0, 1.0, contrast_blend_factor );
	color_gain = u_contrast_adjust_on ? contrast_blend_factor : 1.0;

	last_color = u_contrast_adjust_on?(last_color * contrast_blend_factor):last_color;
	return last_color;
}
//


////
////

group_uniforms u_rim_shadow_light_params;
	// Body
	uniform vec4 u_rim_shadow_color: source_color = vec4(0.0,0.0,0.0,1.0); // _35._m67
	uniform float u_rim_shadow_width = 0.00; // _35._m66
	uniform float u_rim_shadow_feather = 0.99; // _35._m68
	global uniform vec4 g_u_rim_shadow_color =  vec4(1.0,1.0,1.0,0.50196); // _39._m63
	global uniform float g_u_rim_shadow_intensity = 1.0; // _39._m64

	// Common
	uniform vec3 u_rim_shadow_offset = vec3(0.3,0.3,0.2); // _35._m82
	uniform float u_rim_shadow_ct = 1.0; // _35._m79
	uniform float u_rim_shadow_intensity = 1.0; // _35._m80
group_uniforms;


vec3 calculate_rim_shadow_light(vec3 view_dir_vs, vec3 normal_vs, float ramp_level) {
	vec3 rim_shadow_color;
	float rim_shadow_width, rim_shadow_feather;

#ifdef USE_MATERIAL_VALUES_LUT
	rim_shadow_color = texelFetch(u_texture_lut, ivec2(int(ramp_level), 5), 0).xyz;
	vec2 params = texelFetch(u_texture_lut, ivec2(int(ramp_level), 6), 0).xy;
	rim_shadow_width = params.x;
	rim_shadow_feather = params.y;
#else
	rim_shadow_color = u_rim_shadow_color.rgb;
	rim_shadow_width = u_rim_shadow_width;
	rim_shadow_feather = u_rim_shadow_feather;
#endif

	vec3 view_dir_vs_offset = normalize(view_dir_vs - u_rim_shadow_offset.xyz);
	float rim = dot(normal_vs, view_dir_vs_offset);
	rim = clamp(rim, 0.0, 1.0);

	rim_shadow_color = rim_shadow_color * g_u_rim_shadow_color.xyz * g_u_rim_shadow_color.w;

	float rim_shadow = clamp(pow(max(1.0 - rim, 0.001), u_rim_shadow_ct) * rim_shadow_width, 0.0, 1.0);
	rim_shadow = smoothstep(0.0, 1.0, (rim_shadow - rim_shadow_feather) / npr_nonzero(1.0 - rim_shadow_feather));

	rim_shadow =  rim_shadow * (u_rim_shadow_intensity * g_u_rim_shadow_intensity * 0.25);
	return mix(vec3(1.0), rim_shadow_color * 2.0, rim_shadow);
}
////
////

////
////
group_uniforms u_accent_params;
	uniform vec3  u_accent_light_pos = vec3(20.0, 10.0, 40.0); //_23._m7  // 强调光源的世界坐标
	uniform vec3  u_accent_light_direction = vec3(0.5, 0.5, 0.5); //_23._m6 // 强调光源的主要方向

	uniform float u_accent_rim_spot_mix_factor = 0.5; //_23._m2.w // 边缘光与聚光灯的混合因子
	uniform vec3  u_accent_split_tone_tint = vec3(0.2,0.4,0.5); //_23._m2.xyz // 用于分离色调的基准色

	uniform float u_accent_split_tone_strength = 0.5; //_23._m8.x // 分离色调效果的基础强度
	uniform float u_accent_additive_highlight_strength = 0.5; //_23._m8.y // 附加高光效果的基础强度
	uniform vec3  u_accent_additive_highlight_color = vec3(0.5,0.7,0.2); //_23._m3 // 附加高光的颜色
group_uniforms;

// 计算风格化的强调光
vec3 calculate_accent_light(vec3 current_color, vec3 world_pos, vec3 world_normal, float softened_light_atten) {
	// 1a. 计算聚光灯因子 (Spotlight Factor)
	// 从光源位置指向当前像素的方向
	vec3 light_vec_to_pixel = normalize(world_pos - u_accent_light_pos.xyz);
	// 通过与光源主方向的点积，计算聚光灯衰减 (越偏离中心，值越小)
	float spotlight_dot = dot(light_vec_to_pixel, u_accent_light_direction.xyz);
	// 将点积从 [-1, 1] 范围映射到 [0, 1]
	float spotlight_factor = (spotlight_dot + 1.0) * 0.5;

	// 1b. 计算边缘光因子 (Rim Light Factor)
	// 使用表面法线和光源主方向计算点积，作为边缘光的基础
	float rim_dot = dot(world_normal, u_accent_light_direction.xyz);
	// 通过偏移和缩放来调整光照的渐变和范围，这是一种艺术化处理
	float remapped_rim_dot = (rim_dot + 0.5) * 0.666;
	// 使用 smoothstep 创建平滑的边缘光效果
	float rim_factor = smoothstep(0.0, 1.0, remapped_rim_dot);


	// 1c. 混合两种因子并应用总开关
	// 根据 u_rim_spot_mix_factor 在边缘光和聚光灯效果之间插值
	float combined_light_influence = mix(rim_factor, spotlight_factor, u_accent_rim_spot_mix_factor);
	combined_light_influence *= (npr_main_disabled(g_u_character_disable_main_light) ? 0.0 : 1.0);

	// 使用光照影响权重，分别计算分离色调和附加高光的实际应用强度
	float split_tone_blend_amount = combined_light_influence * u_accent_split_tone_strength;
	float additive_highlight_amount = combined_light_influence * u_accent_additive_highlight_strength;


	// 判断每个颜色通道是属于暗部 (< 0.5) 还是亮部 (>= 0.5)
	bvec3 is_dark = lessThan(current_color, vec3(0.5));

	// 暗部处理: 使用独立的 u_split_tone_tint 作为色调基准色
	vec3 dark_path_color = (current_color * 2.0) * u_accent_split_tone_tint;

	// 亮部处理: 同样使用 u_split_tone_tint 来计算
	vec3 bright_path_color = vec3(1.0) - ((vec3(1.0) - current_color) * 2.0 * (vec3(1.0) - u_accent_split_tone_tint));


	// 根据 is_dark 的逐通道判断，合并暗部和亮部的处理结果
	vec3 split_toned_color = mix(bright_path_color, dark_path_color, is_dark);

	// 4a. 将分离色调效果应用到基色上
	// 光照越强的地方，分离色调的效果越明显
	vec3 color_with_split_tone = mix(current_color, split_toned_color, split_tone_blend_amount);

	// 4b. 叠加附加高光
	// 在上述结果的基础上，再叠加一层由光照驱动的纯色高光
	vec3 additive_highlight = additive_highlight_amount * u_accent_additive_highlight_color.xyz * softened_light_atten;
	return color_with_split_tone + additive_highlight;
}
////
////

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



#ifdef NPR_HAIR_OVER_EYE
group_uniforms u_sheen_params;
	uniform float u_hair_sheen_bias = 0.2;
	uniform float u_hair_sheen_intensity = 0.2;
group_uniforms;
#endif

// 启用双面渲染
// 开启后，将根据面的朝向(FRONT_FACING)选择UV/UV2和颜色，实现双面材质。
//#define ENABLE_TWO_SIDED_RENDERING

// Separate from u_hair_sheen_* (which still controls eye-area transparency).
uniform float u_hair_highlight_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 u_hair_highlight_color : source_color = vec4(0.86, 0.9, 1.0, 1.0);

group_uniforms u_npr_hair_extended;
uniform bool u_npr_hair_anisotropy_enabled = false;
uniform bool u_npr_hair_flow_enabled = false;
uniform sampler2D u_npr_hair_flow_map : filter_linear_mipmap, repeat_enable;
uniform float u_npr_hair_anisotropy_strengths[8];
uniform float u_npr_hair_anisotropy_roughness[8];
uniform float u_npr_hair_anisotropy_shifts[8];
uniform vec4 u_npr_hair_anisotropy_color : source_color = vec4(0.82, 0.9, 1.0, 1.0);
uniform float u_npr_hair_anisotropy_global_strength : hint_range(0.0, 1.0) = 1.0;
uniform float u_npr_hair_side_fade_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 u_npr_hair_side_fade_range = vec2(0.45, 0.9);
uniform int u_npr_hair_side_choose : hint_range(-1, 1) = 0;
uniform float u_npr_hair_silhouette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float u_npr_hair_silhouette_power : hint_range(0.25, 8.0) = 2.0;
uniform vec4 u_npr_hair_silhouette_tint : source_color = vec4(0.72, 0.75, 0.95, 1.0);
uniform sampler2D u_npr_hair_wetness_map : filter_linear, repeat_enable;
uniform float u_npr_hair_wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec4 u_npr_hair_wet_specular_color : source_color = vec4(0.72, 0.82, 0.96, 1.0);
uniform bool u_npr_emission_hue_enabled = false;
uniform float u_npr_emission_hues[8];
uniform float u_npr_secondary_emission_strengths[8];
uniform float u_npr_emission_hue_speed = 0.0;
group_uniforms;

vec3 hair_highlight(vec3 n, vec3 v, vec3 l, vec3 albedo, vec3 ilm) {
	vec3 half_sum = v + l;
	vec3 h = half_sum / max(length(half_sum), 0.0001);
	vec3 ribbon_dir = normalize(mix(h, v, 0.75));
	float ribbon_shape = pow(max(dot(n, ribbon_dir), 0.0), 8.0);
	float ribbon = npr_filtered_step(ribbon_shape - 0.5, 0.035);
	// This asset's B is almost entirely zero. Do not pretend it contains a lost
	// broad highlight mask: the R-masked view ribbon is an explicit art control.
	ribbon *= ilm.r * (1.0 - smoothstep(0.02, 0.2, ilm.b));
	float specular = pow(max(dot(n, h), 0.01), 10.0);
	float captured_shape = npr_filtered_step(specular - (1.0 - ilm.b), 0.02);
	captured_shape *= step(0.001, ilm.b);
	float lit_side = smoothstep(-0.05, 0.25, dot(n, l));
	return albedo * u_hair_highlight_color.rgb * u_hair_highlight_strength * (ribbon + 0.3 * captured_shape) * lit_side;
}

vec3 hair_anisotropic_highlight(vec3 n, vec3 v, vec3 l, vec3 t, vec3 b,
		vec2 uv, vec3 albedo, vec4 surface_fx, int material_slot) {
	if (!u_npr_hair_anisotropy_enabled) {
		return vec3(0.0);
	}
	vec2 flow = vec2(1.0, 0.0);
	if (u_npr_hair_flow_enabled) {
		flow = texture(u_npr_hair_flow_map, uv).rg * 2.0 - 1.0;
		float flow_length = length(flow);
		flow = flow_length > 0.0001 ? flow / flow_length : vec2(1.0, 0.0);
	}
	vec3 strand = normalize(t * flow.x + b * flow.y);
	strand = normalize(strand + n * u_npr_hair_anisotropy_shifts[material_slot]);
	vec3 half_sum = v + l;
	vec3 h = half_sum / max(length(half_sum), 0.0001);
	float tangent_half = clamp(dot(strand, h), -1.0, 1.0);
	float sin_tangent_half = sqrt(max(1.0 - tangent_half * tangent_half, 0.0));
	float roughness = max(u_npr_hair_anisotropy_roughness[material_slot], 0.01);
	float lobe = pow(sin_tangent_half, mix(96.0, 4.0, roughness));
	float lit_side = smoothstep(-0.05, 0.25, dot(n, l));
	float strength = surface_fx.r * u_npr_hair_anisotropy_strengths[material_slot]
		* u_npr_hair_anisotropy_global_strength;
	return albedo * u_npr_hair_anisotropy_color.rgb * lobe * lit_side * strength;
}

void fragment() {
	vec4 debug_color = vec4(-1.0,-1.0,-1.0, -1.0);
	vec4 screen_coord = FRAGCOORD;
	float one_over_w = 1.0 / screen_coord.w;

	// 翻转Y坐标以匹配常见纹理坐标系，原逻辑中没有，需要查看是否需要
	vec2 frag_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 frag_uv2 = vec2(UV2.x, 1.0 - UV2.y);

#ifdef ENABLE_TWO_SIDED_RENDERING
	vec4 albedo = texture(u_texture_base_map, FRONT_FACING ? frag_uv : frag_uv2);
	vec4 base_color = mix(u_back_color, u_base_color, bvec4(FRONT_FACING));
#else
	vec4 albedo = texture(u_texture_base_map, frag_uv);
	vec4 base_color = u_base_color;
#endif
	albedo = albedo * base_color;

#ifdef ENABLE_TWO_SIDED_RENDERING
	vec4 ilm = texture(u_texture_ilm_map, FRONT_FACING ? frag_uv : frag_uv2);
#else
	vec4 ilm = texture(u_texture_ilm_map, frag_uv);
#endif
	vec4 surface_fx = npr_surface_effects(frag_uv);
	if (!npr_visibility_keep(FRAGCOORD.xy)) {
		discard;
	}
	float dissolve_distance = npr_dissolve_signed_distance(frag_uv, v_position_ws, surface_fx.a);
	if (dissolve_distance < 0.0) {
		discard;
	}

	// Ramp level，考虑到可能会包含负数，所以做了这种复杂计算
	float ramp_level = floor(ilm.a * 8.0);
	bool is_non_negative = (ramp_level >= 0.0);
	float scale_param = is_non_negative ? 8.0 : -8.0;
	float step_param = is_non_negative ? 0.125 : -0.125;
	float fractional_base = ramp_level * step_param;
	float sawtooth_value = fract(fractional_base);
	ramp_level = sawtooth_value * scale_param;
	int material_slot = clamp(int(ramp_level), 0, 7);

	// Silver Wolf receives shadow attenuation from the native light() stage.
	float softened_light_atten = 1.0;
	float shadow_factor = 1.0;

	bool use_local_main_light = npr_main_disabled(g_u_character_disable_main_light) && !u_character_disable_local_main_light;
	vec3 main_light_dir = use_local_main_light ? u_character_local_main_light_position.xyz : g_u_character_main_light_position.xyz;
	vec3 light_dir_ws = mix(main_light_dir, u_custom_main_light_dir.xyz, u_custom_main_light_dir.w);
	light_dir_ws = u_is_monster? g_u_monster_main_light_dir.xyz : light_dir_ws;
	light_dir_ws = normalize(light_dir_ws);

	vec3 view_dir_ws = normalize(v_view_dir_ws);
	// 根据面朝向修正法线
	vec3 normal_ws = normalize(v_normal_ws);
	normal_ws = FRONT_FACING ? normal_ws : -normal_ws;

	vec3 normal_vs = (VIEW_MATRIX*vec4(normal_ws,0.0)).xyz;
	vec3 view_dir_vs = (VIEW_MATRIX*vec4(view_dir_ws,0.0)).xyz;

	vec2 diffuse_ramp_uv = calculate_diffuse_ramp_uv(ilm, COLOR, normal_ws, light_dir_ws, shadow_factor, softened_light_atten, ramp_level);
	bool is_skin = roundEven(ramp_level) == 0.0; // 判断是否是皮肤
	vec3 sampled_ramp;
	vec3 diffuse_ramp_color = calculate_diffuse_ramp_color(diffuse_ramp_uv, is_skin, sampled_ramp);
	npr_current_ramp = sampled_ramp;
	npr_ramp_uv_blend = vec3(diffuse_ramp_uv, npr_ramp_mix(g_u_character_toon_ramp_mode));
	vec3 tonal_mapped_color = apply_tonal_mapping(diffuse_ramp_color, is_skin);

	float contrast_gain;
	vec3 contrasted_color = apply_local_contrast(tonal_mapped_color, shadow_factor, contrast_gain);

	vec3 base_lit_color = contrasted_color * albedo.rgb;
	vec3 accented_light = calculate_accent_light(base_lit_color, v_position_ws, normal_ws, softened_light_atten);

	vec3 rim_shadow_light = calculate_rim_shadow_light(view_dir_vs, normal_vs, ramp_level);
	vec3 final_color = rim_shadow_light * accented_light;
	// Contrast and the colored rim multiplier are affine in RGB. The accent's
	// additive term is a bias, not shadowable diffuse energy. Keep the existing
	// fragment arithmetic intact, but transport new lights without that bias.
	npr_diffuse_contribution = rim_shadow_light * base_lit_color;
	npr_specular_contribution = hair_highlight(normal_ws, view_dir_ws, light_dir_ws, albedo.rgb, ilm.rgb);
	npr_specular_contribution += hair_anisotropic_highlight(
		normal_ws, view_dir_ws, light_dir_ws, normalize(v_tangent_ws),
		normalize(v_binormal_ws), frag_uv, albedo.rgb, surface_fx, material_slot
	);
	float hair_wetness = texture(u_npr_hair_wetness_map, frag_uv).r
		* clamp(u_npr_hair_wetness, 0.0, 1.0);
	float wet_lobe = pow(clamp(1.0 - abs(dot(normal_ws, view_dir_ws)), 0.0, 1.0), 3.0);
	npr_specular_contribution = mix(npr_specular_contribution,
		u_npr_hair_wet_specular_color.rgb * (0.2 + wet_lobe), hair_wetness);
	final_color += npr_specular_contribution;
	vec3 edge_light = npr_edge_light(normal_ws, view_dir_ws, light_dir_ws, SCREEN_UV, normal_vs, -(VIEW_MATRIX * vec4(v_position_ws, 1.0)).z);
	float silhouette = pow(clamp(1.0 - abs(dot(normal_ws, view_dir_ws)), 0.0, 1.0),
		u_npr_hair_silhouette_power) * surface_fx.g * u_npr_hair_silhouette_strength;
	final_color = mix(final_color, final_color * u_npr_hair_silhouette_tint.rgb,
		clamp(silhouette * u_npr_hair_silhouette_tint.a, 0.0, 1.0));
	float emission_strength = surface_fx.b * u_npr_secondary_emission_strengths[material_slot];
	float emission_hue = u_npr_emission_hues[material_slot] + TIME * u_npr_emission_hue_speed;
	vec3 emission_color = u_npr_emission_hue_enabled
		? npr_hue_rotate(albedo.rgb, emission_hue) : albedo.rgb;
	vec3 emission_accent = emission_color * emission_strength;
	final_color += emission_accent;
	final_color += edge_light;
	vec3 before_dissolve = final_color;
	final_color = npr_apply_dissolve_edge(final_color, dissolve_distance);
	edge_light += emission_accent;
	edge_light += final_color - before_dissolve;

	ALBEDO = npr_dither_color(final_color, u_dither_mask, FRAGCOORD.xy);
	NORMAL = normal_vs;
#ifdef NPR_HAIR_OVER_EYE
	float calculated_sheen = clamp((v_hair_sheen_factor + u_hair_sheen_bias) * u_hair_sheen_intensity, 0.0, 1.0);
	float inverse_sheen_mask = 1.0 - calculated_sheen;
	ALPHA = mix(inverse_sheen_mask * 0.5 + 0.5, inverse_sheen_mask, albedo.a);
#else
	ALPHA = 1.0;
#endif
	float side = smoothstep(u_npr_hair_side_fade_range.x, u_npr_hair_side_fade_range.y,
		abs(v_hair_side_factor));
	float side_match = u_npr_hair_side_choose == 0
		? 1.0 : step(0.0, v_hair_side_factor * float(u_npr_hair_side_choose));
	ALPHA *= 1.0 - clamp(surface_fx.g * side * side_match
		* u_npr_hair_side_fade_strength, 0.0, 1.0);
	ALPHA *= u_npr_visibility_alpha;

		if (u_npr_diagnostic_mode != 0) {
			debug_color.rgb = npr_diagnostic_color(2, material_slot, normal_ws, frag_uv, albedo.rgb, 1.0, 0.0, 0);
			#ifdef NPR_HAIR_POST_LIGHT
				MATERIAL_LIGHT_DATA = vec4(1.0);
			#endif
		}
		if(debug_color.r>=0.0||debug_color.g>=0.0||debug_color.b>=0.0){
		ALBEDO = debug_color.rgb;
	}
	npr_final_color = ALBEDO;
	npr_key_direction_vs = (VIEW_MATRIX * vec4(light_dir_ws, 0.0)).xyz;
	// The affine light delta must receive the same silhouette tint as the base.
	// Keep the unscaled highlight separately for the ordered post-light path.
	#ifdef NPR_HAIR_POST_LIGHT
		npr_hair_late_specular = npr_specular_contribution;
	#endif
	vec3 silhouette_gain = mix(vec3(1.0), u_npr_hair_silhouette_tint.rgb,
		clamp(silhouette * u_npr_hair_silhouette_tint.a, 0.0, 1.0));
	npr_diffuse_contribution *= silhouette_gain;
	npr_specular_contribution *= silhouette_gain;
	vec3 fill_gain = contrast_gain * rim_shadow_light * silhouette_gain;
	npr_surface_color = albedo.rgb * fill_gain;
	// Shadow metadata is already in the contrast/rim-transformed domain;
	// specular and edge light occur AFTER those multipliers, so never divide
	// them by the gain (which can be zero). Clamp before adding the accent bias.
	npr_composition_gain = vec3(1.0);
	npr_pre_composition_color = npr_diffuse_contribution + npr_specular_contribution + edge_light;
	npr_diffuse_contribution = min(npr_diffuse_contribution, max(npr_pre_composition_color, vec3(0.0)));
	bool debug_override = any(greaterThanEqual(debug_color.rgb, vec3(0.0)));
	npr_composition_compatible = float(!g_u_level_adjust_on && (u_dither_mask & 3) == 0 && u_accent_split_tone_strength == 0.0 && all(greaterThanEqual(fill_gain, vec3(0.0))) && !debug_override);
	#ifdef NPR_HAIR_POST_LIGHT
		// Keep the proven affine fast path. Nonlinear/signed settings instead
		// accumulate in ramp space, before tonal mapping, contrast and albedo.
		bool native_contrast = u_npr_native_shadow_contrast && u_contrast_adjust_on;
		npr_hair_post_active = float((npr_composition_compatible < 0.5 || native_contrast) && !debug_override);
		if (npr_hair_post_active > 0.5) {
			npr_hair_input_ramp = diffuse_ramp_color;
			npr_hair_albedo_skin = vec4(albedo.rgb, float(is_skin));
			npr_hair_contrast_gain = contrast_gain;
			npr_hair_soft_attenuation = softened_light_atten;
			npr_hair_normal_ws = normal_ws;
			npr_hair_rim_gain = rim_shadow_light;
			npr_hair_silhouette = clamp(silhouette * u_npr_hair_silhouette_tint.a, 0.0, 1.0);
			npr_hair_edge = edge_light;
			npr_surface_color = vec3(1.0);
			npr_diffuse_contribution = diffuse_ramp_color;
			npr_specular_contribution = vec3(0.0);
			npr_pre_composition_color = diffuse_ramp_color;
			npr_composition_compatible = 1.0;
			// Independent visibility for the highlight added AFTER the color chain.
			// Never encode this scalar in the native diffuse/specular RGB buffers.
			// x: raw key attenuation for contrast; w: artist-weighted late highlight.
			// Missing/disabled key light means fully lit, never synthetic shadow.
			MATERIAL_LIGHT_DATA = vec4(1.0, 0.0, 0.0, 1.0);
		}
	#endif
	EMISSION = npr_final_color;
	ALBEDO = vec3(1.0);
}

#ifdef NPR_HAIR_POST_LIGHT
void post_light() {
		if (u_npr_diagnostic_mode == 7) {
			POST_LIGHT_COLOR = vec3(MATERIAL_LIGHT_DATA.x);
		} else if (npr_hair_post_active > 0.5) {
		vec3 lit_ramp = npr_hair_input_ramp + POST_LIGHT_DIRECT;
		vec3 color = apply_tonal_mapping(lit_ramp, npr_hair_albedo_skin.a > 0.5);
		float contrast_gain = npr_hair_contrast_gain;
		if (u_npr_native_shadow_contrast && u_contrast_adjust_on
				&& !npr_main_disabled(g_u_character_disable_main_light)) {
			float shadow_gain = 1.0;
			// Preserve exact unity in the saturated/unshadowed region: evaluating
			// mix(strength + 1, 1, 1) can retain strength-dependent FMA roundoff.
			if (MATERIAL_LIGHT_DATA.x * 6.666 < 1.0) {
				vec3 unused_color = apply_local_contrast(vec3(1.0), MATERIAL_LIGHT_DATA.x, shadow_gain);
			}
			// Apply artistic shadow strength to the gain, not before the legacy
			// narrow contrast threshold (which would make it unreachable at 0.65).
			contrast_gain = mix(1.0, shadow_gain, clamp(u_npr_shadow_strength, 0.0, 1.0));
		}
		color *= contrast_gain;
		color *= npr_hair_albedo_skin.rgb;
		color = calculate_accent_light(color, v_position_ws, npr_hair_normal_ws, npr_hair_soft_attenuation);
		color *= npr_hair_rim_gain;
		color += npr_hair_late_specular * MATERIAL_LIGHT_DATA.w;
		// Match fragment ordering: tint the lit base and highlight together,
		// before secondary emission, edge light, and final quantization.
		color = mix(color, color * u_npr_hair_silhouette_tint.rgb, npr_hair_silhouette);
		color += npr_hair_edge;
		POST_LIGHT_COLOR = npr_dither_color(color, u_dither_mask, FRAGCOORD.xy);
	}
}
#endif

void light() {
		if (u_npr_diagnostic_mode != 0) {
			#ifdef NPR_HAIR_POST_LIGHT
				if (LIGHT_IS_DIRECTIONAL && dot(LIGHT, npr_key_direction_vs) > 0.9995) {
					MATERIAL_LIGHT_DATA.x = min(MATERIAL_LIGHT_DATA.x, clamp(ATTENUATION, 0.0, 1.0));
				}
			#endif
		} else if (LIGHT_IS_DIRECTIONAL && dot(LIGHT, npr_key_direction_vs) > 0.9995) {
		#ifdef NPR_HAIR_POST_LIGHT
			if (npr_hair_post_active > 0.5) {
				MATERIAL_LIGHT_DATA.x = min(MATERIAL_LIGHT_DATA.x, clamp(ATTENUATION, 0.0, 1.0));
				float visibility = mix(1.0, clamp(ATTENUATION, 0.0, 1.0), clamp(u_npr_shadow_strength, 0.0, 1.0));
				MATERIAL_LIGHT_DATA.w = min(MATERIAL_LIGHT_DATA.w, visibility);
			}
		#endif
		DIFFUSE_LIGHT = min(DIFFUSE_LIGHT, npr_shadow_delta(ATTENUATION, u_texture_diffuse_ramp, u_texture_diffuse_cool_ramp));
	} else {
		SPECULAR_LIGHT += npr_fill_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
	}
}
