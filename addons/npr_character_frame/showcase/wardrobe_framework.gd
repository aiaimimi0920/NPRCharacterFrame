extends Node
## Silver Wolf adapter and art workbench. Reusable policies live in the addon.

const PANEL = preload("res://addons/npr_character_frame/showcase/wardrobe_framework_panel.gd")
const STYLE = preload("res://addons/npr_character_frame/npr_style_preset.gd")
const DIAGNOSTICS = preload("res://addons/npr_character_frame/runtime/npr_render_diagnostics.gd")
const QUALITY = preload("res://addons/npr_character_frame/runtime/npr_screen_quality.gd")
const COMICS = preload("res://addons/npr_character_frame/runtime/npr_comic_layer.gd")

const PRESETS := [
	preload("res://addons/npr_character_frame/presets/daily.tres"),
	preload("res://addons/npr_character_frame/presets/dialogue.tres"),
	preload("res://addons/npr_character_frame/presets/rim.tres"),
	preload("res://addons/npr_character_frame/presets/flat.tres"),
	preload("res://addons/npr_character_frame/presets/illustration.tres")
]

var diagnostics := DIAGNOSTICS.new()
var quality := QUALITY.new()
var comics := COMICS.new()
var locked := false
var duration := 1.5
var overlay := false
var hold_comics := false
var preset_index := 0
var preset_scope := 0
var status_label: Label
var owner_label: Label
var quality_label: Label
var diagnostic_label: Label
var captures: Array[Dictionary] = [{}, {}]
var _host: Control
var _anchor: Node3D
var _comic_profile: NPRComicProfile

var _baseline_style: NPRStylePreset
var _lock: Dictionary = {}
var _requests: Dictionary = {}
var _rain_budget := 32
var _reference: TextureRect
var _label_time := 0.0
var _sequence_serial := 0
var _sequence_speech_token := 0


func setup(host: Control) -> void:
	_host = host
	_comic_profile = host.preview.definition.comic_profile
	if _comic_profile == null or not _comic_profile.validate().is_empty():
		push_error("Complete showcase requires a valid character comic_profile")
		_comic_profile = null
	process_priority = 20
	_baseline_style = STYLE.capture(host.preview)
	host.preview.add_child(diagnostics)
	diagnostics.setup(
		host.preview,
		[
			host.visual_layers.diagnostic_symbol_target(&"eyes"),
			host.visual_layers.diagnostic_symbol_target(&"mouth")
		]
	)
	host.performance.expression_evaluated.connect(_expression_evaluated)
	host.preview.add_child(quality)
	quality.setup(host.preview, [host.camera])
	quality.quality_changed.connect(_quality_changed)
	host.preview.add_child(comics)
	comics.camera = host.camera
	comics.layer_mask = host.preview.meshes[1].layers
	_anchor = Node3D.new()
	_anchor.name = "ComicHeadAnchor"
	host.preview.add_child(_anchor)
	host.performance.pose_applied.connect(_sync_anchor)
	_sync_anchor()
	_reference = TextureRect.new()
	_reference.name = "FrameworkABReference"
	_reference.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reference.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reference.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reference.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_reference.hide()
	host.add_child(_reference)


func build() -> void:
	PANEL.build(_host, self)


func play_behavior(name: StringName) -> void:
	var key: StringName = &"preview_emotion"
	if name in [&"squeeze", &"star_eyes", &"heart_eyes"]:
		key = &"preview_eyes"
	elif name == &"wave_mouth":
		key = &"preview_mouth"
	_requests[key] = _host.performance.expressions.play(name, duration, 80, key)
	_preview_peak()


