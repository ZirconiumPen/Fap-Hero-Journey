class_name JourneyBuilder
extends Control

# ---------------------------------------------------------------------------
# JourneyBuilder.gd  –  Create and save custom journeys
# Users fill out journey metadata, add rounds by picking funscript + video
# files via OS file dialog or drag-and-drop. The folder structure is built
# automatically under user://journeys/ and all files are copied in.
# ---------------------------------------------------------------------------

# All shared colors and style helpers live in `UITheme` (autoload). See
# Globals/UITheme.gd. Local references use UITheme.<COLOR_NAME> / UITheme.style_*.

const TOP_BAR_HEIGHT:  int = 64
const CONTENT_PADDING: int = 48
const COVER_WIDTH:     int = 200
const COVER_HEIGHT:    int = 280
const LABEL_WIDTH:     int = 100
const ROW_SEP:         int = 8   # HBoxContainer separation inside each round row
const JOURNEYS_DIR:    String = "user://journeys"

const DIFFICULTIES: Array = ["Easy", "Medium", "Hard", "Very Hard", "Extreme", "Insane"]

const VIDEO_EXTENSIONS:     Array[String] = ["mp4", "m4v", "mkv", "avi", "mov", "wmv", "webm"]
const FUNSCRIPT_EXTENSIONS: Array[String] = ["funscript", "json"]
const IMAGE_EXTENSIONS:     Array[String] = ["png", "jpg", "jpeg", "webp"]

# EIRTeam.FFmpeg only decodes H.264; everything else gets transcoded on save.
const H264_NAMES: Array[String] = ["h264", "avc1", "avc"]
const TRANSCODE_PROGRESS_FILE: String = "user://transcode_progress.txt"

const DropZoneScript = preload("res://scripts/journey_builder/DropZone.gd")

const GraphViewScene = preload("res://scenes/graph_view/GraphView.tscn")

@onready var _bg:          ColorRect       = $Background
@onready var _top_bar:     HBoxContainer   = $TopBar
@onready var _back_btn:    Button          = $TopBar/BackButton
@onready var _title_lbl:   Label           = $TopBar/TitleLabel
@onready var _status_lbl:  Label           = $TopBar/StatusLabel
@onready var _save_btn:    Button          = $TopBar/SaveButton
@onready var _main_layout: HBoxContainer   = $MainLayout
@onready var _graph_host:  Control         = $MainLayout/GraphHost
@onready var _side_panel:  PanelContainer  = $MainLayout/SidePanel
@onready var _side_scroll: ScrollContainer = $MainLayout/SidePanel/SideScroll
@onready var _side_vbox:   VBoxContainer   = $MainLayout/SidePanel/SideScroll/SideVBox

static var edit_journey: Dictionary = {}

const SIDE_PANEL_WIDTH: int = 480

# Journey metadata: stored as member vars since the side-panel editor widgets
# are created and destroyed dynamically when the user navigates the graph.
var _journey_name:           String = ""
var _journey_author:         String = ""
var _journey_desc:           String = ""
var _journey_difficulty_idx: int    = 0

var _cover_path:    String       = ""
var _cover_texture: ImageTexture = null  # cached so the journey-info view can re-show the preview without re-reading from disk

var _items:      Array  = []  # Array[Dictionary] — {type:"round"|"fork"|"shop"|"storyboard", ...}

var _graph: Control = null  # GraphView instance, host inside _graph_host
var _selected_item: Dictionary = {}  # Mirror of GraphView's current selection.

var _transcode_cancel: bool = false
var _transcode_pid:    int  = -1


func _ready() -> void:
	_apply_layout()
	_apply_theme()
	_connect_signals()
	_setup_graph_view()
	if not edit_journey.is_empty():
		_load_journey(edit_journey)
		edit_journey = {}
	_show_journey_info_panel()


# Builds the GraphView inside the GraphHost slot, wires its selection / insert
# signals to the side panel.
func _setup_graph_view() -> void:
	_graph = GraphViewScene.instantiate()
	_graph.anchor_right  = 1.0
	_graph.anchor_bottom = 1.0
	_graph_host.add_child(_graph)
	_graph.node_selected.connect(_on_graph_node_selected)
	_graph.insert_requested.connect(_on_graph_insert_requested)
	# Initial state: render current _items (empty for a new journey).
	_graph.call_deferred("set_items", _items)


func _on_graph_node_selected(item: Dictionary, arr: Array, idx: int) -> void:
	_selected_item = item
	if item.is_empty():
		_show_journey_info_panel()
	else:
		_show_node_editor(item, arr, idx)


func _on_graph_insert_requested(arr: Array, idx: int, screen_pos: Vector2) -> void:
	_show_insert_popup(self, _graph, arr, idx, screen_pos)


# Replaces _refresh_items()'s former role: rebuild the graph from _items.
# Called after structural changes (load, drop import, etc).
func _refresh_graph() -> void:
	if _graph:
		_graph.set_items(_items)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _apply_layout() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0

	_bg.anchor_right  = 1.0
	_bg.anchor_bottom = 1.0
	_bg.offset_left = 0; _bg.offset_top = 0; _bg.offset_right = 0; _bg.offset_bottom = 0

	var animated_bg: Control = $AnimatedBackground
	animated_bg.anchor_right  = 1.0
	animated_bg.anchor_bottom = 1.0

	_top_bar.anchor_right  = 1.0
	_top_bar.offset_left   = 16
	_top_bar.offset_right  = -16
	_top_bar.offset_top    = 12
	_top_bar.offset_bottom = TOP_BAR_HEIGHT
	_top_bar.add_theme_constant_override("separation", 12)

	# Title expands to fill space between Back (left) and Status/Save (right).
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_main_layout.anchor_right  = 1.0
	_main_layout.anchor_bottom = 1.0
	_main_layout.offset_left   = 16
	_main_layout.offset_right  = -16
	_main_layout.offset_top    = TOP_BAR_HEIGHT + 8
	_main_layout.offset_bottom = -16
	_main_layout.add_theme_constant_override("separation", 12)

	_graph_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_host.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_graph_host.clip_contents         = true

	_side_panel.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH, 0)
	_side_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_side_panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_side_vbox.add_theme_constant_override("separation", 10)
	_side_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------

func _apply_theme() -> void:
	_bg.color = UITheme.BG

	UITheme.style_label(_title_lbl, UITheme.PURPLE_BRIGHT, 18, true)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	UITheme.style_button(_back_btn, UITheme.MAGENTA)
	UITheme.style_button(_save_btn, UITheme.PURPLE_BRIGHT)
	_save_btn.custom_minimum_size = Vector2(180, 0)

	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.visible = false

	# Side panel background
	var sp_style: StyleBoxFlat = StyleBoxFlat.new()
	sp_style.bg_color           = UITheme.PANEL_BG
	sp_style.border_color       = UITheme.PURPLE_MID
	sp_style.border_width_left  = 1; sp_style.border_width_right  = 1
	sp_style.border_width_top   = 1; sp_style.border_width_bottom = 1
	sp_style.content_margin_left   = 14; sp_style.content_margin_right  = 14
	sp_style.content_margin_top    = 14; sp_style.content_margin_bottom = 14
	_side_panel.add_theme_stylebox_override("panel", sp_style)


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

# Style helpers moved to UITheme (autoload). Callers use UITheme.style_*(...).


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_save_btn.pressed.connect(_on_save_pressed)
	get_viewport().files_dropped.connect(_on_viewport_files_dropped)


func _on_back_pressed() -> void:
	Transition.change_scene("res://scenes/main/Main.tscn")


