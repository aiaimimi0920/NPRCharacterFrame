shader_type spatial;
// The custom Forward+ engine advertises this capability. The legacy
// branch is retained for old-engine comparisons, not nonlinear acceptance.
#if defined(HAS_MATERIAL_POST_LIGHT) && !defined(NPR_BODY_LEGACY_REFERENCE)
#define NPR_BODY_POST_LIGHT
varying vec3 npr_body_post_gain;
varying float npr_body_post_active;
#endif
#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_lighting.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/body/npr_hosiery.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_diagnostics.gdshaderinc"
//render_mode skip_vertex_transform, blend_mix, depth_draw_always, cull_back;
render_mode skip_vertex_transform, blend_mix, depth_draw_always, cull_back, specular_disabled, ambient_light_disabled;

stencil_mode write, compare_always, 0x10;

// Active body entry: samples/silver_wolf/scenes/body.tscn.

group_uniforms u_debug_switches;
uniform bool u_debug_frag_height_lerp_enabled = true;
uniform bool u_debug_frag_bloom_enabled = true;
uniform bool u_debug_frag_special_effect_enabled = true;
uniform bool u_debug_frag_fog_enabled = true;
uniform bool u_debug_frag_dithering_enabled = true;
// Artist-authored fallback for the clipped RGBA8 exponent row; never rescale the LUT.
uniform bool u_use_specular_exponent_override = false;
uniform bool u_npr_material_profile_enabled = false;
uniform float u_npr_specular_exponents[8];
// Optional authored garment domains. Skin remains opaque under the hosiery.
uniform bool u_npr_wardrobe_enabled = false;
uniform sampler2D u_npr_garment_mask : filter_linear, repeat_disable;
uniform vec4 u_npr_garment_primary : source_color = vec4(1.0);
uniform vec4 u_npr_garment_secondary : source_color = vec4(1.0);
uniform vec4 u_npr_garment_trim : source_color = vec4(1.0);
uniform float u_npr_garment_mix : hint_range(0.0, 1.0) = 0.0;
uniform float u_npr_hosiery_opacity : hint_range(0.0, 1.0) = 0.5;
uniform bool u_npr_garment_vertex_regions = false;
// Visual-direction contract: wetness_map is a linear R scalar in body UV1.
// The zero default is an exact feature-off path.
uniform sampler2D u_npr_wetness_map : filter_linear, repeat_disable;
uniform sampler2D u_npr_material_wetness_map : filter_linear, repeat_disable;
uniform bool u_npr_material_wetness_enabled = false;
uniform float u_npr_wetness_regions[4]; // skin, hosiery, hair, equipment
uniform vec4 u_npr_wet_specular_color : source_color = vec4(0.78, 0.86, 0.96, 1.0);
varying float npr_hosiery_domain;
varying float npr_equipment_domain;
varying vec3 npr_hosiery_rest_position;
uniform bool u_npr_rain_enabled = false;
uniform bool u_npr_rain_debug = false;
uniform sampler2D u_npr_rain_vertex_uv : filter_nearest, repeat_disable;
uniform sampler2D u_npr_rain_field : filter_linear, repeat_disable;
uniform sampler2D u_npr_rain_heads : filter_linear, repeat_disable;
uniform int u_npr_rain_vertex_count = 0;
varying vec2 npr_rain_uv;
varying float npr_rain_receiver;
// Optional asset-local ILM G repair, independent of stocking height/opacity.
uniform bool u_npr_leg_ao_repair_enabled = false;
uniform vec4 u_npr_leg_ao_repair_uv = vec4(0.0);
uniform vec3 u_npr_leg_ao_repair_values = vec3(0.0); // min height, max height, G floor
group_uniforms;

///////// vertex函数 /////////

uniform int u_part_mask_visible : hint_range(0, 255) = 255;
uniform bool u_hide_parts_flag = false;
varying vec3 v_world_position;
uniform mat4 u_reflection_matrix;
uniform bool u_reflection_flag = false;

uniform vec3 u_uv1_scale = vec3(1.0,1.0,1.0);
uniform vec3 u_uv1_offset = vec3(0.0,0.0,0.0);
uniform vec3 u_uv2_scale = vec3(1.0,1.0,1.0);
uniform vec3 u_uv2_offset = vec3(0.0,0.0,0.0);
uniform vec4 u_channel_mask = vec4(1.0);

varying vec4 v_ndc_position;
varying vec3 v_view_dir;
varying vec4 v_world_normal;

const vec4 C_POSITION_CLIPPED = vec4(-99.0, -99.0, -99.0, 1.0);


void vertex() {
	npr_rain_receiver = float(VERTEX_ID < u_npr_rain_vertex_count);
	npr_rain_uv = vec2(0.0);
	if (u_npr_rain_enabled && VERTEX_ID < u_npr_rain_vertex_count) {
		npr_rain_uv = texelFetch(u_npr_rain_vertex_uv, ivec2(VERTEX_ID % 256, VERTEX_ID / 256), 0).rg;
	}
	npr_hosiery_domain = u_npr_garment_vertex_regions ? max(CUSTOM0.r, 0.0) : 1.0;
	npr_equipment_domain = u_npr_garment_vertex_regions ? float(CUSTOM0.r < -0.5) : 0.0;
	npr_hosiery_rest_position = CUSTOM0.yzw;
	npr_depth_uv_offset = npr_depth_projection_offset(PROJECTION_MATRIX, NPR_DEPTH_PROJECTION);
	npr_depth_view_slot = u_reflection_flag ? 0.0 : npr_select_depth_view(INV_VIEW_MATRIX, NPR_DEPTH_PROJECTION, VIEWPORT_SIZE, CAMERA_VISIBLE_LAYERS);
	// 判断当前部件是否需要显示
	// 注意这里的空间从blender导出可能是伽马矫正后的颜色值，所以这里我们在编辑blender模型时直接取小数代表的颜色，不要取HEX代表的颜色，那个不准，和最后导出的颜色不同（也有可能是插件导致的问题：https://www.bilibili.com/opus/969603272398602247）
	// 所有的模型部件分为8个不同的类型
	// 第一种类型：掩码：1，颜色通道：0.005
	// 第二种类型：掩码：2，颜色通道：0.009
	// 第三种类型：掩码：4，颜色通道：0.017
	// 第四种类型：掩码：8，颜色通道：0.033
	// 第五种类型：掩码：16，颜色通道：0.064
	// 第六种类型：掩码：32，颜色通道：0.126
	// 第七种类型：掩码：64，颜色通道：0.251
	// 第八种类型：掩码：128，颜色通道：0.501
	bool render_condition = npr_part_visible(COLOR, u_part_mask_visible, u_hide_parts_flag, false);

	// 世界坐标变换
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 正常视角裁剪坐标
	vec4 clip_position = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);

	// 反射视角裁剪坐标
	vec4 reflected_clip_position = u_reflection_matrix * vec4(v_world_position, 1.0);

	// 是否使用反射矩阵
	vec4 projected_position = mix(clip_position, reflected_clip_position, bvec4(u_reflection_flag));

	// 根据render_condition判断是否丢弃顶点
	POSITION = mix(C_POSITION_CLIPPED, projected_position, bvec4(render_condition));

	// 主UV偏移
	UV = UV * u_uv1_scale.xy + u_uv1_offset.xy;
	// 副UV
	UV2 = UV2 * u_uv2_scale.xy + u_uv2_offset.xy;

	// 自定义通道混合
	vec4 fallback_value = vec4(1.0, 1.0, 0.5, 0.5);

	vec4 inverse_mask = vec4(1.0) - u_channel_mask;
	COLOR = COLOR * u_channel_mask + fallback_value * inverse_mask;

	// NDC坐标, 不是常规意义上的ndc：https://zhuanlan.zhihu.com/p/686166007
	v_ndc_position.xy = (projected_position.xy + projected_position.w) * 0.5;
	v_ndc_position.zw = projected_position.zw;

	// 顶点到摄像机的方向向量
	v_view_dir = CAMERA_POSITION_WORLD - v_world_position;

	// 法线处理
	vec3 normal = NORMAL;
	vec3 tangent = vec3(0.0, 0.0, -1.0) * abs(normal.x);
	tangent += vec3(1.0, 0.0, 0.0) * abs(normal.y);
	tangent += vec3(1.0, 0.0, 0.0) * abs(normal.z);
	tangent = normalize(tangent);

	vec3 binormal = vec3(0.0, 1.0, 0.0) * abs(normal.x);
	binormal += vec3(0.0, 0.0, -1.0) * abs(normal.y);
	binormal += vec3(0.0, 1.0, 0.0) * abs(normal.z);
	binormal = normalize(binormal);

	NORMAL = normalize((MODELVIEW_NORMAL_MATRIX * vec3(normal)).xyz); // local space -> view space
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(binormal, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(tangent, 0.0)).xyz);
	v_world_normal = vec4(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), 0.0); // view space -> world space
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
uniform sampler2D u_texture_light_map : filter_linear_mipmap, repeat_enable;
group_uniforms;