func play_comic(kind: String) -> void:
	if _comic_profile == null:
		return
	if kind in ["star_eyes", "heart_eyes", "shy", "tension"]:
		play_behavior(StringName(kind))
		if kind not in ["shy", "tension"]:
			return
	var mapped := "hatching" if kind in ["shy", "tension"] else kind
	if mapped in ["tear", "hatching"]:
		_play_face_comic(mapped, Color(1, 0.3, 0.4) if kind == "shy" else Color.WHITE)
		_preview_peak()
		return
	var card := NPRComicProfile.CARDS.find(mapped)
	if card < 0:
		return
	var size := _comic_profile.card_sizes[card]
	var depth_mode: int = COMICS.Occlusion.OVERLAY if overlay else COMICS.Occlusion.SCENE
	var tint := Color(1, 0.3, 0.4) if kind == "shy" else Color.WHITE
	var token: int = comics.play(
		mapped,
		_anchor,
		duration,
		_comic_profile.card_offsets[card],
		size,
		depth_mode,
		StringName(mapped),
		tint,
		COMICS.Attachment.VIEW_PLANE
	)
	_pin_spawn(token)

	_preview_peak()


func _pin_spawn(token: int) -> void:
	if token == 0:
		return
	var geometry := comics.geometry_snapshot(token)
	if geometry.is_empty():
		return
	var transform: Transform3D = geometry.transform
	var size: Vector2 = geometry.size
	var camera: Camera3D = _host.camera
	var space := camera.get_camera_transform().orthonormalized()
	var inverse := space.affine_inverse()
	var point := inverse * transform.origin
	var dimensions := _anchor.global_basis.get_scale().abs()
	var scale := maxf(dimensions.x, maxf(dimensions.y, dimensions.z))
	var nearest := INF
	# Sample the whole card at birth so a hair crest cannot clip the symbol's edges.
	for x in [-0.5, 0.0, 0.5]:
		for y in [-0.5, 0.0, 0.5]:
			var sample := transform * Vector3(x * size.x, y * size.y, 0.0)
			var screen := camera.unproject_position(sample)
			var origin := camera.project_ray_origin(screen)
			var direction := camera.project_ray_normal(screen)
			for role in [1, 2]:
				var hit: Dictionary = _host.preview.intersect_role_ray(role, origin, direction)
				if (
					not hit.is_empty()
					and hit.position.distance_to(_anchor.global_position) < 0.85 * scale
				):
					nearest = minf(nearest, -(inverse * hit.position).z)
	var depth := -(inverse * _anchor.global_position).z
	var target_depth := nearest - 0.04 * scale if is_finite(nearest) else depth - 0.20 * scale
	target_depth = maxf(target_depth, camera.near * 1.1)
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		point *= target_depth / maxf(-point.z, camera.near)
	else:
		point.z = -target_depth
	comics.pin(token, space * point)


func _play_face_comic(kind: String, tint: Color) -> void:
	var material: ShaderMaterial = _host.preview.materials[1]
	_comic_profile.apply_material(material)
	material.set_shader_parameter("u_npr_comic_" + kind + "_tint", tint)
	comics.play(
		kind,
		_anchor,
		duration,
		Vector3.ZERO,
		Vector2.ONE,
		COMICS.Occlusion.SCENE,
		StringName(kind),
		tint,
		COMICS.Attachment.SURFACE,
		material
	)


func clear_effects() -> void:
	_sequence_serial += 1
	if _sequence_speech_token != 0 and _sequence_speech_token == _host.speech.playback_id:
		_host.speech.stop()
	_sequence_speech_token = 0
	comics.clear()
	for token in _requests.values():
		_host.performance.expressions.cancel(token)
	_requests.clear()
	_host.performance.evaluate_expression()


func set_comic_hold(value: bool) -> void:
	hold_comics = value
	if locked:
		_lock.comic_paused = value
	comics.paused = value or locked
	_sync_controls()


func play_sequence() -> void:
	if locked:
		if is_instance_valid(status_label):
			status_label.text = "解除观察锁定后运行组合示例。"
		return
	_sequence_serial += 1
	var serial := _sequence_serial
	var previous_playback: int = _host.speech.playback_id
	_host._play_speech_demo()
	if _host.speech.playback_id != previous_playback:
		_sequence_speech_token = _host.speech.playback_id if _host.speech.player.playing else 0
	_requests.demo = _host.performance.expressions.play(&"surprised", 4.0, 50, &"demo")
	_host.performance.evaluate_expression()
	await get_tree().create_timer(0.65).timeout
	if is_inside_tree() and serial == _sequence_serial:
		play_behavior(&"squeeze")


