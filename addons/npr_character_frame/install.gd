extends SceneTree
## Run once before importing a clean consumer, using the supported custom editor.


func _initialize() -> void:
	var installer = load("res://addons/npr_character_frame/config/install_settings.gd")
	var errors: PackedStringArray = installer.install()
	if errors.is_empty():
		print("NPR_INSTALL_OK")
	else:
		for error in errors:
			push_error(error)
	quit(0 if errors.is_empty() else 1)
