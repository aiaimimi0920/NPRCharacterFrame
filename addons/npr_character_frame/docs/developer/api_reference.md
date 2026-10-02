# API 声明索引

由 `.ci_script/tools/generate_api.py` 从实际源码生成。
此表列出公开类的方法与导出属性；内部下划线方法不作为公开 API。

## NPRCharacter

[源代码](../../npr_character.gd)

```gdscript
@export var definition: NPRCharacterDefinition
func set_face_light(direction: Vector3, weight: float) -> void:
func set_ramp_mix(value: float) -> void:
func set_fill_strength(value: float) -> void:
func set_sdf_feather(value: float) -> void:
func set_shadow_strength(value: float) -> void:
func set_outline_width(value: float) -> void:
func set_hair_highlight(value: float) -> void:
func set_face_expression(weights: Vector3) -> void:
func set_face_eye_expression(value: float) -> void:
func set_lip_outline_enabled(enabled: bool) -> void:
func set_stocking_strength(value: float) -> void:
func set_hosiery_compression(value: float) -> void:
func set_matcap_strength(value: float) -> void:
func set_hair_anisotropy(value: float) -> void:
func set_hair_side_fade(value: float) -> void:
func set_hair_silhouette(value: float) -> void:
func set_dissolve(value: float) -> void:
func set_visibility_alpha(value: float) -> void:
func set_auxiliary_buffer_enabled(value: bool) -> void:
func get_auxiliary_texture() -> Texture2D:
func set_hair_contact(value: float) -> void:
func set_depth_quality(value: int) -> void:
func set_rim_strength(value: float) -> void:
func get_world_bounds() -> AABB:
func intersect_role_ray(role: int, origin: Vector3, direction: Vector3) -> Dictionary:
func pick_surface(origin: Vector3, direction: Vector3) -> Dictionary:
```

## NPRCharacterDefinition

[源代码](../../npr_character_definition.gd)

```gdscript
@export var model_scene: PackedScene
@export var body_path := NodePath("Body")
@export var face_path := NodePath("Face")
@export var hair_path := NodePath("Hair")
@export var material_set: NPRCharacterMaterials
@export var use_source_materials := false
@export var material_profile: NPRMaterialProfile = NPRMaterialProfile.new()
@export var face_motion_profile: NPRFaceMotionProfile
@export var face_atlas_profile: NPRFaceAtlasProfile
@export var symbol_surface_profile: NPRSymbolSurfaceProfile
@export var comic_profile: NPRComicProfile
@export var eye_geometry_profile: NPREyeGeometryProfile
@export var hosiery_profile: NPRHosieryProfile
@export var wetness_profile: NPRWetnessProfile
@export var rain_profile: NPRRainProfile
@export var equipment_profile: NPREquipmentProfile
@export var showcase_camera_profile: NPRShowcaseCameraProfile
@export var showcase_palette_profile: NPRShowcasePaletteProfile
@export var showcase_height_profile: NPRShowcaseHeightProfile
@export_file("*.json") var performance_data_path := ""
@export_file("*.json") var soft_tissue_data_path := ""
@export_file("*.json") var hair_dynamics_data_path := ""
@export_file("*.json") var rig_layout_data_path := ""
@export_range(0.0, 100.0) var display_height := 3.0
func mesh_paths() -> Array[NodePath]:
func validate() -> PackedStringArray:
func load_performance_data() -> Dictionary:
func load_soft_tissue_data() -> Dictionary:
func load_hair_dynamics_data() -> Dictionary:
func load_rig_layout_data() -> Dictionary:
```

## NPRCharacterMaterials

[源代码](../../npr_character_materials.gd)

