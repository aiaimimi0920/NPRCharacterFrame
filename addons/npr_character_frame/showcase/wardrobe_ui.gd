extends RefCounted
## Shared construction helpers for the game-facing wardrobe screen.


static func label(text: String, size: int = 18) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	return node


static func button(text: String, id: String, callback: Callable) -> Button:
	var node := Button.new()
	node.name = id
	node.text = text
	node.custom_minimum_size.y = 44
	node.pressed.connect(callback)
	return node


static func visual_options(parent: Node, state: RefCounted, callback: Callable) -> void:
	for option in [
		["hair_dynamic_enabled", "HairDynamicEnabled", "发束与布带动态"],
		["hair_collision_enabled", "HairCollisionEnabled", "发束与身体碰撞"],
		["authored_materials_enabled", "AuthoredMaterialsEnabled", "装备独立材质"]
	]:
		var toggle := CheckButton.new()
		toggle.name = option[1]
		toggle.text = option[2]
		toggle.button_pressed = state.get(option[0])
		toggle.toggled.connect(callback.bind(option[0]))
		parent.add_child(toggle)


static func box(color: Color, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


static func theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	result.default_font = font
	result.default_font_size = 16
	result.set_color("font_color", "Label", Color("eff6ff"))
	for type in ["Button", "ColorPickerButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var color := Color(0.14, 0.22, 0.33, 0.68)
			if state in ["hover", "pressed"]:
				color = Color(0.32, 0.53, 0.68, 0.85)
			var style := box(color)
			if state in ["pressed", "focus"]:
				style.set_border_width_all(2)
				style.border_color = Color("e6d49a")
			result.set_stylebox(state, type, style)
		result.set_color("font_color", type, Color("f4f7fc"))
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, Color.WHITE)
		result.set_color("font_disabled_color", type, Color("b9c9dc"))
	var track := box(Color("617c94"), 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	result.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("ecd591")
	result.set_stylebox("grabber_area", "HSlider", fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return result