group_uniforms u_shadow_map_group;
uniform sampler2D u_texture_shadow_map : filter_linear_mipmap, repeat_enable;
global uniform float g_u_character_shadow_factor = 1.0; // 已核对数据
uniform vec4 u_rim_shadow_offset = vec4(0.0, 0.0, 0.0, 0.0); // 已核对数据
uniform float u_shadow_ramp = 1.0; // 已核对数据
uniform vec4 u_skin_shadow_color:source_color =  vec4(0.0,0.0,0.0,0.0); // 皮肤暗部颜色 // 已核对数据
uniform vec4 u_level_shadow_color:source_color =  vec4(0.0,0.0,0.0,0.0); // 常规部位暗部颜色 // 已核对数据
group_uniforms;


group_uniforms u_light;
global uniform bool g_u_character_disable_local_main_light = true;//禁用本地角色主光照 // 已核对数据
uniform bool u_character_disable_local_light = false;//禁用本地角色主光照 // 已核对数据
instance uniform vec4 u_main_light_position : instance_index(0) = vec4(-0.38036, 0.43589, 0.81568, 0.00); // 已核对数据
global uniform vec4 g_u_character_local_main_light_position = vec4(-0.38036, 0.43589, 0.81568, 0.00); // 已核对数据
uniform bool u_is_monster = false; //是否为怪物 // 已核对数据
global uniform vec4 g_u_monster_light_dir = vec4(-0.3234, 0.64279, 0.69427, 0.0); // 已核对数据
instance uniform vec4 u_custom_main_light_dir : instance_index(4) = vec4(0.0,0.0,0.0,0.0); // 已核对数据

uniform vec4 u_monster_light_color:source_color = vec4(1.0, 1.0, 1.0, 1.0); // 已核对数据
uniform vec4 u_light_color:source_color = vec4(1.0,1.0,1.0,1.0); // 已核对数据
uniform float u_lightmap_intensity_multiplier = 1.0;//光照贴图强度系数
uniform vec4 u_new_local_light = vec4(0.0,0.0,0.0,0.0); // 已核对数据 // x控制亮度。y控制增加额外颜色的数量。z控制暗部的色彩倾向强度。
group_uniforms;


group_uniforms u_diffuse_group;
uniform sampler2D u_texture_diffuse_ramp : source_color, filter_linear, repeat_disable;
uniform sampler2D u_texture_diffuse_cool_ramp : source_color, filter_linear, repeat_disable;
global uniform float g_u_character_toon_ramp_mode = 0.2; // 已核对数据
uniform float u_character_toon_ramp_mode_compensation = 0.2; // 已核对数据
group_uniforms;

group_uniforms u_metallic_group;
uniform bool u_enable_metal_reflection_flag =  true; // 已核对数据
group_uniforms;

group_uniforms u_spherical_group;
uniform vec4 u_skin_tint_for_overexposed:source_color =  vec4(1.0,1.0,1.0, 0.5);  // 已核对数据
uniform vec4 u_accessory_tint_for_overexposed:source_color =  vec4(1.0,1.0,1.0, 0.5);  // 已核对数据
uniform vec4 u_skin_tint_for_normal:source_color = vec4(1.0,1.0,1.0, 0.5);  // 已核对数据
uniform vec4 u_accessory_tint_for_normal:source_color = vec4(1.0,1.0,1.0, 0.5);  // 已核对数据
uniform float u_remap_max = 1.0; // 已核对数据
uniform float u_remap_min = 0.0; // 已核对数据
uniform float u_remap_middle = 0.55; // 已核对数据
uniform float u_shadow_brightness = 0.0; // 已核对数据
group_uniforms;

group_uniforms u_contrast_group;
uniform bool u_contrast_switch = false; // 已核对数据
group_uniforms;


group_uniforms u_outline_group;
instance uniform vec4 u_light_position : instance_index(9) = vec4(0.0,0.0,0.0,0.0); // 已核对数据
instance uniform vec4 u_outline_light_direction : instance_index(10) = vec4(0.0,0.0,0.0,0.0); // 已核对数据 // 虚拟的边缘光基准方向，边缘光：取决于模型表面朝向和“基准方向”的关系。漫反射光：取决于光线飞行方向和“基准方向”的关系。
uniform vec4 u_dark_area_tint = vec4(0.0,0.0,0.0,0.0); // 已核对数据
uniform bool u_local_main_light_disabled = true; // 已核对数据
uniform vec4 u_outline_additive_factor: source_color = vec4(0.0,0.0,0.0,0.0); // 已核对数据

group_uniforms;


group_uniforms u_rim_shadow_group;
uniform vec4 u_rim_shadow_color: source_color = vec4(0.0,0.0,0.0,0.0);
uniform float u_rim_shadow_width = 0.00; // 已核对数据
uniform float u_rim_shadow_feather = 0.99; // 已核对数据
global uniform vec4 g_u_rim_shadow_color =  vec4(1.0,1.0,1.0,0.50196); // 边缘阴影的modulate，会乘算 // 已核对数据
uniform float u_rim_shadow_ct = 1.0; //边缘阴影对比度，决定边缘阴影是硬朗的卡通风格，还是柔和的写实风格。 // 已核对数据
uniform float u_rim_shadow_intensity = 1.0; // 已核对数据
global uniform float g_u_rim_shadow_intensity = 1.0; // 已核对数据
group_uniforms;

// Rows 1/6 carry numeric parameters. Color rows are decoded explicitly at fetch.
uniform sampler2D u_material_values_pack_lut : filter_nearest, repeat_disable;


group_uniforms u_specular_group;
uniform vec4 u_specular_color: source_color = vec4(0.0,0.0,0.0,1.0); // 已核对数据
uniform float u_specular_shininess = 10.0; // 已核对数据
uniform float u_specular_roughness = 0.02; // 已核对数据
uniform float u_specular_intensity = 1.0; // 已核对数据
global uniform vec4 g_u_specular_color =  vec4(1.0,1.0,1.0,0.5); //高光颜色 // 已核对数据
global uniform float g_u_specular_intensity =  1.0; //高光强度 // 已核对数据
uniform float u_specular_shadow_offset =  0.1;
uniform float u_specular_shadow_multiple =  1.0;

group_uniforms;

group_uniforms u_emissive_group;
uniform float u_emission_threshold = 1.0; // 发光阈值，只有高于这个值才会发光 // 已核对数据
uniform float u_emission_intensity = 0.0; // 发光强度 // 已核对数据
group_uniforms;

group_uniforms u_npr_extended_surface;
uniform bool u_npr_stocking_enabled = false;
uniform float u_npr_stocking_strengths[8];
uniform vec4 u_npr_stocking_color : source_color = vec4(0.28, 0.32, 0.45, 1.0);
uniform vec4 u_npr_stocking_shadow_color : source_color = vec4(0.08, 0.09, 0.15, 1.0);
uniform vec4 u_npr_stocking_sheen_color : source_color = vec4(0.55, 0.65, 0.9, 1.0);
uniform float u_npr_stocking_edge_power : hint_range(0.25, 16.0) = 3.0;
uniform float u_npr_stocking_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float u_npr_stocking_global_strength : hint_range(0.0, 1.0) = 1.0;

uniform bool u_npr_matcap_enabled = false;
uniform sampler2D u_npr_matcap_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float u_npr_matcap_strengths[8];
uniform vec4 u_npr_matcap_tint : source_color = vec4(1.0);
uniform float u_npr_matcap_shadow_strength : hint_range(0.0, 1.0) = 0.35;
uniform float u_npr_matcap_global_strength : hint_range(0.0, 1.0) = 1.0;

uniform bool u_npr_emission_hue_enabled = false;
uniform float u_npr_emission_hues[8];
uniform float u_npr_secondary_emission_strengths[8];
uniform float u_npr_emission_hue_speed = 0.0;
group_uniforms;


group_uniforms u_fresnel_group;
uniform vec4 u_fresnel_color: source_color = vec4(0.0,0.0,0.0,0.0); //菲涅尔颜色 // 已核对数据
uniform vec4 u_fresnel_BSI = vec4(1.0,1.0,1.0, 0.0); //菲涅尔 // 已核对数据
uniform float u_fresnel_color_strength = 1.0; //菲涅尔强度 // 已核对数据
group_uniforms;

global uniform vec4 g_u_add_color = vec4(0.0,0.0,0.0,1.0); //固定叠加色，乘法到albedo上 // 已核对数据


group_uniforms u_height_lerp_group;
uniform vec3 u_character_world_space_offset = vec3(0.0,0.0,0.0); // 角色的全局偏移 // 已核对数据
global uniform vec4 g_u_height_lerp_bottom_color: source_color = vec4(0.31373, 0.31373, 0.4902, 0.50); //高度渲染的底层渐变光 // 已核对数据
global uniform vec4 g_u_height_lerp_middle_color: source_color = vec4(1.0,1.0,1.0,0.5); //高度渲染的中层渐变光 // 已核对数据
global uniform vec4 g_u_height_lerp_top_color: source_color = vec4(1.0,1.0,1.0,0.5); //高度渲染的高层渐变光 // 已核对数据

global uniform float g_u_height_lerp_bottom = 0.4; // 已核对数据
global uniform float g_u_height_lerp_top = 0.2; // 已核对数据
group_uniforms;

