class_name JourneyBuilder
extends Control

# ---------------------------------------------------------------------------
# JourneyBuilder.gd  –  Create and save custom journeys
# Users fill out journey metadata, add rounds by picking funscript + video
# files via OS file dialog or drag-and-drop. The folder structure is built
# automatically under user://journeys/ and all files are copied in.
# ---------------------------------------------------------------------------

const COLOR_BG:            Color = Color(0.0,   0.0,   0.0,   1.0)
const COLOR_PANEL_BG:      Color = Color(0.055, 0.008, 0.086, 1.0)
const COLOR_PURPLE_DARK:   Color = Color(0.176, 0.024, 0.259, 1.0)
const COLOR_PURPLE_MID:    Color = Color(0.408, 0.063, 0.627, 1.0)
const COLOR_PURPLE_BRIGHT: Color = Color(0.698, 0.118, 1.0,   1.0)
const COLOR_MAGENTA:       Color = Color(0.878, 0.0,   0.878, 1.0)
const COLOR_WHITE_SOFT:    Color = Color(0.878, 0.780, 1.0,   1.0)
const COLOR_SEPARATOR:     Color = Color(0.698, 0.118, 1.0,   0.5)
const COLOR_ERROR:         Color = Color(1.0,   0.3,   0.3,   1.0)
const COLOR_SUCCESS:       Color = Color(0.3,   1.0,   0.5,   1.0)

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

@onready var _bg:            ColorRect       = $Background
@onready var _top_bar:       HBoxContainer   = $TopBar
@onready var _back_btn:      Button          = $TopBar/BackButton
@onready var _title_lbl:     Label           = $TopBar/TitleLabel
@onready var _scroll:        ScrollContainer = $Scroll
@onready var _content:       VBoxContainer   = $Scroll/Content
@onready var _cover_border:  PanelContainer  = $Scroll/Content/InfoSection/InfoLayout/CoverColumn/CoverBorder
@onready var _cover_preview: TextureRect     = $Scroll/Content/InfoSection/InfoLayout/CoverColumn/CoverBorder/CoverPreview
@onready var _cover_btn:     Button          = $Scroll/Content/InfoSection/InfoLayout/CoverColumn/CoverButton
@onready var _name_field:    LineEdit        = $Scroll/Content/InfoSection/InfoLayout/FieldsColumn/NameRow/NameField
@onready var _author_field:  LineEdit        = $Scroll/Content/InfoSection/InfoLayout/FieldsColumn/AuthorRow/AuthorField
@onready var _diff_option:   OptionButton    = $Scroll/Content/InfoSection/InfoLayout/FieldsColumn/DiffRow/DiffOption
@onready var _desc_field:    TextEdit        = $Scroll/Content/InfoSection/InfoLayout/FieldsColumn/DescRow/DescField
@onready var _round_header:  HBoxContainer   = $Scroll/Content/RoundsSection/RoundListHeader
@onready var _round_list:    VBoxContainer   = $Scroll/Content/RoundsSection/RoundList
@onready var _add_round_btn: Button          = $Scroll/Content/RoundsSection/AddRoundButton
@onready var _status_lbl:    Label           = $Scroll/Content/BottomSection/StatusLabel
@onready var _save_btn:      Button          = $Scroll/Content/BottomSection/SaveButton

static var edit_journey: Dictionary = {}

var _cover_path: String = ""
var _rounds:     Array  = []  # Array[Dictionary] — {name, funscript_path, video_path, coins}

var _transcode_cancel: bool = false
var _transcode_pid:    int  = -1


