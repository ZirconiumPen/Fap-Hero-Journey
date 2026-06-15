class_name Blinker
extends Node

@export var target: CanvasItem
@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not is_node_ready():
			await ready
		if enabled:
			hide_timer.start()
			return
		show_timer.stop()
		hide_timer.stop()
		target.modulate.a = 1.0

@export var show_time: float:
	set(value):
		show_time = value
		if not is_node_ready():
			await ready
		show_timer.wait_time = show_time
@export var hide_time: float:
	set(value):
		hide_time = value
		if not is_node_ready():
			await ready
		hide_timer.wait_time = hide_time

@onready var show_timer: Timer = $ShowTimer
@onready var hide_timer: Timer = $HideTimer


func _ready() -> void:
	if not target:
		push_error("No target set")
		return
	hide_timer.start()


func _on_show_timer_timeout() -> void:
	target.modulate.a = 1.0
	hide_timer.start()


func _on_hide_timer_timeout() -> void:
	target.modulate.a = 0.0
	show_timer.start()
