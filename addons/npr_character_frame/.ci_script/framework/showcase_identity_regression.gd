extends "symbolic_expression_regression.gd"
## Different identities share sample geometry only as an interface fixture, not P06 proof.

const IDENTITY_STATE = preload("res://addons/npr_character_frame/showcase/wardrobe_state.gd")


func _run() -> void:
	var negative := OS.get_environment("NPR_SHOWCASE_NEGATIVE")
	if not negative.is_empty():
		_rejected_scene(negative)
		return
	_configuration_checks()
	_state_checks()
	_spawn()
	_check(_wardrobe.character_id == "silver_wolf", "Default scene selects the existing identity")
	_check(_has_label("银狼  /  角色装扮"), "Default title is unchanged")
	_wardrobe.state.select_palette(4)
	_wardrobe.save_scheme()
	var original_path: String = _wardrobe.save_path
	var original_bytes := FileAccess.get_file_as_bytes(original_path)
	var demo_path: String = _wardrobe.demo_speech_path
	_wardrobe._play_speech_demo()
	_check(_wardrobe.speech.player.playing, "Configured sample demo actually plays")
	_check(_wardrobe.speech.cues.size() > 1, "Sample Rhubarb cues remain available")
	_wardrobe.speech.stop()
	_wardrobe.free()
	_spawn_identity("review_actor", "接口测试角色")
	_check(_wardrobe.preview.initialized, "Alternate configured actor initializes")
	_check(_wardrobe.preview.definition.display_height == 3.25, "Supplied definition reaches actor")
	_check(
		_wardrobe.preview.definition != _wardrobe.character_definition,
		"Showcase owns its definition copy"
	)
	_check(
		_wardrobe.save_path == "user://review_actor_wardrobe.json", "Default path follows identity"
	)
	_check(_has_label("接口测试角色  /  角色装扮"), "Title follows configured name")
	_check(_has_label("接口测试角色 · 初始服装"), "Clothing heading follows configured name")
	_wardrobe._play_speech_demo()
	_check(not _wardrobe.speech.player.playing, "Empty demo does not fall back to sample audio")
	_check(_wardrobe._status.text.begins_with("未配置口型示例"), "Absent demo is explained to the user")
	_wardrobe.state.select_palette(2)
	_wardrobe.visual_layers.set_pupil_scale(1.35, 0)
	_wardrobe.save_scheme()
	var own_path: String = _wardrobe.save_path
	var own_bytes := FileAccess.get_file_as_bytes(own_path)
	var own_data: Dictionary = _wardrobe.state.to_data()
	_check(own_data.character == "review_actor", "Real saved scheme carries configured identity")
	_wardrobe.configure_save_path(original_path)
	_check(_wardrobe.dirty, "Showcase refuses a different character's real saved file")
	_check(
		_wardrobe.state.to_data().character == "review_actor", "Rejected file cannot change owner"
	)
	_check(_wardrobe.state.palette == 0, "Rejected file cannot import another character's choices")
	_check(
		FileAccess.get_file_as_bytes(original_path) == original_bytes, "Foreign file is untouched"
	)
	_wardrobe.character_id = "mutated_config"
	_wardrobe.reset_scheme()
	_check(_wardrobe.state.to_data().character == "review_actor", "Reset preserves active identity")
	_check(_wardrobe.save_path == original_path, "Reset preserves explicit save path override")
	_wardrobe.configure_save_path(own_path)
	_check(
		not _wardrobe.dirty and _wardrobe.state.to_data() == own_data,
		"Ready path switch reloads owner"
	)
	_wardrobe.save_scheme()
	_check(
		FileAccess.get_file_as_bytes(own_path) == own_bytes, "Path reload preserves all saved bytes"
	)
	_wardrobe.free()
	_spawn_identity("review_actor", "接口测试角色")
	_check(
		_wardrobe.state.to_data() == own_data, "Recreated showcase loads only its own defaults path"
	)
	_check(
		_wardrobe.preview.definition.display_height == 3.25, "Reload does not replace definition"
	)
	_wardrobe.free()
	var alternate_clip := _make_clip(demo_path)
	var override_path := _output.path_join("explicit.json")
	_spawn_identity("clip_actor", "语音接口夹具", override_path, alternate_clip)
	_check(_wardrobe.save_path == override_path, "Pre-ready explicit save path takes precedence")
	_wardrobe._play_speech_demo()
	_check(_wardrobe.speech.player.playing, "Configured external demo actually plays")
	_check(_wardrobe.speech.cues.size() == 1, "Alternate demo is not the sample timeline")
	_check(_wardrobe.speech.sample(0.2) == {"aa": 1.0}, "Alternate cue reaches production sampler")
	_wardrobe.speech.stop()
	_check(_wardrobe.performance.visemes.is_empty(), "Stopping configured clip releases speech")
	_wardrobe.free()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks}, "  ")
	)
	print("SHOWCASE_IDENTITY_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _spawn_identity(id: String, label: String, path := "", clip := "") -> void:
	_wardrobe = SCENE.instantiate()
	_wardrobe.character_id = id
	_wardrobe.character_display_name = label
	_wardrobe.character_definition = _wardrobe.character_definition.duplicate()
	_wardrobe.character_definition.display_height = 3.25
	_wardrobe.demo_speech_path = clip
	if not path.is_empty():
		_wardrobe.configure_save_path(path)
	root.add_child(_wardrobe)
	_wardrobe.performance.automatic = false
	_wardrobe.performance.set_process(false)


func _has_label(text: String) -> bool:
	for label in _wardrobe.find_children("*", "Label", true, false):
		if label.text == text:
			return true
	return false


func _configuration_checks() -> void:
	var scene = SCENE.instantiate()
	_check(scene._configuration_errors().is_empty(), "Default scene configuration validates")
	for id in ["", "../x", "x/y", "x\\y", "UPPER", "with space", "x\n", "x".repeat(65)]:
		scene.character_id = id
		_check(
			not scene._configuration_errors().is_empty(),
			"Unsafe or ambiguous identity rejected: " + id
		)
	for id in ["a", "actor_2", "a".repeat(64)]:
		scene.character_id = id
		_check(scene._configuration_errors().is_empty(), "Safe identity accepted: " + id)
	scene.character_display_name = "  "
	_check(not scene._configuration_errors().is_empty(), "Blank display name rejected")
	scene.character_display_name = "测试"
	scene.character_definition = null
	_check(not scene._configuration_errors().is_empty(), "Missing character definition rejected")
	scene.free()
	scene = SCENE.instantiate()
	scene.demo_speech_path = _output.path_join("missing.json")
	_check(not scene._configuration_errors().is_empty(), "Missing explicit demo rejected")
	scene.demo_speech_path = ""
	_check(scene._configuration_errors().is_empty(), "Demo audio is optional")
	var definition: NPRCharacterDefinition = scene.character_definition
	for field in scene.CONFIGURATION.REQUIRED_PROFILES + scene.CONFIGURATION.REQUIRED_DATA:
		scene.character_definition = definition.duplicate()
		scene.character_definition.set(field, null if field.ends_with("profile") else "")
		_check(
			scene._configuration_errors().has("Full showcase requires " + field),
			"Full feature input required before assembly: " + field
		)
	_check(
		scene.performance == null and scene.speech == null,
		"Pre-ready validation owns no live drivers"
	)
	scene.free()


func _state_checks() -> void:
	for id in ["silver_wolf", "review_actor"]:
		var target = IDENTITY_STATE.new(id, SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
		var baseline: Dictionary = target.to_data()
		_check(baseline.character == id, "State serializes its supplied identity: " + id)
		for schema in [6, 7, 8, 9, 10]:
			var data := baseline.duplicate(true)
			data.schema = schema
			_check(target.load_data(data), "Owner migration accepted: %s/%s" % [id, schema])
			_check(target.to_data() == baseline, "Migration preserves owner and defaults")
		var wrong := baseline.duplicate(true)
		wrong.character = "foreign_actor"
		wrong.palette = 4
		_check(not target.load_data(wrong), "Foreign identity rejected: " + id)
		_check(target.to_data() == baseline, "Rejected identity leaves state intact: " + id)


func _make_clip(source_path: String) -> String:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var wav_path := source_path.get_base_dir().path_join(str(source.metadata.soundFile).get_file())
	var bytes := FileAccess.get_file_as_bytes(wav_path)
	_check(not bytes.is_empty(), "Alternate clip uses real WAV data")
	FileAccess.open(_output.path_join("alternate.wav"), FileAccess.WRITE).store_buffer(bytes)
	var path := _output.path_join("alternate.json")
	FileAccess.open(path, FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"metadata": {"soundFile": "alternate.wav"},
				"mouthCues": [{"start": 0.1, "end": 0.3, "value": "D"}]
			}
		)
	)
	return path


