extends "framework_quality_comic_regression.gd"
## Contract, actual authored placement, per-instance isolation and physical role queries.

const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const WORKBENCH = preload("res://addons/npr_character_frame/showcase/wardrobe_framework.gd")


func _run() -> void:
	_contract_profile()
	_spawn()
	_wardrobe.select_section(8)
	var saved: Dictionary = _wardrobe.state.to_data()
	await _actual_profiles()
	_role_queries()
	_check(_wardrobe.state.to_data() == saved, "Calibration and role queries preserve saved scheme")
	await _gui_targets()
	_finish("COMIC_PROFILE")


func _contract_profile() -> void:
	var original := DEFINITION.comic_profile
	_check(original.validate().is_empty(), "Sample has explicit valid comic calibration")
	_check(not NPRComicProfile.new().validate().is_empty(), "No implicit sample defaults")
	for bone in ["", "unknown", "Head"]:
		_reject_profile(original, "anchor_bone", bone)
	_reject_profile(original, "anchor_origin", Vector3(NAN, 0, 0))
	_reject_profile(original, "anchor_origin", Vector3(0, INF, 0))
	for offsets in [PackedVector3Array(), original.card_offsets.slice(0, 2)]:
		_reject_profile(original, "card_offsets", offsets)
	var offsets := original.card_offsets.duplicate()
	offsets[1] = Vector3(0, 0, INF)
	_reject_profile(original, "card_offsets", offsets)
	_reject_profile(original, "card_sizes", PackedVector2Array())
	for size in [Vector2.ZERO, Vector2(-1, 1), Vector2(1, NAN), Vector2(INF, 1)]:
		var sizes := original.card_sizes.duplicate()
		sizes[2] = size
		_reject_profile(original, "card_sizes", sizes)
	for field in ["tear_left", "tear_right", "hatching_left", "hatching_right"]:
		for value in [
			Vector4(NAN, 0, 1, 1), Vector4(0, INF, 1, 1), Vector4(0, 0, 0, 1), Vector4(0, 0, 1, -1)
		]:
			_reject_profile(original, field, value)
	var base := DEFINITION.duplicate() as NPRCharacterDefinition
	base.comic_profile = null
	_check(base.validate().is_empty(), "Comic profile is optional for base rendering")
	var invalid := NPRComicProfile.new()
	base.comic_profile = invalid
	_check(
		Array(base.validate()).any(func(error: String): return error.begins_with("comic_profile:")),
		"Definition propagates invalid comic profile errors"
	)
	var material := ShaderMaterial.new()
	material.shader = preload("res://addons/npr_character_frame/shaders/face/face_base.gdshader")
	material.set_shader_parameter("u_npr_comic_tear_opacity", 0.37)
	material.set_shader_parameter("u_npr_comic_tear_tint", Color(0.2, 0.4, 0.6))
	original.apply_material(material)
	_check(
		is_equal_approx(material.get_shader_parameter("u_npr_comic_tear_opacity"), 0.37),
		"Applying static calibration preserves dynamic opacity"
	)
	_check(
		material.get_shader_parameter("u_npr_comic_tear_tint") == Color(0.2, 0.4, 0.6),
		"Applying static calibration preserves dynamic tint"
	)


func _reject_profile(original: NPRComicProfile, field: String, value: Variant) -> void:
	var bad := original.duplicate() as NPRComicProfile
	bad.set(field, value)
	_check(not bad.validate().is_empty(), "Reject invalid comic " + field + ": " + str(value))
	_check(original.validate().is_empty(), "Negative control never mutates shared calibration")


