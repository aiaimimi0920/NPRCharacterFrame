extends RefCounted
## Explicit input for non-hover screenshots; never disables production tooltips.


static func park(viewport: Viewport) -> void:
	# Synthetic GUI input, not an OS cursor warp. Call before the normal draw wait.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(-100.0, -100.0)
	motion.global_position = motion.position
	viewport.push_input(motion)