func _show_insert_popup(overlay: Control, graph: Control, arr: Array, insert_idx: int, screen_pos: Vector2) -> void:
	# Builds a small floating panel with 4 type buttons. Clicking outside it
	# dismisses without inserting.
	var popup: PopupPanel = PopupPanel.new()
	overlay.add_child(popup)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = UITheme.PANEL_BG
	panel_style.border_color = UITheme.PURPLE_BRIGHT
	panel_style.border_width_left   = 2; panel_style.border_width_right  = 2
	panel_style.border_width_top    = 2; panel_style.border_width_bottom = 2
	panel_style.content_margin_left   = 6; panel_style.content_margin_right  = 6
	panel_style.content_margin_top    = 6; panel_style.content_margin_bottom = 6
	popup.add_theme_stylebox_override("panel", panel_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup.add_child(vbox)

	var hdr: Label = Label.new()
	hdr.text = "INSERT HERE"
	hdr.add_theme_color_override("font_color", UITheme.SEPARATOR)
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.uppercase = true
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hdr)

	var specs: Array = [
		{"label": "▶ ROUND",      "color": UITheme.PURPLE_MID,    "item": {"type": "round", "name": "", "funscript_path": "", "video_path": "", "coins": 0}},
		{"label": "◆ SHOP",       "color": UITheme.PURPLE_BRIGHT, "item": {"type": "shop", "title": ""}},
		{"label": "◈ STORYBOARD", "color": UITheme.STORYBOARD,    "item": {"type": "storyboard", "coins": 0, "image": "", "lines": []}},
		{"label": "⑂ FORK",       "color": UITheme.MAGENTA,       "item": {
			"type": "fork", "title": "", "description": "",
			"paths": [
				{"name": "Path A", "description": "", "image_path": "", "items": []},
				{"name": "Path B", "description": "", "image_path": "", "items": []},
			],
		}},
	]
	for spec in specs:
		var btn: Button = Button.new()
		btn.text = spec["label"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(180, 0)
		UITheme.style_button(btn, spec["color"])
		var item_template: Dictionary = spec["item"]
		btn.pressed.connect(func() -> void:
			arr.insert(insert_idx, item_template.duplicate(true))
			popup.queue_free()
			# Re-render the graph, then select the newly inserted item so its
			# editor immediately appears in the side panel.
			graph.call_deferred("set_items", _items)
			graph.call_deferred("select_item", arr, insert_idx)
		)
		vbox.add_child(btn)

	popup.popup(Rect2i(Vector2i(screen_pos), Vector2i(0, 0)))


# Default side-panel view (no node selected). Shows the journey metadata form
# (cover, name, author, difficulty, description) plus quick-add buttons for
# the top-level sequence.
func _show_journey_info_panel() -> void:
	if _side_vbox == null:
		return
	for c in _side_vbox.get_children():
		c.queue_free()

	var hdr: Label = Label.new()
	hdr.text = "// JOURNEY INFO //"
	hdr.add_theme_color_override("font_color", UITheme.PURPLE_BRIGHT)
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_side_vbox.add_child(hdr)

	# Cover preview + button
	_side_vbox.add_child(_side_field_label("COVER IMAGE"))
	var cover_border: PanelContainer = PanelContainer.new()
	cover_border.custom_minimum_size = Vector2(0, COVER_HEIGHT * 0.9)
	var cb_style: StyleBoxFlat = StyleBoxFlat.new()
	cb_style.bg_color           = UITheme.PURPLE_DARK
	cb_style.border_color       = UITheme.PURPLE_MID
	cb_style.border_width_left  = 2; cb_style.border_width_right  = 2
	cb_style.border_width_top   = 2; cb_style.border_width_bottom = 2
	cover_border.add_theme_stylebox_override("panel", cb_style)
	_side_vbox.add_child(cover_border)

	var cover_preview: TextureRect = TextureRect.new()
	cover_preview.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	cover_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover_preview.clip_contents = true
	if _cover_texture != null:
		cover_preview.texture = _cover_texture
	cover_border.add_child(cover_preview)

	var cover_btn: Button = Button.new()
	cover_btn.text = "DROP IMAGE OR CLICK TO BROWSE" if _cover_path == "" else "CHANGE COVER"
	UITheme.style_button(cover_btn, UITheme.PURPLE_MID)
	cover_btn.pressed.connect(_on_cover_pressed)
	_side_vbox.add_child(cover_btn)

	_side_vbox.add_child(_side_section_separator())

	# Name
	_side_vbox.add_child(_side_field_label("JOURNEY NAME"))
	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text = "Journey name..."
	name_edit.text = _journey_name
	UITheme.style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void: _journey_name = val)
	_side_vbox.add_child(name_edit)

	# Author
	_side_vbox.add_child(_side_field_label("AUTHOR"))
	var author_edit: LineEdit = LineEdit.new()
	author_edit.placeholder_text = "Author name..."
	author_edit.text = _journey_author
	UITheme.style_line_edit(author_edit)
	author_edit.text_changed.connect(func(val: String) -> void: _journey_author = val)
	_side_vbox.add_child(author_edit)

	# Difficulty
	_side_vbox.add_child(_side_field_label("DIFFICULTY"))
	var diff_btn: OptionButton = OptionButton.new()
	for diff: String in DIFFICULTIES:
		diff_btn.add_item(diff)
	diff_btn.selected = _journey_difficulty_idx
	UITheme.style_option_button(diff_btn)
	diff_btn.item_selected.connect(func(idx: int) -> void: _journey_difficulty_idx = idx)
	_side_vbox.add_child(diff_btn)

	# Description
	_side_vbox.add_child(_side_field_label("DESCRIPTION"))
	var desc_edit: TextEdit = TextEdit.new()
	desc_edit.placeholder_text = "Optional description..."
	desc_edit.text = _journey_desc
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.custom_minimum_size = Vector2(0, 90)
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	UITheme.style_text_edit(desc_edit)
	desc_edit.text_changed.connect(func() -> void: _journey_desc = desc_edit.text)
	_side_vbox.add_child(desc_edit)

	_side_vbox.add_child(_side_section_separator())

	# Quick-add buttons to top level
	var add_lbl: Label = Label.new()
	add_lbl.text = "ADD TO TOP LEVEL"
	add_lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	add_lbl.add_theme_font_size_override("font_size", 10)
	add_lbl.uppercase = true
	_side_vbox.add_child(add_lbl)

	var add_specs: Array = [
		{"label": "+ ROUND",      "color": UITheme.PURPLE_MID,    "item": {"type": "round", "name": "", "funscript_path": "", "video_path": "", "coins": 0}},
		{"label": "◆ SHOP",       "color": UITheme.PURPLE_BRIGHT, "item": {"type": "shop", "title": ""}},
		{"label": "◈ STORYBOARD", "color": UITheme.STORYBOARD,    "item": {"type": "storyboard", "coins": 0, "image": "", "lines": []}},
		{"label": "⑂ FORK",       "color": UITheme.MAGENTA,       "item": {
			"type": "fork", "title": "", "description": "",
			"paths": [
				{"name": "Path A", "description": "", "image_path": "", "items": []},
				{"name": "Path B", "description": "", "image_path": "", "items": []},
			],
		}},
	]
	for spec in add_specs:
		var btn: Button = Button.new()
		btn.text = spec["label"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(btn, spec["color"])
		var item_template: Dictionary = spec["item"]
		btn.pressed.connect(func() -> void:
			_items.append(item_template.duplicate(true))
			_refresh_graph()
		)
		_side_vbox.add_child(btn)


# Builds the editor for the currently selected node into _side_vbox.
func _show_node_editor(item: Dictionary, arr: Array, idx: int) -> void:
	for c in _side_vbox.get_children():
		c.queue_free()
	_build_side_panel_editor(_side_vbox, item, arr, idx, _graph)


# Dispatches to the right inline editor based on item type. The path-item
# editors (`_make_pi_*`) work directly on the parent array reference, so edits
# persist back into _items at any nesting depth.
func _build_side_panel_editor(
		container: VBoxContainer,
		item: Dictionary,
		arr: Array,
		idx: int,
		graph: Control) -> void:
	var t: String = item.get("type", "round")

	var hdr: Label = Label.new()
	var accent: Color
	match t:
		"round":      hdr.text = "// ROUND //";      accent = UITheme.PURPLE_BRIGHT
		"shop":       hdr.text = "// SHOP //";       accent = UITheme.PURPLE_BRIGHT
		"storyboard": hdr.text = "// STORYBOARD //"; accent = UITheme.STORYBOARD
		"fork":       hdr.text = "// FORK //";       accent = UITheme.MAGENTA
		_:            hdr.text = "// ITEM //";       accent = UITheme.PURPLE_MID
	hdr.add_theme_color_override("font_color", accent)
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(hdr)

	# Refresh callback: when the editor mutates a structural property
	# (add line, remove fork path, etc.) the graph needs to redraw.
	var refresh_graph: Callable = func() -> void:
		graph.call_deferred("refresh")

	# Called by editors after a structural change (move / delete / add line) to
	# refresh both the graph and the side panel for the new state.
	var reselect: Callable = func(new_idx: int) -> void:
		graph.select_item(arr, new_idx)

	match t:
		"round":
			container.add_child(_make_side_round_editor(arr, idx, graph, reselect))
		"shop":
			container.add_child(_make_side_shop_editor(arr, idx, graph, reselect))
		"storyboard":
			container.add_child(_make_side_storyboard_editor(arr, idx, graph, reselect))
		"fork":
			# Compact fork editor: title + description only. The fork's structure
			# (paths and their items) is edited via the graph itself.
			container.add_child(_make_fork_compact_editor(arr, idx, graph, reselect))


# Compact editor for a fork node — just metadata (no paths/items, which are
# represented in the graph).
func _side_field_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.uppercase = true
	return lbl


func _side_section_separator() -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	return spacer


# Bottom row of move/delete buttons used by every side-panel editor.
# After a structural change, `reselect.call(new_idx)` re-renders the graph and
# the side panel for the moved item (or deselects when the item is deleted).
func _side_action_row(arr: Array, idx: int, graph: Control, reselect: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var up_btn: Button = UITheme.make_icon_btn("↑ MOVE UP", idx == 0, UITheme.PURPLE_MID)
	up_btn.custom_minimum_size = Vector2(0, 0)
	up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_btn.pressed.connect(func() -> void:
		if idx <= 0: return
		var tmp: Dictionary = arr[idx]
		arr[idx]     = arr[idx - 1]
		arr[idx - 1] = tmp
		reselect.call(idx - 1)
	)
	row.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓ MOVE DOWN", idx == arr.size() - 1, UITheme.PURPLE_MID)
	dn_btn.custom_minimum_size = Vector2(0, 0)
	dn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dn_btn.pressed.connect(func() -> void:
		if idx >= arr.size() - 1: return
		var tmp: Dictionary = arr[idx]
		arr[idx]     = arr[idx + 1]
		arr[idx + 1] = tmp
		reselect.call(idx + 1)
	)
	row.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕ DELETE", false, UITheme.MAGENTA)
	rm_btn.custom_minimum_size = Vector2(0, 0)
	rm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rm_btn.pressed.connect(func() -> void:
		arr.remove_at(idx)
		reselect.call(-1)
	)
	row.add_child(rm_btn)

	return row


func _make_side_round_editor(arr: Array, idx: int, graph: Control, reselect: Callable) -> Control:
	var round_data: Dictionary = arr[idx]
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	col.add_child(_side_field_label("ROUND NAME"))
	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text = "Round name..."
	name_edit.text             = round_data.get("name", "")
	UITheme.style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["name"] = val
	)
	col.add_child(name_edit)

	col.add_child(_side_section_separator())
	col.add_child(_side_field_label("VIDEO FILE"))
	var video_zone: PanelContainer = DropZoneScript.new()
	video_zone.accepted_extensions   = VIDEO_EXTENSIONS.duplicate()
	video_zone.picker_title          = "Select Video"
	video_zone.picker_filters        = ["*.mp4,*.m4v,*.mkv,*.avi,*.mov,*.wmv,*.webm ; Video Files", "*.* ; All Files"]
	video_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(video_zone)
	if round_data.get("video_path", "") != "":
		video_zone.call_deferred("set_file", round_data["video_path"])
	video_zone.file_dropped.connect(func(p: String) -> void:
		arr[idx]["video_path"] = p
		if (arr[idx].get("name","") as String).strip_edges() == "":
			var auto: String = p.get_file().get_basename()
			arr[idx]["name"] = auto
			name_edit.text = auto
	)

	col.add_child(_side_section_separator())
	col.add_child(_side_field_label("FUNSCRIPT"))
	var fs_zone: PanelContainer = DropZoneScript.new()
	fs_zone.accepted_extensions   = FUNSCRIPT_EXTENSIONS.duplicate()
	fs_zone.picker_title          = "Select Funscript"
	fs_zone.picker_filters        = ["*.funscript,*.json ; Funscript Files", "*.* ; All Files"]
	fs_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(fs_zone)
	if round_data.get("funscript_path", "") != "":
		fs_zone.call_deferred("set_file", round_data["funscript_path"])
	fs_zone.file_dropped.connect(func(p: String) -> void:
		arr[idx]["funscript_path"] = p
		if (arr[idx].get("name","") as String).strip_edges() == "":
			var auto: String = p.get_file().get_basename()
			arr[idx]["name"] = auto
			name_edit.text = auto
	)

	col.add_child(_side_section_separator())
	col.add_child(_side_field_label("COINS AWARDED"))
	var coins_edit: LineEdit = LineEdit.new()
	coins_edit.text             = str(round_data.get("coins", 0))
	coins_edit.max_length       = 6
	coins_edit.placeholder_text = "0"
	UITheme.style_line_edit(coins_edit)
	coins_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["coins"] = val.to_int()
	)
	col.add_child(coins_edit)

	col.add_child(_side_section_separator())
	col.add_child(_side_action_row(arr, idx, graph, reselect))
	return col


func _make_side_shop_editor(arr: Array, idx: int, graph: Control, reselect: Callable) -> Control:
	var shop_data: Dictionary = arr[idx]
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	col.add_child(_side_field_label("SHOP TITLE"))
	var title_edit: LineEdit = LineEdit.new()
	title_edit.placeholder_text = "Shop title (optional)..."
	title_edit.text             = shop_data.get("title", "")
	UITheme.style_line_edit(title_edit)
	title_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["title"] = val
	)
	col.add_child(title_edit)

	col.add_child(_side_section_separator())
	col.add_child(_side_action_row(arr, idx, graph, reselect))
	return col


func _make_side_storyboard_editor(arr: Array, idx: int, graph: Control, reselect: Callable) -> Control:
	var sb_data: Dictionary = arr[idx]
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	col.add_child(_side_field_label("COINS AWARDED"))
	var coins_edit: LineEdit = LineEdit.new()
	coins_edit.text             = str(sb_data.get("coins", 0))
	coins_edit.max_length       = 6
	coins_edit.placeholder_text = "0"
	UITheme.style_line_edit(coins_edit)
	coins_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["coins"] = val.to_int()
	)
	col.add_child(coins_edit)

	col.add_child(_side_section_separator())
	col.add_child(_side_field_label("DEFAULT IMAGE"))
	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions   = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title          = "Select Default Image"
	img_zone.picker_filters        = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(img_zone)
	if sb_data.get("image", "") != "":
		img_zone.call_deferred("set_file", sb_data["image"])
	img_zone.file_dropped.connect(func(p: String) -> void:
		arr[idx]["image"] = p
	)

	col.add_child(_side_section_separator())
	col.add_child(_side_field_label("DIALOGUE LINES"))

	# Ensure the lines array exists in the data dict so closures share the reference.
	var lines_arr: Array = sb_data.get("lines", [])
	if not sb_data.has("lines"):
		arr[idx]["lines"] = lines_arr

	var lines_col: VBoxContainer = VBoxContainer.new()
	lines_col.add_theme_constant_override("separation", 6)
	col.add_child(lines_col)

	# When the lines list changes (add / move / delete) we rebuild this storyboard
	# editor by reselecting the same item at the same idx.
	var refresh_self: Callable = func() -> void:
		reselect.call(idx)

	for li in lines_arr.size():
		lines_col.add_child(_make_side_storyboard_line_block(lines_arr, li, refresh_self))

	var add_row: HBoxContainer = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	col.add_child(add_row)

	var add_line_btn: Button = Button.new()
	add_line_btn.text = "+ ADD LINE"
	add_line_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_line_btn, UITheme.STORYBOARD)
	add_line_btn.pressed.connect(func() -> void:
		lines_arr.append({"speaker": "", "text": "", "image": ""})
		refresh_self.call()
	)
	add_row.add_child(add_line_btn)

	var paste_btn: Button = Button.new()
	paste_btn.text = "⎘ PASTE LINES"
	paste_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(paste_btn, UITheme.PURPLE_MID)
	paste_btn.pressed.connect(func() -> void:
		_show_paste_lines_popup(lines_arr, refresh_self)
	)
	add_row.add_child(paste_btn)

	col.add_child(_side_section_separator())
	col.add_child(_side_action_row(arr, idx, graph, reselect))
	return col


# Opens a popup with a large TextEdit. Each non-empty line of the pasted text
# becomes a new dialogue line. Format: "SPEAKER: text" splits on the first
# colon; lines without a colon become narration (no speaker).
func _show_paste_lines_popup(lines_arr: Array, refresh_storyboard: Callable) -> void:
	var popup: PopupPanel = PopupPanel.new()
	add_child(popup)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = UITheme.PANEL_BG
	panel_style.border_color = UITheme.STORYBOARD
	panel_style.border_width_left   = 2; panel_style.border_width_right  = 2
	panel_style.border_width_top    = 2; panel_style.border_width_bottom = 2
	panel_style.content_margin_left   = 16; panel_style.content_margin_right  = 16
	panel_style.content_margin_top    = 16; panel_style.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", panel_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	var hdr: Label = Label.new()
	hdr.text = "// PASTE DIALOGUE LINES //"
	hdr.add_theme_color_override("font_color", UITheme.STORYBOARD)
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hdr)

	var hint: Label = Label.new()
	hint.text = "ONE LINE PER DIALOGUE.  FORMAT:  SPEAKER: text  (LINES WITHOUT A COLON BECOME NARRATION.)"
	hint.add_theme_color_override("font_color", UITheme.SEPARATOR)
	hint.add_theme_font_size_override("font_size", 10)
	hint.uppercase = true
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var text_edit: TextEdit = TextEdit.new()
	text_edit.placeholder_text = "ARIA: Hello there.\nThe wind howled outside.\nKAI: It's getting cold."
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical   = Control.SIZE_FILL
	text_edit.custom_minimum_size = Vector2(0, 200)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	UITheme.style_text_edit(text_edit)
	vbox.add_child(text_edit)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(cancel_btn, UITheme.PURPLE_MID)
	cancel_btn.pressed.connect(func() -> void: popup.queue_free())
	btn_row.add_child(cancel_btn)

	var apply_btn: Button = Button.new()
	apply_btn.text = "+ APPEND LINES"
	apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(apply_btn, UITheme.STORYBOARD)
	apply_btn.pressed.connect(func() -> void:
		var parsed: Array = _parse_pasted_lines(text_edit.text)
		for line: Dictionary in parsed:
			lines_arr.append(line)
		popup.queue_free()
		refresh_storyboard.call()
	)
	btn_row.add_child(apply_btn)

	# Center within the parent window and clamp to 90% so the popup is always
	# visible even on small windows.
	popup.popup_centered_clamped(Vector2i(720, 560), 0.9)
	text_edit.grab_focus()