func _ready() -> void:
	_apply_layout()
	_apply_theme()
	_connect_signals()
	_refresh_rounds()
	if not edit_journey.is_empty():
		_load_journey(edit_journey)
		edit_journey = {}


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
	_top_bar.offset_bottom = TOP_BAR_HEIGHT
	_top_bar.add_theme_constant_override("separation", 0)

	_scroll.anchor_right  = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_top    = TOP_BAR_HEIGHT + 16
	_scroll.offset_left   = CONTENT_PADDING
	_scroll.offset_right  = -CONTENT_PADDING
	_scroll.offset_bottom = -16
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_content.add_theme_constant_override("separation", 36)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var info_sec: VBoxContainer = $Scroll/Content/InfoSection
	info_sec.add_theme_constant_override("separation", 16)

	var info_layout: HBoxContainer = $Scroll/Content/InfoSection/InfoLayout
	info_layout.add_theme_constant_override("separation", 28)

	var cover_col: VBoxContainer = $Scroll/Content/InfoSection/InfoLayout/CoverColumn
	cover_col.add_theme_constant_override("separation", 8)
	cover_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_cover_border.custom_minimum_size = Vector2(COVER_WIDTH, COVER_HEIGHT)

	var fields_col: VBoxContainer = $Scroll/Content/InfoSection/InfoLayout/FieldsColumn
	fields_col.add_theme_constant_override("separation", 14)
	fields_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for row_path: String in [
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/NameRow",
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/AuthorRow",
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/DiffRow",
	]:
		(get_node(row_path) as HBoxContainer).add_theme_constant_override("separation", 12)

	for lbl_path: String in [
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/NameRow/NameLabel",
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/AuthorRow/AuthorLabel",
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/DiffRow/DiffLabel",
	]:
		(get_node(lbl_path) as Label).custom_minimum_size = Vector2(LABEL_WIDTH, 0)

	_name_field.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	_author_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_option.size_flags_horizontal  = Control.SIZE_EXPAND_FILL

	var desc_row: VBoxContainer = $Scroll/Content/InfoSection/InfoLayout/FieldsColumn/DescRow
	desc_row.add_theme_constant_override("separation", 6)
	desc_row.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	_desc_field.custom_minimum_size = Vector2(0, 90)
	_desc_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_field.wrap_mode           = TextEdit.LINE_WRAPPING_BOUNDARY

	var rounds_sec: VBoxContainer = $Scroll/Content/RoundsSection
	rounds_sec.add_theme_constant_override("separation", 8)
	_round_header.add_theme_constant_override("separation", ROW_SEP)
	_round_list.add_theme_constant_override("separation", 6)
	_round_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	(get_node("Scroll/Content/BottomSection") as VBoxContainer).add_theme_constant_override("separation", 12)


# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------

func _apply_theme() -> void:
	_bg.color = COLOR_BG

	_style_label(_title_lbl, COLOR_PURPLE_BRIGHT, 18, true)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER

	_style_button(_back_btn, COLOR_MAGENTA)

	for path: String in [
		"Scroll/Content/InfoSection/InfoHeader",
		"Scroll/Content/RoundsSection/RoundsHeader",
	]:
		_style_label(get_node(path), COLOR_SEPARATOR, 11, true)

	for path: String in [
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/NameRow/NameLabel",
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/AuthorRow/AuthorLabel",
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/DiffRow/DiffLabel",
		"Scroll/Content/InfoSection/InfoLayout/FieldsColumn/DescRow/DescLabel",
	]:
		_style_label(get_node(path), COLOR_PURPLE_MID, 12, true)

	var sep_style: StyleBoxFlat = StyleBoxFlat.new()
	sep_style.bg_color = COLOR_SEPARATOR
	for path: String in [
		"Scroll/Content/InfoSection/InfoDivider",
		"Scroll/Content/RoundsSection/RoundsDivider",
		"Scroll/Content/BottomSection/BottomDivider",
	]:
		(get_node(path) as HSeparator).add_theme_stylebox_override("separator", sep_style)

	var cb: StyleBoxFlat   = StyleBoxFlat.new()
	cb.bg_color            = COLOR_PURPLE_DARK
	cb.border_color        = COLOR_PURPLE_MID
	cb.border_width_left   = 2; cb.border_width_right = 2
	cb.border_width_top    = 2; cb.border_width_bottom = 2
	cb.content_margin_left = 0; cb.content_margin_right = 0
	cb.content_margin_top  = 0; cb.content_margin_bottom = 0
	_cover_border.add_theme_stylebox_override("panel", cb)

	_style_button(_cover_btn, COLOR_PURPLE_MID)
	_cover_btn.text = "DROP IMAGE OR CLICK TO BROWSE"

	_style_line_edit(_name_field)
	_name_field.placeholder_text = "Journey name..."
	_style_line_edit(_author_field)
	_author_field.placeholder_text = "Author name..."
	_style_option_button(_diff_option)
	for diff: String in DIFFICULTIES:
		_diff_option.add_item(diff)
	_style_text_edit(_desc_field)
	_desc_field.placeholder_text = "Optional description..."

	_build_round_header()

	_style_button(_add_round_btn, COLOR_PURPLE_MID)

	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.visible = false

	_style_button(_save_btn, COLOR_PURPLE_BRIGHT)
	_save_btn.custom_minimum_size = Vector2(240, 0)


