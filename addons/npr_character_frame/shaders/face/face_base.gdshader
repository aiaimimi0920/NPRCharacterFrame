shader_type spatial;
#include "res://addons/npr_character_frame/shaders/face/nose_local.gdshaderinc"
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
	npr_nose_local_position = VERTEX;
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
	// Select exact clip coordinates: arithmetic mix loses thin-layer depth precision.
	POSITION = mix(C_POSITION_CLIPPED, position_cs, bvec4(render_condition));

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

#include "res://addons/npr_character_frame/shaders/face/face_lighting_helpers.gdshaderinc"

#include "res://addons/npr_character_frame/shaders/face/face_surface_effects.gdshaderinc"

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
	if (u_npr_nose_local_enabled) {
		albedo_blender_color = npr_nose_local_albedo(albedo.rgb, npr_nose_local_position);
	}


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