group_uniforms u_bloom_group;
uniform float u_bloom_intensity = 0.02; // 已核对
global uniform bool g_u_one_minus_avatar_intensity_enable = false; // 全局是否开启颜色缩减 // 已核对
uniform bool u_one_minus_global_main_intensity_enable = false; // 本物体是否开启颜色缩减 // 已核对
global uniform float g_u_one_minus_avatar_intensity = 0; //全局缩减系数 // 已核对
uniform float u_one_minus_global_main_intensity = 4; //本物体缩减系数 // 已核对
group_uniforms;


group_uniforms u_special_effect_group;
uniform vec4 u_world_gen_params = vec4(300.0, 10.0, 800.0, 130.0); // 已核对
uniform float u_uv_distortion_scale = 0.1;// 已核对
uniform vec2 u_special_gen_uv_scale = vec2(1.0,1.0); // 已核对
uniform mat4 u_special_plane = mat4(vec4(-1.0, 0.0, 0.0, 0.0), vec4(0.00, 1.0, 0.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 1.0, 0.00, 0.0)); // 特殊效果平面 // 已核对
uniform float u_plane_feather_width = 40.0; // 羽化/过渡区域的宽度和方向 // 已核对
uniform float u_effect_intensity_B = 1.0;   // 效果强度参数B // 已核对
uniform float u_plane_offset = 6.0;        // 平面的偏移量 // 已核对

uniform float u_pattern_animation_time = 0.0;     // 图案的动画时间/进度 // 已核对
uniform float u_pattern_animation_speed = 0.0;    // 图案的动画速度/幅度 // 已核对
uniform float u_pattern_v_offset_A = 0.5625;         // 图案A的纵向UV偏移 // 已核对
uniform float u_pattern_v_offset_B = 0.8125;         // 图案B的纵向UV偏移 // 已核对
uniform sampler2D u_effect_pattern_texture: source_color, filter_linear_mipmap, repeat_enable; // 用于采样的图案或噪声纹理
uniform float u_brightness_intensity = 0.0; // 已核对

group_uniforms;


group_uniforms u_fog_group;
uniform float u_fog_density = 0.0; // 雾的密度 // 已核对
uniform float u_fog_offset = 0.0; // 雾的偏移 // 已核对
uniform float u_fog_intensity = 0.0; // 雾的强度 // 已核对
uniform float u_fog_overall_intensity = 0; // 雾效总强度 // 已核对
uniform mat4 u_ndc_to_fog_space_matrix = mat4(vec4(0.47635, 0.0, 0.0, 0.0), vec4(0.00, 0.26795, 0.0, -0.29739), vec4(0.0, 7.89598e-09, 0.00, 0.14703), vec4(0.0, -7.89598E-09, -1.00, -0.14703)); // NDC到雾空间的变换矩阵，本质只有zw通道会被使用 // 已核对
uniform sampler3D u_texture_fog : source_color, filter_linear_mipmap, repeat_enable;
group_uniforms;


group_uniforms u_dither_group;
// 1: Dither Mode 1 (16 color levels)
// 2: Dither Mode 2 (32 color levels)
// 3: Dither Mode 3 (32/64/32 R/G/B levels)
uniform int u_color_mode = 0; // 已核对
const vec4 c_dither_values = vec4(-0.01171875, 0.00390625, 0.01171875, -0.00390625); // 已核对

group_uniforms;

uniform float u_character_shadow_factor_u = 0.0; // 强度采样使用的u // 已核对