```gdscript
@export var body_base: Texture2D
@export var body_ilm: Texture2D
@export var body_lut: Texture2D
@export var body_ramp: Texture2D
@export var body_cool_ramp: Texture2D
@export var body_effects: Texture2D
@export var matcap_texture: Texture2D
@export var face_base: Texture2D
@export var face_ilm: Texture2D
@export var face_map: Texture2D
@export var face_ramp: Texture2D
@export var face_expression: Texture2D
@export var face_outline_control: Texture2D
@export var sdf_on_uv2 := false
@export var face_forward := Vector3(0, 0, 1)
@export var face_right := Vector3(1, 0, 0)
@export var hair_base: Texture2D
@export var hair_ilm: Texture2D
@export var hair_ramp: Texture2D
@export var hair_cool_ramp: Texture2D
@export var hair_effects: Texture2D
@export var hair_flow_map: Texture2D
@export var dissolve_noise: Texture2D
@export var hair_sheen_axis := Vector3(0, 0, 1)
@export var hair_side_axis := Vector3(1, 0, 0)
@export var body_outline_smooth_normal_source := SmoothNormalSource.VERTEX_NORMAL
@export var face_outline_smooth_normal_source := SmoothNormalSource.VERTEX_NORMAL
@export var hair_outline_smooth_normal_source := SmoothNormalSource.VERTEX_NORMAL
func validate() -> PackedStringArray:
func validate_optional() -> PackedStringArray:
func build() -> Array[ShaderMaterial]:
func apply_optional_to(source_materials: Array[ShaderMaterial]) -> bool:
func outline_smooth_normal_source(role: int) -> int:
```

## NPRComicProfile

[源代码](../../npr_comic_profile.gd)

```gdscript
@export var anchor_bone := ""
@export var anchor_origin := Vector3.ZERO
@export var card_offsets := PackedVector3Array()
@export var card_sizes := PackedVector2Array()
@export var tear_left := Vector4.ZERO
@export var tear_right := Vector4.ZERO
@export var hatching_left := Vector4.ZERO
@export var hatching_right := Vector4.ZERO
func validate() -> PackedStringArray:
func apply_material(material: ShaderMaterial) -> void:
```

## NPREquipmentProfile

[源代码](../../npr_equipment_profile.gd)

```gdscript
@export_file("*.json") var geometry_path := ""
@export var material_scene: PackedScene
@export var slot_labels := PackedStringArray()
@export var attachment_bones := PackedStringArray()
@export var swatch_uvs: Dictionary = {}
@export var material_slots: Dictionary = {}
func load_geometry() -> Dictionary:
func validate() -> PackedStringArray:
func validate_bones(bones: Variant) -> PackedStringArray:
func validate_geometry(data: Dictionary) -> PackedStringArray:
```

## NPRExpressionProfile

[源代码](../../npr_expression_profile.gd)

```gdscript
@export var behaviors: Dictionary = {}
func pose(behavior: StringName) -> Dictionary:
static func valid_pose(value: Dictionary) -> bool:
```

## NPREyeGeometryProfile

[源代码](../../npr_eye_geometry_profile.gd)

```gdscript
@export var model_scene: PackedScene
@export_file("*.json") var landmarks_path := ""
@export var gaze_gain := Vector2.ZERO
@export var aperture_size := Vector2.ONE
@export var aperture_slope := 0.0
@export_range(0.0, 1.0) var upper_shade := 0.0
@export var layer_depths := Vector4.ZERO
@export_range(0.0, 1.0) var closure_meeting := 0.5
@export var shell_offset := 0.0
@export var shell_bulge_max := 0.0
@export var shell_bulge_ratio := 0.0
@export var tear_tint := Color.WHITE
@export_range(0.0, 1.0) var tear_alpha := 0.0
@export_range(0.0, 0.05) var refraction_strength := 0.0
@export_range(1.0, 2.0) var ior := 1.0
@export_range(0.0, 0.02) var thickness := 0.0
@export_range(0.0, 1.0) var tear_transmission := 1.0
func load_landmarks() -> Dictionary:
func validate() -> PackedStringArray:
func validate_optics() -> PackedStringArray:
func apply_surface(material: ShaderMaterial, surface_name: String) -> void:
func apply_tear(material: ShaderMaterial) -> void:
static func validate_lid_profiles(data: Dictionary) -> PackedStringArray:
static func validate_landmarks(data: Dictionary) -> PackedStringArray:
static func validate_scene(instance: Node) -> PackedStringArray:
```

