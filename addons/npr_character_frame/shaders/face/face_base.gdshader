shader_type spatial;
#include "res://addons/npr_character_frame/shaders/face/face_atlas_calibration.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/face/symbol_calibration.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/comic/comic_surface.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_screen_depth.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_style.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_diagnostics.gdshaderinc"

// 渲染模式
render_mode skip_vertex_transform, blend_mix, depth_draw_always, cull_back, unshaded, shadows_disabled, ambient_light_disabled;

stencil_mode write, compare_always, 0x1E;

// 注意本份代码的变量存在根本性问题，我怀疑有些地方我使用的向量空间计算错误了

// --- 功能开关 ---
//#define ENABLE_TWO_PART_HIDE

// ===================================================================
// >> Uniforms & Varyings <<
// ===================================================================
// --- Vertex ---

const vec4 C_POSITION_CLIPPED = vec4(-99.0, -99.0, -99.0, 1.0);

group_uniforms u_vertex_base;
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
	// 全局的特殊矩阵，可能用于类似直播小框的计算
	global uniform mat4 g_u_special_ws_to_cs;
	// 指示当前是否使用特殊矩阵计算cs
	instance uniform bool u_use_special_transform = false; // _20._m13
group_uniforms;

group_uniforms u_base_params;
	uniform sampler2D u_texture_base_map : source_color, filter_linear_mipmap, repeat_enable;
	uniform sampler2D u_texture_ilm_map : filter_linear_mipmap, repeat_enable;
	uniform sampler2D u_texture_face : filter_linear_mipmap, repeat_enable;
	uniform sampler2D u_texture_diffuse_ramp : source_color, filter_linear_mipmap;

	uniform bool u_sdf_on_uv2 = true; // _25._m304
	instance uniform bool u_is_monster : instance_index(3) = false; // _25._m1
	instance uniform vec4 u_custom_main_light_dir : instance_index(4) = vec4(1.00, 1.00, 1.00, 0.00); // _25._m18
	global uniform vec4 g_u_monster_main_light_dir = vec4(0.2706, 0.70711, 0.65328, 0.0); // _29._m3
	global uniform vec4 g_u_character_main_light_position = vec4(-0.73723, 0.43589, -0.51623, 0.00); // _20._m0
	global uniform bool g_u_character_disable_main_light = false; // _29._m57
	instance uniform bool u_character_disable_local_main_light : instance_index(5) = false; // _20._m11
	instance uniform vec4 u_character_local_main_light_position : instance_index(6) = vec4(-0.73723, 0.43589, -0.51623, 0.00); // _9._m11

	instance uniform vec4 u_character_local_main_light_color : source_color, instance_index(8) = vec4(1.0,1.0,1.0,1.0); // _15._m12
	global uniform vec4 g_u_character_main_light_color:source_color = vec4(1.0,1.0,1.0,1.0); // _23._m1
group_uniforms;

group_uniforms u_accent_params;
	uniform vec3  u_accent_light_direction = vec3(0.5, 0.5, 0.5); //_20._m6 // 强调光源的主要方向
group_uniforms;

group_uniforms u_npr_expression_params;
	uniform bool u_npr_expression_enabled = false;
	uniform vec3 u_npr_expression_weights = vec3(0.0);
	uniform vec4 u_npr_expression_shadow_color : source_color = vec4(0.55, 0.32, 0.42, 1.0);
	uniform vec4 u_npr_expression_highlight_color : source_color = vec4(1.0, 0.65, 0.72, 1.0);
	uniform vec4 u_npr_expression_blush_color : source_color = vec4(1.0, 0.32, 0.42, 1.0);
	// Linear skin compensation shared by the authored face/body showcase.
	// Eyes remain in the original color domain.
	uniform vec3 u_npr_face_skin_tint = vec3(1.0);
	// Surprised "round eye" preset in the authored Face atlas, clipped by ILM.
	uniform float u_npr_eye_expression : hint_range(0.0, 1.0) = 0.0;
	// Counter-scale only the painted cyan accent, not the pupil or iris artwork.
	uniform float u_npr_pupil_accent_scale : hint_range(0.65, 1.35) = 1.0;
	uniform float u_npr_pupil_accent_scale_right : hint_range(0.65, 1.35) = 1.0;
	uniform bool u_npr_pupil_accent_independent = false;
	// Linear tear mask in face UV1; zero wetness restores the previous result.
		uniform sampler2D u_npr_eye_tear_mask : filter_linear, repeat_disable;
		uniform vec2 u_npr_eye_tear_uv_limit = vec2(0.26, 0.32);
		uniform float u_npr_eye_wetness : hint_range(0.0, 1.0) = 0.0;
		// Animation state, not a user setting. Fully closed eyes have no wet sheen.
		uniform float u_npr_eye_lid_closure : hint_range(0.0, 1.0) = 0.0;
	uniform bool u_npr_replace_eye = false;
group_uniforms;