# Parses a pasted multi-line block into dialogue-line dicts.
# Format: "SPEAKER: text" → {speaker: "SPEAKER", text: "text"}.
# Lines without a colon become narration: {speaker: "", text: "<line>"}.
# Blank lines are skipped.
func _parse_pasted_lines(raw: String) -> Array:
	var result: Array = []
	for raw_line in raw.split("\n"):
		var line: String = (raw_line as String).strip_edges()
		if line == "":
			continue
		var colon_idx: int = line.find(":")
		if colon_idx > 0:
			var speaker: String = line.substr(0, colon_idx).strip_edges()
			var text: String = line.substr(colon_idx + 1).strip_edges()
			result.append({"speaker": speaker, "text": text, "image": ""})
		else:
			result.append({"speaker": "", "text": line, "image": ""})
	return result


# Per-line sub-block for the storyboard side editor: speaker, text (multi-line),
# optional per-line image override, and line move/remove buttons.
# `refresh_storyboard` rebuilds the parent storyboard editor when the line is
# moved, deleted, or otherwise structurally changed.
func _make_side_storyboard_line_block(lines_arr: Array, line_idx: int, refresh_storyboard: Callable) -> Control:
	var line_data: Dictionary = lines_arr[line_idx]

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = UITheme.PANEL_BG
	ps.border_color        = Color(UITheme.STORYBOARD.r, UITheme.STORYBOARD.g, UITheme.STORYBOARD.b, 0.35)
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 10; ps.content_margin_right  = 10
	ps.content_margin_top  = 8;  ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	# Line header
	var hdr_lbl: Label = Label.new()
	hdr_lbl.text = "LINE %d" % (line_idx + 1)
	hdr_lbl.add_theme_color_override("font_color", UITheme.STORYBOARD)
	hdr_lbl.add_theme_font_size_override("font_size", 11)
	hdr_lbl.uppercase = true
	col.add_child(hdr_lbl)

	col.add_child(_side_field_label("SPEAKER"))
	var speaker_edit: LineEdit = LineEdit.new()
	speaker_edit.placeholder_text = "Speaker (optional)..."
	speaker_edit.text             = line_data.get("speaker", "")
	UITheme.style_line_edit(speaker_edit)
	speaker_edit.text_changed.connect(func(val: String) -> void:
		lines_arr[line_idx]["speaker"] = val
	)
	col.add_child(speaker_edit)

	col.add_child(_side_field_label("DIALOGUE"))
	var text_edit: TextEdit = TextEdit.new()
	text_edit.placeholder_text     = "Dialogue text..."
	text_edit.text                  = line_data.get("text", "")
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.custom_minimum_size   = Vector2(0, 90)
	text_edit.wrap_mode             = TextEdit.LINE_WRAPPING_BOUNDARY
	UITheme.style_text_edit(text_edit)
	text_edit.text_changed.connect(func() -> void:
		lines_arr[line_idx]["text"] = text_edit.text
	)
	col.add_child(text_edit)

	col.add_child(_side_field_label("SPEAKER IMAGE (OPTIONAL)"))
	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions   = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title          = "Select Speaker Image for Line %d" % (line_idx + 1)
	img_zone.picker_filters        = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(img_zone)
	if line_data.get("image", "") != "":
		img_zone.call_deferred("set_file", line_data["image"])
	img_zone.file_dropped.connect(func(p: String) -> void:
		lines_arr[line_idx]["image"] = p
	)

	# Line action row (move + delete). Each operation rebuilds the parent
	# storyboard editor so visible line numbers / disabled states stay in sync.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var up_btn: Button = UITheme.make_icon_btn("↑", line_idx == 0, UITheme.STORYBOARD)
	up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_btn.pressed.connect(func() -> void:
		if line_idx <= 0: return
		var tmp: Dictionary = lines_arr[line_idx]
		lines_arr[line_idx]     = lines_arr[line_idx - 1]
		lines_arr[line_idx - 1] = tmp
		refresh_storyboard.call()
	)
	row.add_child(up_btn)
	var dn_btn: Button = UITheme.make_icon_btn("↓", line_idx == lines_arr.size() - 1, UITheme.STORYBOARD)
	dn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dn_btn.pressed.connect(func() -> void:
		if line_idx >= lines_arr.size() - 1: return
		var tmp: Dictionary = lines_arr[line_idx]
		lines_arr[line_idx]     = lines_arr[line_idx + 1]
		lines_arr[line_idx + 1] = tmp
		refresh_storyboard.call()
	)
	row.add_child(dn_btn)
	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rm_btn.pressed.connect(func() -> void:
		lines_arr.remove_at(line_idx)
		refresh_storyboard.call()
	)
	row.add_child(rm_btn)
	col.add_child(row)

	return panel


func _make_fork_compact_editor(arr: Array, idx: int, graph: Control, reselect: Callable) -> Control:
	var item: Dictionary = arr[idx]

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)

	var title_lbl: Label = Label.new()
	title_lbl.text = "TITLE"
	title_lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.uppercase = true
	col.add_child(title_lbl)

	var title_edit: LineEdit = LineEdit.new()
	title_edit.placeholder_text = "Fork title (optional)..."
	title_edit.text = item.get("title", "")
	UITheme.style_line_edit(title_edit)
	title_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["title"] = val
	)
	col.add_child(title_edit)

	var desc_lbl: Label = Label.new()
	desc_lbl.text = "DESCRIPTION"
	desc_lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.uppercase = true
	col.add_child(desc_lbl)

	var desc_edit: LineEdit = LineEdit.new()
	desc_edit.placeholder_text = "Fork description (optional)..."
	desc_edit.text = item.get("description", "")
	UITheme.style_line_edit(desc_edit)
	desc_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["description"] = val
	)
	col.add_child(desc_edit)

	var paths_lbl: Label = Label.new()
	paths_lbl.text = "PATHS"
	paths_lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	paths_lbl.add_theme_font_size_override("font_size", 10)
	paths_lbl.uppercase = true
	col.add_child(paths_lbl)

	# Ensure the paths array reference is shared with the item dict so closures
	# below mutate the underlying data.
	var paths_arr: Array = item.get("paths", [])
	if not item.has("paths"):
		arr[idx]["paths"] = paths_arr

	for pi in paths_arr.size():
		col.add_child(_make_path_editor_block(paths_arr, pi, graph, reselect))

	if paths_arr.size() < 4:
		var add_path_btn: Button = Button.new()
		add_path_btn.text = "+ ADD PATH"
		add_path_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(add_path_btn, UITheme.PURPLE_MID)
		add_path_btn.pressed.connect(func() -> void:
			paths_arr.append({
				"name": "Path %s" % char(65 + paths_arr.size()),
				"description": "",
				"image_path": "",
				"items": [],
			})
			reselect.call(idx)
		)
		col.add_child(add_path_btn)

	col.add_child(_side_section_separator())
	col.add_child(_side_action_row(arr, idx, graph, reselect))
	return col


# Per-path editor card inside the fork compact editor: name, description, card
# image, and (when there are >2 paths) a delete-path button.
func _make_path_editor_block(paths_arr: Array, pi: int, graph: Control, reselect: Callable) -> Control:
	var path: Dictionary = paths_arr[pi]

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color = Color(UITheme.MAGENTA.r, UITheme.MAGENTA.g, UITheme.MAGENTA.b, 0.08)
	ps.border_color = UITheme.MAGENTA
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 10; ps.content_margin_right  = 10
	ps.content_margin_top  = 8;  ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sub: VBoxContainer = VBoxContainer.new()
	sub.add_theme_constant_override("separation", 4)
	panel.add_child(sub)

	# Header row: "PATH N" + delete button (only if >2 paths)
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ROW_SEP)
	sub.add_child(hdr)

	var path_lbl: Label = Label.new()
	path_lbl.text = "PATH %d" % (pi + 1)
	path_lbl.add_theme_color_override("font_color", UITheme.MAGENTA)
	path_lbl.add_theme_font_size_override("font_size", 11)
	path_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(path_lbl)

	if paths_arr.size() > 2:
		var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
		rm_btn.pressed.connect(func() -> void:
			paths_arr.remove_at(pi)
			# Reselect the same fork to rebuild this editor with one fewer path.
			# `idx` isn't in scope here, so we just trigger a graph refresh and
			# let the caller's reselect handle the editor rebuild.
			graph.call_deferred("refresh")
		)
		hdr.add_child(rm_btn)

	# Name
	sub.add_child(_side_field_label("NAME"))
	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text = "Path name..."
	name_edit.text = path.get("name", "")
	UITheme.style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void:
		paths_arr[pi]["name"] = val
	)
	sub.add_child(name_edit)

	# Description
	sub.add_child(_side_field_label("DESCRIPTION"))
	var desc_edit: LineEdit = LineEdit.new()
	desc_edit.placeholder_text = "Description (optional)..."
	desc_edit.text = path.get("description", "")
	UITheme.style_line_edit(desc_edit)
	desc_edit.text_changed.connect(func(val: String) -> void:
		paths_arr[pi]["description"] = val
	)
	sub.add_child(desc_edit)

	# Card image
	sub.add_child(_side_field_label("CARD IMAGE"))
	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions   = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title          = "Select Card Image for Path %d" % (pi + 1)
	img_zone.picker_filters        = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_child(img_zone)
	if path.get("image_path", "") != "":
		img_zone.call_deferred("set_file", path["image_path"])
	img_zone.file_dropped.connect(func(p: String) -> void:
		paths_arr[pi]["image_path"] = p
	)

	return panel


func _on_viewport_files_dropped(files: PackedStringArray) -> void:
	# Anywhere on the viewport accepts an image drop as the journey cover.
	# Item-level drops (video / funscript / round images) are handled by their
	# own DropZone controls which intercept the event first.
	for f: String in files:
		if f.get_extension().to_lower() in IMAGE_EXTENSIONS:
			_cover_path = f
			_update_cover_preview()
			return


func _on_add_round_pressed() -> void:
	_items.append({"type": "round", "name": "", "funscript_path": "", "video_path": "", "coins": 0})
	_refresh_items()


func _on_add_fork_pressed() -> void:
	_items.append({
		"type":        "fork",
		"title":       "",
		"description": "",
		"paths": [
			{"name": "Path A", "description": "", "image_path": "", "items": []},
			{"name": "Path B", "description": "", "image_path": "", "items": []},
		],
	})
	_refresh_items()


func _on_add_shop_pressed() -> void:
	_items.append({"type": "shop", "title": ""})
	_refresh_items()


func _on_add_storyboard_pressed() -> void:
	_items.append({"type": "storyboard", "coins": 0, "image": "", "lines": []})
	_refresh_items()


# ---------------------------------------------------------------------------
# Cover image
# ---------------------------------------------------------------------------

func _on_cover_pressed() -> void:
	var dialog: FileDialog = FileDialog.new()
	dialog.access    = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters   = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	dialog.title     = "Select Cover Image"
	add_child(dialog)
	dialog.popup_centered(Vector2i(900, 600))
	dialog.file_selected.connect(func(path: String) -> void:
		_cover_path = path
		_update_cover_preview()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())


# Loads the cover image from _cover_path into _cover_texture. The journey-info
# side-panel view reads _cover_texture when building its preview widget.
func _update_cover_preview() -> void:
	if _cover_path == "":
		_cover_texture = null
		_show_journey_info_panel()  # refresh visible widgets
		return
	var f: FileAccess = FileAccess.open(_cover_path, FileAccess.READ)
	if f == null:
		return
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	var img: Image = Image.new()
	var err: Error
	if bytes.size() >= 4 and bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	else:
		err = img.load_webp_from_buffer(bytes)
		if err != OK:
			err = img.load_jpg_from_buffer(bytes)
		if err != OK:
			err = img.load_png_from_buffer(bytes)
	if err == OK:
		_cover_texture = ImageTexture.create_from_image(img)
	# Rebuild journey-info panel so the preview widget picks up the new texture
	# (only if no node is currently selected).
	if _selected_item.is_empty():
		_show_journey_info_panel()


# ---------------------------------------------------------------------------
# Load existing journey for editing
# ---------------------------------------------------------------------------

