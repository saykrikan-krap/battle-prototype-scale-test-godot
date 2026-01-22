class_name BattleUI
extends CanvasLayer

signal resolve_requested
signal play_toggled(playing: bool)
signal step_requested
signal speed_changed(ticks_per_second: int)

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

var _playing: bool = true
var _resolving: bool = false
var _spinner_frames = ["|", "/", "-", "\\"]
var _spinner_index: int = 0
var _spinner_elapsed: float = 0.0
var _spinner_interval: float = 0.12

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
