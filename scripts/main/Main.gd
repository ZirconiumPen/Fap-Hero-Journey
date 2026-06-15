extends Control

# Plays the entrance animation only once per app session — replaying it on every
# return to the menu gets tiresome. Static, so it survives scene reloads but
# resets on app restart ("first startup").
static var _intro_played: bool = false

# True once the entrance animation has finished — gates the tagline blink and
# button hover effects so they don't fight the intro tweens.
var _intro_done: bool = false
# Per-button hover scale tween, so a fast re-hover replaces rather than stacks.
var _btn_tweens: Dictionary = {}

@onready var _title_section: VBoxContainer = %TitleSection
@onready var _start_btn: Button = %StartButton
@onready var _options_btn: Button = %OptionsButton
@onready var _build_btn: Button = %BuildButton
@onready var _quit_btn: Button = %QuitButton
@onready var _tagline: Label = %TaglineLabel


func _ready() -> void:
	MusicService.play()
	_connect_buttons()
	_play_intro()
	_tagline.get_node("Blinker").enabled = true


# The update flow: download the platform build, verify, extract into a sibling
# folder, and reveal it. The running app is never overwritten — the user launches
# the new folder and deletes the old one.
func _open_update_modal() -> void:
	var parts: Dictionary = UITheme.build_centered_modal(
		"UPDATE  —  v%s" % UpdateService.available_version, UITheme.MAGENTA, Vector2i(580, 400)
	)
	var modal: Control = parts["modal"]
	var vbox: VBoxContainer = parts["vbox"]
	vbox.add_theme_constant_override("separation", 16)

	var status: Label = Label.new()
	status.text = "A newer version is available. It'll download and extract into a new folder next to your current install — then close this and run the new one."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", UITheme.WHITE_SOFT)
	status.add_theme_font_size_override("font_size", 13)
	vbox.add_child(status)

	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.visible = false
	vbox.add_child(bar)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)

	var dl_btn: Button = Button.new()
	dl_btn.text = "⬇  DOWNLOAD"
	var notes_btn: Button = Button.new()
	notes_btn.text = "RELEASE NOTES"
	var close_btn: Button = Button.new()
	close_btn.text = "CLOSE"
	for b: Button in [dl_btn, notes_btn, close_btn]:
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 0)
		btn_row.add_child(b)

	notes_btn.pressed.connect(func() -> void: OS.shell_open(UpdateService.release_url()))
	close_btn.pressed.connect(modal.queue_free)

	var on_progress: Callable = func(got: int, total: int) -> void:
		bar.visible = true
		if total > 0:
			bar.value = clampf(float(got) / float(total) * 100.0, 0.0, 100.0)
			status.text = "Downloading…  %d%%  (%.1f MB)" % [int(bar.value), got / 1048576.0]
		else:
			status.text = "Downloading…  %.1f MB" % (got / 1048576.0)

	var drop_progress: Callable = func() -> void:
		if UpdateService.download_progress.is_connected(on_progress):
			UpdateService.download_progress.disconnect(on_progress)

	var on_ready: Callable = func(folder: String) -> void:
		drop_progress.call()
		bar.value = 100
		status.text = (
			"Update ready — its folder has been opened:\n%s\n\nClose this app and run the new version there, then delete the old folder."
			% folder
		)
		dl_btn.visible = false
		close_btn.pressed.disconnect(modal.queue_free)
		close_btn.text = "QUIT"
		close_btn.pressed.connect(get_tree().quit)

	var on_failed: Callable = func(reason: String) -> void:
		drop_progress.call()
		bar.visible = false
		status.text = "Update failed: %s" % reason
		dl_btn.disabled = false
		notes_btn.disabled = false

	dl_btn.pressed.connect(
		func() -> void:
			dl_btn.disabled = true
			notes_btn.disabled = true
			bar.visible = true
			status.text = "Starting download…"
			UpdateService.download_progress.connect(on_progress)
			UpdateService.download_ready.connect(on_ready, CONNECT_ONE_SHOT)
			UpdateService.download_failed.connect(on_failed, CONNECT_ONE_SHOT)
			UpdateService.download_and_stage()
	)

	# Closing mid-download drops the progress hook (the download itself finishes
	# in the autoload regardless).
	modal.tree_exiting.connect(drop_progress)

	add_child(modal)


func _connect_buttons() -> void:
	for btn: Button in [_start_btn, _options_btn, _build_btn, _quit_btn]:
		btn.mouse_entered.connect(_hover_btn.bind(btn, true))
		btn.mouse_exited.connect(_hover_btn.bind(btn, false))


# ---------------------------------------------------------------------------
# Entrance animation + hover
# ---------------------------------------------------------------------------


# Staged entrance: the title section pops in, the buttons cascade up one at a
# time, then the tagline fades in. Buttons are locked until it finishes.
func _play_intro() -> void:
	if _intro_played:
		# Already played this session — show the menu fully formed.
		_intro_done = true
		return
	_intro_played = true
	var btns: Array = [_start_btn, _options_btn, _build_btn, _quit_btn]
	_title_section.modulate.a = 0.0
	_tagline.modulate.a = 0.0
	for btn: Button in btns:
		btn.modulate.a = 0.0
		btn.disabled = true

	# Let layout settle (for scale pivots) and the scene transition clear.
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	# Title section — fade + pop.
	_title_section.pivot_offset = _title_section.size / 2.0
	_title_section.scale = Vector2(0.85, 0.85)
	var t1: Tween = create_tween().set_parallel()
	t1.tween_property(_title_section, "modulate:a", 1.0, 0.30)
	(
		t1
		. tween_property(_title_section, "scale", Vector2.ONE, 0.40)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_BACK)
	)
	await t1.finished

	# Buttons — cascade up.
	for i: int in btns.size():
		var b: Button = btns[i]
		b.pivot_offset = b.size / 2.0
		b.scale = Vector2(0.9, 0.9)
		var bt: Tween = create_tween().set_parallel()
		bt.tween_property(b, "modulate:a", 1.0, 0.25).set_delay(i * 0.07)
		(
			bt
			. tween_property(b, "scale", Vector2.ONE, 0.30)
			. set_delay(i * 0.07)
			. set_ease(Tween.EASE_OUT)
			. set_trans(Tween.TRANS_BACK)
		)
	await get_tree().create_timer(0.30 + btns.size() * 0.07).timeout

	# Tagline.
	create_tween().tween_property(_tagline, "modulate:a", 1.0, 0.30)

	for btn: Button in btns:
		btn.disabled = false
	_intro_done = true


# Smoothly scales a menu button on hover. Ignored until the intro finishes so
# it never competes with the cascade tweens.
func _hover_btn(btn: Button, hovering: bool) -> void:
	if not _intro_done:
		return
	var prev: Tween = _btn_tweens.get(btn)
	if prev != null and prev.is_running():
		prev.kill()
	btn.pivot_offset = btn.size / 2.0
	var tw: Tween = create_tween()
	(
		tw
		. tween_property(btn, "scale", Vector2(1.04, 1.04) if hovering else Vector2.ONE, 0.10)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_CUBIC)
	)
	_btn_tweens[btn] = tw


func _on_start_button_pressed() -> void:
	Transition.change_scene("res://scenes/journey_select/JourneySelect.tscn")


func _on_build_button_pressed() -> void:
	Transition.change_scene("res://scenes/journey_builder/JourneyBuilder.tscn")


func _on_options_button_pressed() -> void:
	Transition.change_scene("res://scenes/options/Options.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_update_banner_pressed() -> void:
	_open_update_modal()
