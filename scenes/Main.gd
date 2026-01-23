extends Node2D

const BattleConstants = preload("res://schema/constants.gd")
const BattleResolver = preload("res://resolver/battle_resolver.gd")
const BattleReplayer = preload("res://replayer/battle_replayer.gd")
const BattleView = preload("res://replayer/battle_view.gd")
const BattleUI = preload("res://ui/battle_ui.gd")
const ScaleTestV1 = preload("res://scenarios/scale_test_v1.gd")
const EventLog = preload("res://schema/event_log.gd")

const DEFAULT_TPS = 20

var _battle_view
var _battle_ui
var _replayer
var _resolver_thread: Thread
var _resolving: bool = false
var _last_result
var _last_event_log
var _current_tps: int = DEFAULT_TPS
var _allow_play_toggle: bool = false
var _resume_playing_after_modal: bool = false
var _custom_mode: bool = false
var _setup_input
var _placing_side: int = BattleConstants.Side.RED
var _placing_unit_type: int = -1
var _next_unit_id: int = 0
var _next_squad_id: int = 0
var _setup_tile_unit_count = PackedInt32Array()

func _ready() -> void:
	var args = OS.get_cmdline_args()
	if "--resolve-only" in args:
		_run_headless_resolve()
		return

	_battle_view = BattleView.new()
	add_child(_battle_view)

	_battle_ui = BattleUI.new()
	add_child(_battle_ui)
	_battle_ui.resolve_requested.connect(_start_resolve)
	_battle_ui.play_toggled.connect(_on_play_toggled)
	_battle_ui.step_requested.connect(_on_step_requested)
	_battle_ui.speed_changed.connect(_on_speed_changed)
	_battle_ui.unit_details_closed.connect(_on_unit_details_closed)
	_battle_ui.custom_mode_toggled.connect(_on_custom_mode_toggled)
	_battle_ui.placement_side_changed.connect(_on_placement_side_changed)
	_battle_ui.placement_unit_selected.connect(_on_placement_unit_selected)
	_battle_ui.placement_canceled.connect(_on_placement_canceled)

	var input = ScaleTestV1.build()
	_show_preview(input)
	_battle_ui.set_start_overlay_visible(true)
	_battle_ui.set_resolving(false)
	_allow_play_toggle = false

func _process(delta: float) -> void:
	if _resolving and _resolver_thread != null and not _resolver_thread.is_alive():
		var result = _resolver_thread.wait_to_finish()
		_resolving = false
		_battle_ui.set_resolving(false)
		_on_resolve_complete(result)

	if _replayer != null:
		if not _resolving:
			_replayer.update(delta)
		_battle_view.render(_replayer)
		_update_hover_panel()
	if _battle_view != null:
		if _custom_mode and not _resolving:
			_update_ghost_preview()
		else:
			_battle_view.set_ghost_units([], true)

	_update_debug_overlay()

func _start_resolve() -> void:
	if _resolving:
		return
	_resolving = true
	_battle_ui.set_resolving(true)
	_battle_ui.set_start_overlay_visible(true)
	_battle_ui.set_playing(false)
	_last_event_log = null
	_last_result = null
	if _custom_mode:
		_battle_ui.clear_placement_selection()

	_resolver_thread = Thread.new()
	_resolver_thread.start(Callable(self, "_resolve_task"))

func _resolve_task() -> Dictionary:
	var input = ScaleTestV1.build()
	if _custom_mode and _setup_input != null:
		input = _setup_input
	return BattleResolver.resolve(input)

func _on_resolve_complete(result: Dictionary) -> void:
	_last_event_log = result.get("event_log", null)
	_last_result = result.get("result", null)
	if _last_event_log == null:
		return
	_replayer = BattleReplayer.new()
	_replayer.initialize_from_log(_last_event_log)
	_replayer.set_ticks_per_second(_current_tps)
	_replayer.set_playing(true)
	_battle_ui.set_playing(true)
	_battle_ui.set_start_overlay_visible(false)
	_allow_play_toggle = true

func _input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _battle_ui != null and _battle_ui.is_unit_details_visible():
			return
		if event.keycode == KEY_SPACE and _allow_play_toggle:
			_on_play_toggled(not _replayer.playing)

