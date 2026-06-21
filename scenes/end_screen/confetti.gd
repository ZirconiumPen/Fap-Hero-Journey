class_name Confetti
extends CPUParticles2D


func _ready() -> void:
	# Emit along a wide strip just above the top edge so confetti rains down.
	var width: float = get_viewport_rect().size.x
	position = Vector2(width * 0.5, -20.0)
	emission_rect_extents = Vector2(width * 0.5, 8.0)
