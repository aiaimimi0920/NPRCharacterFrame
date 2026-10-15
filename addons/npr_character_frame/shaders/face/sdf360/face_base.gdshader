shader_type spatial;
#include "res://addons/npr_character_frame/shaders/face/sdf360/face_sdf360.gdshaderinc"
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
#include "res://addons/npr_character_frame/shaders/face/sdf360/face_lighting_block_0.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/face/sdf360/face_lighting_block_1.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/face/sdf360/face_lighting_block_2.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/face/sdf360/face_lighting_block_3.gdshaderinc"
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
    if (u_npr_sdf360_enabled) {
        sdf_factor = npr_sdf360_factor(v_sdf_uv, v_npr_sdf360_light);
    }


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
		if (u_npr_sdf360_enabled && u_npr_sdf360_debug) { debug_color = vec4(vec3(sdf_factor), 1.0); }
		if(debug_color.r>=0.0||debug_color.g>=0.0||debug_color.b>=0.0){
		ALBEDO = debug_color.rgb;
	}
}