func _rejected_scene(mode: String) -> void:
	_wardrobe = SCENE.instantiate()
	_wardrobe.character_definition = _wardrobe.character_definition.duplicate()
	_wardrobe.save_path = _output.path_join("never_written.json")
	if mode == "missing_feature":
		_wardrobe.character_definition.face_atlas_profile = null
	else:
		var model := Node.new()
		var packed := PackedScene.new()
		_check(packed.pack(model) == OK, "Invalid runtime model fixture packs")
		model.free()
		_wardrobe.character_definition.model_scene = packed
		_check(
			_wardrobe._configuration_errors().is_empty(),
			"Runtime fixture passes metadata validation"
		)
	root.add_child(_wardrobe)
	_check(_wardrobe._status == null, "Rejected showcase does not build interactive UI")
	for field in ["performance", "speech", "visual_layers", "display", "framework"]:
		_check(_wardrobe.get(field) == null, "Rejected showcase does not allocate driver: " + field)
	_check(not FileAccess.file_exists(_wardrobe.save_path), "Rejected showcase writes no scheme")
	_check(
		_wardrobe.preview == null or not _wardrobe.preview.initialized,
		"Rejected showcase has no initialized character"
	)
	_wardrobe.free()
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"mode": mode, "checks": _checks}, "  ")
	)
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	print("SHOWCASE_NEGATIVE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	quit(0 if failed.is_empty() else 1)