func set_diagnostic(value: int) -> void:
	_host._set_display_mode("render")
	diagnostics.set_mode(0)
	_host.visual_layers.invalidate_expression_frame()
	_host.performance.evaluate_expression()
	diagnostics.set_mode(value)
	if is_instance_valid(diagnostic_label):
		diagnostic_label.text = DIAGNOSTICS.LEGENDS[diagnostics.mode]
	_sync_controls()


func refresh() -> void:
	if diagnostics.mode != 0:
		set_diagnostic(diagnostics.mode)


func set_locked(value: bool) -> void:
	if value == locked:
		return
	locked = value
	if locked:
		_lock = {
			"pose_paused": _host.performance.is_paused(),
			"water_paused": _host.visual_layers._paused,
			"speech_paused": _host.speech.player.stream_paused,
			"comic_paused": comics.paused,
			"camera": _host.camera.transform,
			"fov": _host.camera.fov,
			"h_offset": _host.camera.h_offset,
			"target": _host._target,
			"distance": _host._distance,
			"pitch": _host._camera_pitch,
			"yaw": _host._model_yaw_degrees,
			"turntable": _host.turntable.transform,
			"style": STYLE.capture(_host.preview),
			"ambient": _host._environment.ambient_light_energy,
			"exposure": _host._environment.tonemap_exposure
		}
		_host.performance.set_paused(true)
		_host.visual_layers.set_paused(true)
		_host.speech.player.stream_paused = true
		comics.paused = true
		_host._dragging = false
		_host._middle_dragging = false
	else:
		_host.performance.set_paused(_lock.pose_paused)
		_host.visual_layers.set_paused(_lock.water_paused)
		_host.speech.player.stream_paused = _lock.speech_paused
		comics.paused = _lock.comic_paused
		_lock.clear()
	_sync_controls()


func _process(delta: float) -> void:
	if _host == null:
		return
	if locked:
		_restore_locked()
	_label_time += delta
	if _label_time < 0.1:
		return
	_label_time = 0.0
	_sync_controls()
	if is_instance_valid(owner_label):
		var frame: Dictionary = _host.performance.expressions.output
		if not frame.is_empty():
			owner_label.text = (
				"眼睛：%s\n嘴巴：%s\n眉毛：%s\n脸部颜色：%s"
				% [frame.owners.eyes, frame.owners.mouth, frame.owners.brows, frame.owners.color]
			)
	if is_instance_valid(quality_label):
		var budget: Dictionary = quality.budget()
		quality_label.text = (
			"%s / %.0f px / 切换 %d 次\n每张深度 %d px；辅助 %d px；雨水每帧上限 %d"
			% [
				QUALITY.LABELS[quality.tier] if quality.enabled else "手动质量",
				quality.pixel_height,
				quality.transitions,
				budget.depth_pixels_per_pass,
				budget.auxiliary_pixels,
				_host.visual_layers.surface_rain.updates_per_frame
			]
		)


func _restore_locked() -> void:
	_host.camera.transform = _lock.camera
	_host.camera.fov = _lock.fov
	_host.camera.h_offset = _lock.h_offset
	_host._target = _lock.target
	_host._distance = _lock.distance
	_host._camera_pitch = _lock.pitch
	_host._model_yaw_degrees = _lock.yaw
	_host.turntable.transform = _lock.turntable
	var current := STYLE.capture(_host.preview)
	if current.lighting_values != _lock.style.lighting_values:
		_lock.style.apply(_host.preview, STYLE.Scope.LIGHTING)
	_host._environment.ambient_light_energy = _lock.ambient
	_host._environment.tonemap_exposure = _lock.exposure


func _sync_controls() -> void:
	if _host == null or _host.section != 8 or not is_instance_valid(_host._content):
		return
	for entry in [
		["FrameworkLock", locked],
		["ComicHold", hold_comics],
		["DiagnosticHideHair", diagnostics.hair_hidden],
		["ScreenQualityEnabled", quality.enabled]
	]:
		var button := _host._content.find_child(entry[0], true, false) as BaseButton
		if button != null:
			button.set_pressed_no_signal(entry[1])
	var picker := _host._content.find_child("DiagnosticMode", true, false) as OptionButton
	if picker != null:
		picker.select(diagnostics.mode)
	if is_instance_valid(diagnostic_label):
		diagnostic_label.text = DIAGNOSTICS.LEGENDS[diagnostics.mode]
	var slider := _host._content.find_child("FaceArtLightWeight", true, false) as HSlider
	if slider != null:
		slider.set_value_no_signal(_host.preview.face_light_weight)
		var label: Label = slider.get_meta("value_label")
		label.text = "脸部艺术光权重：%.2f" % _host.preview.face_light_weight


