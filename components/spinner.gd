class_name Spinner
extends Control

@export var radius: float = 22.0
@export var width: float = 4.0
@export var fill_color := Color(0.698, 0.118, 1.0, 1.0)
@export var back_color := Color(0.408, 0.063, 0.627, 0.4)
@export var fill_percent: float = 0.28

var _angle: float = 0.0


func _ready() -> void:
	var diameter: float = (radius + width) * 2.0
	custom_minimum_size = Vector2(diameter, diameter)
	size = custom_minimum_size


func _process(delta: float) -> void:
	_angle += delta * 2.8
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	draw_arc(center, radius, _angle, _angle + TAU * fill_percent, 48, fill_color, width, true)
	draw_arc(center, radius, _angle + TAU * fill_percent, _angle + TAU, 24, back_color, width, true)