## NPRFaceAtlasProfile

[源代码](../../npr_face_atlas_profile.gd)

```gdscript
@export var accent_uv_min := Vector2.ZERO
@export var accent_uv_max := Vector2.ZERO
@export var accent_plate_uv := Vector2.ZERO
@export_range(0.0, 1.0) var skin_sample_v := 0.0
@export var replacement_eye_a_max_uv := Vector2.ZERO
@export_range(0.0, 1.0) var replacement_eye_b_min_u := 0.0
@export var replacement_eye_b_v_range := Vector2.ZERO
@export var round_eye_center_uv := Vector2.ZERO
@export var round_eye_aspect := Vector2.ZERO
@export var round_eye_pupil_radii := Vector2.ZERO
@export var round_eye_disc_radii := Vector2.ZERO
func validate() -> PackedStringArray:
func apply_material(material: ShaderMaterial) -> bool:
```

## NPRFaceMotionProfile

[源代码](../../npr_face_motion_profile.gd)

```gdscript
@export var expression_profile: NPRExpressionProfile
@export_file("*.json") var lid_surface_path := ""
@export var feature_component_limit := 0
@export var skin_component_min := 0
@export var eye_height_range := Vector2.ZERO
@export var eye_front_min := 0.0
@export var mouth_height_max := 0.0
@export var mouth_front_min := 0.0
@export var mouth_center_x := 0.0
@export var mouth_half_width := 0.0
@export var side_split_x := 0.0
@export var iris_max_u := 0.0
@export var iris_min_v := 0.0
@export var pupil_u_range := Vector2.ZERO
@export var pupil_min_v := 0.0
@export var glint_uv_bounds := Vector4.ZERO
@export var minimum_eye_vertices := 0
@export var expected_pupil_vertices := 0
@export var horizontal_motion := PackedVector3Array()
@export var vertical_motion := Vector3.ZERO
@export var pupil_scale_step := 0.0
@export var pupil_forward_offset := 0.0
@export var lid_centers := PackedVector2Array()
@export var lid_canvas_scale := Vector2.ZERO
func validate() -> PackedStringArray:
func load_lid_data() -> Dictionary:
static func validate_lid_data(data: Dictionary, face_vertex_count := -1) -> PackedStringArray:
```

## NPRHosieryProfile

[源代码](../../npr_hosiery_profile.gd)

```gdscript
@export_file("*.json") var normal_correction_path := ""
@export var weave_texture: Texture2D
@export var roughness_texture: Texture2D
@export var normal_texture: Texture2D
@export var garment_mask: Texture2D
@export var tulle_mask: Texture2D
@export var stitch_mask: Texture2D
@export var domain_height_range := Vector2(0.45, 1.55)
@export var domain_half_width := 0.32
@export var domain_full_width_below := 1.05
@export var cuff_band_width := 0.016
@export var cuff_stitch_offset := 0.012
@export var cuff_stitch_width := 0.0012
@export var textile_period_m := 0.0025
@export var textile_repeats := 8
@export var shell_offset_m := 0.00025
@export var leg_ao_repair_enabled := false
@export var leg_ao_repair_uv := Vector4(0, 0, 1, 1)
@export var leg_ao_repair_values := Vector3(0, 1, 0)
func validate() -> PackedStringArray:
func load_normal_correction() -> Dictionary:
func validate_normal_correction(vertices: PackedVector3Array) -> PackedStringArray:
func apply_normal_correction(arrays: Array) -> PackedStringArray:
func build_regions(
	vertices: PackedVector3Array, source_to_actor: Transform3D
) -> PackedFloat32Array:
func apply_material(material: ShaderMaterial) -> void:
func apply_body_material(material: ShaderMaterial) -> void:
func apply_cuff(material: ShaderMaterial) -> void:
func apply_leg_ao(material: ShaderMaterial) -> void:
func apply_textile(material: ShaderMaterial) -> void:
```

## NPRRainProfile

[源代码](../../npr_rain_profile.gd)

