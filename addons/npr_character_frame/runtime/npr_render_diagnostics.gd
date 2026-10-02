class_name NPRRenderDiagnostics
extends Node
## Stable diagnostic modes on the real shaders, with reversible visibility.

const LABELS := [
	"正常渲染", "脸部替换分区", "世界法线", "UV1 基础色坐标", "脸部 SDF", "材质分区", "基础颜色", "阴影结果", "描边", "眼部遮罩"
]
const LEGENDS := [
	"正常 NPR 输出",
	"蓝：原脸；绿：眼部替换；青：嘴部替换；红：原五官隐藏域。棋盘镂空同时检查上下层。",
	"RGB = 世界法线 XYZ × 0.5 + 0.5，使用实际蒙皮后的法线。",
	"R = U；G = V，使用基础色实际采样坐标；SDF UV 另由资产声明。",
	"脸部 SDF 阈值结果：白为受光，黑为阴影；其余角色以灰色显示。",
	"Body / Hair 各 8 槽，Face 独立分区；颜色来自实际材质槽。",
	"基础色与当前配色，不含灯光、SDF、阴影和描边。",
	"Body / Hair：真实主光遮挡；Face：SDF 与刘海接触遮挡。",
	"白色表面和黑色实际描边，宽度保持当前值。",
	"Face ILM 的眼部 stencil 通道；移开头发可看完整范围。"
]

var mode := 0
var hair_hidden := false
var _actor: NPRCharacter
var _canvases: Array[MeshInstance3D] = []
var _visible: Dictionary = {}
var _hair_visible := true


func setup(actor: NPRCharacter, canvases: Array[MeshInstance3D] = []) -> void:
	_actor = actor
	_canvases.assign(canvases)


func set_mode(value: int) -> void:
	if not is_instance_valid(_actor) or not _actor.initialized:
		return
	if value < 0 or value >= LABELS.size():
		return
	for canvas in _visible:
		if is_instance_valid(canvas):
			canvas.visible = _visible[canvas]
	_visible.clear()
	mode = value
	var materials: Array[ShaderMaterial] = _actor.materials.duplicate()
	materials.append_array(_actor.outlines)
	for material in materials:
		var pass_material := material
		while pass_material != null:
			pass_material.set_shader_parameter("u_npr_diagnostic_mode", mode)
			pass_material = pass_material.next_pass as ShaderMaterial
	if mode == 1:
		for canvas in _canvases:
			if is_instance_valid(canvas):
				_visible[canvas] = canvas.visible
				canvas.show()


func set_hair_hidden(value: bool) -> void:
	if hair_hidden == value or not is_instance_valid(_actor):
		return
	if value:
		_hair_visible = _actor.meshes[2].visible
	hair_hidden = value
	_actor.meshes[2].visible = false if value else _hair_visible


## The character adapter reports its latest visibility after expression arbitration.
## Keep the live owner behind the override, including changes while diagnostics run.
func set_canvas_visibility(canvas: MeshInstance3D, value: bool) -> void:
	if mode == 1 and is_instance_valid(canvas) and _canvases.has(canvas):
		_visible[canvas] = value
		canvas.show()


func reset() -> void:
	set_mode(0)
	set_hair_hidden(false)


func _exit_tree() -> void:
	reset()