void fragment() {
	vec4 now_last_pass_color = vec4(1.0,1.0,1.0,1.0);
	vec3 debug_color = vec3(-1.0,-1.0,-1.0);
	// --- flip fragcoord ---
	// 根据平台和视图设置，翻转屏幕坐标以保持一致性。注意这段代码暂时没有任何作用，但是请暂时保留
	vec2 center = VIEWPORT_SIZE * 0.5;
	vec2 flipped_coord = (FRAGCOORD.xy - center) * c_flip_modes[u_view_flip_index] + center;

	// --- base color ---
	// 根据渲染的是正面还是背面，选择对应的UV坐标来采样纹理。
	vec2 new_uv_1 = vec2(UV.x,1.0-UV.y);
	vec2 new_uv_2 = vec2(UV2.x,1.0-UV2.y);

	vec4 base_map = texture(u_texture_base_map, new_uv_1);
	//vec4 base_map = texture(u_texture_base_map, UV);
	vec4 base_color = u_base_color; // 调制色，和albedo_tex中的颜色相乘

#ifdef TOON_BACK_COLOR
	vec4 back_map = texture(u_texture_base_map, new_uv_2);
	base_map = mix(back_map, base_map, bvec4(FRONT_FACING));
	base_color = mix(u_back_color, base_color, bvec4(FRONT_FACING));
#endif

	vec4 albedo = base_map * base_color;
	float hosiery_domain = 0.0;
	float hosiery_coverage = 0.0;
	float hosiery_compression = 0.0;
	vec3 hosiery_weave = vec3(0.0);
	vec3 hosiery_authored = vec3(0.0);
		float wetness = 0.0;
		vec4 material_wetness = vec4(0.0); // textile, coated/leather, polymer, metal
	if (u_npr_wardrobe_enabled) {
		vec4 garment = texture(u_npr_garment_mask, new_uv_1);
		float luminance = dot(albedo.rgb, vec3(0.2126, 0.7152, 0.0722));
		vec3 dye = garment.r * u_npr_garment_primary.rgb
			+ garment.g * u_npr_garment_secondary.rgb + garment.b * u_npr_garment_trim.rgb;
		float coverage = clamp(dot(garment.rgb, vec3(1.0)), 0.0, 1.0);
		// Relative dye in linear space retains printed shading and black detail.
		// Reference luminance follows each original cloth region, not a gain/bias.
		float reference = dot(garment.rgb, vec3(0.18, 0.035, 0.72));
		vec3 dyed = dye * (luminance / max(reference, 0.001));
		albedo.rgb = mix(albedo.rgb, dyed, coverage * u_npr_garment_mix);
		hosiery_domain = garment.a * npr_hosiery_domain;
		hosiery_authored = npr_hosiery_authored_layers(new_uv_1) * npr_hosiery_domain;
		if (u_npr_hosiery_metric_seams) {
			// Keep the boundary at the call site so editor include hot reload cannot
			// leave a new helper call paired with an older cached include resource.
			float height_aa = max(fwidth(npr_hosiery_rest_position.y), 0.0001);
			float height_coverage = 1.0 - smoothstep(u_npr_hosiery_height - height_aa,
				u_npr_hosiery_height, npr_hosiery_rest_position.y);
			hosiery_domain *= height_coverage;
			hosiery_authored *= height_coverage;
			hosiery_authored.g = npr_hosiery_metric_stitch(npr_hosiery_rest_position)
				* clamp(u_npr_stitch_strength, 0.0, 1.0) * hosiery_domain;
		}
		float clothing_domain = step(0.01, coverage) * (1.0 - hosiery_domain);
		float wet_scope = mix(u_npr_wetness_regions[0], u_npr_wetness_regions[1], hosiery_domain);
		if (u_npr_garment_vertex_regions) {
			// Garment dye coverage describes original clothing, not attachments.
			// Independent equipment has its own material; merged equipment is tagged.
			wet_scope = mix(wet_scope, 0.0, clothing_domain);
			wet_scope = mix(wet_scope, u_npr_wetness_regions[3], npr_equipment_domain);
		} else {
			wet_scope = mix(wet_scope, u_npr_wetness_regions[3], clothing_domain);
		}
			wetness = texture(u_npr_wetness_map, new_uv_1).r * clamp(wet_scope, 0.0, 1.0);
			if (u_npr_material_wetness_enabled) {
				vec4 material_regions = texture(u_npr_material_wetness_map, new_uv_1);
				material_regions /= max(dot(material_regions, vec4(1.0)), 1.0);
				material_wetness = material_regions * clamp(u_npr_wetness_regions[3], 0.0, 1.0)
					* (1.0 - hosiery_domain) * (1.0 - npr_equipment_domain);
				// Absorption belongs to the base reflectance, not a white overlay.
				albedo.rgb *= 1.0 - dot(material_wetness, vec4(0.25, 0.10, 0.0, 0.0));
			}
	}
	vec2 rain = vec2(0.0);
	float rain_cloth = 0.0;
	if (u_npr_rain_enabled && u_npr_wardrobe_enabled) {
		vec4 rain_regions = texture(u_npr_material_wetness_map, new_uv_1);
		rain_cloth = rain_regions.r;
		float rain_scope = max(clamp(dot(rain_regions, vec4(1.0)), 0.0, 1.0),
			hosiery_domain * step(0.01, u_npr_hosiery_opacity));
		rain = clamp(vec2(texture(u_npr_rain_field, npr_rain_uv).r,
			texture(u_npr_rain_heads, npr_rain_uv).g), vec2(0.0), vec2(1.0)) * rain_scope
			* step(0.99, npr_rain_receiver) * (1.0 - npr_equipment_domain);
	}
	now_last_pass_color = albedo;

	//debug_color = albedo.rgb;
	// --- Light Map ---
	// gba通道包含了多个用于光照计算的遮罩信息。r通道控制RimLightWidth强度。g通道控制明暗阈值，类似ao，最终用于dot(halfLambert.xx,mask.yy)。b通道控制高光阈值，或者说范围。a通道控制这个地方是什么部位的采样，比如手，肩等。
	vec4 mask = texture(u_texture_light_map, FRONT_FACING? new_uv_1:new_uv_2);
	if (u_npr_wardrobe_enabled && u_npr_leg_ao_repair_enabled) {
		vec2 repair_uv = FRONT_FACING ? new_uv_1 : new_uv_2;
		float repair = step(u_npr_leg_ao_repair_uv.x, repair_uv.x)
			* step(repair_uv.x, u_npr_leg_ao_repair_uv.z)
			* step(u_npr_leg_ao_repair_uv.y, repair_uv.y)
			* step(repair_uv.y, u_npr_leg_ao_repair_uv.w)
			* step(u_npr_leg_ao_repair_values.x, npr_hosiery_rest_position.y)
			* step(npr_hosiery_rest_position.y, u_npr_leg_ao_repair_values.y)
			* step(npr_hosiery_rest_position.x, 0.0)
			* npr_hosiery_domain * texture(u_npr_garment_mask, repair_uv).a;
		mask.g = mix(mask.g, max(mask.g, u_npr_leg_ao_repair_values.z), repair);
	}
	vec4 surface_fx = npr_surface_effects(new_uv_1);
	if (!npr_visibility_keep(FRAGCOORD.xy)) {
		discard;
	}
	float dissolve_distance = npr_dissolve_signed_distance(new_uv_1, v_world_position, surface_fx.a);
	if (dissolve_distance < 0.0) {
		discard;
	}

	#ifdef TOON_HAIR
		float shadow_AO = mask.y + mask.y;
	#else
		float shadow_AO = (mask.y + mask.y) * COLOR.r;
	#endif

	// --- ramp level ---
	float ramp_level = floor(mask.a * 8.0); // 从light map图的a通道读取部位信息,将其量化为0-7的整数等级,用于选择Ramp贴图的行
	ramp_level = fract(0.125 * ramp_level) * 8.0f;


	// --- shadow map ---

	float shadow_u_coord = u_character_shadow_factor_u;
	float shadow_map = textureLod(u_texture_shadow_map, vec2(shadow_u_coord,0.0), 0.0).x;
	shadow_map = 1.25 * shadow_map - 0.25;
	shadow_map = clamp(shadow_map, 0.0, 1.0);
	float character_shadow_factor = mix(shadow_map, 1.0, g_u_character_shadow_factor);

	// --- 归一化一个等效光源及颜色 ---
	bool use_main_light = !((!g_u_character_disable_local_main_light)&&u_character_disable_local_light); // 只有当本地灯禁用，且全局灯未禁用时才用全局灯
	// g_u_character_disable_local_main_light = true u_character_disable_local_light = true => use_main_light = true
	// g_u_character_disable_local_main_light = true u_character_disable_local_light = false => use_main_light = true
	// g_u_character_disable_local_main_light = false u_character_disable_local_light = true => use_main_light = false
	// g_u_character_disable_local_main_light = false u_character_disable_local_light = false => use_main_light = true

	vec3 main_light_dir = use_main_light?u_main_light_position.xyz:g_u_character_local_main_light_position.xyz; // u_main_light_position 为角色本地主灯 g_u_character_local_main_light_position 为全局角色主灯（全局统一）
	bool is_monster = u_is_monster;
	vec3 light_dir = is_monster? g_u_monster_light_dir.xyz : main_light_dir; // 如果是怪物则使用全局怪物灯，否则使用 main_light_dir

	light_dir = mix(light_dir, u_custom_main_light_dir.xyz , u_custom_main_light_dir.w); // 将灯和本地自定义灯做一次混合，形成一个偏转
	light_dir = is_monster? g_u_monster_light_dir.xyz : light_dir;                  // 怪物灯不做任何偏转，只有人物灯需要偏转
	light_dir = normalize(light_dir);

	vec3 light_color = is_monster? u_monster_light_color.rgb : u_light_color.rgb;   // 根据是否是怪物，判断使用的灯颜色

	// --- 标准化数据 ---
	vec3 world_view_dir = normalize(v_view_dir); // 标准视线向量, 世界坐标系下的摄像机方向
	vec3 half_sum = world_view_dir + light_dir;
	vec3 world_bent_view_dir = half_sum / max(length(half_sum), 0.0001);
	vec4 world_normal = normalize(v_world_normal);
	world_normal = FRONT_FACING ? world_normal : -world_normal;
	// Water perturbs its own reflection, never the toon diffuse normal.
	// Screen derivatives of world position produce a metric surface gradient,
	// independent of mirrored UVs and the current skeletal pose.
	vec3 rain_normal = world_normal.xyz;
	if (u_npr_rain_enabled) {
		float height = rain.y * 0.0008 + rain.x * 0.00035;
		vec3 px = dFdx(v_world_position);
		vec3 py = dFdy(v_world_position);
		vec3 sx = cross(py, world_normal.xyz);
		vec3 sy = cross(world_normal.xyz, px);
		float determinant = dot(px, sx);
		if (abs(determinant) > 0.000000001) {
			vec3 gradient = (sx * dFdx(height) + sy * dFdy(height)) / determinant;
			rain_normal = normalize(world_normal.xyz - gradient);
		}
	}

	vec3 view_normal = (VIEW_MATRIX * vec4(world_normal.xyz,0.0)).xyz;
	vec3 view_dir = (VIEW_MATRIX * vec4(world_view_dir, 0.0)).xyz;

	float nodt_l = dot(world_normal.xyz, light_dir.xyz); // 漫反射因子 (NdotL)，表示光线与法线的夹角余弦关系
	float nodt_v = dot(world_normal.xyz, world_view_dir); // 菲涅尔/边缘光因子 (NdotV)，表示视线与法线的夹角余弦关系
	if (u_npr_wardrobe_enabled && u_npr_hosiery_opacity > 0.0) {
		hosiery_weave = npr_hosiery_weave(
			npr_hosiery_weave_coordinates(new_uv_1, npr_hosiery_rest_position));
		hosiery_coverage = npr_hosiery_coverage(u_npr_hosiery_opacity, nodt_v, hosiery_domain, hosiery_weave.x);
		hosiery_compression = npr_hosiery_compression(hosiery_coverage);
		vec3 fabric = u_npr_hosiery_fabric_color.rgb * (1.0 + hosiery_weave.x * 0.18);
		albedo.rgb = mix(albedo.rgb, fabric, hosiery_coverage);
		albedo.rgb = mix(albedo.rgb, u_npr_hosiery_fabric_color.rgb, hosiery_authored.r * 0.32);
		albedo.rgb = mix(albedo.rgb, u_npr_stitch_color.rgb, hosiery_authored.g);
		albedo.rgb *= 1.0 - 0.16 * hosiery_compression;
	}
	albedo.rgb *= 1.0 - rain.x * mix(0.24, 0.30, rain_cloth);

	vec3 view_dir_vs_offset = view_dir - u_rim_shadow_offset.xyz; // 视图空间下，视图方向减去shader偏移量
	view_dir_vs_offset = normalize(view_dir_vs_offset);
	float rim = dot(view_dir_vs_offset, view_normal); // 模型表面的法线与矫正后的视图方向做点积，判断夹角使用
	rim = clamp(rim, 0.0, 1.0);  // 这里其实是用一个伪边缘光照的角度做边缘光照的，例如模型的左后方固定有个灯。

	float modulated_lightmap_intensity = mask.y * 2.0 * u_lightmap_intensity_multiplier; // 将烘焙光贡献增强两倍，用于和实时光进行混合
	float half_lambert_diffuse = clamp((nodt_l * 0.5) + 0.5, 0.0, 1.0); // 将实时漫反射因子应用“半兰伯特”模型，使其从[-1,1]映射到[0,1]，避免暗部死黑


	float combined_light_factor = 2.0 * half_lambert_diffuse * modulated_lightmap_intensity;// 将处理后的实时漫反射光与增强后的烘焙光混合

	// --- 计算阴影系数 ---
	float final_shadow_factor = mix(character_shadow_factor, 1.0, g_u_character_local_main_light_position.w);
	final_shadow_factor = g_u_character_disable_local_main_light? character_shadow_factor:final_shadow_factor; // 如果禁用本地光照，则使用原始光照，否则使用混合光照


	// --- 通过Half-Lambert 2 计算强度 ---
	float final_color_factor = combined_light_factor * final_shadow_factor;

	float half_lambert = clamp(final_color_factor, 0.001, 1.0);
	float half_lambert_2 = (half_lambert * 0.85) + 0.15;

	// 判断是否处于深度阴影，限制光照贴图的最大亮度贡献，防止在阴影中出现过曝的烘焙光
	float lightmap_override_factor =  (final_shadow_factor<0.1)?min(mask.y * u_lightmap_intensity_multiplier , 0.8):1.0;

	// --- 根据一个亮度阈值(shadow_ramp)进行二值化处理，创建卡通风格的硬朗光照边缘 ---
	vec2 diffuse_ramp_uv = vec2(0.0,0.0);
	// 计算UV的X坐标：由卡通光照强度和深度阴影逻辑共同决定
	diffuse_ramp_uv.x = ((u_shadow_ramp < min(final_color_factor, 1.0)) ? 0.99 : half_lambert_2) * lightmap_override_factor;

	//debug_color = vec3(diffuse_ramp_uv.x);

	// 计算UV的Y坐标：由外部的 ramp_level 参数选择使用LUT中的哪一条颜色渐变带, 0.0625 = 1/16，这是一种精确选择第N行像素中心位置的技巧
	#ifdef TOON_HAIR
		diffuse_ramp_uv.y = 0.0625;
	#else
		diffuse_ramp_uv.y = ((ramp_level * 2.0) + 1.0) * 0.0625;
	#endif

	vec3 ramp = texture(u_texture_diffuse_ramp, diffuse_ramp_uv).rgb;
	vec3 ramp_cool = texture(u_texture_diffuse_cool_ramp, diffuse_ramp_uv).rgb;
	//debug_color = vec3(diffuse_ramp_uv.xy,1.0);
	// --- 混合冷暖 Ramp 色 ---
	float ramp_mode = npr_ramp_mix(g_u_character_toon_ramp_mode) - u_character_toon_ramp_mode_compensation;
	ramp_mode = clamp(ramp_mode, 0.0, 1.0);
	vec3 ramp_color = mix(ramp, ramp_cool, ramp_mode);
	npr_current_ramp = ramp_color;
	npr_ramp_uv_blend = vec3(diffuse_ramp_uv, ramp_mode);

	//debug_color = vec3(ramp_cool.rgb);

	// --- 利用亮度阈值的区域创建一个平滑的遮罩 ---
	float diffuse_shadow_mask = (diffuse_ramp_uv.x - 0.8)*10.0;
	diffuse_shadow_mask = (1.0 - smoothstep(0.0, 1.0, diffuse_shadow_mask)) * u_new_local_light.z;// 越亮值越小

	// --- 根据 ramp_level 判断是身体还是配件，应用不同的边缘光染色 ---
	bool is_skin = roundEven(ramp_level) == 0.0; // 判断是否是皮肤
	vec3 skin_shadow_color = ramp_color * mix(vec3(1.0), u_skin_shadow_color.rgb, diffuse_shadow_mask);
	vec3 accessory_shadow_color = ramp_color * mix(vec3(1.0), u_level_shadow_color.rgb, diffuse_shadow_mask);
	vec3 shadow_color = mix(accessory_shadow_color, skin_shadow_color, float(is_skin)); // 暗部颜色插值



  ///////////////////// kkkkkkkkkkkkkkk

	//debug_color = vec3(skin_shadow_color.rgb);

	// 用于开启或关闭“金属反射”效果
	bool is_stylized_reflection_enabled = u_enable_metal_reflection_flag;
	// 计算最终基础颜色的总亮度 (R+G+B)
	float base_color_luminance = dot(shadow_color, vec3(1.0));
	bool is_overexposed = (base_color_luminance > 2.9); // 检查是否过曝
	float skin_accessory_blend_factor = is_skin ? 0.0 : 1.0;


	// --- 计算球谐光照 (Spherical Harmonics)，实现环境光反射 ---
	// -- 漫反射 环境光 --

	// -- 准备用于“过曝”情况下的染色值 --
	vec3 skin_tint_color_for_overexposed = u_skin_tint_for_overexposed.xyz * u_skin_tint_for_overexposed.w * 2.0;
	vec3 accessory_tint_color_for_overexposed = u_accessory_tint_for_overexposed.xyz * u_accessory_tint_for_overexposed.w * 2.0;
	vec3 blended_tint_color_for_overexposed = mix(skin_tint_color_for_overexposed, accessory_tint_color_for_overexposed, skin_accessory_blend_factor);

	// -- 准备用于“正常”情况下的染色值 --
	vec3 skin_tint_color_for_normal = u_skin_tint_for_normal.xyz * u_skin_tint_for_normal.w * 2.0;
	vec3 accessory_tint_color_for_normal = u_accessory_tint_for_normal.xyz * u_accessory_tint_for_normal.w * 2.0;
	vec3 blended_tint_color_for_normal = mix(skin_tint_color_for_normal, accessory_tint_color_for_normal, skin_accessory_blend_factor);

	// -- 用于控制“过曝染色”的遮罩 (从亮部提取) --
	vec3 remapped_color_for_overexposed_mask = (shadow_color - vec3(u_remap_middle)) / max(u_remap_max - u_remap_middle, 0.0001);
	vec3 overexposed_tint_mask = clamp(remapped_color_for_overexposed_mask * 0.5 + vec3(0.5), vec3(0.0), vec3(1.0));

	// -- 用于控制“正常染色”的遮罩 (从暗部/中间调提取) --
	vec3 remapped_color_for_normal_mask = (shadow_color - vec3(u_remap_middle)) / max(u_remap_middle - u_remap_min, 0.0001);
	vec3 normal_tint_mask = clamp(remapped_color_for_normal_mask * 0.5 + vec3(0.5), vec3(0.0), vec3(1.0));

	// --- 步骤 4: 应用遮罩，并根据是否过曝选择最终的反射染色 ---
	vec3 final_overexposed_reflection = blended_tint_color_for_overexposed * overexposed_tint_mask;
	vec3 final_normal_reflection = blended_tint_color_for_normal * normal_tint_mask;

	vec3 selected_reflection_tint = is_overexposed ? final_overexposed_reflection : final_normal_reflection;

	// --- 根据是否“启用金属反射”，决定最终的颜色 ---
	vec3 final_pixel_color = is_stylized_reflection_enabled?selected_reflection_tint:shadow_color;

	bool enable_final_contrast_effect = u_contrast_switch; // 对比度调节


	// -- 基于阴影值，创建一个极其平滑的过渡因子，将原始阴影因子范围扩大，增加对比度 --
	float high_contrast_shadow = clamp(final_shadow_factor * 6.666, 0.0, 1.0);
	float smooth_shadow_factor = smoothstep(0.0, 1.0, high_contrast_shadow);

	// -- 计算一个亮度乘数，在阴影区域会使用 source_brightness, 在亮部区域会过渡到 1.0 --
	float source_brightness = u_shadow_brightness + 1.0;
	float final_contrast_multiplier = mix(source_brightness, 1.0, smooth_shadow_factor);

	vec3 contrast_adjusted_color = final_pixel_color * final_contrast_multiplier; // 应用对比度调整

	vec3 final_output_color = enable_final_contrast_effect?contrast_adjusted_color:final_pixel_color;

	final_output_color = final_output_color * albedo.rgb; // 和基础色混合
	int material_slot = clamp(int(ramp_level), 0, 7);
	float stocking_coverage = float(u_npr_stocking_enabled) * surface_fx.r
		* u_npr_stocking_strengths[material_slot] * u_npr_stocking_global_strength;
	if (u_npr_wardrobe_enabled && u_npr_hosiery_metric_seams) {
		// Wardrobe has a fitted, height-clipped garment domain. The legacy
		// surface map/material slots describe different equipment on this actor.
		stocking_coverage = float(u_npr_stocking_enabled)
			* u_npr_stocking_global_strength * hosiery_domain;
	}
	float stocking_facing = pow(clamp(1.0 - abs(nodt_v), 0.0, 1.0), u_npr_stocking_edge_power);
	vec3 stocking_tint = mix(u_npr_stocking_shadow_color.rgb, u_npr_stocking_color.rgb,
		clamp(half_lambert_diffuse, 0.0, 1.0));
	vec3 stocking_gain = mix(vec3(1.0), stocking_tint, clamp(stocking_coverage, 0.0, 1.0));
	vec3 stocking_bias = u_npr_stocking_sheen_color.rgb * stocking_facing * stocking_coverage;
	final_output_color = final_output_color * stocking_gain + stocking_bias;



	// ----------- 注意下面的逻辑并不是描边或者边缘光之类的东西，而是调整亮度，并且可以稍微加一点额外的颜色，会根据明暗做不同的运算，因为叠加同样的亮度，明暗区的变化是不一样的。
	vec3 outline_light_dir = v_world_position - u_light_position.xyz; // 描边灯方向
	outline_light_dir = normalize(outline_light_dir);
	float light_ndot_l = dot(outline_light_dir.xyz, u_outline_light_direction.xyz);
	float special_normal_dot = dot(v_world_normal.xyz, u_outline_light_direction.xyz); // 两个法线的余弦？

	float special_factor = clamp((special_normal_dot + 0.5) * 0.666, 0.0, 1.0);
	// 边缘光因子 (Rim Light)
	float lambert = smoothstep(0.0, 1.0, special_factor);
	// 漫反射光因子 (Diffuse Light)
	float darken_val = (light_ndot_l+1.0) *0.5;
	// 混合光因子
	float outline_color_factor = mix(lambert, darken_val, u_dark_area_tint.w);

	float main_light_active_multiplier = u_local_main_light_disabled ? 0.0 : 1.0; // 如果角色主光源被禁用，则描边效果也随之禁用
	outline_color_factor = outline_color_factor * main_light_active_multiplier;

	vec2 final_outline_params = outline_color_factor * u_new_local_light.xy; // x控制亮度。y控制控制附加描边光的亮度。z控制暗部的色彩倾向强度。

	// --- 分离色调 (Split Toning):为颜色的“暗部”和“亮部”创建两种不同的颜色路径 ---
	bvec3 is_color_channel_dark = lessThan(final_output_color, vec3(0.5));// 判断各颜色通道是否低于 0.5 (是否为暗部)

	// 暗部颜色
	vec3 dark_path_color = (final_output_color * 2.0) * u_dark_area_tint.xyz;

	// 亮部颜色
	vec3 inverted_color_doubled = (vec3(1.0) - final_output_color) * 2.0;
	vec3 inverted_tint = vec3(1.0) - u_dark_area_tint.xyz;
	vec3 bright_path_color = vec3(1.0) - (inverted_color_doubled * inverted_tint);

	// 根据每个通道的明暗，独立地从亮/暗路径中选择颜色
	vec3 split_toned_color = mix(bright_path_color, dark_path_color, is_color_channel_dark);

	// 使用描边因子，将分离色调效果混合到主颜色上
	vec3 color_with_outline = mix(final_output_color, split_toned_color, final_outline_params.x);
	// 再叠加上一个受强度控制的加色，完成最终效果
	color_with_outline = (final_outline_params.y * u_outline_additive_factor.xyz) + color_with_outline;


	//debug_color = dark_path_color;

	// --- 边缘阴影 (Rim Shadow):计算一个基于视角和光照的柔和内阴影，增加体积感。 ---
	#ifdef USE_MATERIAL_VALUES_LUT
		// 根据 ramp_level 从数据纹理(LUT)中加载该材质的边缘阴影参数
		ivec2 coord_for_color = ivec2(int(ramp_level), 5);
		ivec2 coord_for_params = ivec2(int(ramp_level), 6);
			vec3 rim_shadow_color = npr_srgb_to_linear(texelFetch(u_material_values_pack_lut, coord_for_color, 0).xyz);
		vec2 params = texelFetch(u_material_values_pack_lut, coord_for_params, 0).xy;
		float rim_shadow_width = params.x;
		float rim_shadow_feather = params.y;
	#else
		// 使用全局默认值
			vec3 rim_shadow_color = u_rim_shadow_color.rgb;
		float rim_shadow_width = u_rim_shadow_width;
		float rim_shadow_feather = u_rim_shadow_feather;
	#endif
	vec3 tinted_rim_shadow_color = rim_shadow_color * g_u_rim_shadow_color.xyz * g_u_rim_shadow_color.w; // 边缘阴影的颜色和强度
	float rim_shadow = pow(max(1.0 - rim, 0.001), u_rim_shadow_ct) *rim_shadow_width;
	rim_shadow = clamp(rim_shadow, 0.0, 1.0);

	// 根据宽度和羽化值，计算一个平滑的遮罩
	float remapped_mask = clamp((rim_shadow - rim_shadow_feather) / max(1.0 - rim_shadow_feather, 0.0001), 0.0, 1.0);
	rim_shadow = smoothstep(0.0, 1.0, remapped_mask);
	rim_shadow = rim_shadow * u_rim_shadow_intensity * g_u_rim_shadow_intensity * 0.25;
	rim_shadow_color = mix(vec3(1.0), tinted_rim_shadow_color * 2.0, rim_shadow);




	// ===================================================================
	// 高光 (Specular)
	// ===================================================================
	#ifdef USE_MATERIAL_VALUES_LUT
		// 根据 ramp_level 从数据纹理(LUT)中加载该材质的边缘阴影参数
		ivec2 coord_color = ivec2(int(ramp_level), 0);
		ivec2 coord_params = ivec2(int(ramp_level), 1);
			vec3 specular_color = npr_srgb_to_linear(texelFetch(u_material_values_pack_lut, coord_color, 0).xyz);

		vec3 params2 = texelFetch(u_material_values_pack_lut, coord_params, 0).xyz;
		float specular_shininess = params2.x;
		float cur_specular_roughness = params2.y;
		float specular_intensity = params2.z;
	#else
		// 使用全局默认值
			vec3 specular_color = u_specular_color.rgb;
		float specular_shininess = u_specular_shininess;
		float cur_specular_roughness = u_specular_roughness;
		float specular_intensity = u_specular_intensity;
	#endif
	// 计算高光颜色和强度
	//debug_color = vec3(specular_color);

	vec3 sp_color = mix(vec3(1.0), g_u_specular_color.rgb, g_u_specular_color.a);
	specular_color = specular_color * sp_color * (u_npr_studio_enabled ? 0.3 : g_u_specular_intensity);

	// Interpolated vertex normals are no longer unit length; use the fragment
	// normal so the tightened highlight does not inherit triangle-size artifacts.
	float specular_nodt_h = dot(world_normal.xyz, world_bent_view_dir);
	if (u_use_specular_exponent_override) {
		specular_shininess = u_specular_shininess;
	}
	if (u_npr_material_profile_enabled) {
		specular_shininess = u_npr_specular_exponents[clamp(int(ramp_level), 0, 7)];
	}
		float wet_sharpness = 1.0 + dot(material_wetness, vec4(0.3, 1.0, 2.3, 2.3));
		float specular = pow(max(specular_nodt_h, 0.01), specular_shininess * wet_sharpness);
	float specular_roughness = max(cur_specular_roughness, 0.001);



	float inv_mask_z = 1.0 - mask.z;
	#ifdef TOON_HAIR
		float shadow_value = dot(half_lambert, shadow_AO) * final_shadow_factor;
		float specular_shadow = u_specular_shadow_offset < shadow_value? 1.0:u_specular_shadow_multiple;
		specular = min(specular, 1.0);
		specular = npr_filtered_step(specular * specular_shadow - inv_mask_z, specular_roughness);
		// specular = specular * specular_color
	#else
		specular = npr_filtered_step(specular - inv_mask_z, specular_roughness);
		// specular = specular * specular_color;
	#endif

	vec3 spec_color = specular_color * specular * specular_intensity * albedo.xyz; // 最后的高光颜色
	if (u_npr_wardrobe_enabled && u_npr_hosiery_opacity > 0.0) {
		// The weave samples (U, 1-V); preserve both this flip and mirrored UV handedness.
		vec3 fabric_axis = (INV_VIEW_MATRIX * vec4(-BINORMAL, 0.0)).xyz;
		vec3 fabric_across = (INV_VIEW_MATRIX * vec4(TANGENT, 0.0)).xyz;
		vec3 fabric_specular = npr_hosiery_sheen(world_normal.xyz, world_bent_view_dir,
			fabric_axis, fabric_across, nodt_v, nodt_l, hosiery_weave);
		// Keep the fabric lobe in the existing shadowed specular accumulator.
		spec_color = mix(spec_color, fabric_specular, hosiery_coverage);
		spec_color += vec3(0.035, 0.028, 0.032) * hosiery_compression;
	}
	// Water film narrows the response and raises a view-dependent lobe while
	// preserving the authored base color. It does not use an unbounded add.
	float wet_fresnel = pow(clamp(1.0 - abs(nodt_v), 0.0, 1.0), 2.0);
		spec_color = mix(spec_color, u_npr_wet_specular_color.rgb * (0.28 + 0.72 * wet_fresnel), wetness);
		// A material water film requires a real light-facing half-vector lobe.
		// No constant Fresnel floor is added over the whole clothing surface.
		float film_exponent = 32.0 + 64.0 * clamp(material_wetness.b + material_wetness.a, 0.0, 1.0);
		float film_lobe = pow(max(specular_nodt_h, 0.0), film_exponent)
			* max(nodt_l, 0.0) * final_shadow_factor;
		float film_strength = dot(material_wetness, vec4(0.035, 0.10, 0.18, 0.18));
			spec_color += u_npr_wet_specular_color.rgb * film_lobe * film_strength
				* (0.2 + 0.8 * wet_fresnel);
		if (u_npr_rain_enabled) {
			float water_mask = clamp(rain.y + rain.x * 0.55, 0.0, 1.0);
			float water_lobe = pow(max(dot(rain_normal, world_bent_view_dir), 0.0), 36.0);
			float water_edge = pow(1.0 - clamp(dot(rain_normal, world_view_dir), 0.0, 1.0), 5.0);
			float water_light = max(dot(rain_normal, light_dir), 0.0) * final_shadow_factor;
			spec_color += light_color * water_mask * water_light
				* (water_lobe * mix(0.85, 0.38, rain_cloth) + water_edge * 0.055
					+ rain.y * 0.045);
		}
	//debug_color = vec3(spec_color);


	// ===================================================================
	// 自发光 (Emissive via Alpha) 可以让部分位置发光
	// ===================================================================
	float emission_factor = clamp((albedo.a - u_emission_threshold) / max(1.0 - u_emission_threshold, 0.001), 0.0, 1.0);
	emission_factor = (u_emission_threshold<albedo.a) ? emission_factor : 0.0; // 只有确实高于阈值时，遮罩才有效
	float secondary_emission = surface_fx.b * u_npr_secondary_emission_strengths[material_slot];
	float resolved_emission = max(emission_factor, secondary_emission);
	float emission_hue = u_npr_emission_hues[material_slot] + TIME * u_npr_emission_hue_speed;
	vec3 hue_emission = u_npr_emission_hue_enabled
		? npr_hue_rotate(albedo.rgb, emission_hue) : albedo.rgb;
	vec3 emission_color = mix(color_with_outline, hue_emission * u_emission_intensity, resolved_emission);

	// ===================================================================
	// 菲涅尔效应 (Fresnel Effect)
	// ===================================================================
	float fresnel = 1.0 - abs(nodt_v) - u_fresnel_BSI.x;
	fresnel = clamp(fresnel / max(u_fresnel_BSI.y, 0.001), 0.0, 1.0);
	vec3 fresnel_color =  u_fresnel_color.rgb * fresnel * u_fresnel_color_strength;
	fresnel_color = max(fresnel_color, vec3(0.0)); // 确保不会输出负值
	// ===================================================================
	// 混合颜色 ((自发光/主色 * 边缘阴影) + 高光) * 灯色 + 菲涅尔颜色 + 额外色
	// ===================================================================

	#ifdef TOON_HORN
		vec3 base_composite_color = emission_color + spec_color;
	#else
		vec3 base_composite_color = (emission_color * rim_shadow_color) + spec_color;
	#endif
	float matcap_strength = float(u_npr_matcap_enabled) * surface_fx.g
		* u_npr_matcap_strengths[material_slot] * u_npr_matcap_global_strength;
	matcap_strength *= 1.0 - hosiery_coverage;
	vec3 matcap_sample = texture(u_npr_matcap_texture, npr_matcap_uv(view_normal)).rgb;
	float matcap_visibility = mix(u_npr_matcap_shadow_strength, 1.0, half_lambert_diffuse);
	base_composite_color += matcap_sample * u_npr_matcap_tint.rgb * matcap_strength * matcap_visibility;
	base_composite_color = base_composite_color * light_color + fresnel_color;
	base_composite_color = (u_npr_studio_enabled ? vec3(0.0) : g_u_add_color.xyz) * albedo.xyz + base_composite_color;
	// Emission/Fresnel remain independent; only diffuse and specular receive CSM.
		npr_diffuse_contribution = color_with_outline * rim_shadow_color * light_color * (1.0 - resolved_emission);
	npr_specular_contribution = spec_color * light_color;
	base_composite_color += npr_edge_light(world_normal.xyz, world_view_dir, light_dir, SCREEN_UV, view_normal, -(VIEW_MATRIX * vec4(v_world_position, 1.0)).z) * (is_skin ? 0.3 : 1.0);

		now_last_pass_color.rgb = base_composite_color;
		// Track the derivative with respect to INPUT COLOR, not position/masks.
		// The four stages below are color-affine even when their masks use pow/LUTs.
			vec3 post_gain = stocking_gain;

	vec4 last_height_lerp_color = vec4(1.0,1.0,1.0,1.0);
	vec4 last_bloom_color = vec4(1.0,1.0,1.0,1.0);
	vec4 last_special_effect_color = vec4(1.0,1.0,1.0,1.0);
	vec4 last_fog_color = vec4(1.0,1.0,1.0,1.0);
	vec4 last_dithering_color = vec4(1.0,1.0,1.0,1.0);
	// ===================================================================
	// 高度渐变 从一定距离往下逐渐变暗，模拟脚比较暗的效果
	// ===================================================================
	if(u_debug_frag_height_lerp_enabled){
		float relative_height = v_world_position.y - u_character_world_space_offset.y; // 高度差
		float height_lerp01 = 1.0 - smoothstep(0.0, 1.0, clamp(relative_height / max(g_u_height_lerp_bottom, 0.001), 0.0, 1.0)); // 主遮罩:在渐变底部为 1，顶部为 0，平滑过渡。
		float height_lerp10 = smoothstep(0.0, 1.0, (relative_height - g_u_height_lerp_top)*2.0); // 次级遮罩:在高度超过一个阈值后，才开始从 0 平滑过渡到 1。

		float height_mask = clamp(1.0-height_lerp01-height_lerp10, 0.0,1.0);
		vec3 height_bottom_color = height_lerp01 * g_u_height_lerp_bottom_color.rgb * g_u_height_lerp_bottom_color.a;
		vec3 height_middle_color = height_mask * g_u_height_lerp_middle_color.rgb * g_u_height_lerp_middle_color.a;
		vec3 height_top_color = height_lerp10 * g_u_height_lerp_top_color.rgb * g_u_height_lerp_top_color.a;

		vec3 height_color = clamp(height_bottom_color+height_middle_color+height_top_color, vec3(0.0), vec3(1.0));
			last_height_lerp_color.rgb = base_composite_color * height_color * 2.0; // “乘算”(Tint/染色)
			post_gain *= height_color * 2.0;
		now_last_pass_color = last_height_lerp_color;
	}

 	// ===================================================================
	// 辉光效果(bloom)
	// ===================================================================

	if(u_debug_frag_bloom_enabled){
		#ifdef USE_MATERIAL_VALUES_LUT
			ivec2 coord_color_2 = ivec2(int(ramp_level), 6);
			ivec2 coord_param_2 = ivec2(int(ramp_level), 7);
			float bloom_intensity = texelFetch(u_material_values_pack_lut, coord_color_2, 0).z;
			vec3 cur_bloom_color = npr_srgb_to_linear(texelFetch(u_material_values_pack_lut, coord_param_2, 0).xyz);
			// debug_color = cur_bloom_color;
		#else
			vec3 cur_bloom_color = vec3(1.0,1.0,1.0);
			float bloom_intensity = u_bloom_intensity;
			// debug_color = cur_bloom_color;
		#endif
		vec3 bloom_multiplier = (cur_bloom_color * bloom_intensity) + vec3(1.0);
		vec3 bloom_color = now_last_pass_color.rgb * bloom_multiplier;

		// TODO:注意这行逻辑，需要做调整，身体部分的代码只使用了global_minus_intensity， 饰品/双面部分的才使用两者 global_minus_intensity * local_minus_intensity
		float global_minus_intensity = g_u_one_minus_avatar_intensity_enable?(1.0 -  g_u_one_minus_avatar_intensity):1.0;
		float local_minus_intensity = u_one_minus_global_main_intensity_enable?(1.0 - u_one_minus_global_main_intensity):1.0;

			last_bloom_color.rgb = bloom_color * global_minus_intensity * local_minus_intensity;
			post_gain *= bloom_multiplier * global_minus_intensity * local_minus_intensity;
		now_last_pass_color = last_bloom_color;
	}

	// ===================================================================
	// 动态特效 程序化纹理，以遮罩形式提供水面或热浪等扭曲、流动的视觉效果
	// ===================================================================
	if(u_debug_frag_special_effect_enabled){
		// 1. 根据坐标、摄像机等信息生成一套动态uv
		float distance_from_world_camera =  length(v_world_position - CAMERA_POSITION_WORLD);

		vec2 processed_position = mix(u_world_gen_params.xy , u_world_gen_params.zw, u_uv_distortion_scale);

		vec2 special_size = vec2(distance_from_world_camera, distance_from_world_camera) - processed_position;
		vec2 position_to_max_size = u_world_gen_params.zw - processed_position.xy;
		vec2 special_uv = clamp(vec2(special_size / position_to_max_size),vec2(0.0),vec2(1.0));
		special_uv = special_uv*u_special_gen_uv_scale;
		vec2 smoothed_uv_intermediate = special_uv - special_uv*special_uv;
		vec2 final_dynamic_uv = smoothed_uv_intermediate*special_uv + special_uv;

		// 2. 根据一个裁剪平面，生成一套遮罩
		float dist_from_plane = dot(v_world_position, u_special_plane[3].xyz) - u_special_plane[3].w;
		float plane_feather = u_plane_feather_width > 0.0 ? (dist_from_plane- u_plane_offset) : -(dist_from_plane- u_plane_offset);
		plane_feather = max(plane_feather, 0.0);
		float planar_mask = 1.0 - min(plane_feather / (abs(u_plane_feather_width) + 1.0), 1.0);
		float final_plane_mask = clamp((planar_mask * u_effect_intensity_B) - 1.0, 0.0, 1.0);

		float final_plane_mask_scale = clamp(final_plane_mask * u_special_gen_uv_scale.y -1.0,0.0,1.0);
		float animated_v_offset = (1.0 - u_pattern_animation_time) * u_pattern_animation_speed;

		float pattern_v_coord_A = (animated_v_offset * 0.125) + u_pattern_v_offset_A;

		vec3 sampled_pattern_A = textureLod(u_effect_pattern_texture, vec2(final_dynamic_uv.x, pattern_v_coord_A), 0.0).xyz;
		float main_mask = clamp(u_special_gen_uv_scale.x-1.0, 0.0, 1.0);

		vec2 spherical_masks = clamp(final_dynamic_uv, vec2(0.0), vec2(1.0));
		float main_spherical_mask = spherical_masks.x;    // 主效果区域的遮罩
		float feather_mask = spherical_masks.y; // 羽化过渡区域的遮罩

		vec3 special_final_color = (sampled_pattern_A * main_spherical_mask) + (-now_last_pass_color.rgb);
		vec3 special_base_blender_final_color = (special_final_color * main_spherical_mask) + now_last_pass_color.rgb;
		vec3 special_blender_final_color = (main_spherical_mask * sampled_pattern_A) + special_base_blender_final_color;

		vec3 special_color_1 = (special_blender_final_color*main_mask) + special_base_blender_final_color;

		float pattern_v_coord_B = animated_v_offset * 0.125 + u_pattern_v_offset_B;
		vec3 sampled_pattern_B_color = textureLod(u_effect_pattern_texture, vec2(final_dynamic_uv.y, pattern_v_coord_B), 0.0).xyz;

		// 用planar_mask调整图案B
		vec3 tinted_pattern_B = sampled_pattern_B_color * vec3(planar_mask);

		vec3 cur_blended_1 = tinted_pattern_B * feather_mask - special_color_1;
		vec3 cur_blended_2 = (feather_mask * cur_blended_1) + special_color_1;
		vec3 cur_blended_3 =  (tinted_pattern_B * feather_mask) + cur_blended_2;
		vec3 final_blended_color = (cur_blended_3 * final_plane_mask_scale) + cur_blended_2;

		float pattern_B_brightness = max(sampled_pattern_B_color.r, max(sampled_pattern_B_color.g, sampled_pattern_B_color.b)); // 取三通道的最大分量作为亮度值

		vec3 planar_masked_color = final_plane_mask * final_blended_color;

		vec3 cur_val_1 = (planar_masked_color * feather_mask) + special_color_1;

		vec3 feather_blended_color = mix(special_color_1, final_blended_color, feather_mask);

		float pattern_B_intensity = (u_brightness_intensity * (-pattern_B_brightness)) + pattern_B_brightness;

			last_special_effect_color.rgb = mix(feather_blended_color, cur_val_1, pattern_B_intensity);
			// Same affine chain as above, differentiated only with respect to color.
			// Pattern samples and spatial masks are independent of incoming lighting.
			float color_1_gain = (1.0 - main_spherical_mask) * (1.0 + main_mask);
			float blended_2_gain = (1.0 - feather_mask) * color_1_gain;
			float final_blended_gain = (1.0 + final_plane_mask_scale) * blended_2_gain;
			float value_1_gain = final_plane_mask * final_blended_gain * feather_mask + color_1_gain;
			float feather_gain = mix(color_1_gain, final_blended_gain, feather_mask);
			post_gain *= mix(feather_gain, value_1_gain, pattern_B_intensity);
		now_last_pass_color = last_special_effect_color;


	}

	// 特殊片段 222 开始
	//now_last_pass_color = (((-bloom_color * global_minus_intensity) * local_minus_intensity) + now_last_pass_color) * local_minus_intensity + last_bloom_color;
	// 特殊片段 222 结束

	// ===========================================================================================
	// 雾效果(fog) 使用一个非标准的、基于屏幕角度的因子去采样3D雾效查找表(LUT)，实现风格化的雾。
	// ===========================================================================================
	// TODO: 注意这里需要在使用双面小饰品时，采用一种新的散射模型
	if(u_debug_frag_fog_enabled && u_fog_overall_intensity > 0.0001){
		float normalize_z = (2.0*FRAGCOORD.z)-1.0;
		vec2 ndc = v_ndc_position.xy / v_ndc_position.w; // 归一化设备坐标 (NDC)，范围[0, 1]。
		vec2 transformed_ndc = (ndc * 2.0) - 1.0;
		vec2 temp_pos = (u_ndc_to_fog_space_matrix[0u].zw * transformed_ndc.x) + (u_ndc_to_fog_space_matrix[1u].zw * transformed_ndc.y) + (u_ndc_to_fog_space_matrix[2u].zw * normalize_z);
		temp_pos = temp_pos + u_ndc_to_fog_space_matrix[3u].zw;

		float angular_metric = - temp_pos.x / temp_pos.y; // 角度的“度量衡”，雾的浓度不仅和深度有关，还和它在屏幕上的位置有关。

		float linear_fog_factor = angular_metric * u_fog_density + u_fog_offset; // 非物理的度量衡进行缩放和偏移。
		float exponential_fog_factor = log2(max(linear_fog_factor, 0.0001)); // 应用“指数雾”模型调节强度
		float final_fog_factor = exponential_fog_factor * u_fog_intensity; // 应用全局强度缩放
		vec4 fog_data = textureLod(u_texture_fog, vec3(ndc.x, ndc.y, final_fog_factor), 0.0); // u_texture_fog 是雾效查找表采样雾的颜色

		vec3 color_with_fog = (now_last_pass_color.rgb * fog_data.a) + fog_data.rgb; // 标准的大气散射物理模型。
			last_fog_color = vec4(mix(now_last_pass_color.rgb, color_with_fog, u_fog_overall_intensity), albedo.a); // 混合“无雾颜色”和“有雾颜色”
			post_gain *= mix(1.0, fog_data.a, u_fog_overall_intensity);

		//debug_color = vec3(u_fog_overall_intensity);

		now_last_pass_color = last_fog_color;
	}

	// 下面是根据颜色模式添加扰动，有可能是像素化模型、小型化模型时使用
	#ifndef NPR_BODY_POST_LIGHT
		if (u_debug_frag_dithering_enabled) {
			now_last_pass_color.rgb = npr_dither_color(now_last_pass_color.rgb, u_color_mode, FRAGCOORD.xy);
		}
		#endif
		float dissolve_edge = npr_dissolve_edge(dissolve_distance) * float(u_npr_dissolve_enabled);
		now_last_pass_color.rgb = npr_apply_dissolve_edge(now_last_pass_color.rgb, dissolve_distance);
		post_gain *= 1.0 - dissolve_edge * u_npr_dissolve_edge_color.a;
			ALBEDO = now_last_pass_color.rgb;
		if (u_npr_diagnostic_mode != 0) {
			debug_color = npr_diagnostic_color(0, material_slot, v_world_normal.xyz, new_uv_1, albedo.rgb, 1.0, 0.0, 0);
			#ifdef NPR_BODY_POST_LIGHT
				MATERIAL_LIGHT_DATA = vec4(1.0);
			#endif
		}
	if(debug_color.r>=0.0||debug_color.g>=0.0||debug_color.b>=0.0){
		ALBEDO = debug_color.rgb;
	}
	if (u_npr_rain_debug) {
		ALBEDO = vec3(rain.x, rain.y, 0.0);
	}
	npr_final_color = ALBEDO;
	npr_key_direction_vs = (VIEW_MATRIX * vec4(light_dir, 0.0)).xyz;
	npr_surface_color = albedo.rgb;
		npr_pre_composition_color = base_composite_color;
		bool debug_override = debug_color.r >= 0.0 || debug_color.g >= 0.0 || debug_color.b >= 0.0;
		#ifdef NPR_BODY_POST_LIGHT
			// Accumulate shadow/fill in the original material space. In particular,
			// directional min must run BEFORE a negative derivative inverts it.
			npr_composition_gain = vec3(1.0);
			npr_composition_compatible = float(!debug_override);
			npr_body_post_gain = post_gain;
			npr_body_post_active = float(!debug_override);
		#else
			npr_composition_gain = post_gain;
			// Old engines cannot represent the nonlinear/signed chain safely.
		npr_composition_compatible = float(!(u_debug_frag_dithering_enabled && (u_color_mode & 3) != 0) && all(greaterThanEqual(post_gain, vec3(0.0))) && !debug_override);
		#endif
		// Clamp in the same pre-post space as the recorded diffuse/specular terms.
		npr_diffuse_contribution = min(npr_diffuse_contribution, max(base_composite_color, vec3(0.0)));
	EMISSION = npr_final_color;
	ALBEDO = vec3(1.0);
		#ifdef TOON_BACK_COLOR
			ALPHA = albedo.a * u_npr_visibility_alpha; // 双面材质会用这个
		#else
			ALPHA = mix(1.0, u_npr_stocking_opacity, clamp(stocking_coverage, 0.0, 1.0))
				* u_npr_visibility_alpha;
		#endif
}

