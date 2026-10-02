extends "res://addons/npr_character_frame/npr_character.gd"
## Silver Wolf is an authored consumer of the reusable character module.


func _init() -> void:
	definition = (
		preload("res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres")
		. duplicate()
	)