group_uniforms u_npr_lip_outline_params;
	uniform bool u_npr_outline_lip_fix_enabled = false;
	uniform bool u_npr_outline_control_enabled = false;
	uniform sampler2D u_npr_outline_control : filter_linear_mipmap, repeat_enable;
	uniform float u_npr_outline_lip_width_pixels : hint_range(0.0, 4.0, 0.1) = 0.7;
group_uniforms;

// --- Varyings ---

// NDC坐标和裁剪空间Z/W
varying vec4 v_position_ndc;
varying vec3 v_position_ws;
varying vec2 npr_pupil_uv_pivot;
varying float npr_pupil_side;
varying vec3 v_normal_ws;
varying float v_forward_light_factor;
// 将实时的主光源方向转换为用于采样一张特殊“光照+SDF+高光”复合纹理的UV坐标 (.xy)，并提供一个补充的角度参数 (.z)
varying vec3 v_light_sdf_uv_and_angle;
// 将一个固定的“风格化方向”用同样的方式编码，用于对SDF图进行动态“切片”或查找，以实现如轮廓光、动态描边等高级风格化效果。
varying vec3 v_accent_sdf_uv_and_angle;
varying vec2 v_sdf_uv;

// Imported legacy assets keep their calibrated YZ rotation. New assets declare
// orthonormal local forward/right axes explicitly instead of imitating FBX axes.
uniform bool u_npr_sdf_basis_enabled = false;
uniform vec3 u_npr_face_forward = vec3(0.0, 0.0, 1.0);
uniform vec3 u_npr_face_right = vec3(1.0, 0.0, 0.0);

// ===================================================================
// >> Vertex Shader <<
// ===================================================================

vec3 calculate_sdf_uv_and_angle(vec3 direction_vec, mat3 model_normal_matrix, vec2 uv_input) {
	// 检查输入向量的长度是否有效，防止对零向量进行归一化
	if (dot(direction_vec, direction_vec) < 0.00000001) {
		return vec3(uv_input, 0.0001);
	}

	// 1. 将方向向量从视图空间变换到模型的法线空间
	// Only the horizontal angle is needed. Avoid normalizing a degenerate vector.
	vec3 transformed_dir = transpose(model_normal_matrix) * direction_vec;
	if (u_npr_sdf_basis_enabled) {
		vec2 horizontal = vec2(dot(transformed_dir, u_npr_face_forward), dot(transformed_dir, u_npr_face_right));
		if (dot(horizontal, horizontal) < 0.00000001) {
			return vec3(uv_input, 0.0001);
		}
		float local_angle = atan(horizontal.y, horizontal.x);
		// atan at the exact back direction may return either signed PI. The
		// geometric side owns mirroring, so signed zero cannot flip the atlas.
		vec2 local_uv = vec2(horizontal.y < 0.0 ? 1.0 - uv_input.x : uv_input.x, uv_input.y);
		return vec3(local_uv, clamp(abs(local_angle / PI), 0.0001, 0.9999));
	}
	if (dot(transformed_dir.yz, transformed_dir.yz) < 0.00000001) {
		return vec3(uv_input, 0.0001);
	}

	// 2. 将变换后向量的 yz 分量组成的 2D 向量旋转 -10 度
	// cos(-10 deg) ≈ 0.9848, sin(-10 deg) ≈ -0.1736
	const float COS_ANGLE = 0.98480999;
	const float SIN_ANGLE = -0.17364999;
	vec2 yz_plane_vec = transformed_dir.yz;
	vec2 rotated_yz = vec2(
		dot(yz_plane_vec, vec2(COS_ANGLE, -SIN_ANGLE)),
		dot(yz_plane_vec, vec2(SIN_ANGLE, COS_ANGLE))
	);

	float angle = atan(rotated_yz.y, rotated_yz.x);

	// 4. 根据角度的符号进行翻转
	bool is_angle_negative = (angle < 0.0);
	vec2 flipped_uv = vec2(1.0 - uv_input.x, uv_input.y);
	vec2 mixed_uv = mix(uv_input, flipped_uv, bvec2(is_angle_negative));

	// 5. 将角度从 [-PI, PI] 映射到 [-1, 1] 区间，然后进行 clamp
	// -1.0 / PI ≈ -0.3183099
	float angle_z = -angle / PI;
	angle_z = clamp(abs(angle_z), 0.0001, 0.9999);

	return vec3(mixed_uv, angle_z);
}

// 顶点着色器 - 部件显隐与掩码处理
bool get_render_condition(vec4 color) {
#ifdef ENABLE_TWO_PART_HIDE
	return npr_part_visible(color, u_show_part_id, u_hide_character_parts, u_hide_npc_parts);
#else
	return npr_part_visible(color, u_show_part_id, u_hide_character_parts, false);
#endif
}


uniform int u_npr_mouth_symbol = 0;
uniform float u_npr_mouth_symbol_size = 1.0;
uniform float u_npr_mouth_symbol_stroke = 0.10;
uniform int u_npr_eye_symbol = 0;
uniform vec3 u_npr_face_art_light_dir = vec3(0.15, 0.5, 0.85);
uniform float u_npr_face_art_light_weight = 0.0;
uniform float u_npr_eye_symbol_size = 1.0;
uniform float u_npr_eye_symbol_stroke = 0.10;
varying vec4 npr_symbol_canvas;
varying float npr_symbol_lash;

