@tool
extends RefCounted
## Shared by the editor plugin and the headless installer. Never overwrites conflicts.

const DEFAULTS := "res://addons/npr_character_frame/config/shader_globals.cfg"
const TYPES := {
	"bool": RenderingServer.GLOBAL_VAR_TYPE_BOOL,
	"int": RenderingServer.GLOBAL_VAR_TYPE_INT,
	"float": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
	"vec2": RenderingServer.GLOBAL_VAR_TYPE_VEC2,
	"vec3": RenderingServer.GLOBAL_VAR_TYPE_VEC3,
	"vec4": RenderingServer.GLOBAL_VAR_TYPE_VEC4,
	"color": RenderingServer.GLOBAL_VAR_TYPE_COLOR,
	"mat4": RenderingServer.GLOBAL_VAR_TYPE_MAT4
}


static func install() -> PackedStringArray:
	var errors := PackedStringArray()
	var defaults := ConfigFile.new()
	if defaults.load(DEFAULTS) != OK:
		return PackedStringArray(["Cannot read " + DEFAULTS])
	# Headless CLI writes configuration for the next process. Live global queries
	# are editor-only in the custom renderer, and must not run in game code.
	var registered: Array[StringName] = []
	if Engine.is_editor_hint():
		registered = RenderingServer.global_shader_parameter_get_list()
	for key in defaults.get_section_keys("shader_globals"):
		var setting := "shader_globals/" + key
		var expected: Dictionary = defaults.get_value("shader_globals", key)
		if not TYPES.has(expected.type):
			errors.append("Unsupported global type: " + str(expected.type))
		elif (
			key in registered
			and RenderingServer.global_shader_parameter_get_type(key) != TYPES[expected.type]
		):
			errors.append("Conflicting live shader global type: " + key)
		if (
			ProjectSettings.has_setting(setting)
			and ProjectSettings.get_setting(setting) != expected
		):
			errors.append("Conflicting host setting: " + setting)
	if not errors.is_empty():
		return errors
	for key in defaults.get_section_keys("shader_globals"):
		var expected: Dictionary = defaults.get_value("shader_globals", key)
		ProjectSettings.set_setting("shader_globals/" + key, expected)
		if Engine.is_editor_hint() and key not in registered:
			RenderingServer.global_shader_parameter_add(key, TYPES[expected.type], expected.value)
	var result := ProjectSettings.save()
	if result != OK:
		errors.append("Cannot save project.godot: " + error_string(result))
	return errors