```gdscript
@export_file("*.json") var surface_path := ""
@export_file("*.bin") var chart_path := ""
@export_file("*.bin") var vertex_uv_path := ""
func load_surface() -> Dictionary:
func validate() -> PackedStringArray:
static func validate_surface(surface: Dictionary) -> PackedStringArray:
```

## NPRShowcaseCameraProfile

[源代码](../../npr_showcase_camera_profile.gd)

```gdscript
@export var view_heights := PackedFloat64Array()
@export var view_distances := PackedFloat64Array()
@export var horizontal_offset := 0.0
@export var vertical_offset := 0.0
@export_range(1.0, 179.0) var field_of_view := 36.0
@export var pressure_target := Vector3.ZERO
@export var pressure_distance := 1.0
func validate() -> PackedStringArray:
```

## NPRShowcaseHeightProfile

[源代码](../../npr_showcase_height_profile.gd)

```gdscript
@export var min_height := 0.0
@export var max_height := 0.0
@export var default_height := 0.0
@export var step := 0.0
func validate() -> PackedStringArray:
func accepts(value: float) -> bool:
```

## NPRShowcasePaletteProfile

[源代码](../../npr_showcase_palette_profile.gd)

```gdscript
@export var labels := PackedStringArray()
@export var rgb := PackedStringArray()
@export var default_index := 0
func validate() -> PackedStringArray:
func colors_at(index: int) -> Array[Color]:
```

## NPRStylePreset

[源代码](../../npr_style_preset.gd)

```gdscript
@export var display_name := ""
@export var character_values: Dictionary = {}
@export var lighting_values: Dictionary = {}
@export var face_light_direction := Vector3(0.15, 0.5, 0.85)
func apply(actor: NPRCharacter, scope: Scope = Scope.ALL) -> bool:
func is_valid() -> bool:
static func capture(actor: NPRCharacter) -> NPRStylePreset:
```

## NPRSymbolSurfaceProfile

[源代码](../../npr_symbol_surface_profile.gd)

```gdscript
@export var eye_centers := PackedVector2Array()
@export var eye_radius := Vector2.ZERO
@export var eye_ink_scale := Vector2.ZERO
@export var mouth_center := Vector2.ZERO
@export var mouth_radius := Vector2.ZERO
@export var mouth_ink_scale := Vector2.ZERO
@export var outline_eye_centers := PackedVector2Array()
@export var outline_eye_radius := Vector2.ZERO
@export var skin_front_min := 0.0
func validate() -> PackedStringArray:
func apply_material(material: ShaderMaterial) -> void:
```

## NPRWetnessProfile

[源代码](../../npr_wetness_profile.gd)

```gdscript
@export var body_mask: Texture2D
@export var material_regions: Texture2D
@export var eye_tear_mask: Texture2D
@export var hair_mask: Texture2D
@export var eye_tear_uv_limit := Vector2.ONE
func validate() -> PackedStringArray:
func apply_materials(
	body: ShaderMaterial, face: ShaderMaterial, hair_passes: Array[ShaderMaterial]
) -> void:
```

## NPRComicLayer

[源代码](../../runtime/npr_comic_layer.gd)

```gdscript
func play(
	kind: String,
	anchor: Node3D,
	duration := 1.5,
	offset := Vector3.ZERO,
	size := Vector2(0.18, 0.22),
	occlusion: Occlusion = Occlusion.SCENE,
	key: StringName = &"",
	tint := Color.WHITE,
	attachment: Attachment = Attachment.ANCHOR,
	surface_material: ShaderMaterial = null
) -> int:
func geometry_snapshot(token: int) -> Dictionary:
func pin(token: int, world_position: Vector3) -> void:
func cancel(token: int) -> void:
func clear() -> void:
func active_count() -> int:
func advance(delta: float) -> void:
```

## NPRDepthArray

[源代码](../../runtime/npr_depth_array.gd)

```gdscript
func replace(sources: Array[RID]) -> Error:
func update(sources: Array[RID], dirty_layers: PackedInt32Array) -> Error:
func update_layers(sources: Array[RID], destinations: PackedInt32Array) -> Error:
func release() -> void:
```

