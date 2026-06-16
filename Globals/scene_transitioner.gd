extends CanvasLayer

var _root_window: Window

@onready var _animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_root_window = get_tree().root
	_root_window.remove_child.call_deferred(self)


func change_scene(path: String) -> void:
	if is_inside_tree():
		push_error("Tried to scene transition while already transitioning")
		return
	if not ResourceLoader.exists(path):
		push_error("Scene not found: %s" % path)
		return

	ResourceLoader.load_threaded_request(path)

	_root_window.add_child(self)

	_animation_player.play("fade_to_black")
	await _animation_player.animation_finished

	get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(path))

	_animation_player.play_backwards("fade_to_black")
	await _animation_player.animation_finished

	_root_window.remove_child(self)
