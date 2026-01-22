class_name BattleUI
extends CanvasLayer

signal resolve_requested
signal play_toggled(playing: bool)
signal step_requested
signal speed_changed(ticks_per_second: int)
signal unit_details_closed

var _resolve_button: Button
var _play_button: Button
var _step_button: Button
var _speed_option: OptionButton
var _status_label: Label
var _debug_label: Label
var _panel: PanelContainer
var _start_overlay: PanelContainer
var _start_button: Button
var _spinner_label: Label
var _hover_panel: PanelContainer
var _hover_title: Label
var _hover_entries = []
var _unit_textures = []
var _details_backdrop: ColorRect
var _details_panel: PanelContainer
var _details_title: Label
var _details_icon: TextureRect
var _details_name: Label
var _details_stats: GridContainer
var _details_stat_values = []
var _details_prev: Button
var _details_next: Button
var _details_count: Label
var _details_close: Button
var _details_units: Array = []
var _details_tile: Vector2i = Vector2i(-1, -1)
var _details_index: int = 0

var _playing: bool = true
var _resolving: bool = false
var _spinner_frames = ["|", "/", "-", "\\"]
var _spinner_index: int = 0
var _spinner_elapsed: float = 0.0
var _spinner_interval: float = 0.12

const UNIT_TEXTURE_PATHS = [
	"res://assets/sprites/units/infantry.png",
	"res://assets/sprites/units/heavy_infantry.png",
	"res://assets/sprites/units/elite_infantry.png",
	"res://assets/sprites/units/archer.png",
	"res://assets/sprites/units/cavalry.png",
	"res://assets/sprites/units/heavy_cavalry.png",
	"res://assets/sprites/units/mage.png",
]

const UNIT_NAMES = [
	"Infantry",
	"Heavy Infantry",
	"Elite Infantry",
	"Archer",
	"Cavalry",
	"Heavy Cavalry",
	"Mage",
]

const DETAIL_STATS = [
	"Unit ID",
	"Side",
	"Size",
	"Move Cost",
	"Action Speed",
	"Range",
]

func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(10, 10)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	_panel.add_child(vbox)

	_resolve_button = Button.new()
	_resolve_button.text = "Resolve"
	_resolve_button.pressed.connect(_on_resolve_pressed)
	vbox.add_child(_resolve_button)

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	_play_button = Button.new()
	_play_button.text = "Pause"
	_play_button.pressed.connect(_on_play_pressed)
	hbox.add_child(_play_button)

	_step_button = Button.new()
	_step_button.text = "Step"
	_step_button.pressed.connect(_on_step_pressed)
	hbox.add_child(_step_button)

	_speed_option = OptionButton.new()
	_speed_option.add_item("10 tps", 10)
	_speed_option.add_item("20 tps", 20)
	_speed_option.add_item("40 tps", 40)
	_speed_option.select(1)
	_speed_option.item_selected.connect(_on_speed_selected)
	vbox.add_child(_speed_option)

	_status_label = Label.new()
	_status_label.text = ""
	vbox.add_child(_status_label)

	_debug_label = Label.new()
	_debug_label.position = Vector2(10, 140)
	_debug_label.text = ""
	add_child(_debug_label)

	_start_overlay = PanelContainer.new()
	_start_overlay.anchor_left = 0.5
	_start_overlay.anchor_top = 0.5
	_start_overlay.anchor_right = 0.5
	_start_overlay.anchor_bottom = 0.5
	_start_overlay.offset_left = -180
	_start_overlay.offset_top = -90
	_start_overlay.offset_right = 180
	_start_overlay.offset_bottom = 90
	add_child(_start_overlay)

	var overlay_box = VBoxContainer.new()
	overlay_box.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_box.add_theme_constant_override("separation", 10)
	_start_overlay.add_child(overlay_box)

	var title = Label.new()
	title.text = "Ready to Resolve"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(title)

	_start_button = Button.new()
	_start_button.text = "Start Resolution"
	_start_button.custom_minimum_size = Vector2(260, 50)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.pressed.connect(_on_resolve_pressed)
	overlay_box.add_child(_start_button)

	_spinner_label = Label.new()
	_spinner_label.text = ""
	_spinner_label.visible = false
	_spinner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(_spinner_label)

	set_start_overlay_visible(true)
	_build_hover_panel()
	_build_unit_details_modal()