vec3 npr_face_light_direction(vec3 scene_direction) {
	if (u_npr_face_art_light_weight <= 0.0) { return scene_direction; }
	vec3 mixed_direction = mix(normalize(scene_direction), u_npr_face_art_light_dir,
		clamp(u_npr_face_art_light_weight, 0.0, 1.0));
	return dot(mixed_direction, mixed_direction) > 0.00001 ? normalize(mixed_direction) : scene_direction;
}

void vertex() {
	npr_pupil_uv_pivot = CUSTOM0.xy;
	npr_symbol_canvas = CUSTOM1;

	npr_symbol_lash = CUSTOM0.w;
	npr_pupil_side = CUSTOM0.z;
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

	vec2 use_sdf_uv = mix(UV, UV2, bvec2(u_sdf_on_uv2)) * u_uv1_scale.xy + u_uv1_offset.xy;
	v_sdf_uv = u_sdf_on_uv2? UV2* u_uv1_scale.xy + u_uv1_offset.xy:vec2(0.0);

	UV = UV * u_uv1_scale.xy + u_uv1_offset.xy;
	UV2 = u_sdf_on_uv2?UV2:vec2(0.0);

	// NDC坐标, 不是常规意义上的ndc：https://zhuanlan.zhihu.com/p/686166007 , 因为是否需要翻转在引擎层已经处理好了，所以这里不做翻转乘积操作
	v_position_ndc.xy = (position_cs.xy + position_cs.w) * 0.5;
	v_position_ndc.zw = position_cs.zw;

	v_normal_ws = normalize(MODEL_NORMAL_MATRIX * NORMAL); // model space -> world space

	// === 4. 光源方向与阴影相关变量计算 ===
	// 只有在主灯关闭，并且局部灯打开的情况下才使用局部灯
	bool use_local_main_light = g_u_character_disable_main_light && !u_character_disable_local_main_light;
	vec3 main_light_dir = use_local_main_light ? u_character_local_main_light_position.xyz : g_u_character_main_light_position.xyz;
	vec3 v_light_dir_ws = mix(main_light_dir, u_custom_main_light_dir.xyz, u_custom_main_light_dir.w);
	v_light_dir_ws = u_is_monster? g_u_monster_main_light_dir.xyz : v_light_dir_ws; // 这是视图空间下的，主要是形成模型的固定边缘光
		v_light_dir_ws = normalize(v_light_dir_ws);
		v_light_dir_ws = npr_face_light_direction(v_light_dir_ws);


	// 这里返回的是模型的面朝向，即模型的脸朝向在变换后在视图中的方向
	vec3 forward_vector_ws = MODEL_NORMAL_MATRIX * (u_npr_sdf_basis_enabled ? u_npr_face_forward : vec3(0.0,1.0,0.0));
	forward_vector_ws  = normalize(forward_vector_ws);
	float forward_light_factor = dot(forward_vector_ws, v_light_dir_ws);
	v_forward_light_factor = clamp(forward_light_factor + 1.0, 0.0, 1.0);


	// 分别对光照方向和视角方向进行编码计算
	v_light_sdf_uv_and_angle = calculate_sdf_uv_and_angle(v_light_dir_ws, MODEL_NORMAL_MATRIX, use_sdf_uv);
	v_accent_sdf_uv_and_angle = calculate_sdf_uv_and_angle(u_accent_light_direction.xyz, MODEL_NORMAL_MATRIX, use_sdf_uv);

	// 部件显隐与顶点掩码处理
	bool render_condition = get_render_condition(COLOR);
	POSITION = mix(C_POSITION_CLIPPED, position_cs, float(render_condition));

		vec3 tangent_ms = TANGENT;
		vec3 binormal_ms = BINORMAL;
		NORMAL = normalize(MODEL_NORMAL_MATRIX * NORMAL);
		TANGENT = normalize(MODEL_NORMAL_MATRIX * tangent_ms);
		BINORMAL = normalize(MODEL_NORMAL_MATRIX * binormal_ms);
}


// ===================================================================
// >> Fragment Shader <<
// ===================================================================

// 启用双面渲染
// 开启后，将根据面的朝向(FRONT_FACING)选择UV/UV2和颜色，实现双面材质。
//#define ENABLE_TWO_SIDED_RENDERING

// 启用Alpha混合 (透明效果)
// 开启后，最终的Alpha值将取自纹理，实现透明或半透明效果。
// #define ENABLE_ALPHA_BLEND

// 启用高度颜色渐变
// 开启后，将根据模型的世界坐标高度，在底部叠加上一层颜色渐变。
#define ENABLE_HEIGHT_LERP_EFFECT

// 使用备用辉光/散射模型
// 开启后，辉光(Bloom)部分将使用特殊计算模型。关闭后则使用标准模型。
// #define USE_ALTERNATIVE_SCATTERING_MODEL

// [开关] 启用风格化金属反射
// 开启后，会根据颜色亮度模拟出一种风格化的、非PBR的金属反射质感。
#define ENABLE_METAL_REFLECTION