func _load_journey(journey: Dictionary) -> void:
	_journey_name   = journey.get("title", "")
	_journey_author = journey.get("author", "")
	_journey_desc   = journey.get("description", "")

	var diff: String  = journey.get("difficulty", "Easy")
	var diff_idx: int = DIFFICULTIES.find(diff)
	if diff_idx >= 0:
		_journey_difficulty_idx = diff_idx

	var cover: String = journey.get("cover_path", "")
	if cover != "":
		_cover_path = cover
		_update_cover_preview()

	_items.clear()

	var rounds: Array = journey.get("rounds", []).duplicate()
	rounds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("order", 0) as int) < (b.get("order", 0) as int)
	)
	var forks:       Array = journey.get("forks",       []).duplicate()
	var shops:       Array = journey.get("shops",       []).duplicate()
	var storyboards: Array = journey.get("storyboards", []).duplicate()

	# Interleave rounds, storyboards, shops, and forks by sort key (same logic as GameState.BuildSequence)
	var seq: Array = []
	for r: Dictionary in rounds:
		seq.append({
			"key": (r.get("order", 0) as int) * 3,
			"data": {
				"type":           "round",
				"name":           r.get("name", ""),
				"funscript_path": r.get("funscript_path", ""),
				"video_path":     _find_video_in_round(r.get("folder", "")),
				"coins":          r.get("coins", 0),
			},
		})
	for sb: Dictionary in storyboards:
		seq.append({
			"key": (sb.get("order", 0) as int) * 3,
			"data": {
				"type":  "storyboard",
				"coins": sb.get("coins", 0),
				"image": sb.get("image", ""),
				"lines": sb.get("lines", []),
			},
		})
	for sh: Dictionary in shops:
		seq.append({
			"key": (sh.get("after_order", 0) as int) * 3 + 1,
			"data": {
				"type":  "shop",
				"title": sh.get("title", ""),
			},
		})
	for f: Dictionary in forks:
		seq.append({
			"key": (f.get("after_order", 0) as int) * 3 + 2,
			"data": _build_fork_item(f),
		})
	seq.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["key"] as int) < (b["key"] as int))
	for s in seq:
		_items.append(s["data"])

	_refresh_items()


# Recursively converts a parsed-journey fork dict into the builder _items model
# (which uses a single mixed items[] array per path rather than separate
# rounds/storyboards/shops/forks arrays).
func _build_fork_item(f: Dictionary) -> Dictionary:
	var paths_out: Array = []
	for p: Dictionary in f.get("paths", []):
		paths_out.append({
			"name":        p.get("name", ""),
			"description": p.get("description", ""),
			"image_path":  p.get("image_path", ""),
			"items":       _build_path_items(p),
		})
	return {
		"type":        "fork",
		"title":       f.get("title", ""),
		"description": f.get("description", ""),
		"paths":       paths_out,
	}


# Recursively rebuilds a path's mixed items[] array from the parsed-journey
# separate rounds/storyboards/shops/forks arrays. Nested forks recurse.
func _build_path_items(p: Dictionary) -> Array:
	var sub: Array = []
	for pr: Dictionary in p.get("rounds", []):
		sub.append({
			"key": (pr.get("order", 0) as int) * 3,
			"data": {
				"type":           "round",
				"name":           pr.get("name", ""),
				"funscript_path": pr.get("funscript_path", ""),
				"video_path":     _find_video_in_round(pr.get("folder", "")),
				"coins":          pr.get("coins", 0),
			},
		})
	for psb: Dictionary in p.get("storyboards", []):
		sub.append({
			"key": (psb.get("order", 0) as int) * 3,
			"data": {
				"type":  "storyboard",
				"coins": psb.get("coins", 0),
				"image": psb.get("image", ""),
				"lines": psb.get("lines", []),
			},
		})
	for ps: Dictionary in p.get("shops", []):
		sub.append({
			"key": (ps.get("after_order", 0) as int) * 3 + 1,
			"data": {
				"type":  "shop",
				"title": ps.get("title", ""),
			},
		})
	for nf: Dictionary in p.get("forks", []):
		sub.append({
			"key": (nf.get("after_order", 0) as int) * 3 + 2,
			"data": _build_fork_item(nf),
		})
	sub.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["key"] as int) < (b["key"] as int))
	var items: Array = []
	for s in sub:
		items.append(s["data"])
	return items


# Recursively validates a fork. Returns "" if OK, or an error message.
# `context_label` is used in messages so the user knows where the error is
# (e.g. "fork after round 3" or "nested fork in path \"Path A\"").
func _validate_fork(fork_item: Dictionary, context_label: String) -> String:
	var paths: Array = fork_item.get("paths", [])
	if paths.size() < 2:
		return "The %s needs at least 2 paths." % context_label
	for pi in paths.size():
		var ppath: Dictionary = paths[pi]
		var pname: String = ppath.get("name","")
		if (pname as String).strip_edges() == "":
			return "Path %d of %s needs a name." % [pi + 1, context_label]
		var pi_list: Array = ppath.get("items", [])
		var pr_count: int = pi_list.reduce(func(acc: int, x: Dictionary) -> int:
			return acc + (1 if x.get("type","round") == "round" else 0), 0)
		if pr_count == 0:
			return "Path \"%s\" (in %s) needs at least one round." % [pname, context_label]
		for pi_item: Dictionary in pi_list:
			var pi_t: String = pi_item.get("type","round")
			match pi_t:
				"round":
					if (pi_item.get("name","") as String).strip_edges() == "":
						return "A round in path \"%s\" needs a name." % pname
					if pi_item.get("funscript_path","") == "":
						return "Round \"%s\" in path \"%s\" needs a funscript." % [pi_item.get("name","?"), pname]
				"fork":
					var nested_err: String = _validate_fork(pi_item, "nested fork in path \"%s\"" % pname)
					if nested_err != "":
						return nested_err
	return ""


func _items_have_any_video(items: Array) -> bool:
	for it in items:
		match it.get("type","round"):
			"round":
				if it.get("video_path","") != "":
					return true
			"fork":
				for p in it.get("paths", []):
					if _items_have_any_video(p.get("items", [])):
						return true
	return false


func _find_video_in_round(folder: String) -> String:
	if folder == "":
		return ""
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() in VIDEO_EXTENSIONS:
			dir.list_dir_end()
			return folder + "/" + fname
		fname = dir.get_next()
	dir.list_dir_end()
	return ""


# ---------------------------------------------------------------------------
# Round list
# ---------------------------------------------------------------------------

func _refresh_items() -> void:
	# Now an alias for the graph-rebuild path. The function name is kept
	# because many internal handlers still call it after mutating _items.
	_refresh_graph()


func _make_round_row(idx: int) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat      = StyleBoxFlat.new()
	ps.bg_color            = UITheme.PANEL_BG
	ps.border_color        = UITheme.PURPLE_DARK
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 10; ps.content_margin_right  = 10
	ps.content_margin_top  = 8;  ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	panel.add_child(hbox)

	# Count only round-type items up to this idx for the displayed number
	var round_num: int = 0
	for i in idx + 1:
		if _items[i].get("type", "round") == "round":
			round_num += 1

	var order_lbl: Label = Label.new()
	order_lbl.text = "%02d." % round_num
	order_lbl.custom_minimum_size = Vector2(30, 0)
	order_lbl.add_theme_color_override("font_color", UITheme.PURPLE_MID)
	order_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(order_lbl)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text      = "Round name..."
	name_edit.text                   = _items[idx].get("name", "")
	name_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void:
		_items[idx]["name"] = val
	)
	hbox.add_child(name_edit)

	var video_zone: PanelContainer = DropZoneScript.new()
	video_zone.accepted_extensions = VIDEO_EXTENSIONS.duplicate()
	video_zone.picker_title        = "Select Video for Round %d" % round_num
	video_zone.picker_filters      = ["*.mp4,*.m4v,*.mkv,*.avi,*.mov,*.wmv,*.webm ; Video Files", "*.* ; All Files"]
	video_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(video_zone)
	if _items[idx].get("video_path", "") != "":
		video_zone.call_deferred("set_file", _items[idx]["video_path"])
	video_zone.file_dropped.connect(func(path: String) -> void:
		_items[idx]["video_path"] = path
		if (_items[idx].get("name", "") as String).strip_edges() == "":
			var auto: String = path.get_file().get_basename()
			_items[idx]["name"] = auto
			name_edit.text = auto
	)

	var fs_zone: PanelContainer = DropZoneScript.new()
	fs_zone.accepted_extensions  = FUNSCRIPT_EXTENSIONS.duplicate()
	fs_zone.picker_title         = "Select Funscript for Round %d" % round_num
	fs_zone.picker_filters       = ["*.funscript,*.json ; Funscript Files", "*.* ; All Files"]
	fs_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(fs_zone)
	if _items[idx].get("funscript_path", "") != "":
		fs_zone.call_deferred("set_file", _items[idx]["funscript_path"])
	fs_zone.file_dropped.connect(func(path: String) -> void:
		_items[idx]["funscript_path"] = path
		if (_items[idx].get("name", "") as String).strip_edges() == "":
			var auto: String = path.get_file().get_basename()
			_items[idx]["name"] = auto
			name_edit.text = auto
	)

	var coins_edit: LineEdit = LineEdit.new()
	coins_edit.text              = str(_items[idx].get("coins", 0))
	coins_edit.custom_minimum_size = Vector2(70, 0)
	coins_edit.max_length        = 6
	coins_edit.placeholder_text  = "0"
	UITheme.style_line_edit(coins_edit)
	coins_edit.text_changed.connect(func(val: String) -> void:
		_items[idx]["coins"] = val.to_int()
	)
	hbox.add_child(coins_edit)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.PURPLE_MID)
	up_btn.pressed.connect(func() -> void: _move_item(idx, -1))
	hbox.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == _items.size() - 1, UITheme.PURPLE_MID)
	dn_btn.pressed.connect(func() -> void: _move_item(idx, 1))
	hbox.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		_items.remove_at(idx)
		_refresh_items()
	)
	hbox.add_child(rm_btn)

	return panel


func _make_shop_block(idx: int) -> Control:
	var item: Dictionary = _items[idx]

	var outer: PanelContainer = PanelContainer.new()
	var os: StyleBoxFlat = StyleBoxFlat.new()
	os.bg_color              = Color(UITheme.PURPLE_BRIGHT.r, UITheme.PURPLE_BRIGHT.g, UITheme.PURPLE_BRIGHT.b, 0.06)
	os.border_color          = UITheme.PURPLE_BRIGHT
	os.border_width_left     = 2; os.border_width_right  = 2
	os.border_width_top      = 2; os.border_width_bottom = 2
	os.content_margin_left   = 12; os.content_margin_right  = 12
	os.content_margin_top    = 10; os.content_margin_bottom = 10
	outer.add_theme_stylebox_override("panel", os)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	outer.add_child(hbox)

	var shop_lbl: Label = Label.new()
	shop_lbl.text = "◆ SHOP"
	shop_lbl.add_theme_color_override("font_color", UITheme.PURPLE_BRIGHT)
	shop_lbl.add_theme_font_size_override("font_size", 13)
	shop_lbl.custom_minimum_size = Vector2(72, 0)
	hbox.add_child(shop_lbl)

	var title_edit: LineEdit = LineEdit.new()
	title_edit.placeholder_text     = "Shop title (optional)..."
	title_edit.text                  = item.get("title", "")
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(title_edit)
	title_edit.text_changed.connect(func(val: String) -> void: _items[idx]["title"] = val)
	hbox.add_child(title_edit)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.PURPLE_MID)
	up_btn.pressed.connect(func() -> void: _move_item(idx, -1))
	hbox.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == _items.size() - 1, UITheme.PURPLE_MID)
	dn_btn.pressed.connect(func() -> void: _move_item(idx, 1))
	hbox.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		_items.remove_at(idx)
		_refresh_items()
	)
	hbox.add_child(rm_btn)

	return outer