#ifdef NPR_BODY_POST_LIGHT
void post_light() {
		if (u_npr_diagnostic_mode == 7) {
			POST_LIGHT_COLOR = vec3(MATERIAL_LIGHT_DATA.x);
		} else if (npr_body_post_active > 0.5) {
		// Fragment already evaluated F(base), including each affine bias once.
		// Replace the raw increment by gain * increment without dividing by gain
		// or subtracting/reconstructing the authored base (zero gains are valid).
		// Use the native-scaled direct term: SSAO/decal AO and metallic may alter
		// it after light(), even though this shader itself uses neutral ALBEDO.
		POST_LIGHT_COLOR += POST_LIGHT_DIRECT * (npr_body_post_gain - vec3(1.0));
		if (u_debug_frag_dithering_enabled) {
			POST_LIGHT_COLOR = npr_dither_color(POST_LIGHT_COLOR, u_color_mode, FRAGCOORD.xy);
		}
	}
}
#endif

void light() {
		if (u_npr_diagnostic_mode != 0) {
			#ifdef NPR_BODY_POST_LIGHT
				if (LIGHT_IS_DIRECTIONAL && dot(LIGHT, npr_key_direction_vs) > 0.9995) {
					MATERIAL_LIGHT_DATA.x = min(MATERIAL_LIGHT_DATA.x, clamp(ATTENUATION, 0.0, 1.0));
				}
			#endif
		} else if (LIGHT_IS_DIRECTIONAL && dot(LIGHT, npr_key_direction_vs) > 0.9995) {
		DIFFUSE_LIGHT = min(DIFFUSE_LIGHT, npr_shadow_delta(ATTENUATION, u_texture_diffuse_ramp, u_texture_diffuse_cool_ramp));
	} else {
		// Separate accumulator so key-shadow min() never erases additive fill.
		SPECULAR_LIGHT += npr_fill_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
	}
}
