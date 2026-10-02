class_name NPRShowcaseHeightProfile
extends Resource
## Hosiery selection in actor-rest Y; independent of the geometric candidate domain.

@export var min_height := 0.0
@export var max_height := 0.0
@export var default_height := 0.0
@export var step := 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(min_height) or not is_finite(max_height) or min_height >= max_height:
		errors.append("Height bounds must be finite and strictly increasing")
	if not is_finite(default_height) or default_height < min_height or default_height > max_height:
		errors.append("Default height must be finite and inside the inclusive bounds")
	if not is_finite(step) or step <= 0.0:
		errors.append("Height step must be finite and positive")
	return errors


func accepts(value: float) -> bool:
	return is_finite(value) and value >= min_height and value <= max_height
