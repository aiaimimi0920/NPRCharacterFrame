extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(
		(
			load("res://addons/npr_character_frame/.ci_script/framework/module_consumer.tscn")
			. instantiate()
		)
	)
