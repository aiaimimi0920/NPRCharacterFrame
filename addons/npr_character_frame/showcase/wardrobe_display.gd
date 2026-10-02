extends Node3D
## Transient diagnostic rendering; original materials and simulation remain authoritative.

const MODES := ["render", "white", "skeleton"]
var mode := "render"
var white_material: StandardMaterial3D
var overlay: MeshInstance3D
var material_snapshots: Array[Dictionary] = []
var _actor: NPRCharacter
var _driver: Node
var _layout: Dictionary
var _mesh := ImmediateMesh.new()
var _overlay_material: StandardMaterial3D


func setup(actor: NPRCharacter, driver: Node) -> void:
	var layout := actor.definition.load_rig_layout_data()
	var errors := NPRCharacterDefinition.RIG_LAYOUT_DATA.validate(layout)
	if not errors.is_empty():
		push_error("Invalid rig layout data: " + "; ".join(errors))
		return
	_actor = actor
	_driver = driver
	_layout = layout
	white_material = StandardMaterial3D.new()
	white_material.albedo_color = Color("d5dbe2")
	white_material.roughness = 1.0
	white_material.metallic_specular = 0.0
	white_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_overlay_material = StandardMaterial3D.new()
	_overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_material.vertex_color_use_as_albedo = true
	_overlay_material.vertex_color_is_srgb = true
	_overlay_material.no_depth_test = true
	_overlay_material.disable_fog = true
	_overlay_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Render after opaque geometry so diagnostic bones remain visible inside it.
	_overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_material.render_priority = 100
	_overlay_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	overlay = MeshInstance3D.new()
	overlay.name = "SkeletonDiagnosticOverlay"
	overlay.mesh = _mesh
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.visible = false
	add_child(overlay)
	_driver.pose_applied.connect(_update_geometry)


func set_mode(value: String) -> void:
	if value not in MODES:
		return
	restore_materials()
	mode = value
	if mode != "render":
		for node: Node in _actor.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			if (
				is_ancestor_of(geometry)
				or geometry.get_viewport() != _actor.get_viewport()
				or geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			):
				continue
			(
				material_snapshots
				. append(
					{
						"geometry": geometry,
						"override": geometry.material_override,
						"overlay": geometry.material_overlay,
					}
				)
			)
			geometry.material_override = white_material
			geometry.material_overlay = null
	overlay.visible = mode == "skeleton"
	_update_geometry()


func restore_materials() -> void:
	# State setters may update opacity/uniforms through material_override. Restore
	# real materials before those writes, then refresh the diagnostic view afterward.
	for row in material_snapshots:
		if is_instance_valid(row.geometry):
			row.geometry.material_override = row.override
			row.geometry.material_overlay = row.overlay
	material_snapshots.clear()


func refresh() -> void:
	set_mode(mode)


func overridden_count() -> int:
	return material_snapshots.size()


func diagnostic_geometry() -> Dictionary:
	var bones: Array[Dictionary] = []
	# The runtime Skeleton3D is a flat deformation palette with identity rests.
	# Apply that same palette to authored rest endpoints, rather than inventing
	# a hierarchy from the palette's nonexistent parents or its matrix origins.
	for bone: Dictionary in _layout.bones:
		var deformation: Transform3D = _driver.bone_deformation(bone.name)
		(
			bones
			. append(
				{
					"name": bone.name,
					"parent": bone.parent,
					"head": _array(deformation * _vector(bone.head)),
					"tail": _array(deformation * _vector(bone.tail)),
				}
			)
		)
	var dynamic: Dictionary = _driver.hair_collision_contract()
	return {
		"bones": bones,
		"chains": dynamic.geometry.chains,
		"colliders": dynamic.geometry.colliders,
		"collision_enabled": dynamic.enabled,
		"dynamic_enabled": dynamic.dynamic_enabled,
	}


func _update_geometry() -> void:
	if mode != "skeleton":
		return
	var geometry := diagnostic_geometry()
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _overlay_material)
	for bone: Dictionary in geometry.bones:
		_bone(_vector(bone.head), _vector(bone.tail), 0.014, Color("ffd166"))
	for chain: Dictionary in geometry.chains:
		for index in range(chain.points.size() - 1):
			_bone(
				_vector(chain.points[index]),
				_vector(chain.points[index + 1]),
				0.009,
				Color("53e0e4")
			)
	_mesh.surface_end()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _overlay_material)
	for collider: Dictionary in geometry.colliders:
		_capsule(
			_vector(collider.start),
			_vector(collider.end),
			float(collider.radius),
			Color("ff82bd") if geometry.collision_enabled else Color("b88c80")
		)
	_mesh.surface_end()


func _bone(start: Vector3, end: Vector3, radius: float, color: Color) -> void:
	var direction := (end - start).normalized()
	if direction.is_zero_approx():
		return
	var side := _perpendicular(direction) * radius
	var up := direction.cross(side).normalized() * radius
	var middle := start.lerp(end, 0.28)
	var ring := [middle + side, middle + up, middle - side, middle - up]
	_mesh.surface_set_color(color)
	for index in 4:
		for tip in [start, end]:
			_mesh.surface_add_vertex(tip)
			_mesh.surface_add_vertex(ring[index])
			_mesh.surface_add_vertex(ring[(index + 1) % 4])


func _capsule(start: Vector3, end: Vector3, radius: float, color: Color) -> void:
	var axis := (end - start).normalized()
	var side := _perpendicular(axis)
	var up := axis.cross(side).normalized()
	_mesh.surface_set_color(color)
	for center in [start, end]:
		for index in 24:
			var a := TAU * float(index) / 24.0
			var b := TAU * float(index + 1) / 24.0
			_line(
				center + (side * cos(a) + up * sin(a)) * radius,
				center + (side * cos(b) + up * sin(b)) * radius
			)
	for radial in [side, up, -side, -up]:
		_line(start + radial * radius, end + radial * radius)
		for index in 8:
			var a := PI * 0.5 * float(index) / 8.0
			var b := PI * 0.5 * float(index + 1) / 8.0
			_line(
				start + (radial * cos(a) - axis * sin(a)) * radius,
				start + (radial * cos(b) - axis * sin(b)) * radius
			)
			_line(
				end + (radial * cos(a) + axis * sin(a)) * radius,
				end + (radial * cos(b) + axis * sin(b)) * radius
			)


func _line(start: Vector3, end: Vector3) -> void:
	_mesh.surface_add_vertex(start)
	_mesh.surface_add_vertex(end)


static func _perpendicular(axis: Vector3) -> Vector3:
	return axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()


static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
