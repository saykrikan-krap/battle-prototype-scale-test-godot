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

var _playing: bool = true

func _ready() -> void:
	var panel = PanelContainer.new()
	panel.position = Vector2(10, 10)
	add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

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

func set_resolving(resolving: bool) -> void:
	_resolve_button.disabled = resolving
	_step_button.disabled = resolving
	_speed_option.disabled = resolving
	_status_label.text = "Resolving..." if resolving else ""

func set_playing(playing: bool) -> void:
	_playing = playing
	_play_button.text = "Pause" if playing else "Play"

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
