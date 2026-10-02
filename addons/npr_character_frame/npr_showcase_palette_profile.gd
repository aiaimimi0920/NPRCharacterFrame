class_name NPRShowcasePaletteProfile
extends Resource
## Ordered author inputs. Slot zero always means original material, never dye.

@export var labels := PackedStringArray()
## Flattened RGB triplets in main, secondary and trim order; six hex digits each.
@export var rgb := PackedStringArray()
@export var default_index := 0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if labels.is_empty() or rgb.size() != labels.size() * 3:
		errors.append("Palette requires nonempty labels and exactly three RGB values per slot")
	for label in labels:
		if label.strip_edges().is_empty():
			errors.append("Palette labels must not be blank")
	var pattern := RegEx.create_from_string("^[0-9a-fA-F]{6}$")
	for value in rgb:
		var matched := pattern.search(value)
		if matched == null or matched.get_string() != value:
			errors.append("Palette RGB must contain exactly six hexadecimal digits")
	if default_index < 0 or default_index >= labels.size():
		errors.append("default_index must identify an authored palette slot")
	return errors


func colors_at(index: int) -> Array[Color]:
	return [Color(rgb[index * 3]), Color(rgb[index * 3 + 1]), Color(rgb[index * 3 + 2])]