func _build_round_header() -> void:
	for child in _round_header.get_children():
		child.queue_free()

	# Columns must match _make_round_row layout exactly
	# Order: [30px #] [expand NAME] [expand VIDEO] [expand FUNSCRIPT] [70px COINS] [96px buttons]
	var cols: Array = [
		["#",          30,   false],
		["ROUND NAME", -1,   false],
		["VIDEO FILE", -1,   false],
		["FUNSCRIPT",  -1,   false],
		["COINS",      70,   true ],
		["",           96,   false],  # spacer for ↑↓✕ buttons
	]
	for col: Array in cols:
		var lbl: Label = Label.new()
		lbl.text = col[0]
		lbl.uppercase = true
		lbl.add_theme_color_override("font_color", COLOR_SEPARATOR)
		lbl.add_theme_font_size_override("font_size", 10)
		if col[1] == -1:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			lbl.custom_minimum_size = Vector2(col[1], 0)
		if col[2]:
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_round_header.add_child(lbl)


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _style_label(label: Label, color: Color, size: int, uppercase: bool = false) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.uppercase = uppercase


func _style_button(btn: Button, accent: Color) -> void:
	btn.add_theme_color_override("font_color",         accent)
	btn.add_theme_color_override("font_hover_color",   COLOR_WHITE_SOFT)
	btn.add_theme_color_override("font_pressed_color", COLOR_BG)
	btn.add_theme_font_size_override("font_size", 14)
	btn.text = btn.text.to_upper()
	btn.add_theme_stylebox_override("normal",  _make_btn_style(accent, COLOR_PURPLE_DARK))
	btn.add_theme_stylebox_override("hover",   _make_btn_style(accent, COLOR_PURPLE_MID))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(accent, accent))
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())


