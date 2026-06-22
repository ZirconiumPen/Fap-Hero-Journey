class_name GraphEdge
extends RefCounted

var from: Vector2
var to: Vector2
var color: Color


func _init(new_from: Vector2, new_to: Vector2, new_color: Color) -> void:
	from = new_from
	to = new_to
	color = new_color