// [开关] 启用对比度调整
// 开启后，会根据阴影强度对颜色进行一次对比度增强。
#define ENABLE_CONTRAST_ADJUST

// [开关] 使用材质属性查找表 (LUT)
// 开启后，高光、辉光、边缘阴影等参数将从一张特殊的纹理(LUT)中读取，实现更丰富的材质变化。
#define USE_MATERIAL_VALUES_LUT

// [开关] 启用局部的、特殊的辉光调整
#define USE_LOCAL_BLOOM_MODULATION


/**
 * @brief 计算遮罩深度测试遮蔽因子。
 */
group_uniforms u_special_occlusion_params;
	uniform bool u_ref_occ_flag = false; //_23._m14 // 是否打开反射遮挡开关？
	uniform float u_occ_normal_bias=0.0; //_35._m10 // 遮挡判断时的法线偏移，防止自遮挡问题
	uniform float u_occ_self_weight=0.63; // 如果为0会采用光线偏转后的方向，如果为1则会采用本身的方向
	uniform sampler2D u_texture_reflection_mask : source_color, filter_linear_mipmap, repeat_enable;
group_uniforms;

float calculate_special_occlusion_factor(vec3 position_ws, vec3 normal_ws, mat4 cur_matrix, bool use_local_main_light) {
	// 步骤1: 功能开关
	if (u_ref_occ_flag) {
		vec3 main_light_dir = use_local_main_light ? u_character_local_main_light_position.xyz : g_u_character_main_light_position.xyz;

		vec3 light_dir = mix(main_light_dir, u_custom_main_light_dir.xyz, u_custom_main_light_dir.w);
		light_dir = u_is_monster? g_u_monster_main_light_dir.xyz : light_dir;

		light_dir.y = max(light_dir.y,0.2);
		light_dir = normalize(light_dir); // 自定义偏转后的光源

		vec3 fixed_position_ws = (u_occ_normal_bias * normal_ws).xyz + v_position_ws.xyz; // fixed_position_ws

		vec4 clip_pos_A = cur_matrix * vec4(fixed_position_ws, 1.0);

		vec3 offset_world_pos_2 = fixed_position_ws + light_dir * 0.008;
		vec4 clip_pos_B = cur_matrix * vec4(offset_world_pos_2, 1.0);

		vec2 sample_uv;
		sample_uv.x = mix(clip_pos_B.x , clip_pos_A.x , u_occ_self_weight) / clip_pos_B.z;
		sample_uv.y = clip_pos_B.y / clip_pos_B.z;

		sample_uv = sample_uv * vec2(0.5, -0.5) + 0.5;

		float mask_value = textureLod(u_texture_reflection_mask, sample_uv, 0.0).r;
		bool is_visible = (clip_pos_A.y/clip_pos_A.z) > mask_value;
		return float(is_visible);
	}
	// 如果功能关闭，则返回1.0，代表无任何遮挡效果。
	return 1.0;
}

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

float npr_mouth_ink(vec2 position) {
	vec2 p = position / u_npr_mouth_symbol_size;
	float d = 1.0;
	if (u_npr_mouth_symbol == 1) {
		for (int i = 0; i < 24; i++) {
			float x = -0.8 + float(i) * 1.6 / 24.0;
			float x2 = x + 1.6 / 24.0;
			d = min(d, npr_symbol_segment(p, vec2(x, 0.25 * sin(x * 8.0)), vec2(x2, 0.25 * sin(x2 * 8.0))));
		}
	} else if (u_npr_mouth_symbol == 2) {
		d = abs(length(p) - 0.5);
	} else if (u_npr_mouth_symbol == 3) {
		d = npr_symbol_segment(p, vec2(-0.75, 0.0), vec2(0.75, 0.0));
	}
	float aa = max(fwidth(d), 0.006);
	return 1.0 - smoothstep(u_npr_mouth_symbol_stroke - aa, u_npr_mouth_symbol_stroke + aa, d);
}

