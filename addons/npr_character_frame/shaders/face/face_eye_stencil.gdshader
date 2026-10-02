shader_type spatial;
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
// 注意这个代码不是做渲染的，而是将眼睛部位特殊标记出来，和后续的头发渲染做叠加，其部位的显示优先级会比头发高，然后头发再做一次渲染，形成透明的感觉

// 渲染模式
// Test against the face depth; only stencil/zero-alpha blending is owned by this pass.
render_mode skip_vertex_transform, blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled, ambient_light_disabled;

stencil_mode write, compare_always, 0x11;

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
	global uniform mat4 g_u_special_ws_to_cs;
	// 指示当前是否使用特殊矩阵计算cs
	instance uniform bool u_use_special_transform = false; // _20._m13

	uniform bool u_sdf_on_uv2 = true;
	instance uniform bool u_is_monster : instance_index(3) = false;

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
varying vec3 v_normal_ws;
varying float v_forward_light_factor;
// 将实时的主光源方向转换为用于采样一张特殊“光照+SDF+高光”复合纹理的UV坐标 (.xy)，并提供一个补充的角度参数 (.z)
varying vec3 v_light_sdf_uv_and_angle;
// 将一个固定的“风格化方向”用同样的方式编码，用于对SDF图进行动态“切片”或查找，以实现如轮廓光、动态描边等高级风格化效果。
varying vec3 v_accent_sdf_uv_and_angle;
varying vec2 v_sdf_uv;


// ===================================================================
// >> Vertex Shader <<
// ===================================================================

vec3 calculate_sdf_uv_and_angle(vec3 direction_vec, mat3 model_normal_matrix, vec2 uv_input) {
	// 检查输入向量的长度是否有效，防止对零向量进行归一化
	if (length(direction_vec) < 0.9) {
		return vec3(0.0, 1.0, 0.0);
	}

	// 1. 将方向向量从世界空间变换到模型的法线空间
	vec3 transformed_dir = normalize(transpose(model_normal_matrix) * direction_vec);

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

	// 模型空间 -> clip空间
	vec4 position_cs = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);

	// 世界空间 -> 特殊裁剪空间（极有可能是使用一个虚拟摄像机将模型直接渲染到合适的位置然后叠加，用途可能是直播小框）
	vec4 special_cs = g_u_special_ws_to_cs * vec4(v_position_ws, 1.0);

	// 根据是否为特殊计算，使用不同的cs
	position_cs = mix(position_cs, special_cs, bvec4(u_use_special_transform));

	vec2 use_sdf_uv = mix(UV, UV2, bvec2(u_sdf_on_uv2));
	v_sdf_uv = u_sdf_on_uv2? UV2* u_uv1_scale.xy + u_uv1_offset.xy:vec2(0.0);

	UV = UV * u_uv1_scale.xy + u_uv1_offset.xy;
	UV2 = u_sdf_on_uv2?UV2:vec2(0.0);

	// NDC坐标, 不是常规意义上的ndc：https://zhuanlan.zhihu.com/p/686166007 , 因为是否需要翻转在引擎层已经处理好了，所以这里不做翻转乘积操作
	v_position_ndc.xy = (position_cs.xy + position_cs.w) * 0.5;
	v_position_ndc.zw = position_cs.zw;

	// 世界空间的法线
	v_normal_ws = normalize(MODEL_NORMAL_MATRIX * NORMAL); // model space -> world space

	// === 4. 光源方向与阴影相关变量计算 ===
	// 只有在主灯关闭，并且局部灯打开的情况下才使用局部灯
	bool use_local_main_light = g_u_character_disable_main_light && !u_character_disable_local_main_light;
	vec3 main_light_dir = use_local_main_light ? u_character_local_main_light_position.xyz : g_u_character_main_light_position.xyz;
	vec3 v_light_dir_ws = mix(main_light_dir, u_custom_main_light_dir.xyz, u_custom_main_light_dir.w);
	v_light_dir_ws = u_is_monster? g_u_monster_main_light_dir.xyz : v_light_dir_ws; // 这是视图空间下的，主要是形成模型的固定边缘光
	v_light_dir_ws = normalize(v_light_dir_ws);


	// 这里返回的是模型的面朝向，即模型的脸朝向在变换后在视图中的方向
	vec3 forward_vector_ws = MODEL_NORMAL_MATRIX * vec3(0.0,1.0,0.0);
	forward_vector_ws  = normalize(forward_vector_ws);
	float forward_light_factor = dot(forward_vector_ws, v_light_dir_ws);
	v_forward_light_factor = clamp(forward_light_factor + 1.0, 0.0, 1.0);

	// 分别对光照方向和视角方向进行编码计算
	v_light_sdf_uv_and_angle = calculate_sdf_uv_and_angle(v_light_dir_ws, MODEL_NORMAL_MATRIX, use_sdf_uv);
	v_accent_sdf_uv_and_angle = calculate_sdf_uv_and_angle(u_accent_light_dir.xyz, MODEL_NORMAL_MATRIX, use_sdf_uv);

	v_sdf_uv = use_sdf_uv * u_uv1_scale.xy + u_uv1_offset.xy;

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


group_uniforms u_textures;
	uniform sampler2D u_texture_ilm : filter_linear_mipmap, repeat_enable;
group_uniforms;



/**
 * @brief 最终的抖动和量化
 */
group_uniforms u_dither_params;
	uniform int u_dither_mask = 0;
	// uniform int u_color_mode = 0;
	const vec4 c_dither_values = vec4(-0.01171875, 0.00390625, 0.01171875, -0.00390625);
group_uniforms;


uniform bool u_npr_symbolic_eyes = false;
uniform float u_eye_threshold = 0.5;
void fragment() {
	if (u_npr_symbolic_eyes) { discard; }
	vec2 use_sdf_uv = mix(v_sdf_uv, UV, bvec2(u_sdf_on_uv2));
	vec2 frag_uv = vec2(use_sdf_uv.x, 1.0 - use_sdf_uv.y);
	vec4 surface_fx = npr_surface_effects(frag_uv);
	if (!npr_visibility_keep(FRAGCOORD.xy)) {
		discard;
	}
	if (npr_dissolve_signed_distance(frag_uv, v_position_ws, surface_fx.a) < 0.0) {
		discard;
	}
	float baked_mask = texture(u_texture_ilm, frag_uv).g; // 眼睛部分
	int result = (baked_mask > u_eye_threshold) ? 1 : 0;
	//int need_shader = int(max(floor(min(baked_mask - u_eye_threshold, 1.0) +1.0),0.0));

	//ALBEDO = vec3(0.7,0.3,0.6);

	if(result == 0){
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
