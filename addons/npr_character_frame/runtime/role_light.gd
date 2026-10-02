@tool
extends DirectionalLight3D

@export var model_instance_array: Array[Node3D] = []
@export var change_params_name: String = ""


func _ready() -> void:
	await get_tree().process_frame
	set_notify_transform(true)
	init_light_dir()


func init_light_dir() -> void:
	var light_dir := (global_transform.basis * Vector3(0, 0, -1)).normalized()
	for cur_model in model_instance_array:
		if is_instance_valid(cur_model):
			cur_model.set_instance_shader_parameter(
				change_params_name, Vector4(light_dir.x, light_dir.y, light_dir.z, 0.3)
			)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			init_light_dir()
