class_name ButtonEffects
extends Node

@export var target: BaseButton
@export var enabled: bool = true
@export var hover_scale: Vector2 = Vector2.ONE * 1.04

var _tween: Tween


func _ready() -> void:
	target.mouse_entered.connect(_rescale_button.bind(hover_scale))
	target.mouse_exited.connect(_rescale_button)


func _rescale_button(target_scale: Vector2 = Vector2.ONE) -> void:
	target.pivot_offset = target.size / 2
	_tween = create_tween()
	_tween.tween_property(target, "scale", target_scale, 0.10).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_CUBIC
	)
