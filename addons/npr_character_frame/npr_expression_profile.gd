class_name NPRExpressionProfile
extends Resource
## Character-authored behavior -> four independently owned output channels.
## eyes/mouth/brows contain blend-shape weights; color is shadow/highlight/blush.
## A symbol claims its channel with an empty dictionary and switches discretely.

@export var behaviors: Dictionary = {}


func pose(behavior: StringName) -> Dictionary:
	var value: Variant = behaviors.get(String(behavior), {})
	return value.duplicate(true) if value is Dictionary else {}


static func valid_pose(value: Dictionary) -> bool:
	for key in value:
		if (
			key
			not in [
				"eyes",
				"mouth",
				"brows",
				"color",
				"eye_symbol",
				"mouth_symbol",
				"eye_emphasis",
				"block_blink",
				"block_speech",
				"transition"
			]
		):
			return false
		var item: Variant = value[key]
		if key in ["eyes", "mouth", "brows"]:
			if not item is Dictionary:
				return false
			for shape in item:
				if not shape is String or shape.is_empty() or not _weight(item[shape]):
					return false
		elif key == "color":
			if not item is Vector3 or not item.is_finite():
				return false
			if item.x < 0 or item.y < 0 or item.z < 0:
				return false
			if item.x > 1 or item.y > 1 or item.z > 1:
				return false
		elif key in ["block_blink", "block_speech"]:
			if not item is bool:
				return false
		elif key in ["eye_symbol", "mouth_symbol"]:
			if not item is int or item < 0 or item > (6 if key == "eye_symbol" else 3):
				return false
		elif key == "transition":
			if not (item is float or item is int) or not is_finite(item) or item < 0 or item > 2:
				return false
		elif not _weight(item):
			return false
	return not value.is_empty()


static func _weight(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value) and value >= 0 and value <= 1