func _make_fork_block(idx: int) -> Control:
	var item: Dictionary = _items[idx]

	var outer: PanelContainer = PanelContainer.new()
	var os: StyleBoxFlat = StyleBoxFlat.new()
	os.bg_color              = Color(UITheme.MAGENTA.r, UITheme.MAGENTA.g, UITheme.MAGENTA.b, 0.06)
	os.border_color          = UITheme.MAGENTA
	os.border_width_left     = 2; os.border_width_right  = 2
	os.border_width_top      = 2; os.border_width_bottom = 2
	os.content_margin_left   = 12; os.content_margin_right  = 12
	os.content_margin_top    = 10; os.content_margin_bottom = 10
	outer.add_theme_stylebox_override("panel", os)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	outer.add_child(col)

	# Header row
	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", ROW_SEP)
	col.add_child(header_row)

	var fork_lbl: Label = Label.new()
	fork_lbl.text = "⑂ FORK"
	fork_lbl.add_theme_color_override("font_color", UITheme.MAGENTA)
	fork_lbl.add_theme_font_size_override("font_size", 13)
	fork_lbl.custom_minimum_size = Vector2(72, 0)
	header_row.add_child(fork_lbl)

	var title_edit: LineEdit = LineEdit.new()
	title_edit.placeholder_text     = "Fork title (optional)..."
	title_edit.text                  = item.get("title", "")
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(title_edit)
	title_edit.text_changed.connect(func(val: String) -> void: _items[idx]["title"] = val)
	header_row.add_child(title_edit)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.PURPLE_MID)
	up_btn.pressed.connect(func() -> void: _move_item(idx, -1))
	header_row.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == _items.size() - 1, UITheme.PURPLE_MID)
	dn_btn.pressed.connect(func() -> void: _move_item(idx, 1))
	header_row.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		_items.remove_at(idx)
		_refresh_items()
	)
	header_row.add_child(rm_btn)

	# Description row
	var desc_edit: LineEdit = LineEdit.new()
	desc_edit.placeholder_text     = "Fork description (optional)..."
	desc_edit.text                  = item.get("description", "")
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(desc_edit)
	desc_edit.text_changed.connect(func(val: String) -> void: _items[idx]["description"] = val)
	col.add_child(desc_edit)

	# Paths
	var paths_col: VBoxContainer = VBoxContainer.new()
	paths_col.add_theme_constant_override("separation", 6)
	col.add_child(paths_col)

	var paths: Array = item.get("paths", [])
	for pi in paths.size():
		paths_col.add_child(_make_fork_path_block(idx, pi))

	if paths.size() < 4:
		var add_path_btn: Button = Button.new()
		add_path_btn.text = "+ ADD PATH"
		UITheme.style_button(add_path_btn, UITheme.PURPLE_MID)
		add_path_btn.pressed.connect(func() -> void:
			_items[idx]["paths"].append({"name": "Path %s" % (char(65 + _items[idx]["paths"].size())), "description": "", "image_path": "", "items": []})
			_refresh_items()
		)
		col.add_child(add_path_btn)

	return outer


func _make_fork_path_block(fork_idx: int, path_idx: int) -> Control:
	var path_data: Dictionary = _items[fork_idx]["paths"][path_idx]

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = Color(UITheme.PURPLE_MID.r, UITheme.PURPLE_MID.g, UITheme.PURPLE_MID.b, 0.10)
	ps.border_color        = UITheme.PURPLE_MID
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 10; ps.content_margin_right  = 10
	ps.content_margin_top  = 8;  ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	# Path header
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ROW_SEP)
	col.add_child(hdr)

	var path_lbl: Label = Label.new()
	path_lbl.text = "PATH %d" % (path_idx + 1)
	path_lbl.add_theme_color_override("font_color", UITheme.PURPLE_BRIGHT)
	path_lbl.add_theme_font_size_override("font_size", 11)
	path_lbl.custom_minimum_size = Vector2(60, 0)
	hdr.add_child(path_lbl)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text     = "Path name..."
	name_edit.text                  = path_data.get("name", "")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void:
		_items[fork_idx]["paths"][path_idx]["name"] = val
	)
	hdr.add_child(name_edit)

	var desc_edit: LineEdit = LineEdit.new()
	desc_edit.placeholder_text     = "Description (optional)..."
	desc_edit.text                  = path_data.get("description", "")
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(desc_edit)
	desc_edit.text_changed.connect(func(val: String) -> void:
		_items[fork_idx]["paths"][path_idx]["description"] = val
	)
	hdr.add_child(desc_edit)

	if _items[fork_idx]["paths"].size() > 2:
		var rm_path_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
		rm_path_btn.pressed.connect(func() -> void:
			_items[fork_idx]["paths"].remove_at(path_idx)
			_refresh_items()
		)
		hdr.add_child(rm_path_btn)

	# Card image
	var img_lbl: Label = Label.new()
	img_lbl.text = "CARD IMAGE"
	img_lbl.add_theme_color_override("font_color", UITheme.PURPLE_MID)
	img_lbl.add_theme_font_size_override("font_size", 10)
	img_lbl.uppercase = true
	col.add_child(img_lbl)

	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions   = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title          = "Select Card Image for Path %d" % (path_idx + 1)
	img_zone.picker_filters        = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(img_zone)
	if path_data.get("image_path", "") != "":
		img_zone.call_deferred("set_file", path_data["image_path"])
	img_zone.file_dropped.connect(func(path: String) -> void:
		_items[fork_idx]["paths"][path_idx]["image_path"] = path
	)

	# Items list for this path — mixed rounds, shops, storyboards, and nested forks.
	var items_list: VBoxContainer = VBoxContainer.new()
	items_list.add_theme_constant_override("separation", 4)
	col.add_child(items_list)

	var path_items: Array = path_data.get("items", [])
	_render_path_items(path_items, items_list)

	var add_btns_row: HBoxContainer = HBoxContainer.new()
	add_btns_row.add_theme_constant_override("separation", 8)
	col.add_child(add_btns_row)

	var add_round_btn: Button = Button.new()
	add_round_btn.text                  = "+ ROUND"
	add_round_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_round_btn, UITheme.PURPLE_MID)
	add_round_btn.pressed.connect(func() -> void:
		path_items.append({"type": "round", "name": "", "funscript_path": "", "video_path": "", "coins": 0})
		_refresh_items()
	)
	add_btns_row.add_child(add_round_btn)

	var add_shop_btn: Button = Button.new()
	add_shop_btn.text                  = "◆ SHOP"
	add_shop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_shop_btn, UITheme.PURPLE_BRIGHT)
	add_shop_btn.pressed.connect(func() -> void:
		path_items.append({"type": "shop", "title": ""})
		_refresh_items()
	)
	add_btns_row.add_child(add_shop_btn)

	var add_sb_btn: Button = Button.new()
	add_sb_btn.text                  = "◈ STORYBOARD"
	add_sb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_sb_btn, UITheme.STORYBOARD)
	add_sb_btn.pressed.connect(func() -> void:
		path_items.append({"type": "storyboard", "coins": 0, "image": "", "lines": []})
		_refresh_items()
	)
	add_btns_row.add_child(add_sb_btn)

	var add_fork_btn: Button = Button.new()
	add_fork_btn.text                  = "⑂ FORK"
	add_fork_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_fork_btn, UITheme.MAGENTA)
	add_fork_btn.pressed.connect(func() -> void:
		path_items.append({
			"type":        "fork",
			"title":       "",
			"description": "",
			"paths": [
				{"name": "Path A", "description": "", "image_path": "", "items": []},
				{"name": "Path B", "description": "", "image_path": "", "items": []},
			],
		})
		_refresh_items()
	)
	add_btns_row.add_child(add_fork_btn)

	return panel


# Renders an items[] array (a fork path's items, or a nested fork path's items) into a
# container. Dispatches by type — recurses through nested forks.
func _render_path_items(items_arr: Array, container: Container) -> void:
	for i in items_arr.size():
		var t: String = items_arr[i].get("type", "round")
		match t:
			"round":      container.add_child(_make_pi_round_row(items_arr, i))
			"shop":       container.add_child(_make_pi_shop_row(items_arr, i))
			"storyboard": container.add_child(_make_pi_storyboard_block(items_arr, i))
			"fork":       container.add_child(_make_pi_fork_block(items_arr, i))


func _move_pi(arr: Array, idx: int, direction: int) -> void:
	var new_idx: int = idx + direction
	if new_idx < 0 or new_idx >= arr.size():
		return
	var tmp: Dictionary = arr[idx]
	arr[idx]     = arr[new_idx]
	arr[new_idx] = tmp
	_refresh_items()


func _make_pi_round_row(arr: Array, idx: int) -> Control:
	var round_data: Dictionary = arr[idx]

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = UITheme.PANEL_BG
	ps.border_color        = UITheme.PURPLE_DARK
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 8; ps.content_margin_right  = 8
	ps.content_margin_top  = 6; ps.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	panel.add_child(hbox)

	var order_lbl: Label = Label.new()
	order_lbl.text = "%d." % (idx + 1)
	order_lbl.custom_minimum_size = Vector2(24, 0)
	order_lbl.add_theme_color_override("font_color", UITheme.PURPLE_MID)
	order_lbl.add_theme_font_size_override("font_size", 12)
	hbox.add_child(order_lbl)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text     = "Round name..."
	name_edit.text                  = round_data.get("name", "")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["name"] = val
	)
	hbox.add_child(name_edit)

	var video_zone: PanelContainer = DropZoneScript.new()
	video_zone.accepted_extensions   = VIDEO_EXTENSIONS.duplicate()
	video_zone.picker_title          = "Select Video"
	video_zone.picker_filters        = ["*.mp4,*.m4v,*.mkv,*.avi,*.mov,*.wmv,*.webm ; Video Files", "*.* ; All Files"]
	video_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(video_zone)
	if round_data.get("video_path", "") != "":
		video_zone.call_deferred("set_file", round_data["video_path"])
	video_zone.file_dropped.connect(func(path: String) -> void:
		arr[idx]["video_path"] = path
		if (arr[idx].get("name","") as String).strip_edges() == "":
			var auto: String = path.get_file().get_basename()
			arr[idx]["name"] = auto
			name_edit.text = auto
	)

	var fs_zone: PanelContainer = DropZoneScript.new()
	fs_zone.accepted_extensions    = FUNSCRIPT_EXTENSIONS.duplicate()
	fs_zone.picker_title           = "Select Funscript"
	fs_zone.picker_filters         = ["*.funscript,*.json ; Funscript Files", "*.* ; All Files"]
	fs_zone.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	hbox.add_child(fs_zone)
	if round_data.get("funscript_path", "") != "":
		fs_zone.call_deferred("set_file", round_data["funscript_path"])
	fs_zone.file_dropped.connect(func(path: String) -> void:
		arr[idx]["funscript_path"] = path
		if (arr[idx].get("name","") as String).strip_edges() == "":
			var auto: String = path.get_file().get_basename()
			arr[idx]["name"] = auto
			name_edit.text = auto
	)

	var coins_edit: LineEdit = LineEdit.new()
	coins_edit.text                = str(round_data.get("coins", 0))
	coins_edit.custom_minimum_size = Vector2(64, 0)
	coins_edit.max_length          = 6
	coins_edit.placeholder_text    = "0"
	UITheme.style_line_edit(coins_edit)
	coins_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["coins"] = val.to_int()
	)
	hbox.add_child(coins_edit)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.PURPLE_MID)
	up_btn.pressed.connect(func() -> void: _move_pi(arr, idx, -1))
	hbox.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == arr.size() - 1, UITheme.PURPLE_MID)
	dn_btn.pressed.connect(func() -> void: _move_pi(arr, idx, 1))
	hbox.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		arr.remove_at(idx)
		_refresh_items()
	)
	hbox.add_child(rm_btn)

	return panel


func _make_pi_shop_row(arr: Array, idx: int) -> Control:
	var shop_data: Dictionary = arr[idx]

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = Color(UITheme.PURPLE_BRIGHT.r, UITheme.PURPLE_BRIGHT.g, UITheme.PURPLE_BRIGHT.b, 0.06)
	ps.border_color        = UITheme.PURPLE_BRIGHT
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 8; ps.content_margin_right  = 8
	ps.content_margin_top  = 6; ps.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	panel.add_child(hbox)

	var shop_lbl: Label = Label.new()
	shop_lbl.text = "◆ SHOP"
	shop_lbl.add_theme_color_override("font_color", UITheme.PURPLE_BRIGHT)
	shop_lbl.add_theme_font_size_override("font_size", 12)
	shop_lbl.custom_minimum_size = Vector2(60, 0)
	hbox.add_child(shop_lbl)

	var title_edit: LineEdit = LineEdit.new()
	title_edit.placeholder_text     = "Shop title (optional)..."
	title_edit.text                  = shop_data.get("title", "")
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(title_edit)
	title_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["title"] = val
	)
	hbox.add_child(title_edit)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.PURPLE_MID)
	up_btn.pressed.connect(func() -> void: _move_pi(arr, idx, -1))
	hbox.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == arr.size() - 1, UITheme.PURPLE_MID)
	dn_btn.pressed.connect(func() -> void: _move_pi(arr, idx, 1))
	hbox.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		arr.remove_at(idx)
		_refresh_items()
	)
	hbox.add_child(rm_btn)

	return panel


