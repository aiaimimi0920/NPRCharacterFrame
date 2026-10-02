extends RefCounted
## Original procedural integration asset. No Silver Wolf resources are referenced.


static func create_definition() -> NPRCharacterDefinition:
	var model := Node3D.new()
	model.name = "Mannequin"
	var body_tool := SurfaceTool.new()
	body_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(body_tool, Vector3(0.68, 0.9, 0.38), Vector3(0, 1.55, 0))
	for side in [-1.0, 1.0]:
		_box(body_tool, Vector3(0.22, 1.0, 0.25), Vector3(side * 0.22, 0.55, 0))
		_box(body_tool, Vector3(0.19, 0.8, 0.23), Vector3(side * 0.52, 1.5, 0))
		_box(body_tool, Vector3(0.27, 0.15, 0.46), Vector3(side * 0.22, 0.1, 0.08))
	# Equipment is disconnected geometry within the one body surface.
	_box(body_tool, Vector3(0.42, 0.55, 0.22), Vector3(0, 1.65, -0.3))
	_add_mesh(model, "Body", body_tool.commit())
	var face_tool := SurfaceTool.new()
	face_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := SphereMesh.new()
	head.radius = 0.38
	head.height = 0.78
	head.radial_segments = 48
	head.rings = 24
	face_tool.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(0, 2.4, 0)))
	_add_mesh(model, "Face", face_tool.commit())
	var hair_tool := SurfaceTool.new()
	hair_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(hair_tool, Vector3(0.79, 0.18, 0.63), Vector3(0, 2.75, -0.04))
	for index in range(5):
		_box(hair_tool, Vector3(0.145, 0.32, 0.12), Vector3((index - 2) * 0.15, 2.61, 0.31))
	_box(hair_tool, Vector3(0.77, 0.6, 0.14), Vector3(0, 2.38, -0.33))
	_add_mesh(model, "Hair", hair_tool.commit())
	var scene := PackedScene.new()
	var packed := scene.pack(model)
	model.free()
	if packed != OK:
		return null
	var definition := NPRCharacterDefinition.new()
	definition.model_scene = scene
	definition.material_set = create_materials()
	return definition


static func create_materials() -> NPRCharacterMaterials:
	var inputs := NPRCharacterMaterials.new()
	inputs.body_base = _solid(Color(0.15, 0.68, 0.64, 1))
	inputs.body_ilm = _solid(Color(1, 0.5, 0.7, 0.0625))
	var lut := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	lut.fill(Color(0, 0, 0, 1))
	for slot in range(8):
		lut.set_pixel(slot, 0, Color(0.6, 0.65, 0.7, 1))
		lut.set_pixel(slot, 1, Color(1, 0.04, 0.5, 1))
	inputs.body_lut = ImageTexture.create_from_image(lut)
	inputs.body_ramp = _ramp(Color(0.42, 0.40, 0.55), Color(1, 0.95, 0.91))
	inputs.body_cool_ramp = _ramp(Color(0.32, 0.43, 0.58), Color(0.90, 0.96, 1))
	inputs.face_base = _solid(Color(0.96, 0.78, 0.63, 1))
	var face_ilm := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			# Diagnostic angular threshold atlas; replace with painted facial SDF.
			face_ilm.set_pixel(x, y, Color(0, 0, 0, 0.15 + 0.7 * float(x) / 63.0))
	inputs.face_ilm = ImageTexture.create_from_image(face_ilm)
	inputs.face_map = _solid(Color(0, 0, 0, 1))
	inputs.face_ramp = inputs.body_ramp
	inputs.hair_base = _solid(Color(0.43, 0.29, 0.7, 1))
	inputs.hair_ilm = _solid(Color(1, 0.5, 0, 0.0625))
	inputs.hair_ramp = inputs.body_ramp
	inputs.hair_cool_ramp = inputs.body_cool_ramp
	return inputs


static func _box(tool: SurfaceTool, size: Vector3, position: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	tool.append_from(box, 0, Transform3D(Basis.IDENTITY, position))


static func _add_mesh(model: Node3D, label: String, mesh: ArrayMesh) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	model.add_child(node)
	node.owner = model


static func _solid(color: Color) -> Texture2D:
	var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


static func _ramp(dark: Color, light: Color) -> Texture2D:
	var image := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(64):
			image.set_pixel(x, y, dark.lerp(light, smoothstep(0.40, 0.60, float(x) / 63.0)))
	return ImageTexture.create_from_image(image)