func _actual_profiles() -> void:
	var workbench: Node = _wardrobe.framework
	var source: NPRComicProfile = DEFINITION.comic_profile
	var alternate := source.duplicate() as NPRComicProfile
	alternate.anchor_bone = "neck"
	alternate.anchor_origin += Vector3(0.025, -0.02, 0.01)
	for index in 3:
		alternate.card_offsets[index] += Vector3(0.06, -0.02, 0)
		alternate.card_sizes[index] *= 1.4
	for field in ["tear_left", "tear_right", "hatching_left", "hatching_right"]:
		var region: Vector4 = alternate.get(field)
		alternate.set(field, region + Vector4(0.018, -0.008, 0.012, 0.006))
	_check(alternate.validate().is_empty(), "Alternate authored calibration is valid")
	workbench.comics.set_process(false)
	workbench.set_comic_hold(true)
	await _capture("neutral")
	for kind in ["sweat", "anger", "emphasis", "tear", "hatching"]:
		workbench._comic_profile = source
		workbench._sync_anchor()
		workbench.play_comic(kind)
		await _capture(kind + "_original")
		_check(
			not _same_image("neutral", kind + "_original"), kind + " draws at sample calibration"
		)
		_check_effect_profile(workbench, source, kind)
		workbench.clear_effects()
		workbench._comic_profile = alternate
		workbench._sync_anchor()
		workbench.play_comic(kind)
		await _capture(kind + "_alternate")
		_check(
			not _same_image(kind + "_original", kind + "_alternate"),
			kind + " alternate calibration changes actual GPU pixels"
		)
		_check_effect_profile(workbench, alternate, kind)
		workbench.clear_effects()
		workbench._comic_profile = source
		workbench._sync_anchor()
		workbench.play_comic(kind)
		await _capture(kind + "_restored")
		_check(_same_image(kind + "_original", kind + "_restored"), kind + " exact sample restore")
		workbench.clear_effects()
	await _capture("cleared")
	_check(_same_image("neutral", "cleared"), "Clearing authored comics restores exact pixels")
	# A second real character and fresh setup consume its own definition, not cached sample values.
	var second := SCENE.instantiate()
	second.save_path = _output.path_join("second_unused.json")
	root.add_child(second)
	second.performance.automatic = false
	second.performance.set_process(false)
	second.preview.definition.comic_profile = alternate
	var independent := WORKBENCH.new()
	second.add_child(independent)
	independent.setup(second)
	independent.comics.set_process(false)
	independent.set_comic_hold(true)
	second.performance.action = "look_around"
	second.performance.apply_pose(0.8)
	var expected: Transform3D = second.performance.bone_deformation(alternate.anchor_bone)
	expected *= Transform3D(Basis.IDENTITY, alternate.anchor_origin)
	_check(
		independent._anchor.transform == expected, "Fresh setup follows alternate canonical bone"
	)
	_check(workbench._comic_profile == source, "Other instance retains original cached profile")
	independent.play_comic("tear")
	_check_effect_profile(independent, alternate, "tear")
	_check(
		(
			_wardrobe.preview.materials[1].get_shader_parameter("u_npr_comic_tear_left")
			== source.tear_left
		),
		"Second character's uniforms never alter first character"
	)
	_check(
		DEFINITION.comic_profile == source and source != alternate, "Shared source profile retained"
	)
	_check(source.anchor_bone == "head", "Alternate bone never mutates sample resource")
	second.free()
	workbench.set_comic_hold(false)


func _check_effect_profile(workbench: Node, profile: NPRComicProfile, kind: String) -> void:
	var expected: Transform3D = workbench._host.performance.bone_deformation(profile.anchor_bone)
	expected *= Transform3D(Basis.IDENTITY, profile.anchor_origin)
	_check(workbench._anchor.transform == expected, kind + " consumes authored anchor")
	var effect: Dictionary = workbench.comics._effects[0]
	var index := NPRComicProfile.CARDS.find(kind)
	if index >= 0:
		_check(effect.mesh.mesh.size == profile.card_sizes[index], kind + " consumes authored size")
		_check(
			effect.attachment == NPRComicLayer.Attachment.PINNED, kind + " preserves birth pinning"
		)
		_check_expected_pin(workbench, profile, kind, effect)
	else:
		_check(
			effect.attachment == NPRComicLayer.Attachment.SURFACE,
			kind + " remains on original skin"
		)
		var material: ShaderMaterial = workbench._host.preview.materials[1]
		for field in [
			"anchor_origin", "tear_left", "tear_right", "hatching_left", "hatching_right"
		]:
			_check(
				material.get_shader_parameter("u_npr_comic_" + field) == profile.get(field),
				kind + " consumes uniform " + field
			)


func _check_expected_pin(
	workbench: Node, profile: NPRComicProfile, kind: String, actual: Dictionary
) -> void:
	# Independent old private-query path: filter each role's hit before taking the nearest.
	var reference := NPRComicLayer.new()
	workbench._host.preview.add_child(reference)
	reference.camera = workbench._host.camera
	reference.set_process(false)
	var index := NPRComicProfile.CARDS.find(kind)
	var token := reference.play(
		kind,
		workbench._anchor,
		1.5,
		profile.card_offsets[index],
		profile.card_sizes[index],
		NPRComicLayer.Occlusion.SCENE,
		&"",
		Color.WHITE,
		NPRComicLayer.Attachment.VIEW_PLANE
	)
	var mesh: MeshInstance3D = reference._effects[0].mesh
	var camera: Camera3D = reference.camera
	var space := camera.get_camera_transform().orthonormalized()
	var inverse := space.affine_inverse()
	var point := inverse * mesh.global_position
	var dimensions: Vector3 = workbench._anchor.global_basis.get_scale().abs()
	var scale := maxf(dimensions.x, maxf(dimensions.y, dimensions.z))
	var nearest := INF
	for x in [-0.5, 0.0, 0.5]:
		for y in [-0.5, 0.0, 0.5]:
			var sample := mesh.to_global(Vector3(x * mesh.mesh.size.x, y * mesh.mesh.size.y, 0.0))
			var screen := camera.unproject_position(sample)
			for role in [1, 2]:
				var hit: Dictionary = workbench._host.preview._geometry[role].intersect_ray(
					camera.project_ray_origin(screen), camera.project_ray_normal(screen)
				)
				if (
					not hit.is_empty()
					and hit.position.distance_to(workbench._anchor.global_position) < 0.85 * scale
				):
					nearest = minf(nearest, -(inverse * hit.position).z)
	var depth: float = -(inverse * workbench._anchor.global_position).z
	var target_depth := nearest - 0.04 * scale if is_finite(nearest) else depth - 0.20 * scale
	target_depth = maxf(target_depth, camera.near * 1.1)
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		point *= target_depth / maxf(-point.z, camera.near)
	else:
		point.z = -target_depth
	reference.pin(token, space * point)
	var expected: Dictionary = reference._effects[0]
	_check(
		actual.offset == expected.offset, kind + " authored offset and old pin query remain exact"
	)
	_check(
		actual.pin_scale == expected.pin_scale, kind + " old perspective pin scaling remains exact"
	)
	reference.free()


