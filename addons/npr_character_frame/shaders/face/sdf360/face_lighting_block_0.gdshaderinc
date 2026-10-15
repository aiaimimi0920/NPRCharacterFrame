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
    vec3 sdf_forward_ws = normalize(mat3(MODEL_MATRIX) * u_npr_face_forward);
    vec3 sdf_right_ws = normalize(mat3(MODEL_MATRIX) * u_npr_face_right);
    vec3 sdf_up_ws = normalize(cross(sdf_forward_ws, sdf_right_ws));
    v_npr_sdf360_light = vec3(dot(v_light_dir_ws, sdf_right_ws), dot(v_light_dir_ws, sdf_up_ws), dot(v_light_dir_ws, sdf_forward_ws));

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