func set_resolving(resolving: bool) -> void:
	_resolving = resolving
	_resolve_button.disabled = resolving
	_step_button.disabled = resolving
	_speed_option.disabled = resolving
	_start_button.disabled = resolving
	_status_label.text = "Resolving..." if resolving else ""
	_spinner_label.visible = resolving
	if resolving:
		_spinner_index = 0
		_spinner_elapsed = 0.0
		_spinner_label.text = "%s Resolving..." % _spinner_frames[_spinner_index]

func set_playing(playing: bool) -> void:
	_playing = playing
	_play_button.text = "Pause" if playing else "Play"

func set_start_overlay_visible(visible: bool) -> void:
	_start_overlay.visible = visible
	_panel.visible = not visible

func set_debug_text(text: String) -> void:
	_debug_label.text = text

func set_hovered_units(tile: Vector2i, unit_types: Array) -> void:
	_ensure_unit_textures()
	if tile.x < 0:
		_hover_title.text = "Hover a tile"
		_set_hover_entries([])
		return
	if unit_types.is_empty():
		_hover_title.text = "Tile %d,%d (empty)" % [tile.x, tile.y]
		_set_hover_entries([])
		return
	_hover_title.text = "Tile %d,%d" % [tile.x, tile.y]
	_set_hover_entries(unit_types)

func show_unit_details(tile: Vector2i, units: Array) -> void:
	_ensure_unit_textures()
	_details_tile = tile
	_details_units = units.duplicate()
	_details_index = 0
	_details_backdrop.visible = true
	_update_unit_details()

func hide_unit_details() -> void:
	if _details_backdrop == null or not _details_backdrop.visible:
		return
	_details_backdrop.visible = false
	emit_signal("unit_details_closed")

func is_unit_details_visible() -> bool:
	return _details_backdrop != null and _details_backdrop.visible

func _on_resolve_pressed() -> void:
	emit_signal("resolve_requested")

func _on_play_pressed() -> void:
	_playing = not _playing
	set_playing(_playing)
	emit_signal("play_toggled", _playing)

func _on_step_pressed() -> void:
	emit_signal("step_requested")

func _on_speed_selected(index: int) -> void:
	var tps = _speed_option.get_item_id(index)
	emit_signal("speed_changed", tps)

func _process(delta: float) -> void:
	if not _resolving:
		return
	_spinner_elapsed += delta
	if _spinner_elapsed < _spinner_interval:
		return
	_spinner_elapsed = 0.0
	_spinner_index = (_spinner_index + 1) % _spinner_frames.size()
	_spinner_label.text = "%s Resolving..." % _spinner_frames[_spinner_index]

func _build_hover_panel() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.anchor_left = 1.0
	_hover_panel.anchor_top = 1.0
	_hover_panel.anchor_right = 1.0
	_hover_panel.anchor_bottom = 1.0
	_hover_panel.offset_left = -300
	_hover_panel.offset_top = -200
	_hover_panel.offset_right = -10
	_hover_panel.offset_bottom = -10
	add_child(_hover_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_hover_panel.add_child(vbox)

	_hover_title = Label.new()
	_hover_title.text = "Hover a tile"
	vbox.add_child(_hover_title)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	for i in range(4):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		grid.add_child(row)

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

		var label = Label.new()
		label.text = ""
		row.add_child(label)

		_hover_entries.append({
			"row": row,
			"icon": icon,
			"label": label,
		})

func _build_unit_details_modal() -> void:
	_details_backdrop = ColorRect.new()
	_details_backdrop.anchor_left = 0.0
	_details_backdrop.anchor_top = 0.0
	_details_backdrop.anchor_right = 1.0
	_details_backdrop.anchor_bottom = 1.0
	_details_backdrop.offset_left = 0
	_details_backdrop.offset_top = 0
	_details_backdrop.offset_right = 0
	_details_backdrop.offset_bottom = 0
	_details_backdrop.color = Color(0, 0, 0, 0.45)
	_details_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_details_backdrop.visible = false
	add_child(_details_backdrop)

	_details_panel = PanelContainer.new()
	_details_panel.anchor_left = 0.5
	_details_panel.anchor_top = 0.5
	_details_panel.anchor_right = 0.5
	_details_panel.anchor_bottom = 0.5
	_details_panel.offset_left = -220
	_details_panel.offset_top = -170
	_details_panel.offset_right = 220
	_details_panel.offset_bottom = 170
	_details_backdrop.add_child(_details_panel)

	var panel_vbox = VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 12)
	_details_panel.add_child(panel_vbox)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	panel_vbox.add_child(header)

	_details_title = Label.new()
	_details_title.text = "Tile"
	_details_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_details_title)

	_details_close = Button.new()
	_details_close.text = "Close"
	_details_close.pressed.connect(_on_details_close)
	header.add_child(_details_close)

	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel_vbox.add_child(content)

	_details_icon = TextureRect.new()
	_details_icon.custom_minimum_size = Vector2(72, 72)
	_details_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_details_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(_details_icon)

	var details_vbox = VBoxContainer.new()
	details_vbox.add_theme_constant_override("separation", 6)
	details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(details_vbox)

	_details_name = Label.new()
	_details_name.text = ""
	details_vbox.add_child(_details_name)

	_details_stats = GridContainer.new()
	_details_stats.columns = 2
	_details_stats.add_theme_constant_override("h_separation", 12)
	_details_stats.add_theme_constant_override("v_separation", 6)
	details_vbox.add_child(_details_stats)

	for label_text in DETAIL_STATS:
		var key_label = Label.new()
		key_label.text = "%s:" % label_text
		_details_stats.add_child(key_label)

		var value_label = Label.new()
		value_label.text = ""
		_details_stats.add_child(value_label)
		_details_stat_values.append(value_label)

	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	panel_vbox.add_child(footer)

	_details_prev = Button.new()
	_details_prev.text = "Prev"
	_details_prev.pressed.connect(_on_details_prev)
	footer.add_child(_details_prev)

	_details_count = Label.new()
	_details_count.text = "0 units"
	_details_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_details_count)

	_details_next = Button.new()
	_details_next.text = "Next"
	_details_next.pressed.connect(_on_details_next)
	footer.add_child(_details_next)