## NPRDepthGroupPlan

[源代码](../../runtime/npr_depth_group_plan.gd)

```gdscript
static func build(
	sizes: Array[Vector2i],
	bytes_per_pixel: int,
	payload_limit: int,
	live_limit: int,
	resident_payload_bytes := 0,
	layer_limit := DEFAULT_LAYER_LIMIT,
	row_limit := DEFAULT_ROW_LIMIT,
	max_group_count := 0
) -> Dictionary:
static func coalesce(
	plan: Dictionary,
	group_limit: int,
	payload_limit: int,
	live_limit: int,
	resident_payload_bytes := 0
) -> Dictionary:
```

## NPRDepthGroupStorage

[源代码](../../runtime/npr_depth_group_storage.gd)

```gdscript
func replace(sources: Array[RID], sizes: Array[Vector2i], plan: Dictionary) -> Error:
func update_view(view_index: int, sources: Array[RID]) -> Error:
func invalidate_view(view_index: int) -> Error:
func view_binding(view_index: int) -> Dictionary:
func status() -> Dictionary:
func release() -> void:
```

## NPRDepthGroupViewUpdate

[源代码](../../runtime/npr_depth_group_view_update.gd)

```gdscript
func queue_update(sources: Array[RID]) -> int:
func result() -> Dictionary:
func release() -> void:
```

## NPRDepthViewFlags

[源代码](../../runtime/npr_depth_view_flags.gd)

```gdscript
func reset(count: int) -> Error:
func set_ready(view: int, expected_epoch: int, ready: bool) -> Error:
func release() -> void:
```

## NPRDepthViewTable

[源代码](../../runtime/npr_depth_view_table.gd)

```gdscript
func update_views(rows: Array[Dictionary]) -> Error:
```

## NPRExpressionController

[源代码](../../runtime/npr_expression_controller.gd)

```gdscript
func set_base(pose: Dictionary) -> bool:
func play(behavior: StringName, duration: float, priority := 50, key: StringName = &"") -> int:
func push(
	pose: Dictionary,
	duration: float,
	priority := 50,
	key: StringName = &"",
	label: StringName = &"request"
) -> int:
func cancel(token: int) -> void:
func clear() -> void:
func active_count() -> int:
func advance(delta: float) -> Dictionary:
```

## NPRGeometryState

[源代码](../../runtime/npr_geometry_state.gd)

```gdscript
static func attach(mesh_source: MeshInstance3D, kind: int) -> NPRGeometryState:
func set_shadow_proxy(proxy: MeshInstance3D) -> void:
func refresh() -> void:
func apply_to(proxy: MeshInstance3D) -> void:
func sample_surface_vertices(surface: int, indices: PackedInt32Array) -> PackedVector3Array:
func intersect_ray(origin: Vector3, direction: Vector3) -> Dictionary:
```

## NPRKeyLightPool

[源代码](../../runtime/npr_key_light_pool.gd)

```gdscript
static func attach(viewport: Viewport, during_sync: bool = false) -> NPRKeyLightPool:
func register_member(
	member: Node3D, light: DirectionalLight3D, layer: int, direction: Vector3, shadows: bool
) -> void:
func unregister_member(member: Node3D) -> void:
func member_settings(member: Node3D) -> Dictionary:
func request(member: Node3D, direction: Vector3, shadows: bool) -> void:
func update_member_layer(member: Node3D, layer: int) -> void:
func configure_member(member: Node3D, overrides: Dictionary) -> bool:
func get_group_count() -> int:
func synchronize() -> void:
```

## NPRMaterialProfile

[源代码](../../runtime/npr_material_profile.gd)

