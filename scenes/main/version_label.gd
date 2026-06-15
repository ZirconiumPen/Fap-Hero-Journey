class_name VersionLabel
extends Label


func _ready() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if not version:
		push_error("No version found in project settings, freeing self")
		queue_free()
		return
	text = "v" + version