void fragment() {
		if (u_npr_diagnostic_mode != 1) {
			if (u_npr_eye_symbol != 0 && abs(npr_symbol_lash - 1.0) < 0.1) { discard; }
			if (u_npr_mouth_symbol != 0 && abs(npr_symbol_lash - 2.0) < 0.1) { discard; }
		}
	vec4 debug_color = vec4(-1.0,-1.0,-1.0, -1.0);

	vec4 screen_coord = FRAGCOORD;
	float one_over_w = 1.0 / screen_coord.w;

	// 翻转Y坐标以匹配常见纹理坐标系，原逻辑中没有，需要查看是否需要
	vec2 frag_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 frag_uv2 = vec2(UV2.x, 1.0 - UV2.y);
	bool lid_canvas = abs(npr_symbol_canvas.w - 4.0) < 0.1;
	bool mouth_canvas = abs(npr_symbol_canvas.w - 3.0) < 0.1;
		bool skin_canvas = abs(npr_symbol_canvas.w - 2.0) < 0.1;
		if (u_npr_diagnostic_mode == 1 && (lid_canvas || mouth_canvas)) {
			if (mod(floor(FRAGCOORD.x / 6.0) + floor(FRAGCOORD.y / 6.0), 2.0) < 1.0) { discard; }
		}
	vec2 l = (npr_symbol_canvas.xy - u_npr_symbol_eye_left) / u_npr_symbol_eye_radius;
	vec2 r = (npr_symbol_canvas.xy - u_npr_symbol_eye_right) / u_npr_symbol_eye_radius;
	float eye_radius = min(length(l), length(r));
	float mouth_radius = length((npr_symbol_canvas.xy - u_npr_symbol_mouth_center) / u_npr_symbol_mouth_radius);
	// Original skin remains beneath the conformed overlap; only disconnected
	// original eye/mouth geometry is discarded. This preserves profile silhouettes.
	if (lid_canvas && eye_radius > 1.0) { discard; }
	if (mouth_canvas && mouth_radius > 1.0) { discard; }
	float clean_skin = 0.0;
	if (lid_canvas) { clean_skin = 1.0 - smoothstep(0.55, 0.96, eye_radius); }
	if (mouth_canvas) { clean_skin = 1.0 - smoothstep(0.45, 0.96, mouth_radius); }
	if (skin_canvas && npr_symbol_canvas.z > u_npr_symbol_skin_front_min && u_npr_eye_symbol != 0) { clean_skin = max(clean_skin, 1.0 - smoothstep(0.55, 0.96, eye_radius)); }
	if (skin_canvas && npr_symbol_canvas.z > u_npr_symbol_skin_front_min && u_npr_mouth_symbol != 0) { clean_skin = max(clean_skin, 1.0 - smoothstep(0.45, 0.96, mouth_radius)); }

#ifdef ENABLE_TWO_SIDED_RENDERING
	vec4 albedo = texture(u_texture_base_map, FRONT_FACING ? frag_uv : frag_uv2);
#else
	vec4 albedo = texture(u_texture_base_map, frag_uv);
#endif
	float accent_scale = u_npr_pupil_accent_independent && npr_pupil_side > 0.5
		? u_npr_pupil_accent_scale_right : u_npr_pupil_accent_scale;
	if (u_npr_face_atlas_enabled && npr_pupil_uv_pivot.x > 0.0 && abs(accent_scale - 1.0) > 0.00001) {
		// Authored face atlas: accent over a flat dark pupil plate.
		// Let the inner accent follow 30% of the outer pupil's size change.
		vec2 low = u_npr_face_atlas_accent_uv_min;
		vec2 high = u_npr_face_atlas_accent_uv_max;
		vec3 plate = texture(u_texture_base_map, u_npr_face_atlas_accent_plate_uv).rgb;
		if (all(greaterThanEqual(frag_uv, low)) && all(lessThanEqual(frag_uv, high))) {
			// The crop corners include the black pupil rim. Remove only the
			// brighter accent residual, preserving that darker contour in place.
			albedo.rgb -= max(albedo.rgb - plate, vec3(0.0));
		}
		float inner_scale = 1.0 + (accent_scale - 1.0) * 0.30;
		vec2 accent_uv = npr_pupil_uv_pivot + (frag_uv - npr_pupil_uv_pivot) * (accent_scale / inner_scale);
		if (all(greaterThanEqual(accent_uv, low)) && all(lessThanEqual(accent_uv, high))) {
			// Never transport the rim's negative residual into the pupil interior.
			albedo.rgb += max(texture(u_texture_base_map, accent_uv).rgb - plate, vec3(0.0));
		}
	}

	// Remove painted lip/eyelash marks using adjacent skin at the same atlas X.
	if (u_npr_face_atlas_enabled) {
		vec4 adjacent_skin = texture(u_texture_base_map, vec2(frag_uv.x, u_npr_face_atlas_skin_sample_v));
		albedo = mix(albedo, adjacent_skin, clean_skin);
	}
	float fixed_shadow_mask = albedo.g; // G通道是固定阴影
	float material_id = albedo.b; // B通道是材质/SDF区域ID

	// The authored face SDF and optional occlusion own its shadow shape.
	float shadow_factor = 1.0;

	bool use_local_main_light = g_u_character_disable_main_light && !u_character_disable_local_main_light;
	vec3 main_light_color = use_local_main_light ? u_character_local_main_light_color.rgb : g_u_character_main_light_color.rgb;
	main_light_color = u_npr_studio_enabled ? vec3(1.0) : main_light_color;

	// 特殊遮蔽计算
	float special_occlusion = calculate_special_occlusion_factor(v_position_ws, v_normal_ws.rgb, g_u_special_ws_to_cs, use_local_main_light);

	shadow_factor *= special_occlusion;

	// 从 ILM 贴图采样
	vec4 ilm_sample = texture(u_texture_ilm_map, v_light_sdf_uv_and_angle.xy);
	float baked_mask = texture(u_texture_ilm_map, frag_uv).r;
	// ILM alone also has antialiased non-eye pixels (including the mouth).
	// Restrict replacement to the authored iris/pupil/glint and sclera domains.
	bool replacement_eye_island = npr_face_atlas_replacement_eye(frag_uv);
	if (u_npr_face_atlas_enabled && u_npr_replace_eye && replacement_eye_island && baked_mask > 0.1 && baked_mask < 0.8) {
		discard;
	}
	vec3 face_mask = texture(u_texture_face, frag_uv).rgb;
	vec4 surface_fx = npr_surface_effects(frag_uv);
	if (!npr_visibility_keep(FRAGCOORD.xy)) {
		discard;
	}
	float dissolve_distance = npr_dissolve_signed_distance(frag_uv, v_position_ws, surface_fx.a);
	if (dissolve_distance < 0.0) {
		discard;
	}

	vec3 normal_ws = normalize(v_normal_ws);
	vec3 view_dir_ws = normalize(CAMERA_POSITION_WORLD - v_position_ws);

	vec3 normal_vs = (VIEW_MATRIX*vec4(normal_ws,0.0)).xyz;
	vec3 view_dir_vs = (VIEW_MATRIX*vec4(view_dir_ws,0.0)).xyz;
	float NdotV = dot(normal_ws, view_dir_ws);

	// --- 鼻线 ---
	float nose_line_factor  = calculate_nose_line_factor(normal_ws, view_dir_ws, ilm_sample.b);
	vec3 albedo_blender_color = mix(albedo.rgb, u_nose_line_color, nose_line_factor);


	// --- 唇线 ---
	float dist_to_cam = length(v_position_ws - CAMERA_POSITION_WORLD);
	vec4 vertex_color = COLOR;
	float lip_line_fix_factor = calculate_lip_line_fix_factor(dist_to_cam, vertex_color.g);// 这里其实是一个反向的参数，为0时使用唇部的修复颜色，为1时使用本来色
	if (clean_skin > 0.0) { lip_line_fix_factor = 1.0; }
	vec3 color_after_lip_line_fix = mix(u_lip_line_fix_color, albedo_blender_color, lip_line_fix_factor);

	// --- 眼部叠加混合颜色 ---
	//debug_color.rgb = vec3(vertex_color.r);
	vec3 eye_base_color = mix(u_eye_base_shadow_color, vec3(1.0), vertex_color.r);
	vec3 tint_factor = eye_base_color  * u_eye_blend_tint;
	vec3 modulation_blender_color = color_after_lip_line_fix * tint_factor;

	// --- 自发光效果 ---
	float emission_factor = calculate_emission_factor(vertex_color.a);
	vec3 bloom_blend_color = modulation_blender_color * (emission_factor + 1.0); // 这里是一个调制好的albedo基础色

	//debug_color.rgb =  vec3(emission_factor);


	bool is_above_threshold = vertex_color.a > u_emission_threshold;
	float emission_factor_2 = mix(vertex_color.a/u_emission_threshold, 1.0, float(is_above_threshold)); // 小辉光强度，有辉光则为1，没有辉光则返回比例

	//debug_color.rgb = vec3(emission_factor_2).rgb;
	// --- 边缘光颜色 ---

	vec3 rim_light_color = calculate_rim_light_color(NdotV);

	// --- 面部染色 ---
	vec3 facial_tint = calculate_face_makeup_and_tone(face_mask, baked_mask);
	vec2 baked_mask_switch = baked_mask > 0.1 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);


	// --- SDF因子 ---
	float sdf_value_from_lut  = ilm_sample.a;
	sdf_value_from_lut = u_sdf_invert ? 1.0 - sdf_value_from_lut : sdf_value_from_lut;
	float sdf_factor = calculate_sdf_factor(sdf_value_from_lut, v_light_sdf_uv_and_angle.z);

	shadow_factor = shadow_factor * sdf_factor;

	// --- 顶光控制 ---
	float light_control_factor = calculate_lighting_control_factor(baked_mask, v_forward_light_factor, baked_mask_switch);
	vec3 light_control_color = calculate_lighting_control_color(shadow_factor, light_control_factor, baked_mask_switch);



	vec3 light_grading_color = apply_lighting_color_grading(shadow_factor, light_control_factor, baked_mask_switch, light_control_color);
	vec3 light_grading_blend_color = bloom_blend_color*light_grading_color;


	// 调整眼球效果和颜色，ilm贴图 r=0.5的区域为眼球区域
	vec3 eyeball_effect_color = apply_eyeball_effect(light_grading_blend_color, baked_mask);


	// 在眼球上叠加一层专属的动态视觉特效 (VFX)
	vec3 color_with_eyeball_vfx = apply_eyeball_vfx(eyeball_effect_color, frag_uv, TIME, baked_mask, baked_mask_switch);

	// --- sdf因子计算 ---
	float sdf_sample = texture(u_texture_ilm_map, frag_uv).a;
	float sdf_sheen_factor = calculate_sdf_sheen_factor(sdf_sample, v_accent_sdf_uv_and_angle.z ,v_position_ws);
	sdf_sheen_factor = sdf_sheen_factor*(npr_main_disabled(g_u_character_disable_main_light)?0.0 : 1.0);
	sdf_sheen_factor = (sdf_factor*0.5 +0.5) *sdf_sheen_factor;
	vec2 final_sdf_sheen_factor = sdf_sheen_factor * u_shading_sheen_factor.xy;
	// 调整对比度
	vec3 contrast_color = apply_contrast_adjustment(color_with_eyeball_vfx, final_sdf_sheen_factor, baked_mask_switch);


	// 叠加额外的sdf色
	float sdf_add_factor = baked_mask_switch.y * final_sdf_sheen_factor.y;
	contrast_color = contrast_color + sdf_add_factor * u_sdf_add_color.rgb;


	//
	// 边缘阴影光
	vec3 rim_shadow_light_color = calculate_rim_shadow_light(view_dir_vs, normal_vs, frag_uv);

	bool is_eyeball_area = baked_mask > 0.1 && baked_mask < 0.8;
	float is_eyeball_area_factor  = float(is_eyeball_area);

	// bloom_blend_color 实际是调制好的aldebo色
	// contrast_color 这个对比度实际也是从bloom_blend_color推理到的，也是包含调制好的aldebo色
	vec3 main_color = facial_tint * contrast_color * main_light_color;
	vec3 expression = surface_fx.rgb * u_npr_expression_weights
		* float(u_npr_expression_enabled) * (1.0 - step(0.1, baked_mask));
	main_color *= mix(vec3(1.0), u_npr_expression_shadow_color.rgb,
		clamp(expression.r * u_npr_expression_shadow_color.a, 0.0, 1.0));
	// Skin highlights use available color headroom and the same SDF lighting.
	// An unbounded additive overlay bleached the forehead and lit shadowed skin.
	float expression_highlight = clamp(expression.g * u_npr_expression_highlight_color.a, 0.0, 1.0)
		* clamp(shadow_factor * light_control_factor, 0.0, 1.0);
	main_color += max(vec3(1.0) - main_color, vec3(0.0))
		* u_npr_expression_highlight_color.rgb * expression_highlight;
	float blush_weight = clamp(expression.b * u_npr_expression_blush_color.a, 0.0, 1.0);
	// Preserve the already-lit face. Replacing it with a flat blush color
	// erased the SDF shadow gradient and widened the face/body hue gap.
	main_color *= mix(vec3(1.0), u_npr_expression_blush_color.rgb, blush_weight);
	vec3 contact_light_ws = mix(use_local_main_light ? u_character_local_main_light_position.xyz : g_u_character_main_light_position.xyz, u_custom_main_light_dir.xyz, u_custom_main_light_dir.w);
		contact_light_ws = u_is_monster ? g_u_monster_main_light_dir.xyz : contact_light_ws;
		contact_light_ws = npr_face_light_direction(contact_light_ws);
	vec3 contact_light_vs = (VIEW_MATRIX * vec4(normalize(contact_light_ws), 0.0)).xyz;
	float hair_contact = npr_hair_contact(SCREEN_UV, (VIEW_MATRIX * vec4(v_position_ws, 1.0)).xyz, contact_light_vs, PROJECTION_MATRIX);
	main_color *= mix(vec3(1.0), vec3(0.78, 0.68, 0.72), hair_contact * (1.0 - is_eyeball_area_factor));
	main_color *= mix(vec3(1.0), u_npr_face_skin_tint, 1.0 - is_eyeball_area_factor);
	// Round-eye expression: a soft dark pupil disc with a bright ring drawn in
	// iris-island UV space, clipped by the authored eye mask so eyelids, lashes
	// and skin are never touched.
	if (u_npr_face_atlas_enabled) {
		vec2 eye_delta = (frag_uv - u_npr_face_atlas_round_eye_center_uv) * u_npr_face_atlas_round_eye_aspect;
		float eye_dist = length(eye_delta);
		float eye_pupil = 1.0 - smoothstep(u_npr_face_atlas_round_eye_pupil_radii.x, u_npr_face_atlas_round_eye_pupil_radii.y, eye_dist);
		float eye_disc = 1.0 - smoothstep(u_npr_face_atlas_round_eye_disc_radii.x, u_npr_face_atlas_round_eye_disc_radii.y, eye_dist);
		float eye_weight = is_eyeball_area_factor * clamp(u_npr_eye_expression, 0.0, 1.0);
		// Flatten the iris to a pale disc, then stamp a small dark pupil.
		main_color = mix(main_color, vec3(0.90, 0.92, 0.97), eye_disc * eye_weight * 0.85);
		main_color = mix(main_color, vec3(0.08, 0.09, 0.14), eye_pupil * eye_weight * 0.95);
	}
	// Original painted eyes: a restrained lower-iris sheen, never a tinted veil.
	// Keep pupil/white highlights, UVs and geometry unchanged. The authored mask
	// follows the iris; real eyelid depth naturally occludes it during blinking.
	float tear_mask = texture(u_npr_eye_tear_mask, frag_uv).r
			* is_eyeball_area_factor
			* float(frag_uv.x < u_npr_eye_tear_uv_limit.x && frag_uv.y < u_npr_eye_tear_uv_limit.y);
	float tear_weight = tear_mask * clamp(u_npr_eye_wetness, 0.0, 1.0)
		* (1.0 - smoothstep(0.75, 1.0, u_npr_eye_lid_closure));
	float sheen_light = mix(0.6, 1.0,
		smoothstep(-0.2, 0.7, dot(normal_vs, contact_light_vs)));
	float sheen_view = mix(0.75, 1.0, clamp(abs(NdotV), 0.0, 1.0));
	vec3 sheen_headroom = max(vec3(1.0) - main_color, vec3(0.0));
	main_color += min(sheen_headroom, max(main_color, vec3(0.0)) * 0.5)
		* tear_weight * sheen_light * sheen_view;



	vec3 baked_mask_blender_color = vec3(1.0-is_eyeball_area_factor) * bloom_blend_color.rgb * u_bloom_no_mid_baked_mask_intensity; // 给非眼球部位再叠加一个颜色上去
	vec3 blender_color = (main_color * rim_shadow_light_color) + baked_mask_blender_color + rim_light_color + g_u_bloom_add_color.rgb * bloom_blend_color;



	vec3 blender_bloom_color = apply_bloom_blend(blender_color, bloom_blend_color, emission_factor_2);

	// 高度渐变后的混合结果
	vec3 height_gradient_blender_color = apply_height_gradient(v_position_ws.y, blender_bloom_color);

	vec3 multiple_color = (1.0+u_bloom_no_mid_baked_mask_intensity) *height_gradient_blender_color;
	multiple_color = (1.0-float(u_use_global_interior_line_darken_factor)*g_u_interior_line_darken_factor) * multiple_color;

	vec3 distance_lut_grading_color = apply_distance_lut_grading(dist_to_cam, multiple_color, v_position_ws); // 距离渐变+调色后的颜色

	vec3 fog_blender_color = apply_fog_effect(distance_lut_grading_color, v_position_ndc, FRAGCOORD.z);
	fog_blender_color = npr_apply_dissolve_edge(fog_blender_color, dissolve_distance);
	bool mouth_region = mouth_canvas || (skin_canvas && length((npr_symbol_canvas.xy - u_npr_symbol_mouth_center) / u_npr_symbol_mouth_radius) < 1.0);
	if (!(u_npr_mouth_symbol != 0 && mouth_region) && u_npr_outline_lip_fix_enabled && u_npr_outline_control_enabled) {
		vec3 outline_control = texture(u_npr_outline_control, frag_uv).rgb;
		float lip_ring = smoothstep(0.02, 0.42, max(outline_control.g - outline_control.r, 0.0));
		float lip_strength = clamp(u_npr_outline_lip_width_pixels / 0.7, 0.0, 1.0);
		fog_blender_color = mix(fog_blender_color, u_lip_line_fix_color, lip_ring * lip_strength * (1.0 - clean_skin));
	}


	if (u_npr_mouth_symbol != 0 && mouth_canvas) {
		fog_blender_color = mix(fog_blender_color, vec3(0.025, 0.018, 0.04), npr_mouth_ink((npr_symbol_canvas.xy - u_npr_symbol_mouth_center) / u_npr_symbol_mouth_ink_scale));
	}
		if (u_npr_eye_symbol != 0 && lid_canvas) {
			vec3 ink = u_npr_eye_symbol == 5 ? vec3(0.85, 0.42, 0.015)
				: (u_npr_eye_symbol == 6 ? vec3(0.8, 0.035, 0.14) : vec3(0.025, 0.018, 0.04));
			fog_blender_color = mix(fog_blender_color, ink,
			npr_symbol_ink((npr_symbol_canvas.xy - (l.x < 1.0 && length(l) < length(r) ? u_npr_symbol_eye_left : u_npr_symbol_eye_right)) / u_npr_symbol_eye_ink_scale, length(l) < length(r) ? -1.0 : 1.0));
	}
		fog_blender_color = npr_face_comics(fog_blender_color, npr_symbol_canvas, v_position_ws);
		ALBEDO = npr_dither_color(fog_blender_color, u_dither_mask, FRAGCOORD.xy);

	// Keep the ordered transparent/stencil path. These are real Godot semantics,
	// not the three custom color attachments in the captured fragment program.
	ALPHA = u_npr_visibility_alpha;
	NORMAL = normal_vs;


		if (u_npr_diagnostic_mode != 0) {
			int domain = lid_canvas ? 1 : (mouth_canvas ? 2 : 0);
			if (abs(npr_symbol_lash - 1.0) < 0.1 || abs(npr_symbol_lash - 2.0) < 0.1) { domain = 3; }
			float diagnostic_shadow = u_npr_diagnostic_mode == 4 ? sdf_factor : shadow_factor * (1.0 - hair_contact);
			debug_color.rgb = npr_diagnostic_color(1, 0, v_normal_ws, frag_uv, albedo.rgb, diagnostic_shadow,
				texture(u_texture_ilm_map, frag_uv).g, domain);
		}
		if(debug_color.r>=0.0||debug_color.g>=0.0||debug_color.b>=0.0){
		ALBEDO = debug_color.rgb;
	}
}
