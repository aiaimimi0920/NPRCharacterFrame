class_name NPRComicLayer
extends Node3D
## Transient camera-facing ink at caller-owned character/bone anchors.
## SCENE tests real depth; OVERLAY intentionally ignores ALL scene occluders.

enum Occlusion { SCENE, OVERLAY }
enum Attachment { ANCHOR, VIEW_PLANE, SURFACE, PINNED }

const SCENE_SHADER = preload("res://addons/npr_character_frame/shaders/comic/comic_scene.gdshader")
const OVERLAY_SHADER = preload(
	"res://addons/npr_character_frame/shaders/comic/comic_overlay.gdshader"
)
const TYPES := ["sweat", "tear", "anger", "emphasis", "hatching"]
const MAX_EFFECTS := 16

var paused := false
var layer_mask := 1
var camera: Camera3D
var _effects: Array[Dictionary] = []
var _serial := 0


func _ready() -> void:
	process_priority = 10


func play(
	kind: String,
	anchor: Node3D,
	duration := 1.5,
	offset := Vector3.ZERO,
	size := Vector2(0.18, 0.22),
	occlusion: Occlusion = Occlusion.SCENE,
	key: StringName = &"",
	tint := Color.WHITE,
	attachment: Attachment = Attachment.ANCHOR,
	surface_material: ShaderMaterial = null
) -> int:
	if (
		not is_inside_tree()
		or occlusion not in [Occlusion.SCENE, Occlusion.OVERLAY]
		or (
			attachment
			not in [Attachment.ANCHOR, Attachment.VIEW_PLANE, Attachment.SURFACE, Attachment.PINNED]
		)
	):
		return 0
	if kind not in TYPES or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return 0
	if not is_finite(duration) or duration <= 0.0 or not offset.is_finite() or not size.is_finite():
		return 0
	if size.x <= 0.0 or size.y <= 0.0:
		return 0
	var replace_token := 0
	for effect in _effects:
		if not key.is_empty() and effect.key == key:
			replace_token = effect.token
	if replace_token == 0 and _effects.size() >= MAX_EFFECTS:
		return 0
	cancel(replace_token)
	var material := ShaderMaterial.new()
	material.shader = OVERLAY_SHADER if occlusion == Occlusion.OVERLAY else SCENE_SHADER
	material.render_priority = 100
	material.set_shader_parameter("kind", TYPES.find(kind))
	material.set_shader_parameter("ink_tint", tint)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mesh.mesh = quad
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.layers = layer_mask
	_serial += 1
	mesh.name = "Comic%d" % _serial
	add_child(mesh)
	_effects.append(
		{
			"token": _serial,
			"key": key,
			"kind": kind,
			"anchor": weakref(anchor),
			"mesh": mesh,
			"material": material,
			"duration": duration,
			"elapsed": 0.0,
			"offset": offset,
			"attachment": attachment,
			"surface_material": surface_material
		}
	)
	_update_effect(_effects.back())
	return _serial


func pin(token: int, world_position: Vector3) -> void:
	# Capture only once at birth. Later camera changes must never rewrite this offset.
	var view := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if view == null or not world_position.is_finite():
		return
	for effect in _effects:
		if effect.token != token:
			continue
		var anchor := effect.anchor.get_ref() as Node3D
		var mesh: MeshInstance3D = effect.mesh
		if not is_instance_valid(anchor):
			return
		var space := view.get_camera_transform().orthonormalized()
		var previous_depth := -(space.affine_inverse() * mesh.global_position).z
		var target_depth := -(space.affine_inverse() * world_position).z
		var dimensions := anchor.global_basis.get_scale().abs()
		var scale := maxf(dimensions.x, maxf(dimensions.y, dimensions.z))
		var ratio := 1.0
		if view.projection != Camera3D.PROJECTION_ORTHOGONAL:
			ratio = target_depth / maxf(previous_depth, view.near)
		effect.offset = anchor.to_local(world_position)
		effect.pin_scale = mesh.global_basis.get_scale().x * ratio / maxf(scale, 0.0001)
		effect.pin_normal = anchor.global_basis.inverse() * space.basis.z
		effect.attachment = Attachment.PINNED
		_update_effect(effect)


func cancel(token: int) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		if _effects[index].token == token:
			_remove(index)


func clear() -> void:
	for index in range(_effects.size() - 1, -1, -1):
		_remove(index)


func active_count() -> int:
	return _effects.size()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		var anchor := effect.anchor.get_ref() as Node3D
		if not is_instance_valid(anchor) or not anchor.is_inside_tree():
			_remove(index)
			continue
		if not paused:
			effect.elapsed += maxf(delta, 0.0) if is_finite(delta) else 0.0
		if effect.elapsed >= effect.duration:
			_remove(index)
		else:
			_update_effect(effect)