func _unhandled_input(event) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if _custom_mode and _placing_unit_type != -1 and _battle_ui != null:
				_battle_ui.clear_placement_selection()
				return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if _custom_mode and _placing_unit_type != -1 and _is_setup_active():
			if _try_place_squad():
				return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _resolving or _battle_view == null or _battle_ui == null or _replayer == null:
			return
		if _battle_ui.is_unit_details_visible():
			return
		var tile = _battle_view.get_hovered_tile()
		if tile.x < 0:
			return
		var units = _collect_units_on_tile(tile)
		if units.is_empty():
			return
		_open_unit_details(tile, units)

func _on_play_toggled(playing: bool) -> void:
	if _replayer == null:
		return
	_replayer.set_playing(playing)

func _on_step_requested() -> void:
	if _replayer == null:
		return
	_replayer.step_tick()

func _on_speed_changed(tps: int) -> void:
	_current_tps = tps
	if _replayer != null:
		_replayer.set_ticks_per_second(tps)

func _on_custom_mode_toggled(enabled: bool) -> void:
	_custom_mode = enabled
	_placing_unit_type = -1
	if _battle_view != null:
		_battle_view.set_ghost_units([], true)
	if not enabled:
		var input = ScaleTestV1.build()
		_show_preview(input)
		_allow_play_toggle = false
		return

	if _setup_input == null:
		_setup_input = ScaleTestV1.build_empty()
	_next_unit_id = _setup_input.unit_ids.size()
	_next_squad_id = _setup_input.squad_ids.size()
	_rebuild_setup_occupancy()
	_show_preview(_setup_input)
	_allow_play_toggle = false

func _on_placement_side_changed(side: int) -> void:
	_placing_side = side

func _on_placement_unit_selected(unit_type: int) -> void:
	_placing_unit_type = unit_type

func _on_placement_canceled() -> void:
	_placing_unit_type = -1
	if _battle_view != null:
		_battle_view.set_ghost_units([], true)

func _open_unit_details(tile: Vector2i, units: Array) -> void:
	if _battle_ui == null:
		return
	_resume_playing_after_modal = false
	if _allow_play_toggle and _replayer != null and _replayer.playing:
		_resume_playing_after_modal = true
		_replayer.set_playing(false)
		_battle_ui.set_playing(false)
	_battle_ui.show_unit_details(tile, units)

func _on_unit_details_closed() -> void:
	if _resume_playing_after_modal and _replayer != null:
		_replayer.set_playing(true)
		_battle_ui.set_playing(true)
	_resume_playing_after_modal = false

func _update_debug_overlay() -> void:
	if _battle_ui == null:
		return
	var lines = []
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	if _replayer != null:
		lines.append("Tick: %d" % _replayer.current_tick)
		lines.append("Alive: R %d / B %d" % [_replayer.units_remaining[BattleConstants.Side.RED], _replayer.units_remaining[BattleConstants.Side.BLUE]])
	if _last_event_log != null:
		lines.append("Events: %d" % _last_event_log.count())
	if _last_result != null:
		lines.append("Resolve: %d ms (%.1f tps)" % [_last_result.resolve_ms, _last_result.avg_ticks_per_sec])
		lines.append("Log hash: %08x" % _last_result.event_hash)
		lines.append("Winner: %s" % _winner_name(_last_result.winner))
	if _resolving:
		lines.append("Resolving...")
	_battle_ui.set_debug_text("\n".join(lines))

func _winner_name(winner: int) -> String:
	if winner == BattleConstants.Side.RED:
		return "Red"
	if winner == BattleConstants.Side.BLUE:
		return "Blue"
	return "Draw"

func _run_headless_resolve() -> void:
	var input = ScaleTestV1.build()
	var result = BattleResolver.resolve(input)
	var battle_result = result.get("result", null)
	if battle_result != null:
		print("Resolved ticks: %d" % battle_result.ticks_elapsed)
		print("Winner: %s" % _winner_name(battle_result.winner))
		print("Units remaining: R %d / B %d" % [battle_result.units_remaining_by_side[BattleConstants.Side.RED], battle_result.units_remaining_by_side[BattleConstants.Side.BLUE]])
		print("Resolve ms: %d" % battle_result.resolve_ms)
		print("Avg ticks/sec: %.2f" % battle_result.avg_ticks_per_sec)
		print("Event count: %d" % battle_result.event_count)
		print("Event hash: %08x" % battle_result.event_hash)
	get_tree().quit()

