@tool
extends DirectionalLight3D

@export var model_instance_array: Array[Node3D] = []
@export var change_params_name: String = ""


func _ready() -> void:
	await get_tree().process_frame
	set_notify_transform(true)
	init_light_dir()


func init_light_dir() -> void:
	var light_position := Vector4(global_position.x, global_position.y, global_position.z, 0.3)
	for cur_model in model_instance_array:
		if is_instance_valid(cur_model):
			cur_model.set_instance_shader_parameter(change_params_name, light_position)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			init_light_dir()
