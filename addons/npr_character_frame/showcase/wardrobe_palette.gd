extends Button
## Show all three garment colors without manufacturing outfit thumbnails.

var palette_colors: Array[Color] = []
var caption := ""


func _draw() -> void:
	for index in palette_colors.size():
		var center := Vector2(size.x * 0.5 + (index - 1) * 18, 26)
		draw_circle(center, 12, Color(0.9, 0.94, 1, 0.5))
		draw_circle(center, 10, palette_colors[index])
	var font := get_theme_font("font")
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(
		font,
		Vector2((size.x - width) * 0.5, 60),
		caption,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color.WHITE
	)