func _make_storyboard_block(idx: int) -> Control:
	var item: Dictionary = _items[idx]

	var outer: PanelContainer = PanelContainer.new()
	var os: StyleBoxFlat = StyleBoxFlat.new()
	os.bg_color              = Color(UITheme.STORYBOARD.r, UITheme.STORYBOARD.g, UITheme.STORYBOARD.b, 0.06)
	os.border_color          = UITheme.STORYBOARD
	os.border_width_left     = 2; os.border_width_right  = 2
	os.border_width_top      = 2; os.border_width_bottom = 2
	os.content_margin_left   = 12; os.content_margin_right  = 12
	os.content_margin_top    = 10; os.content_margin_bottom = 10
	outer.add_theme_stylebox_override("panel", os)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	outer.add_child(col)

	# Header row
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ROW_SEP)
	col.add_child(hdr)

	var sb_lbl: Label = Label.new()
	sb_lbl.text = "◈ STORYBOARD"
	sb_lbl.add_theme_color_override("font_color", UITheme.STORYBOARD)
	sb_lbl.add_theme_font_size_override("font_size", 13)
	sb_lbl.custom_minimum_size = Vector2(130, 0)
	hdr.add_child(sb_lbl)

	var coins_lbl: Label = Label.new()
	coins_lbl.text = "COINS"
	coins_lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	coins_lbl.add_theme_font_size_override("font_size", 10)
	coins_lbl.uppercase = true
	hdr.add_child(coins_lbl)

	var coins_edit: LineEdit = LineEdit.new()
	coins_edit.text              = str(item.get("coins", 0))
	coins_edit.custom_minimum_size = Vector2(70, 0)
	coins_edit.max_length        = 6
	coins_edit.placeholder_text  = "0"
	UITheme.style_line_edit(coins_edit)
	coins_edit.text_changed.connect(func(val: String) -> void:
		_items[idx]["coins"] = val.to_int()
	)
	hdr.add_child(coins_edit)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.STORYBOARD)
	up_btn.pressed.connect(func() -> void: _move_item(idx, -1))
	hdr.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == _items.size() - 1, UITheme.STORYBOARD)
	dn_btn.pressed.connect(func() -> void: _move_item(idx, 1))
	hdr.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		_items.remove_at(idx)
		_refresh_items()
	)
	hdr.add_child(rm_btn)

	# Default image
	var img_lbl: Label = Label.new()
	img_lbl.text = "DEFAULT IMAGE"
	img_lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	img_lbl.add_theme_font_size_override("font_size", 10)
	img_lbl.uppercase = true
	col.add_child(img_lbl)

	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions   = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title          = "Select Default Image for Storyboard"
	img_zone.picker_filters        = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(img_zone)
	if item.get("image", "") != "":
		img_zone.call_deferred("set_file", item["image"])
	img_zone.file_dropped.connect(func(path: String) -> void:
		_items[idx]["image"] = path
	)

	# Lines
	var lines_col: VBoxContainer = VBoxContainer.new()
	lines_col.add_theme_constant_override("separation", 4)
	col.add_child(lines_col)

	var lines: Array = item.get("lines", [])
	for li in lines.size():
		lines_col.add_child(_make_storyboard_line_row(idx, li))

	var add_line_btn: Button = Button.new()
	add_line_btn.text = "+ ADD DIALOGUE LINE"
	add_line_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_line_btn, UITheme.STORYBOARD)
	add_line_btn.pressed.connect(func() -> void:
		_items[idx]["lines"].append({"speaker": "", "text": "", "image": ""})
		_refresh_items()
	)
	col.add_child(add_line_btn)

	return outer


func _make_storyboard_line_row(sb_idx: int, line_idx: int) -> Control:
	var line_data: Dictionary = _items[sb_idx]["lines"][line_idx]
	var lines_count: int = _items[sb_idx]["lines"].size()

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = UITheme.PANEL_BG
	ps.border_color        = Color(UITheme.STORYBOARD.r, UITheme.STORYBOARD.g, UITheme.STORYBOARD.b, 0.4)
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 8; ps.content_margin_right  = 8
	ps.content_margin_top  = 6; ps.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	panel.add_child(hbox)

	var num_lbl: Label = Label.new()
	num_lbl.text = "%d." % (line_idx + 1)
	num_lbl.custom_minimum_size = Vector2(24, 0)
	num_lbl.add_theme_color_override("font_color", UITheme.STORYBOARD)
	num_lbl.add_theme_font_size_override("font_size", 12)
	hbox.add_child(num_lbl)

	var speaker_edit: LineEdit = LineEdit.new()
	speaker_edit.placeholder_text     = "Speaker..."
	speaker_edit.text                  = line_data.get("speaker", "")
	speaker_edit.custom_minimum_size   = Vector2(120, 0)
	UITheme.style_line_edit(speaker_edit)
	speaker_edit.text_changed.connect(func(val: String) -> void:
		_items[sb_idx]["lines"][line_idx]["speaker"] = val
	)
	hbox.add_child(speaker_edit)

	var text_edit: TextEdit = TextEdit.new()
	text_edit.placeholder_text      = "Dialogue text..."
	text_edit.text                   = line_data.get("text", "")
	text_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	text_edit.custom_minimum_size    = Vector2(0, 72)
	text_edit.wrap_mode              = TextEdit.LINE_WRAPPING_BOUNDARY
	UITheme.style_text_edit(text_edit)
	text_edit.text_changed.connect(func() -> void:
		_items[sb_idx]["lines"][line_idx]["text"] = text_edit.text
	)
	hbox.add_child(text_edit)

	var img_col: VBoxContainer = VBoxContainer.new()
	img_col.add_theme_constant_override("separation", 2)
	img_col.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(img_col)

	var img_lbl: Label = Label.new()
	img_lbl.text = "SPEAKER IMAGE"
	img_lbl.add_theme_color_override("font_color", UITheme.SEPARATOR)
	img_lbl.add_theme_font_size_override("font_size", 9)
	img_lbl.uppercase = true
	img_col.add_child(img_lbl)

	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title        = "Select Speaker Image for Line %d" % (line_idx + 1)
	img_zone.picker_filters      = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_col.add_child(img_zone)
	if line_data.get("image", "") != "":
		img_zone.call_deferred("set_file", line_data["image"])
	img_zone.file_dropped.connect(func(path: String) -> void:
		_items[sb_idx]["lines"][line_idx]["image"] = path
	)

	var lines_arr: Array = _items[sb_idx]["lines"]
	var up_btn: Button = UITheme.make_icon_btn("↑", line_idx == 0, UITheme.STORYBOARD)
	up_btn.pressed.connect(func() -> void: _move_pi(lines_arr, line_idx, -1))
	hbox.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", line_idx == lines_count - 1, UITheme.STORYBOARD)
	dn_btn.pressed.connect(func() -> void: _move_pi(lines_arr, line_idx, 1))
	hbox.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		_items[sb_idx]["lines"].remove_at(line_idx)
		_refresh_items()
	)
	hbox.add_child(rm_btn)

	return panel


func _make_pi_storyboard_block(arr: Array, idx: int) -> Control:
	var sb_data: Dictionary = arr[idx]

	var outer: PanelContainer = PanelContainer.new()
	var os: StyleBoxFlat = StyleBoxFlat.new()
	os.bg_color              = Color(UITheme.STORYBOARD.r, UITheme.STORYBOARD.g, UITheme.STORYBOARD.b, 0.06)
	os.border_color          = UITheme.STORYBOARD
	os.border_width_left     = 1; os.border_width_right  = 1
	os.border_width_top      = 1; os.border_width_bottom = 1
	os.content_margin_left   = 8; os.content_margin_right  = 8
	os.content_margin_top    = 6; os.content_margin_bottom = 6
	outer.add_theme_stylebox_override("panel", os)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	outer.add_child(col)

	# Header
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ROW_SEP)
	col.add_child(hdr)

	var sb_lbl: Label = Label.new()
	sb_lbl.text = "◈ STORYBOARD"
	sb_lbl.add_theme_color_override("font_color", UITheme.STORYBOARD)
	sb_lbl.add_theme_font_size_override("font_size", 12)
	sb_lbl.custom_minimum_size = Vector2(110, 0)
	hdr.add_child(sb_lbl)

	var coins_edit: LineEdit = LineEdit.new()
	coins_edit.text                = str(sb_data.get("coins", 0))
	coins_edit.custom_minimum_size = Vector2(64, 0)
	coins_edit.max_length          = 6
	coins_edit.placeholder_text    = "0"
	UITheme.style_line_edit(coins_edit)
	coins_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["coins"] = val.to_int()
	)
	hdr.add_child(coins_edit)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.STORYBOARD)
	up_btn.pressed.connect(func() -> void: _move_pi(arr, idx, -1))
	hdr.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == arr.size() - 1, UITheme.STORYBOARD)
	dn_btn.pressed.connect(func() -> void: _move_pi(arr, idx, 1))
	hdr.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		arr.remove_at(idx)
		_refresh_items()
	)
	hdr.add_child(rm_btn)

	# Default image
	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions   = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title          = "Select Default Image"
	img_zone.picker_filters        = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(img_zone)
	if sb_data.get("image", "") != "":
		img_zone.call_deferred("set_file", sb_data["image"])
	img_zone.file_dropped.connect(func(path: String) -> void:
		arr[idx]["image"] = path
	)

	# Lines
	var lines_arr: Array = sb_data.get("lines", [])
	# Ensure the data dict has the lines array so the closure can mutate it.
	if not sb_data.has("lines"):
		arr[idx]["lines"] = lines_arr

	var lines_col: VBoxContainer = VBoxContainer.new()
	lines_col.add_theme_constant_override("separation", 3)
	col.add_child(lines_col)

	for li in lines_arr.size():
		lines_col.add_child(_make_pi_storyboard_line_row(lines_arr, li))

	var add_line_btn: Button = Button.new()
	add_line_btn.text = "+ ADD LINE"
	add_line_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_line_btn, UITheme.STORYBOARD)
	add_line_btn.pressed.connect(func() -> void:
		lines_arr.append({"speaker": "", "text": "", "image": ""})
		_refresh_items()
	)
	col.add_child(add_line_btn)

	return outer


func _make_pi_storyboard_line_row(lines_arr: Array, line_idx: int) -> Control:
	var line_data: Dictionary = lines_arr[line_idx]

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = UITheme.PANEL_BG
	ps.border_color        = Color(UITheme.STORYBOARD.r, UITheme.STORYBOARD.g, UITheme.STORYBOARD.b, 0.35)
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 6; ps.content_margin_right  = 6
	ps.content_margin_top  = 4; ps.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	panel.add_child(hbox)

	var num_lbl: Label = Label.new()
	num_lbl.text = "%d." % (line_idx + 1)
	num_lbl.custom_minimum_size = Vector2(20, 0)
	num_lbl.add_theme_color_override("font_color", UITheme.STORYBOARD)
	num_lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(num_lbl)

	var speaker_edit: LineEdit = LineEdit.new()
	speaker_edit.placeholder_text     = "Speaker..."
	speaker_edit.text                  = line_data.get("speaker", "")
	speaker_edit.custom_minimum_size   = Vector2(100, 0)
	UITheme.style_line_edit(speaker_edit)
	speaker_edit.text_changed.connect(func(val: String) -> void:
		lines_arr[line_idx]["speaker"] = val
	)
	hbox.add_child(speaker_edit)

	var text_edit: TextEdit = TextEdit.new()
	text_edit.placeholder_text      = "Dialogue text..."
	text_edit.text                   = line_data.get("text", "")
	text_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	text_edit.custom_minimum_size    = Vector2(0, 72)
	text_edit.wrap_mode              = TextEdit.LINE_WRAPPING_BOUNDARY
	UITheme.style_text_edit(text_edit)
	text_edit.text_changed.connect(func() -> void:
		lines_arr[line_idx]["text"] = text_edit.text
	)
	hbox.add_child(text_edit)

	var up_btn: Button = UITheme.make_icon_btn("↑", line_idx == 0, UITheme.STORYBOARD)
	up_btn.pressed.connect(func() -> void: _move_pi(lines_arr, line_idx, -1))
	hbox.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", line_idx == lines_arr.size() - 1, UITheme.STORYBOARD)
	dn_btn.pressed.connect(func() -> void: _move_pi(lines_arr, line_idx, 1))
	hbox.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		lines_arr.remove_at(line_idx)
		_refresh_items()
	)
	hbox.add_child(rm_btn)

	return panel


# Renders a nested fork inside a path. The fork's paths recurse back through
# _render_path_items for their own items.
func _make_pi_fork_block(arr: Array, idx: int) -> Control:
	var item: Dictionary = arr[idx]

	var outer: PanelContainer = PanelContainer.new()
	var os: StyleBoxFlat = StyleBoxFlat.new()
	os.bg_color              = Color(UITheme.MAGENTA.r, UITheme.MAGENTA.g, UITheme.MAGENTA.b, 0.06)
	os.border_color          = UITheme.MAGENTA
	os.border_width_left     = 2; os.border_width_right  = 2
	os.border_width_top      = 2; os.border_width_bottom = 2
	os.content_margin_left   = 10; os.content_margin_right  = 10
	os.content_margin_top    = 8;  os.content_margin_bottom = 8
	outer.add_theme_stylebox_override("panel", os)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	outer.add_child(col)

	# Header row
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ROW_SEP)
	col.add_child(hdr)

	var fork_lbl: Label = Label.new()
	fork_lbl.text = "⑂ NESTED FORK"
	fork_lbl.add_theme_color_override("font_color", UITheme.MAGENTA)
	fork_lbl.add_theme_font_size_override("font_size", 12)
	fork_lbl.custom_minimum_size = Vector2(110, 0)
	hdr.add_child(fork_lbl)

	var title_edit: LineEdit = LineEdit.new()
	title_edit.placeholder_text     = "Fork title (optional)..."
	title_edit.text                  = item.get("title", "")
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(title_edit)
	title_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["title"] = val
	)
	hdr.add_child(title_edit)

	var up_btn: Button = UITheme.make_icon_btn("↑", idx == 0, UITheme.MAGENTA)
	up_btn.pressed.connect(func() -> void: _move_pi(arr, idx, -1))
	hdr.add_child(up_btn)

	var dn_btn: Button = UITheme.make_icon_btn("↓", idx == arr.size() - 1, UITheme.MAGENTA)
	dn_btn.pressed.connect(func() -> void: _move_pi(arr, idx, 1))
	hdr.add_child(dn_btn)

	var rm_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		arr.remove_at(idx)
		_refresh_items()
	)
	hdr.add_child(rm_btn)

	# Description
	var desc_edit: LineEdit = LineEdit.new()
	desc_edit.placeholder_text     = "Fork description (optional)..."
	desc_edit.text                  = item.get("description", "")
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(desc_edit)
	desc_edit.text_changed.connect(func(val: String) -> void:
		arr[idx]["description"] = val
	)
	col.add_child(desc_edit)

	# Paths — reuse the existing path block by passing this nested fork's index.
	# Since _make_fork_path_block uses _items[fork_idx]["paths"][path_idx], we can't
	# reuse it directly for nested forks. We render paths inline here using a
	# small recursive helper.
	var paths_col: VBoxContainer = VBoxContainer.new()
	paths_col.add_theme_constant_override("separation", 6)
	col.add_child(paths_col)

	var paths_arr: Array = item.get("paths", [])
	# Ensure dict has the paths array so closures mutate it.
	if not item.has("paths"):
		arr[idx]["paths"] = paths_arr

	for pi in paths_arr.size():
		paths_col.add_child(_make_nested_path_block(paths_arr, pi))

	if paths_arr.size() < 4:
		var add_path_btn: Button = Button.new()
		add_path_btn.text = "+ ADD PATH"
		UITheme.style_button(add_path_btn, UITheme.PURPLE_MID)
		add_path_btn.pressed.connect(func() -> void:
			paths_arr.append({
				"name": "Path %s" % char(65 + paths_arr.size()),
				"description": "",
				"image_path": "",
				"items": [],
			})
			_refresh_items()
		)
		col.add_child(add_path_btn)

	return outer