```gdscript
@export_multiline var source_note := "Artist-authored; not recovered capture constants."
@export var capture_verified := false
@export var specular_exponents := PackedFloat32Array([24, 24, 24, 24, 24, 24, 24, 24])
@export var region_outline_enabled := false
@export var outline_colors := PackedColorArray(
@export var lip_outline_fix_enabled := false
@export_range(0.0, 1.0) var lip_outline_width_scale := 0.35
@export_range(0.0, 4.0, 0.1) var lip_outline_width_pixels := 0.7
@export var stocking_enabled := false
@export var stocking_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var stocking_color := Color(0.28, 0.32, 0.45)
@export var stocking_shadow_color := Color(0.08, 0.09, 0.15)
@export var stocking_sheen_color := Color(0.55, 0.65, 0.9)
@export_range(0.25, 16.0) var stocking_edge_power := 3.0
@export_range(0.0, 1.0) var stocking_opacity := 1.0
@export_range(0.0, 1.0) var stocking_global_strength := 1.0
@export var matcap_enabled := false
@export var matcap_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var matcap_tint := Color.WHITE
@export_range(0.0, 1.0) var matcap_shadow_strength := 0.35
@export_range(0.0, 1.0) var matcap_global_strength := 1.0
@export var emission_hue_enabled := false
@export var emission_hues := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var secondary_emission_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var emission_hue_speed := 0.0
@export var expression_shadow_color := Color(0.55, 0.32, 0.42)
@export var expression_highlight_color := Color(1.0, 0.65, 0.72)
@export var expression_blush_color := Color(1.0, 0.32, 0.42)
@export var face_skin_tint := Color.WHITE
@export_range(0.0001, 4.0, 0.0001) var face_distance_lut_distance_scale := 0.05
@export var hair_anisotropy_enabled := false
@export var hair_anisotropy_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var hair_anisotropy_roughness := PackedFloat32Array(
@export var hair_anisotropy_shifts := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var hair_anisotropy_color := Color(0.82, 0.9, 1.0)
@export_range(0.0, 1.0) var hair_anisotropy_global_strength := 1.0
@export_range(0.0, 1.0) var hair_side_fade_strength := 0.0
@export var hair_side_fade_range := Vector2(0.45, 0.9)
@export_range(-1, 1, 1) var hair_side_choose := 0
@export_range(0.0, 1.0) var hair_silhouette_strength := 0.0
@export_range(0.25, 8.0) var hair_silhouette_power := 2.0
@export var hair_silhouette_tint := Color(0.72, 0.75, 0.95)
@export_range(0.0, 0.25) var dissolve_edge_width := 0.04
@export var dissolve_edge_color := Color(0.25, 0.75, 1.0)
@export var dissolve_world_space := false
@export var dissolve_world_scale := Vector2.ONE
@export var dissolve_world_offset := Vector2.ZERO
@export_range(0.0, 1.0) var visibility_alpha_cutoff := 0.0
@export var visibility_dither_enabled := false
func is_valid() -> bool:
func apply_to(material: ShaderMaterial) -> bool:
func apply_body(material: ShaderMaterial) -> bool:
func apply_face(material: ShaderMaterial) -> bool:
func apply_hair(material: ShaderMaterial) -> bool:
func apply_outline(material: ShaderMaterial) -> bool:
func apply_visibility(material: ShaderMaterial) -> bool:
```

## NPRRenderDiagnostics

[源代码](../../runtime/npr_render_diagnostics.gd)

```gdscript
func setup(actor: NPRCharacter, canvases: Array[MeshInstance3D] = []) -> void:
func set_mode(value: int) -> void:
func set_hair_hidden(value: bool) -> void:
func set_canvas_visibility(canvas: MeshInstance3D, value: bool) -> void:
func reset() -> void:
```

## NPRScreenQuality

[源代码](../../runtime/npr_screen_quality.gd)

```gdscript
@export var near_pixels := 900.0
@export var middle_pixels := 350.0
@export_range(0.0, 0.4) var hysteresis := 0.15
@export_range(0.1, 2.0) var settle_seconds := 0.35
func setup(actor: NPRCharacter, views: Array[Camera3D] = []) -> void:
func set_enabled(value: bool) -> void:
func evaluate(delta: float) -> void:
func requested_tier(height: float) -> int:
func budget() -> Dictionary:
static func projected_height(camera: Camera3D, transform: Transform3D, bounds: AABB) -> float:
```
