class_name UpdateBanner
extends Button


func _ready() -> void:
	if not UpdateService.checked() and SettingsService.get_update_check_enabled():
		UpdateService.check_for_update()
	if not UpdateService.has_update():
		queue_free()
		return
	text = "▲  UPDATE AVAILABLE  —  v%s" % UpdateService.available_version

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)