func _ensure_unit_textures() -> void:
	if _unit_textures.size() > 0:
		return
	_unit_textures.resize(UNIT_TEXTURE_PATHS.size())
	for i in range(UNIT_TEXTURE_PATHS.size()):
		_unit_textures[i] = _load_texture(UNIT_TEXTURE_PATHS[i])

func _load_texture(path: String) -> Texture2D:
	var image = Image.new()
	var err = image.load(path)
	if err != OK:
		var fallback = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(0.2, 0.2, 0.2))
		return ImageTexture.create_from_image(fallback)
	return ImageTexture.create_from_image(image)

func _set_hover_entries(unit_types: Array) -> void:
	for i in range(_hover_entries.size()):
		var entry = _hover_entries[i]
		var row = entry["row"]
		if i < unit_types.size():
			var unit_type = int(unit_types[i])
			row.visible = true
			entry["icon"].texture = _unit_textures[unit_type]
			entry["label"].text = UNIT_NAMES[unit_type]
		else:
			row.visible = false

func _update_unit_details() -> void:
	if _details_backdrop == null:
		return
	if _details_tile.x >= 0:
		_details_title.text = "Tile %d,%d" % [_details_tile.x, _details_tile.y]
	else:
		_details_title.text = "Tile"

	if _details_units.is_empty():
		_details_name.text = "No units on this tile."
		_details_icon.visible = false
		_details_stats.visible = false
		_details_count.text = "0 units"
		_details_prev.disabled = true
		_details_next.disabled = true
		return

	_details_icon.visible = true
	_details_stats.visible = true

	if _details_index < 0:
		_details_index = 0
	if _details_index >= _details_units.size():
		_details_index = _details_units.size() - 1

	var unit = _details_units[_details_index]
	var unit_type = int(unit.get("unit_type", 0))
	_details_icon.texture = _unit_textures[unit_type]
	_details_name.text = UNIT_NAMES[unit_type]

	var side_value = int(unit.get("side", 0))
	var side_label = "Red" if side_value == 0 else "Blue"
	var range_value = int(unit.get("range", 0))
	var range_label = "Melee" if range_value <= 0 else str(range_value)

	var values = [
		str(unit.get("unit_id", 0)),
		side_label,
		str(unit.get("size", 0)),
		str(unit.get("move_cost", 0)),
		str(unit.get("attack_cost", 0)),
		range_label,
	]

	for i in range(_details_stat_values.size()):
		_details_stat_values[i].text = values[i]

	_details_count.text = "Unit %d of %d" % [_details_index + 1, _details_units.size()]
	var disable_nav = _details_units.size() <= 1
	_details_prev.disabled = disable_nav
	_details_next.disabled = disable_nav

func _on_details_prev() -> void:
	if _details_units.is_empty():
		return
	_details_index = (_details_index - 1 + _details_units.size()) % _details_units.size()
	_update_unit_details()

func _on_details_next() -> void:
	if _details_units.is_empty():
		return
	_details_index = (_details_index + 1) % _details_units.size()
	_update_unit_details()

func _on_details_close() -> void:
	hide_unit_details()
