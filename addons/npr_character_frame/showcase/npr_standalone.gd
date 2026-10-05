extends Node
## Standalone entry for the complete character showcase and its debug controls.

const SHOWCASE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")


func _ready() -> void:
	if "--multiview" in OS.get_cmdline_user_args():
		push_error("The material browser was removed; use the complete character showcase.")
		get_tree().quit(2)
		return
	get_tree().change_scene_to_packed.call_deferred(SHOWCASE)