func _role_queries() -> void:
	var actor: NPRCharacter = _wardrobe.preview
	var camera: Camera3D = _wardrobe.camera
	var hit_counts := PackedInt32Array([0, 0, 0])
	var profile: NPRComicProfile = DEFINITION.comic_profile
	var screens: Array[Vector2] = [Vector2(540, 360), Vector2(1, 1)]
	for delta in [Vector3(0, -0.08, 0.06), Vector3(0, 0.17, 0.06), Vector3(0.05, -0.04, 0.06)]:
		screens.append(camera.unproject_position(actor.to_global(profile.anchor_origin + delta)))
	for screen in screens:
		var origin := camera.project_ray_origin(screen)
		var direction := camera.project_ray_normal(screen)
		for role in 3:
			var physical := actor.intersect_role_ray(role, origin, direction)
			_check(
				physical == actor._geometry[role].intersect_ray(origin, direction),
				"Public physical query exactly delegates role %d / %s" % [role, screen]
			)
			if not physical.is_empty():
				hit_counts[role] += 1
				_check(
					(
						physical.keys().size() == 3
						and physical.has("position")
						and physical.has("distance")
						and physical.has("mesh")
					),
					"Physical query does not invent persistent topology"
				)
			var mesh := actor.meshes[role]
			var visibility := mesh.visible
			mesh.hide()
			_check(
				actor.intersect_role_ray(role, origin, direction) == physical,
				"Hidden role remains physical"
			)
			mesh.visible = visibility
			var mask := camera.cull_mask
			camera.cull_mask = 0
			_check(
				actor.intersect_role_ray(role, origin, direction) == physical,
				"Camera mask does not filter role"
			)
			_check(
				actor.pick_surface(origin, direction).is_empty(),
				"Visible pick still respects camera mask"
			)
			camera.cull_mask = mask
	_check(
		hit_counts[1] > 0 and hit_counts[2] > 0, "Delegation checked on actual face and hair hits"
	)
	for role in [-1, 3, 2147483647]:
		_check(
			actor.intersect_role_ray(role, Vector3.ZERO, Vector3.FORWARD).is_empty(),
			"Invalid role safely misses"
		)
	for direction in [Vector3.ZERO, Vector3(NAN, 0, 1), Vector3(0, INF, 1)]:
		_check(
			actor.intersect_role_ray(1, Vector3.ZERO, direction).is_empty(),
			"Invalid ray safely misses"
		)
	var uninitialized := NPRCharacter.new()
	_check(
		uninitialized.intersect_role_ray(1, Vector3.ZERO, Vector3.FORWARD).is_empty(),
		"Uninitialized role safely misses"
	)
	uninitialized.free()


func _gui_targets() -> void:
	root.size = Vector2i(1440, 900)
	_wardrobe.select_section(8)
	await _frames(8)
	var targets := {"viewport": [1440, 900], "buttons": {}, "comic_buttons": {}}
	for id in [
		"Section8",
		"FrameworkFaceView",
		"Save",
		"ComicHold",
		"ComicOverlay",
		"Comic_sweat",
		"Comic_tear",
		"Comic_anger",
		"Comic_emphasis",
		"Comic_hatching"
	]:
		var button := _wardrobe.find_child(id, true, false) as BaseButton
		if button == null:
			continue
		var rect := button.get_global_rect()
		targets.buttons[id] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var clear_button := _wardrobe.find_child("ClearFrameworkEffects", true, false) as BaseButton
	_wardrobe._options_scroll.ensure_control_visible(clear_button)
	await _frames(8)
	var rect := clear_button.get_global_rect()
	targets.clear_scroll = _wardrobe._options_scroll.scroll_vertical
	targets.clear_button = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	FileAccess.open(_output.path_join("gui_targets.json"), FileAccess.WRITE).store_string(
		JSON.stringify(targets, "  ")
	)