func _update_effect(effect: Dictionary) -> void:
	var anchor := effect.anchor.get_ref() as Node3D
	var view := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	var mesh: MeshInstance3D = effect.mesh
	if not is_instance_valid(anchor) or view == null or not anchor.is_inside_tree():
		mesh.hide()
		return
	mesh.visible = anchor.is_visible_in_tree()
	mesh.layers = layer_mask
	if effect.attachment == Attachment.SURFACE:
		# Ink is evaluated on the source face's own geometry and skinning.
		mesh.hide()
		if is_instance_valid(effect.surface_material):
			effect.surface_material.set_shader_parameter(
				"u_npr_comic_world_to_anchor", anchor.global_transform.affine_inverse()
			)
			var alpha := minf(effect.elapsed / 0.08, (effect.duration - effect.elapsed) / 0.15)
			var facing := (
				anchor.global_basis.z.dot(view.global_position - anchor.global_position) > 0.0
			)
			effect.surface_material.set_shader_parameter(
				"u_npr_comic_" + effect.kind + "_opacity",
				clampf(alpha, 0.0, 1.0) if facing and anchor.is_visible_in_tree() else 0.0
			)
	elif effect.attachment == Attachment.PINNED:
		mesh.global_position = anchor.global_transform * effect.offset
		var dimensions := anchor.global_basis.get_scale().abs()
		var scale := maxf(dimensions.x, maxf(dimensions.y, dimensions.z))
		mesh.global_basis = view.get_camera_transform().basis.orthonormalized().scaled(
			Vector3.ONE * float(effect.get("pin_scale", 1.0)) * scale
		)
		var normal: Vector3 = anchor.global_basis * effect.get("pin_normal", Vector3.BACK)
		mesh.visible = (
			mesh.visible and normal.dot(view.global_position - mesh.global_position) > 0.0
		)
	elif effect.attachment == Attachment.VIEW_PLANE:
		_place_in_view(effect, anchor, view)
	else:
		mesh.global_position = anchor.global_transform * effect.offset
		if effect.kind in ["sweat", "tear"]:
			mesh.global_position -= (
				anchor.global_basis.y.normalized() * minf(effect.elapsed * 0.045, 0.08)
			)
		mesh.global_basis = view.global_basis.orthonormalized()
	var fade := minf(effect.elapsed / 0.08, (effect.duration - effect.elapsed) / 0.15)
	effect.material.set_shader_parameter("opacity", clampf(fade, 0.0, 1.0))


func _place_in_view(effect: Dictionary, anchor: Node3D, view: Camera3D) -> void:
	# The head owns translation and scale; the camera owns the comic composition.
	# Positive offset.z is an authored head-front clearance, not disabled depth.
	var mesh: MeshInstance3D = effect.mesh
	var camera_space := view.get_camera_transform().orthonormalized()
	var point := camera_space.affine_inverse() * anchor.global_position
	var depth := -point.z
	if depth <= view.near or depth >= view.far:
		mesh.hide()
		return
	var dimensions := anchor.global_basis.get_scale().abs()
	var scale := maxf(dimensions.x, maxf(dimensions.y, dimensions.z))
	if not is_finite(scale) or scale <= 0.0:
		mesh.hide()
		return
	var offset: Vector3 = effect.offset
	if effect.kind in ["sweat", "tear"]:
		# Short motion stays attached to the temple/under-eye region even at 8 s.
		offset.y -= minf(effect.elapsed * 0.018, minf(mesh.mesh.size.y * 0.12, 0.012))
	var forward := clampf(offset.z * scale, 0.0, maxf(depth - view.near * 1.1, 0.0))
	var perspective := 1.0
	if view.projection != Camera3D.PROJECTION_ORTHOGONAL:
		perspective = (depth - forward) / depth
	# Move along the camera ray, compensating both size and off-axis position.
	# This keeps the icon attached when zooming or using h_offset / v_offset.
	point.x = (point.x + offset.x * scale) * perspective
	point.y = (point.y + offset.y * scale) * perspective
	point.z += forward
	mesh.global_position = camera_space * point
	mesh.global_basis = camera_space.basis.scaled(Vector3.ONE * scale * perspective)


func _remove(index: int) -> void:
	var effect: Dictionary = _effects[index]
	if is_instance_valid(effect.surface_material):
		effect.surface_material.set_shader_parameter("u_npr_comic_" + effect.kind + "_opacity", 0.0)
	if is_instance_valid(_effects[index].mesh):
		_effects[index].mesh.queue_free()
	_effects.remove_at(index)


func _exit_tree() -> void:
	clear()