func _make_btn_style(border: Color, fill: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat   = StyleBoxFlat.new()
	s.bg_color            = fill
	s.border_color        = border
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.content_margin_left = 16; s.content_margin_right  = 16
	s.content_margin_top  = 10; s.content_margin_bottom = 10
	return s


func _style_line_edit(le: LineEdit) -> void:
	le.add_theme_color_override("font_color",             COLOR_WHITE_SOFT)
	le.add_theme_color_override("font_placeholder_color", COLOR_PURPLE_MID)
	le.add_theme_color_override("caret_color",            COLOR_PURPLE_BRIGHT)
	le.add_theme_font_size_override("font_size", 14)
	var s: StyleBoxFlat   = StyleBoxFlat.new()
	s.bg_color            = COLOR_PURPLE_DARK
	s.border_color        = COLOR_PURPLE_MID
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.content_margin_left = 10; s.content_margin_right  = 10
	s.content_margin_top  = 8;  s.content_margin_bottom = 8
	le.add_theme_stylebox_override("normal", s)
	var sf: StyleBoxFlat = s.duplicate()
	sf.border_color = COLOR_PURPLE_BRIGHT
	le.add_theme_stylebox_override("focus", sf)


func _style_text_edit(te: TextEdit) -> void:
	te.add_theme_color_override("font_color",  COLOR_WHITE_SOFT)
	te.add_theme_color_override("caret_color", COLOR_PURPLE_BRIGHT)
	te.add_theme_font_size_override("font_size", 13)
	var s: StyleBoxFlat   = StyleBoxFlat.new()
	s.bg_color            = COLOR_PURPLE_DARK
	s.border_color        = COLOR_PURPLE_MID
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.content_margin_left = 10; s.content_margin_right  = 10
	s.content_margin_top  = 8;  s.content_margin_bottom = 8
	te.add_theme_stylebox_override("normal", s)
	var sf: StyleBoxFlat = s.duplicate()
	sf.border_color = COLOR_PURPLE_BRIGHT
	te.add_theme_stylebox_override("focus", sf)


func _style_option_button(ob: OptionButton) -> void:
	ob.add_theme_color_override("font_color",       COLOR_WHITE_SOFT)
	ob.add_theme_color_override("font_hover_color", COLOR_PURPLE_BRIGHT)
	ob.add_theme_font_size_override("font_size", 14)
	var s: StyleBoxFlat   = StyleBoxFlat.new()
	s.bg_color            = COLOR_PURPLE_DARK
	s.border_color        = COLOR_PURPLE_MID
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.content_margin_left = 10; s.content_margin_right  = 10
	s.content_margin_top  = 8;  s.content_margin_bottom = 8
	ob.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate()
	sh.border_color = COLOR_PURPLE_BRIGHT
	ob.add_theme_stylebox_override("hover",   sh)
	ob.add_theme_stylebox_override("pressed", sh)
	ob.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_cover_btn.pressed.connect(_on_cover_pressed)
	_add_round_btn.pressed.connect(_on_add_round_pressed)
	_save_btn.pressed.connect(_on_save_pressed)
	get_viewport().files_dropped.connect(_on_viewport_files_dropped)


func _on_back_pressed() -> void:
	Transition.change_scene("res://scenes/main/Main.tscn")


func _on_viewport_files_dropped(files: PackedStringArray) -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var cover_col: Control = $Scroll/Content/InfoSection/InfoLayout/CoverColumn
	if not cover_col.get_global_rect().has_point(mouse_pos):
		return
	for f: String in files:
		if f.get_extension().to_lower() in IMAGE_EXTENSIONS:
			_cover_path = f
			_update_cover_preview()
			return


func _on_add_round_pressed() -> void:
	_rounds.append({"name": "", "funscript_path": "", "video_path": "", "coins": 0})
	_refresh_rounds()


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


func _update_cover_preview() -> void:
	if _cover_path == "":
		_cover_preview.texture = null
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
		_cover_preview.texture = ImageTexture.create_from_image(img)
	_cover_btn.text = "DROP IMAGE OR CLICK TO CHANGE"


# ---------------------------------------------------------------------------
# Load existing journey for editing
# ---------------------------------------------------------------------------

func _load_journey(journey: Dictionary) -> void:
	_name_field.text   = journey.get("title", "")
	_author_field.text = journey.get("author", "")
	_desc_field.text   = journey.get("description", "")

	var diff: String  = journey.get("difficulty", "Easy")
	var diff_idx: int = DIFFICULTIES.find(diff)
	if diff_idx >= 0:
		_diff_option.selected = diff_idx

	var cover: String = journey.get("cover_path", "")
	if cover != "":
		_cover_path = cover
		_update_cover_preview()

	_rounds.clear()
	var rounds: Array = journey.get("rounds", []).duplicate()
	rounds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("order", 0) as int) < (b.get("order", 0) as int)
	)
	for r: Dictionary in rounds:
		_rounds.append({
			"name":           r.get("name", ""),
			"funscript_path": r.get("funscript_path", ""),
			"video_path":     _find_video_in_round(r.get("folder", "")),
			"coins":          r.get("coins", 0),
		})
	_refresh_rounds()


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

func _refresh_rounds() -> void:
	for child in _round_list.get_children():
		child.queue_free()
	for i in _rounds.size():
		_round_list.add_child(_make_round_row(i))


