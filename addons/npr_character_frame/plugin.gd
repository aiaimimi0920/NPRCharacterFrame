@tool
extends EditorPlugin

const SHOWCASE := "res://addons/npr_character_frame/showcase/wardrobe.tscn"


func _enter_tree() -> void:
	var installer = load("res://addons/npr_character_frame/config/install_settings.gd")
	var errors: PackedStringArray = installer.install()
	if errors.is_empty():
		add_tool_menu_item("Run NPR Character Showcase", _run_showcase)
		print("NPR Character Frame ready. Use Project > Tools > Run NPR Character Showcase.")
	else:
		for error in errors:
			push_error(error)


func _exit_tree() -> void:
	remove_tool_menu_item("Run NPR Character Showcase")


func _run_showcase() -> void:
	get_editor_interface().play_custom_scene(SHOWCASE)
