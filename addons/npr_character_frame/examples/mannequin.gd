extends Node3D

var actor: NPRCharacter


func _ready() -> void:
	var factory = load("res://addons/npr_character_frame/examples/mannequin_factory.gd")
	actor = NPRCharacter.new()
	actor.definition = factory.create_definition()
	add_child(actor)
	var environment := WorldEnvironment.new()
	environment.environment = preload(
		"res://addons/npr_character_frame/materials/studio_environment.tres"
	)
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 1.55, 5.0)
	camera.look_at(Vector3(0, 1.55, 0))
	camera.current = true
	get_viewport().msaa_3d = Viewport.MSAA_4X