func _make_round_row(idx: int) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat      = StyleBoxFlat.new()
	ps.bg_color            = COLOR_PANEL_BG
	ps.border_color        = COLOR_PURPLE_DARK
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.content_margin_left = 10; ps.content_margin_right  = 10
	ps.content_margin_top  = 8;  ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	panel.add_child(hbox)

	# Order number — fixed 30px, matches header "#"
	var order_lbl: Label = Label.new()
	order_lbl.text = "%02d." % (idx + 1)
	order_lbl.custom_minimum_size = Vector2(30, 0)
	order_lbl.add_theme_color_override("font_color", COLOR_PURPLE_MID)
	order_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(order_lbl)

	# Round name — expands, matches header "ROUND NAME"
	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text      = "Round name..."
	name_edit.text                   = _rounds[idx].get("name", "")
	name_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_style_line_edit(name_edit)
	name_edit.text_changed.connect(func(val: String) -> void:
		_rounds[idx]["name"] = val
	)
	hbox.add_child(name_edit)

	# Video drop zone — expands, matches header "VIDEO FILE"
	var video_zone: PanelContainer = DropZoneScript.new()
	video_zone.accepted_extensions = VIDEO_EXTENSIONS.duplicate()
	video_zone.picker_title        = "Select Video for Round %d" % (idx + 1)
	video_zone.picker_filters      = ["*.mp4,*.m4v,*.mkv,*.avi,*.mov,*.wmv,*.webm ; Video Files", "*.* ; All Files"]
	video_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(video_zone)
	if _rounds[idx].get("video_path", "") != "":
		video_zone.call_deferred("set_file", _rounds[idx]["video_path"])
	video_zone.file_dropped.connect(func(path: String) -> void:
		_rounds[idx]["video_path"] = path
		if (_rounds[idx].get("name", "") as String).strip_edges() == "":
			var auto: String = path.get_file().get_basename()
			_rounds[idx]["name"] = auto
			name_edit.text = auto
	)

	# Funscript drop zone — expands, matches header "FUNSCRIPT"
	var fs_zone: PanelContainer = DropZoneScript.new()
	fs_zone.accepted_extensions  = FUNSCRIPT_EXTENSIONS.duplicate()
	fs_zone.picker_title         = "Select Funscript for Round %d" % (idx + 1)
	fs_zone.picker_filters       = ["*.funscript,*.json ; Funscript Files", "*.* ; All Files"]
	fs_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(fs_zone)
	if _rounds[idx].get("funscript_path", "") != "":
		fs_zone.call_deferred("set_file", _rounds[idx]["funscript_path"])
	fs_zone.file_dropped.connect(func(path: String) -> void:
		_rounds[idx]["funscript_path"] = path
		if (_rounds[idx].get("name", "") as String).strip_edges() == "":
			var auto: String = path.get_file().get_basename()
			_rounds[idx]["name"] = auto
			name_edit.text = auto
	)

	# Coins — fixed 70px, matches header "COINS"
	var coins_edit: LineEdit = LineEdit.new()
	coins_edit.text              = str(_rounds[idx].get("coins", 0))
	coins_edit.custom_minimum_size = Vector2(70, 0)
	coins_edit.max_length        = 6
	coins_edit.placeholder_text  = "0"
	_style_line_edit(coins_edit)
	coins_edit.text_changed.connect(func(val: String) -> void:
		_rounds[idx]["coins"] = val.to_int()
	)
	hbox.add_child(coins_edit)

	# Action buttons — 3 × 32px = 96px total, matches header spacer
	var up_btn: Button = _make_icon_btn("↑", idx == 0, COLOR_PURPLE_MID)
	up_btn.pressed.connect(func() -> void: _move_round(idx, -1))
	hbox.add_child(up_btn)

	var dn_btn: Button = _make_icon_btn("↓", idx == _rounds.size() - 1, COLOR_PURPLE_MID)
	dn_btn.pressed.connect(func() -> void: _move_round(idx, 1))
	hbox.add_child(dn_btn)

	var rm_btn: Button = _make_icon_btn("✕", false, COLOR_MAGENTA)
	rm_btn.pressed.connect(func() -> void:
		_rounds.remove_at(idx)
		_refresh_rounds()
	)
	hbox.add_child(rm_btn)

	return panel


func _make_icon_btn(icon: String, disabled: bool, accent: Color) -> Button:
	var btn: Button = Button.new()
	btn.text = icon
	btn.custom_minimum_size = Vector2(32, 0)
	btn.disabled = disabled
	btn.add_theme_color_override("font_color",         accent)
	btn.add_theme_color_override("font_hover_color",   COLOR_WHITE_SOFT)
	btn.add_theme_color_override("font_pressed_color", COLOR_BG)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_stylebox_override("normal",  _make_btn_style(accent, COLOR_PURPLE_DARK))
	btn.add_theme_stylebox_override("hover",   _make_btn_style(accent, COLOR_PURPLE_MID))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(accent, accent))
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
	return btn


func _move_round(idx: int, direction: int) -> void:
	var new_idx: int = idx + direction
	if new_idx < 0 or new_idx >= _rounds.size():
		return
	var tmp: Dictionary  = _rounds[idx]
	_rounds[idx]         = _rounds[new_idx]
	_rounds[new_idx]     = tmp
	_refresh_rounds()


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func _show_status(msg: String, is_error: bool) -> void:
	_status_lbl.text = msg
	_status_lbl.add_theme_color_override("font_color", COLOR_ERROR if is_error else COLOR_SUCCESS)
	_status_lbl.visible = true