# Renders a path block for a nested fork (paths_arr is the fork's "paths" array).
# Mirrors _make_fork_path_block but uses array references so it works at any depth.
func _make_nested_path_block(paths_arr: Array, path_idx: int) -> Control:
	var path_data: Dictionary = paths_arr[path_idx]

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = Color(UITheme.PURPLE_MID.r, UITheme.PURPLE_MID.g, UITheme.PURPLE_MID.b, 0.10)
	ps.border_color        = UITheme.PURPLE_MID
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 10; ps.content_margin_right  = 10
	ps.content_margin_top  = 8;  ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	# Path header
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ROW_SEP)
	col.add_child(hdr)

	var path_lbl: Label = Label.new()
	path_lbl.text = "PATH %d" % (path_idx + 1)
	path_lbl.add_theme_color_override("font_color", UITheme.PURPLE_BRIGHT)
	path_lbl.add_theme_font_size_override("font_size", 11)
	path_lbl.custom_minimum_size = Vector2(60, 0)
	hdr.add_child(path_lbl)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text     = "Path name..."
	name_edit.text                  = path_data.get("name", "")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void:
		paths_arr[path_idx]["name"] = val
	)
	hdr.add_child(name_edit)

	var desc_edit: LineEdit = LineEdit.new()
	desc_edit.placeholder_text     = "Description (optional)..."
	desc_edit.text                  = path_data.get("description", "")
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(desc_edit)
	desc_edit.text_changed.connect(func(val: String) -> void:
		paths_arr[path_idx]["description"] = val
	)
	hdr.add_child(desc_edit)

	if paths_arr.size() > 2:
		var rm_path_btn: Button = UITheme.make_icon_btn("✕", false, UITheme.MAGENTA)
		rm_path_btn.pressed.connect(func() -> void:
			paths_arr.remove_at(path_idx)
			_refresh_items()
		)
		hdr.add_child(rm_path_btn)

	# Card image
	var img_zone: PanelContainer = DropZoneScript.new()
	img_zone.accepted_extensions   = IMAGE_EXTENSIONS.duplicate()
	img_zone.picker_title          = "Select Card Image"
	img_zone.picker_filters        = ["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]
	img_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(img_zone)
	if path_data.get("image_path", "") != "":
		img_zone.call_deferred("set_file", path_data["image_path"])
	img_zone.file_dropped.connect(func(p: String) -> void:
		paths_arr[path_idx]["image_path"] = p
	)

	# Items list — recursive
	var items_list: VBoxContainer = VBoxContainer.new()
	items_list.add_theme_constant_override("separation", 4)
	col.add_child(items_list)

	var path_items: Array = path_data.get("items", [])
	if not path_data.has("items"):
		paths_arr[path_idx]["items"] = path_items

	_render_path_items(path_items, items_list)

	# Add buttons
	var add_btns_row: HBoxContainer = HBoxContainer.new()
	add_btns_row.add_theme_constant_override("separation", 8)
	col.add_child(add_btns_row)

	var add_round_btn: Button = Button.new()
	add_round_btn.text = "+ ROUND"
	add_round_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_round_btn, UITheme.PURPLE_MID)
	add_round_btn.pressed.connect(func() -> void:
		path_items.append({"type": "round", "name": "", "funscript_path": "", "video_path": "", "coins": 0})
		_refresh_items()
	)
	add_btns_row.add_child(add_round_btn)

	var add_shop_btn: Button = Button.new()
	add_shop_btn.text = "◆ SHOP"
	add_shop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_shop_btn, UITheme.PURPLE_BRIGHT)
	add_shop_btn.pressed.connect(func() -> void:
		path_items.append({"type": "shop", "title": ""})
		_refresh_items()
	)
	add_btns_row.add_child(add_shop_btn)

	var add_sb_btn: Button = Button.new()
	add_sb_btn.text = "◈ STORYBOARD"
	add_sb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_sb_btn, UITheme.STORYBOARD)
	add_sb_btn.pressed.connect(func() -> void:
		path_items.append({"type": "storyboard", "coins": 0, "image": "", "lines": []})
		_refresh_items()
	)
	add_btns_row.add_child(add_sb_btn)

	var add_fork_btn: Button = Button.new()
	add_fork_btn.text = "⑂ FORK"
	add_fork_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(add_fork_btn, UITheme.MAGENTA)
	add_fork_btn.pressed.connect(func() -> void:
		path_items.append({
			"type":        "fork",
			"title":       "",
			"description": "",
			"paths": [
				{"name": "Path A", "description": "", "image_path": "", "items": []},
				{"name": "Path B", "description": "", "image_path": "", "items": []},
			],
		})
		_refresh_items()
	)
	add_btns_row.add_child(add_fork_btn)

	return panel


func _move_item(idx: int, direction: int) -> void:
	var new_idx: int = idx + direction
	if new_idx < 0 or new_idx >= _items.size():
		return
	var tmp: Dictionary = _items[idx]
	_items[idx]         = _items[new_idx]
	_items[new_idx]     = tmp
	_refresh_items()


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func _show_status(msg: String, is_error: bool) -> void:
	_status_lbl.text = msg
	_status_lbl.add_theme_color_override("font_color", UITheme.ERROR_SOFT if is_error else UITheme.SUCCESS)
	_status_lbl.visible = true