func _expression_evaluated(frame: Dictionary) -> void:
	diagnostics.set_canvas_visibility(
		_host.visual_layers.diagnostic_symbol_target(&"eyes"), frame.eye_symbol != 0
	)
	diagnostics.set_canvas_visibility(
		_host.visual_layers.diagnostic_symbol_target(&"mouth"), frame.mouth_symbol != 0
	)


func set_auto_quality(value: bool) -> void:
	if value and not quality.enabled:
		_rain_budget = _host.visual_layers.surface_rain.updates_per_frame
	quality.set_enabled(value)
	if not value:
		_host.visual_layers.surface_rain.updates_per_frame = _rain_budget
	_sync_controls()


func _quality_changed(tier: int) -> void:
	_host.visual_layers.surface_rain.updates_per_frame = QUALITY.RAIN_UPDATES[tier]


func set_quality_view(index: int) -> void:
	if locked:
		return
	_host._target = Vector3(0, _host._camera_profile.view_heights[0], 0)
	_host._distance = [3.0, 7.0, 18.0][index]
	_host.camera.h_offset = (
		_host._camera_profile.horizontal_offset
		* _host._distance
		/ _host._camera_profile.view_distances[0]
	)
	_host._update_camera()


func apply_preset() -> bool:
	if locked and preset_scope != STYLE.Scope.CHARACTER:
		if is_instance_valid(status_label):
			status_label.text = "灯光已锁定：选择仅角色参数，或先解除锁定。"
		return false
	var applied: bool = PRESETS[preset_index].apply(_host.preview, preset_scope)
	if is_instance_valid(status_label):
		status_label.text = "已应用：" + PRESETS[preset_index].display_name if applied else "预设无效"
	_sync_controls()
	return applied


func restore_style() -> void:
	_baseline_style.apply(_host.preview, STYLE.Scope.CHARACTER if locked else STYLE.Scope.ALL)
	_sync_controls()


func set_face_light_weight(value: float) -> void:
	_host.preview.set_face_light(_host.preview.face_light_direction, value)


func capture(slot: int) -> void:
	if slot not in [0, 1]:
		return
	set_locked(true)
	await RenderingServer.frame_post_draw
	var frame: Image = _host.viewport.get_texture().get_image()
	captures[slot] = {
		"image": frame,
		"texture": ImageTexture.create_from_image(frame),
		"camera": _host.camera.transform,
		"clock": _host.performance.clock,
		"lighting": STYLE.capture(_host.preview).lighting_values.duplicate(true),
		"diagnostic": diagnostics.mode
	}
	if is_instance_valid(status_label):
		status_label.text = "已记录 %s；相机、动作、灯光保持锁定。" % ("A" if slot == 0 else "B")


func show_capture(slot: int) -> void:
	var valid := slot in [0, 1] and not captures[slot].is_empty()
	_reference.visible = valid
	_host._stage.visible = not valid
	_reference.texture = captures[slot].texture if valid else null


func clear_captures() -> void:
	show_capture(-1)
	captures = [{}, {}]


func reset() -> void:
	set_locked(false)
	set_comic_hold(false)
	clear_effects()
	diagnostics.reset()
	set_auto_quality(false)
	clear_captures()
	restore_style()


func _sync_anchor() -> void:
	if _comic_profile == null:
		return
	_anchor.transform = (
		_host.performance.bone_deformation(_comic_profile.anchor_bone)
		* Transform3D(Basis.IDENTITY, _comic_profile.anchor_origin)
	)


func _preview_peak() -> void:
	# A new request is observable even when the art workbench holds animation time.
	if locked or hold_comics:
		comics.paused = false
		comics.advance(0.08)
		comics.paused = true
	_host.performance.evaluate_expression(0.08 if locked else 0.0)
	refresh()
