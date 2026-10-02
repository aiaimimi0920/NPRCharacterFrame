extends Node
## Export-only entry; closed choice of scenes, never a user-supplied resource path.

const SINGLE = preload("res://addons/npr_character_frame/showcase/npr_lab.tscn")
const MULTIVIEW = preload("res://addons/npr_character_frame/showcase/npr_multiview_lab.tscn")


func _ready() -> void:
	var scene := MULTIVIEW if "--multiview" in OS.get_cmdline_user_args() else SINGLE
	get_tree().change_scene_to_packed.call_deferred(scene)