func _update_hover_panel() -> void:
	if _battle_ui == null or _battle_view == null or _replayer == null:
		return
	var tile = _battle_view.get_hovered_tile()
	var unit_types = []
	if tile.x >= 0:
		var unit_count = _replayer.unit_alive.size()
		for id in range(unit_count):
			if _replayer.unit_alive[id] == 0:
				continue
			if _replayer.unit_x[id] == tile.x and _replayer.unit_y[id] == tile.y:
				unit_types.append(_replayer.unit_type[id])
	_battle_ui.set_hovered_units(tile, unit_types)

func _collect_units_on_tile(tile: Vector2i) -> Array:
	var units = []
	if _replayer == null:
		return units
	var unit_count = _replayer.unit_alive.size()
	for id in range(unit_count):
		if _replayer.unit_alive[id] == 0:
			continue
		if _replayer.unit_x[id] == tile.x and _replayer.unit_y[id] == tile.y:
			var u_type = _replayer.unit_type[id]
			units.append({
				"unit_id": id,
				"unit_type": u_type,
				"side": _replayer.unit_side[id],
				"size": BattleConstants.UNIT_SIZE[u_type],
				"move_cost": BattleConstants.MOVE_COST[u_type],
				"attack_cost": BattleConstants.ATTACK_COST[u_type],
				"range": BattleConstants.RANGED_RANGE[u_type],
			})
	return units

func _show_preview(input) -> void:
	var log = EventLog.new()
	log.add_event(
		0,
		0,
		BattleConstants.EventType.BATTLE_INIT,
		input.grid_width,
		input.grid_height,
		input.time_limit_ticks,
		input.unit_count()
	)
	for i in range(input.unit_count()):
		var unit_id = input.unit_ids[i]
		log.add_event(
			0,
			unit_id,
			BattleConstants.EventType.UNIT_SPAWNED,
			unit_id,
			input.unit_sides[i],
			input.unit_types[i],
			BattleConstants.encode_pos(input.unit_x[i], input.unit_y[i])
		)
	_replayer = BattleReplayer.new()
	_replayer.initialize_from_log(log)
	_replayer.set_ticks_per_second(_current_tps)
	_replayer.set_playing(false)

func _is_setup_active() -> bool:
	return not _allow_play_toggle and not _resolving

func _rebuild_setup_occupancy() -> void:
	if _setup_input == null:
		return
	var tile_count = _setup_input.grid_width * _setup_input.grid_height
	_setup_tile_unit_count.resize(tile_count)
	for i in range(tile_count):
		_setup_tile_unit_count[i] = 0
	for i in range(_setup_input.unit_x.size()):
		var ux = _setup_input.unit_x[i]
		var uy = _setup_input.unit_y[i]
		if ux < 0 or uy < 0:
			continue
		var tile = BattleConstants.tile_index(ux, uy, _setup_input.grid_width)
		if tile >= 0 and tile < tile_count:
			_setup_tile_unit_count[tile] += 1

func _update_ghost_preview() -> void:
	if not _custom_mode or _placing_unit_type == -1:
		_battle_view.set_ghost_units([], true)
		return
	if _setup_input == null or _battle_view == null:
		return
	var anchor = _battle_view.get_hovered_tile()
	if anchor.x < 0:
		_battle_view.set_ghost_units([], true)
		return
	var layout = _build_squad_layout(_placing_unit_type, BattleConstants.MAX_SQUAD_SIZE)
	var tiles = _layout_world_tiles(layout, anchor, _placing_side)
	var valid = _is_layout_valid(tiles)
	var ghost_units = _build_ghost_units(layout, tiles, _placing_unit_type, _placing_side)
	_battle_view.set_ghost_units(ghost_units, valid)