func _on_save_pressed() -> void:
	_save_btn.disabled  = true
	_status_lbl.visible = false

	var journey_name: String = _name_field.text.strip_edges()
	if journey_name == "":
		_show_status("Journey name is required.", true)
		_save_btn.disabled = false
		return
	if _rounds.is_empty():
		_show_status("Add at least one round before saving.", true)
		_save_btn.disabled = false
		return
	for i in _rounds.size():
		var r: Dictionary = _rounds[i]
		if (r.get("name", "") as String).strip_edges() == "":
			_show_status("Round %d needs a name." % (i + 1), true)
			_save_btn.disabled = false
			return
		if r.get("funscript_path", "") == "":
			_show_status("Round %d needs a funscript file." % (i + 1), true)
			_save_btn.disabled = false
			return

	# Check ffmpeg availability up-front if any round has a video, so we don't
	# spew ERR_CANT_FORK from ffprobe before we've had a chance to error cleanly.
	var any_video: bool = false
	for r: Dictionary in _rounds:
		if r.get("video_path", "") != "":
			any_video = true
			break

	var ffmpeg_ok: bool = _ffmpeg_available() if any_video else false

	# Pre-scan: identify which videos need transcoding to H.264.
	var transcode_plan: Dictionary = {}  # round_idx -> { codec: String, duration: float }
	if ffmpeg_ok:
		for i in _rounds.size():
			var vid: String = _rounds[i].get("video_path", "")
			if vid == "":
				continue
			var codec: String = _get_video_codec(vid)
			if codec == "" or codec in H264_NAMES:
				continue
			transcode_plan[i] = {
				"codec":    codec,
				"duration": _video_duration_seconds(vid),
			}

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

	var rounds_json: Array = []
	for i in _rounds.size():
		var r: Dictionary    = _rounds[i]
		var round_name: String = (r.get("name", "") as String).strip_edges()
		var round_dir: String  = abs_dir + "/" + round_name
		DirAccess.make_dir_recursive_absolute(round_dir)

		var fs_src: String = r.get("funscript_path", "")
		var fs_ext: String = fs_src.get_extension()
		_copy_file(fs_src, round_dir + "/" + round_name + "." + fs_ext)

		var vid_src: String = r.get("video_path", "")
		if vid_src != "":
			if i in transcode_plan:
				var info: Dictionary = transcode_plan[i]
				var vid_dst: String  = round_dir + "/" + vid_src.get_file().get_basename() + ".mp4"
				_update_modal_round(modal, i + 1, _rounds.size(), round_name, info["codec"])
				var ok: bool = await _transcode_video(vid_src, vid_dst, info["duration"], modal)
				if not ok:
					if modal:
						modal.queue_free()
					_show_status("Transcoding cancelled. Journey not saved.", true)
					_save_btn.disabled = false
					return
			else:
				_copy_file(vid_src, round_dir + "/" + vid_src.get_file())

		rounds_json.append({
			"Name":         round_name,
			"Order":        i + 1,
			"CoinsAwarded": r.get("coins", 0) as int,
			"RoundType":    "Normal",
		})

	if modal:
		modal.queue_free()

	var data: Dictionary = {
		"Name":        journey_name,
		"Author":      _author_field.text.strip_edges(),
		"Description": _desc_field.text.strip_edges(),
		"Difficulty":  DIFFICULTIES[_diff_option.selected],
		"Rounds":      rounds_json,
		"Shops":       [],
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
	ps.bg_color            = COLOR_PANEL_BG
	ps.border_color        = COLOR_PURPLE_BRIGHT
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
	_style_label(title, COLOR_PURPLE_BRIGHT, 16, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var round_lbl: Label = Label.new()
	round_lbl.name = "RoundLabel"
	round_lbl.text = ""
	_style_label(round_lbl, COLOR_WHITE_SOFT, 13, false)
	round_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(round_lbl)

	var bar: ProgressBar = ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var bar_bg: StyleBoxFlat = StyleBoxFlat.new()
	bar_bg.bg_color = COLOR_PURPLE_DARK
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill: StyleBoxFlat = StyleBoxFlat.new()
	bar_fill.bg_color = COLOR_PURPLE_BRIGHT
	bar.add_theme_stylebox_override("fill", bar_fill)
	vb.add_child(bar)

	var status_lbl: Label = Label.new()
	status_lbl.name = "Status"
	status_lbl.text = "Starting..."
	_style_label(status_lbl, COLOR_PURPLE_MID, 12, false)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(status_lbl)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(120, 0)
	_style_button(cancel_btn, COLOR_MAGENTA)
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