func _on_save_pressed() -> void:
	_save_btn.disabled  = true
	_status_lbl.visible = false

	var journey_name: String = _journey_name.strip_edges()
	if journey_name == "":
		_show_status("Journey name is required.", true)
		_save_btn.disabled = false
		return

	var has_any_round: bool = _items.any(func(it: Dictionary) -> bool: return it.get("type","round") == "round")
	if not has_any_round:
		_show_status("Add at least one round before saving.", true)
		_save_btn.disabled = false
		return

	var round_count: int = 0
	for i in _items.size():
		var it: Dictionary = _items[i]
		var t: String = it.get("type", "round")
		if t == "round":
			round_count += 1
			if (it.get("name","") as String).strip_edges() == "":
				_show_status("Round %d needs a name." % round_count, true)
				_save_btn.disabled = false
				return
			if it.get("funscript_path","") == "":
				_show_status("Round %d needs a funscript file." % round_count, true)
				_save_btn.disabled = false
				return
		elif t == "shop" or t == "storyboard":
			# Shops and storyboards have no required fields for save.
			pass
		else:
			# Fork (top-level or nested via recursion).
			var err: String = _validate_fork(it, "fork after round %d" % round_count)
			if err != "":
				_show_status(err, true)
				_save_btn.disabled = false
				return

	# Walks items[] (and nested forks) looking for any round with a video.
	var any_video: bool = _items_have_any_video(_items)
	var ffmpeg_ok: bool = _ffmpeg_available() if any_video else false

	# Transcode plan only for main rounds (fork path rounds are copied as-is)
	var transcode_plan: Dictionary = {}
	var main_round_idx: int = 0
	if ffmpeg_ok:
		for i in _items.size():
			if _items[i].get("type","round") != "round":
				continue
			var vid: String = _items[i].get("video_path", "")
			if vid != "":
				var codec: String = _get_video_codec(vid)
				if codec != "" and not (codec in H264_NAMES):
					transcode_plan[i] = {"codec": codec, "duration": _video_duration_seconds(vid)}
			main_round_idx += 1

	if not transcode_plan.is_empty() and not ffmpeg_ok:
		_show_status("Videos need transcoding (non-H.264) but ffmpeg is not on PATH. Install ffmpeg and restart Godot.", true)
		_save_btn.disabled = false
		return

	var folder_name: String = _sanitize_folder_name(journey_name)
	var journey_dir: String = JOURNEYS_DIR + "/" + folder_name
	var abs_dir: String     = ProjectSettings.globalize_path(journey_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	if _cover_path != "":
		var ext: String = _cover_path.get_extension().to_lower()
		_copy_file(_cover_path, abs_dir + "/cover." + ext)

	var modal: Control = null
	if not transcode_plan.is_empty():
		modal = _create_transcode_modal()
		add_child(modal)

	var rounds_json:      Array = []
	var forks_json:       Array = []
	var shops_json:       Array = []
	var storyboards_json: Array = []
	var rorder: int = 0
	var last_rorder: int = 0
	var total_main_rounds: int = _items.count(func(it: Dictionary) -> bool: return it.get("type","round") == "round")

	for i in _items.size():
		var it: Dictionary = _items[i]
		var it_type: String = it.get("type","round")
		if it_type == "shop":
			shops_json.append({
				"AfterOrder": last_rorder,
				"Title":      it.get("title",""),
			})
			continue
		if it_type == "storyboard":
			rorder += 1
			last_rorder = rorder
			var sb_slug: String = "storyboard_%d" % rorder
			var sb_img_src: String = it.get("image", "")
			var sb_img_fname: String = ""
			if sb_img_src != "":
				var sb_ext: String = sb_img_src.get_extension().to_lower()
				sb_img_fname = sb_slug + "." + sb_ext
				_copy_file(sb_img_src, abs_dir + "/" + sb_img_fname)
			var sb_lines_json: Array = []
			for sb_li_idx in (it.get("lines", []) as Array).size():
				var sb_li: Dictionary = it["lines"][sb_li_idx]
				var li_img_src: String = sb_li.get("image", "")
				var li_img_fname: String = ""
				if li_img_src != "":
					var li_ext: String = li_img_src.get_extension().to_lower()
					li_img_fname = sb_slug + "_line_%d.%s" % [sb_li_idx, li_ext]
					_copy_file(li_img_src, abs_dir + "/" + li_img_fname)
				sb_lines_json.append({
					"Speaker": sb_li.get("speaker", ""),
					"Text":    sb_li.get("text",    ""),
					"Image":   li_img_fname,
				})
			storyboards_json.append({
				"Order":        rorder,
				"CoinsAwarded": it.get("coins", 0) as int,
				"Image":        sb_img_fname,
				"Lines":        sb_lines_json,
			})
			continue
		if it_type == "round":
			rorder += 1
			last_rorder = rorder

			var round_name: String = (it.get("name","") as String).strip_edges()
			var round_dir: String  = abs_dir + "/" + round_name
			DirAccess.make_dir_recursive_absolute(round_dir)

			var fs_src: String = it.get("funscript_path","")
			_copy_file(fs_src, round_dir + "/" + round_name + "." + fs_src.get_extension())

			var vid_src: String = it.get("video_path","")
			if vid_src != "":
				if i in transcode_plan:
					var info: Dictionary = transcode_plan[i]
					var vid_dst: String  = round_dir + "/" + vid_src.get_file().get_basename() + ".mp4"
					_update_modal_round(modal, rorder, total_main_rounds, round_name, info["codec"])
					var ok: bool = await _transcode_video(vid_src, vid_dst, info["duration"], modal)
					if not ok:
						if modal: modal.queue_free()
						_show_status("Transcoding cancelled. Journey not saved.", true)
						_save_btn.disabled = false
						return
				else:
					_copy_file(vid_src, round_dir + "/" + vid_src.get_file())

			rounds_json.append({
				"Name":         round_name,
				"Order":        rorder,
				"CoinsAwarded": it.get("coins",0) as int,
				"RoundType":    "Normal",
			})
		else:
			# Fork — recursively save the fork and all nested forks.
			var slug_prefix: String = "fork%d" % forks_json.size()
			forks_json.append(_save_fork(it, abs_dir, last_rorder, slug_prefix))

	if modal:
		modal.queue_free()

	var data: Dictionary = {
		"Name":        journey_name,
		"Author":      _journey_author.strip_edges(),
		"Description": _journey_desc.strip_edges(),
		"Difficulty":  DIFFICULTIES[_journey_difficulty_idx],
		"Rounds":      rounds_json,
		"Forks":       forks_json,
		"Shops":       shops_json,
		"Storyboards": storyboards_json,
	}

	var f: FileAccess = FileAccess.open(journey_dir + "/journey.json", FileAccess.WRITE)
	if f == null:
		_show_status("Failed to write journey.json — check folder permissions.", true)
		_save_btn.disabled = false
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	_show_status("Journey saved! Returning to catalogue...", false)
	await get_tree().create_timer(1.5).timeout
	Transition.change_scene("res://scenes/journey_select/JourneySelect.tscn")


# Recursively serializes a fork item to JSON. Calls _save_path for each path.
# `slug_prefix` makes nested-storyboard filenames unique across the journey.
func _save_fork(fork_item: Dictionary, abs_dir: String, after_order: int, slug_prefix: String) -> Dictionary:
	var fork_entry: Dictionary = {
		"AfterOrder":  after_order,
		"Title":       fork_item.get("title",""),
		"Description": fork_item.get("description",""),
		"Paths":       [],
	}
	for pi in (fork_item.get("paths", []) as Array).size():
		var path_data: Dictionary = fork_item["paths"][pi]
		var path_slug: String = "%s_p%d" % [slug_prefix, pi]
		fork_entry["Paths"].append(_save_path(path_data, abs_dir, path_slug))
	return fork_entry


# Recursively serializes a single fork path to JSON, splitting its items into
# Rounds, Shops, Storyboards, and (nested) Forks arrays.
func _save_path(path_data: Dictionary, abs_dir: String, slug_prefix: String) -> Dictionary:
	var img_src: String  = path_data.get("image_path", "")
	var img_fname: String = ""
	if img_src != "":
		var safe_name: String = _sanitize_folder_name(path_data.get("name", slug_prefix))
		img_fname = safe_name + "_cover." + img_src.get_extension().to_lower()
		_copy_file(img_src, abs_dir + "/" + img_fname)

	var path_entry: Dictionary = {
		"Name":        path_data.get("name", ""),
		"Description": path_data.get("description", ""),
		"Image":       img_fname,
		"Rounds":      [],
		"Shops":       [],
		"Storyboards": [],
		"Forks":       [],
	}

	var pr_order: int = 0
	var pr_last_order: int = 0
	var nested_fork_count: int = 0

	for pi_item: Dictionary in path_data.get("items", []):
		var pi_type: String = pi_item.get("type","round")
		match pi_type:
			"shop":
				path_entry["Shops"].append({
					"AfterOrder": pr_last_order,
					"Title":      pi_item.get("title",""),
				})
			"storyboard":
				pr_order += 1
				pr_last_order = pr_order
				var psb_slug: String = "%s_storyboard_%d" % [slug_prefix, pr_order]
				var psb_img_src: String = pi_item.get("image", "")
				var psb_img_fname: String = ""
				if psb_img_src != "":
					var psb_ext: String = psb_img_src.get_extension().to_lower()
					psb_img_fname = psb_slug + "." + psb_ext
					_copy_file(psb_img_src, abs_dir + "/" + psb_img_fname)
				var psb_lines_json: Array = []
				for psb_li_idx in (pi_item.get("lines",[]) as Array).size():
					var psb_li: Dictionary = pi_item["lines"][psb_li_idx]
					var psb_li_img_src: String = psb_li.get("image","")
					var psb_li_img_fname: String = ""
					if psb_li_img_src != "":
						var psb_li_ext: String = psb_li_img_src.get_extension().to_lower()
						psb_li_img_fname = psb_slug + "_line_%d.%s" % [psb_li_idx, psb_li_ext]
						_copy_file(psb_li_img_src, abs_dir + "/" + psb_li_img_fname)
					psb_lines_json.append({
						"Speaker": psb_li.get("speaker",""),
						"Text":    psb_li.get("text",""),
						"Image":   psb_li_img_fname,
					})
				path_entry["Storyboards"].append({
					"Order":        pr_order,
					"CoinsAwarded": pi_item.get("coins",0) as int,
					"Image":        psb_img_fname,
					"Lines":        psb_lines_json,
				})
			"fork":
				# Nested fork — recurse. Sort key uses pr_last_order so it lands
				# after the last round/storyboard authored before it in this path.
				var nested_slug: String = "%s_f%d" % [slug_prefix, nested_fork_count]
				nested_fork_count += 1
				path_entry["Forks"].append(_save_fork(pi_item, abs_dir, pr_last_order, nested_slug))
			_:
				# Round
				pr_order += 1
				pr_last_order = pr_order
				var pr_name: String = (pi_item.get("name","") as String).strip_edges()
				var pr_dir: String  = abs_dir + "/" + pr_name
				DirAccess.make_dir_recursive_absolute(pr_dir)
				var pr_fs: String = pi_item.get("funscript_path","")
				if pr_fs != "":
					_copy_file(pr_fs, pr_dir + "/" + pr_name + "." + pr_fs.get_extension())
				var pr_vid: String = pi_item.get("video_path","")
				if pr_vid != "":
					_copy_file(pr_vid, pr_dir + "/" + pr_vid.get_file())
				path_entry["Rounds"].append({
					"Name":         pr_name,
					"Order":        pr_order,
					"CoinsAwarded": pi_item.get("coins",0) as int,
				})

	return path_entry


# ---------------------------------------------------------------------------
# Transcoding
# ---------------------------------------------------------------------------

func _ffmpeg_binary(name: String) -> String:
	# Try bundled binary first (works in both editor and exported builds), then PATH.
	var exe: String = name + ".exe" if OS.get_name() == "Windows" else name
	var bundled: String = ProjectSettings.globalize_path("res://bin/" + exe)
	if FileAccess.file_exists(bundled):
		return bundled
	var next_to_app: String = OS.get_executable_path().get_base_dir() + "/bin/" + exe
	if FileAccess.file_exists(next_to_app):
		return next_to_app
	return name  # fall back to PATH lookup


func _ffmpeg_available() -> bool:
	var out: Array = []
	return OS.execute(_ffmpeg_binary("ffprobe"), ["-version"], out, true, false) == 0


func _get_video_codec(path: String) -> String:
	var out: Array = []
	var args: PackedStringArray = [
		"-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=codec_name",
		"-of", "csv=p=0",
		ProjectSettings.globalize_path(path),
	]
	if OS.execute(_ffmpeg_binary("ffprobe"), args, out, true, false) != 0 or out.is_empty():
		return ""
	return (out[0] as String).strip_edges().to_lower()


func _video_duration_seconds(path: String) -> float:
	var out: Array = []
	var args: PackedStringArray = [
		"-v", "error",
		"-show_entries", "format=duration",
		"-of", "csv=p=0",
		ProjectSettings.globalize_path(path),
	]
	if OS.execute(_ffmpeg_binary("ffprobe"), args, out, true, false) != 0 or out.is_empty():
		return 0.0
	return (out[0] as String).strip_edges().to_float()


func _transcode_video(input: String, output: String, duration: float, modal: Control) -> bool:
	_transcode_cancel = false

	var progress_abs: String = ProjectSettings.globalize_path(TRANSCODE_PROGRESS_FILE)
	# Truncate any prior progress file so old data doesn't mislead the parser.
	var pf: FileAccess = FileAccess.open(progress_abs, FileAccess.WRITE)
	if pf:
		pf.close()

	var args: PackedStringArray = [
		"-y",
		"-hide_banner",
		"-loglevel", "error",
		"-i", ProjectSettings.globalize_path(input),
		"-c:v", "libx264",
		"-preset", "fast",
		"-crf", "22",
		"-pix_fmt", "yuv420p",
		"-c:a", "aac",
		"-b:a", "192k",
		"-progress", progress_abs,
		ProjectSettings.globalize_path(output),
	]

	_transcode_pid = OS.create_process(_ffmpeg_binary("ffmpeg"), args)
	if _transcode_pid <= 0:
		return false

	while OS.is_process_running(_transcode_pid):
		if _transcode_cancel:
			OS.kill(_transcode_pid)
			_transcode_pid = -1
			return false
		_poll_progress(progress_abs, duration, modal)
		await get_tree().create_timer(0.4).timeout

	# Final poll to flush "progress=end".
	_poll_progress(progress_abs, duration, modal)
	_transcode_pid = -1
	return FileAccess.file_exists(output)


func _poll_progress(progress_path: String, duration: float, modal: Control) -> void:
	if modal == null:
		return
	var f: FileAccess = FileAccess.open(progress_path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var us: int = 0
	var speed: String = ""
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("out_time_us="):
			us = line.substr(12).to_int()
		elif line.begins_with("out_time_ms="):
			us = line.substr(12).to_int()
		elif line.begins_with("speed="):
			speed = line.substr(6)
	var current_s: float = us / 1_000_000.0
	var progress: float = 0.0
	if duration > 0.0:
		progress = clampf(current_s / duration, 0.0, 1.0)
	_update_modal_progress(modal, progress, current_s, duration, speed)


# ---------------------------------------------------------------------------
# Transcode modal UI
# ---------------------------------------------------------------------------

func _create_transcode_modal() -> Control:
	var modal: Control = Control.new()
	modal.name = "TranscodeModal"
	modal.anchor_right = 1.0
	modal.anchor_bottom = 1.0
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.85)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	modal.add_child(backdrop)

	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color            = UITheme.PANEL_BG
	ps.border_color        = UITheme.PURPLE_BRIGHT
	ps.border_width_left   = 2; ps.border_width_right  = 2
	ps.border_width_top    = 2; ps.border_width_bottom = 2
	ps.content_margin_left = 32; ps.content_margin_right  = 32
	ps.content_margin_top  = 24; ps.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5;  panel.anchor_bottom = 0.5
	panel.offset_left = -260; panel.offset_right = 260
	panel.offset_top = -120;  panel.offset_bottom = 120
	modal.add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "TRANSCODING VIDEO"
	UITheme.style_label(title, UITheme.PURPLE_BRIGHT, 16, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var round_lbl: Label = Label.new()
	round_lbl.name = "RoundLabel"
	round_lbl.text = ""
	UITheme.style_label(round_lbl, UITheme.WHITE_SOFT, 13, false)
	round_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(round_lbl)

	var bar: ProgressBar = ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var bar_bg: StyleBoxFlat = StyleBoxFlat.new()
	bar_bg.bg_color = UITheme.PURPLE_DARK
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill: StyleBoxFlat = StyleBoxFlat.new()
	bar_fill.bg_color = UITheme.PURPLE_BRIGHT
	bar.add_theme_stylebox_override("fill", bar_fill)
	vb.add_child(bar)

	var status_lbl: Label = Label.new()
	status_lbl.name = "Status"
	status_lbl.text = "Starting..."
	UITheme.style_label(status_lbl, UITheme.PURPLE_MID, 12, false)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(status_lbl)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(120, 0)
	UITheme.style_button(cancel_btn, UITheme.MAGENTA)
	cancel_btn.pressed.connect(func() -> void: _transcode_cancel = true)
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_child(cancel_btn)
	vb.add_child(btn_row)

	return modal


func _update_modal_round(modal: Control, round_num: int, total: int, round_name: String, codec: String) -> void:
	if modal == null:
		return
	var lbl: Label = modal.get_node("PanelContainer/VBoxContainer/RoundLabel") as Label
	if lbl == null:
		# Fallback: walk children since we didn't name the intermediate panel/vbox.
		lbl = modal.find_child("RoundLabel", true, false) as Label
	if lbl:
		lbl.text = "Round %d / %d — %s  (%s → h264)" % [round_num, total, round_name, codec.to_upper()]


func _update_modal_progress(modal: Control, progress: float, current_s: float, total_s: float, speed: String) -> void:
	if modal == null:
		return
	var bar: ProgressBar = modal.find_child("Bar", true, false) as ProgressBar
	if bar:
		bar.value = progress
	var status: Label = modal.find_child("Status", true, false) as Label
	if status:
		var pct: int = int(round(progress * 100.0))
		var cur: String = _format_time(current_s)
		var tot: String = _format_time(total_s) if total_s > 0.0 else "?"
		var spd: String = ("  •  " + speed) if speed != "" else ""
		status.text = "%s / %s  •  %d%%%s" % [cur, tot, pct, spd]


func _format_time(seconds: float) -> String:
	var s: int = int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


func _sanitize_folder_name(name: String) -> String:
	const INVALID: String = "\\/:*?\"<>|"
	var result: String = ""
	for ch: String in name:
		if ch in INVALID:
			continue
		result += "_" if ch == " " else ch
	return result if result != "" else "Journey"


func _copy_file(src: String, dst: String) -> void:
	var src_file: FileAccess = FileAccess.open(src, FileAccess.READ)
	if src_file == null:
		printerr("JourneyBuilder: cannot read: " + src)
		return
	var bytes: PackedByteArray = src_file.get_buffer(src_file.get_length())
	src_file.close()
	var dst_file: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if dst_file == null:
		printerr("JourneyBuilder: cannot write: " + dst)
		return
	dst_file.store_buffer(bytes)
	dst_file.close()