func _try_place_squad() -> bool:
	if _setup_input == null or _battle_view == null:
		return false
	var anchor = _battle_view.get_hovered_tile()
	if anchor.x < 0:
		return false
	var layout = _build_squad_layout(_placing_unit_type, BattleConstants.MAX_SQUAD_SIZE)
	var tiles = _layout_world_tiles(layout, anchor, _placing_side)
	if not _is_layout_valid(tiles):
		return false
	var squad_id = _next_squad_id
	_next_squad_id += 1
	_setup_input.squad_ids.append(squad_id)
	_setup_input.squad_sides.append(_placing_side)
	_setup_input.squad_formations.append(BattleConstants.Formation.SQUARE)

	var unit_size = BattleConstants.UNIT_SIZE[_placing_unit_type]
	for i in range(tiles.size()):
		var tile = tiles[i]
		var count = layout["tile_units"][i]
		var tile_index = BattleConstants.tile_index(tile.x, tile.y, _setup_input.grid_width)
		for j in range(count):
			var unit_id = _next_unit_id
			_next_unit_id += 1
			_setup_input.unit_ids.append(unit_id)
			_setup_input.unit_sides.append(_placing_side)
			_setup_input.unit_types.append(_placing_unit_type)
			_setup_input.unit_sizes.append(unit_size)
			_setup_input.unit_x.append(tile.x)
			_setup_input.unit_y.append(tile.y)
			_setup_input.unit_next_tick.append(0)
			_setup_input.unit_squad_ids.append(squad_id)
			if tile_index >= 0 and tile_index < _setup_tile_unit_count.size():
				_setup_tile_unit_count[tile_index] += 1

	_show_preview(_setup_input)
	return true

func _build_squad_layout(unit_type: int, squad_size: int) -> Dictionary:
	var unit_size = BattleConstants.UNIT_SIZE[unit_type]
	var max_units = _setup_input.max_units_per_tile
	var max_total_size = _setup_input.max_total_size_per_tile
	var tile_units = []
	var current_count = 0
	var current_size = 0

	for i in range(squad_size):
		if current_count >= max_units or current_size + unit_size > max_total_size:
			tile_units.append(current_count)
			current_count = 0
			current_size = 0
		current_count += 1
		current_size += unit_size
	if current_count > 0:
		tile_units.append(current_count)

	var formation = _square_tile_positions(tile_units.size())
	return {
		"tile_units": tile_units,
		"positions": formation["positions"],
		"width": formation["width"],
		"height": formation["height"],
	}

func _square_tile_positions(tile_count: int) -> Dictionary:
	var width = int(ceil(sqrt(float(tile_count))))
	if width < 1:
		width = 1
	var height = int(ceil(float(tile_count) / float(width)))
	if height < 1:
		height = 1

	var positions = []
	var remaining = tile_count
	for y in range(height):
		for x in range(width):
			if remaining <= 0:
				break
			positions.append(Vector2i(x, y))
			remaining -= 1
		if remaining <= 0:
			break

	return {
		"width": width,
		"height": height,
		"positions": positions,
	}

func _layout_world_tiles(layout: Dictionary, anchor: Vector2i, side: int) -> Array:
	var tiles = []
	var positions: Array = layout["positions"]
	for local in positions:
		var pos = local as Vector2i
		var world_x = anchor.x + pos.x
		if side == BattleConstants.Side.RED:
			world_x = anchor.x - pos.x
		var world_y = anchor.y + pos.y
		tiles.append(Vector2i(world_x, world_y))
	return tiles

func _is_layout_valid(tiles: Array) -> bool:
	if _setup_input == null:
		return false
	for tile in tiles:
		var pos = tile as Vector2i
		if pos.x < 0 or pos.y < 0 or pos.x >= _setup_input.grid_width or pos.y >= _setup_input.grid_height:
			return false
		var tile_index = BattleConstants.tile_index(pos.x, pos.y, _setup_input.grid_width)
		if tile_index < 0 or tile_index >= _setup_tile_unit_count.size():
			return false
		if _setup_tile_unit_count[tile_index] > 0:
			return false
	return true

func _build_ghost_units(layout: Dictionary, tiles: Array, unit_type: int, side: int) -> Array:
	var ghost_units = []
	for i in range(tiles.size()):
		var tile = tiles[i] as Vector2i
		if tile.x < 0 or tile.y < 0 or tile.x >= _setup_input.grid_width or tile.y >= _setup_input.grid_height:
			continue
		var count = int(layout["tile_units"][i])
		for slot in range(count):
			ghost_units.append({
				"type": unit_type,
				"x": tile.x,
				"y": tile.y,
				"slot": slot,
				"side": side,
			})
	return ghost_units
