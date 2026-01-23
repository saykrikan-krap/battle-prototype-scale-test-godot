class_name BattleReplayer
extends Object

const BattleConstants = preload("res://schema/constants.gd")

var event_log
var event_index: int = 0
var current_tick: int = 0
var tick_accumulator: float = 0.0
var ticks_per_second: int = 20
var playing: bool = false
var end_tick: int = 0

var grid_width: int = 0
var grid_height: int = 0

var unit_alive = PackedInt32Array()
var unit_side = PackedInt32Array()
var unit_type = PackedInt32Array()
var unit_x = PackedInt32Array()
var unit_y = PackedInt32Array()
var prev_x = PackedInt32Array()
var prev_y = PackedInt32Array()
var last_move_tick = PackedInt32Array()
var last_attack_tick = PackedInt32Array()
var units_remaining = PackedInt32Array([0, 0])
var tile_unit_count = PackedInt32Array()
var tile_facing = PackedInt32Array()

var squad_anchor_x = PackedInt32Array()
var squad_anchor_y = PackedInt32Array()
var squad_facing = PackedInt32Array()
var squad_slack = PackedInt32Array()
var squad_choke = PackedInt32Array()
var squad_anchor_delay = PackedInt32Array()
var squad_count: int = 0

var projectile_ids = []
var projectile_type = []
var projectile_from = []
var projectile_to = []
var projectile_fire_tick = []
var projectile_impact_tick = []
var projectile_index_by_id = {}

func initialize_from_log(log) -> void:
	event_log = log
	_event_scan_for_init()
	_reset_state()
	apply_events_for_tick(0)
	playing = true

func _event_scan_for_init() -> void:
	var count = event_log.count()
	var max_unit_id = -1
	var unit_count = 0
	end_tick = 0
	grid_width = 0
	grid_height = 0
	var max_squad_id = -1

	for i in range(count):
		var event_type = event_log.types[i]
		if event_type == BattleConstants.EventType.BATTLE_INIT:
			grid_width = event_log.a[i]
			grid_height = event_log.b[i]
			unit_count = event_log.d[i]
		elif event_type == BattleConstants.EventType.UNIT_SPAWNED:
			var unit_id = event_log.a[i]
			if unit_id > max_unit_id:
				max_unit_id = unit_id
		elif event_type == BattleConstants.EventType.SQUAD_DEBUG:
			var squad_id = event_log.a[i]
			if squad_id > max_squad_id:
				max_squad_id = squad_id
		elif event_type == BattleConstants.EventType.BATTLE_ENDED:
			end_tick = event_log.b[i]

	if unit_count <= 0:
		unit_count = max_unit_id + 1
	if unit_count < 0:
		unit_count = 0
	squad_count = max_squad_id + 1 if max_squad_id >= 0 else 0

	unit_alive.resize(unit_count)
	unit_side.resize(unit_count)
	unit_type.resize(unit_count)
	unit_x.resize(unit_count)
	unit_y.resize(unit_count)
	prev_x.resize(unit_count)
	prev_y.resize(unit_count)
	last_move_tick.resize(unit_count)
	last_attack_tick.resize(unit_count)

func _reset_state() -> void:
	event_index = 0
	current_tick = 0
	tick_accumulator = 0.0
	units_remaining[0] = 0
	units_remaining[1] = 0

	for i in range(unit_alive.size()):
		unit_alive[i] = 0
		unit_side[i] = 0
		unit_type[i] = 0
		unit_x[i] = 0
		unit_y[i] = 0
		prev_x[i] = 0
		prev_y[i] = 0
		last_move_tick[i] = -1
		last_attack_tick[i] = -1

	var tile_count = grid_width * grid_height
	tile_unit_count.resize(tile_count)
	tile_facing.resize(tile_count)
	for i in range(tile_count):
		tile_unit_count[i] = 0
		tile_facing[i] = -1

	squad_anchor_x.resize(squad_count)
	squad_anchor_y.resize(squad_count)
	squad_facing.resize(squad_count)
	squad_slack.resize(squad_count)
	squad_choke.resize(squad_count)
	squad_anchor_delay.resize(squad_count)
	for i in range(squad_count):
		squad_anchor_x[i] = -1
		squad_anchor_y[i] = -1
		squad_facing[i] = 0
		squad_slack[i] = 0
		squad_choke[i] = 0
		squad_anchor_delay[i] = 0

	projectile_ids.clear()
	projectile_type.clear()
	projectile_from.clear()
	projectile_to.clear()
	projectile_fire_tick.clear()
	projectile_impact_tick.clear()
	projectile_index_by_id.clear()

func _ensure_squad_capacity(min_size: int) -> void:
	if min_size <= squad_count:
		return
	var old_size = squad_count
	squad_count = min_size
	squad_anchor_x.resize(squad_count)
	squad_anchor_y.resize(squad_count)
	squad_facing.resize(squad_count)
	squad_slack.resize(squad_count)
	squad_choke.resize(squad_count)
	squad_anchor_delay.resize(squad_count)
	for i in range(old_size, squad_count):
		squad_anchor_x[i] = -1
		squad_anchor_y[i] = -1
		squad_facing[i] = 0
		squad_slack[i] = 0
		squad_choke[i] = 0
		squad_anchor_delay[i] = 0

func set_playing(value: bool) -> void:
	playing = value

func set_ticks_per_second(value: int) -> void:
	ticks_per_second = value

func step_tick() -> void:
	if event_log == null:
		return
	if end_tick > 0 and current_tick >= end_tick:
		return
	current_tick += 1
	apply_events_for_tick(current_tick)
	tick_accumulator = 0.0

func update(delta: float) -> void:
	if event_log == null:
		return
	if not playing:
		return
	if end_tick > 0 and current_tick >= end_tick:
		playing = false
		return
	
	tick_accumulator += delta * float(ticks_per_second)
	while tick_accumulator >= 1.0:
		current_tick += 1
		apply_events_for_tick(current_tick)
		tick_accumulator -= 1.0
		if end_tick > 0 and current_tick >= end_tick:
			playing = false
			break

func tick_alpha() -> float:
	return tick_accumulator

func apply_events_for_tick(tick: int) -> void:
	if event_log == null:
		return
	var total = event_log.count()
	while event_index < total and event_log.ticks[event_index] <= tick:
		_apply_event(event_index)
		event_index += 1

func _apply_event(index: int) -> void:
	var event_type = event_log.types[index]
	match event_type:
		BattleConstants.EventType.BATTLE_INIT:
			grid_width = event_log.a[index]
			grid_height = event_log.b[index]
		BattleConstants.EventType.UNIT_SPAWNED:
			var unit_id = event_log.a[index]
			var side = event_log.b[index]
			var u_type = event_log.c[index]
			var pos = event_log.d[index]
			var x = BattleConstants.decode_x(pos)
			var y = BattleConstants.decode_y(pos)
			unit_alive[unit_id] = 1
			unit_side[unit_id] = side
			unit_type[unit_id] = u_type
			unit_x[unit_id] = x
			unit_y[unit_id] = y
			prev_x[unit_id] = x
			prev_y[unit_id] = y
			last_move_tick[unit_id] = -1
			units_remaining[side] += 1
			var tile_index = x + y * grid_width
			if tile_index >= 0 and tile_index < tile_unit_count.size():
				tile_unit_count[tile_index] += 1
				if tile_facing[tile_index] == -1:
					tile_facing[tile_index] = BattleConstants.DEFAULT_FACING[side]
		BattleConstants.EventType.UNIT_MOVED:
			var move_id = event_log.a[index]
			var from_pos = event_log.b[index]
			var to_pos = event_log.c[index]
			var from_x = BattleConstants.decode_x(from_pos)
			var from_y = BattleConstants.decode_y(from_pos)
			var to_x = BattleConstants.decode_x(to_pos)
			var to_y = BattleConstants.decode_y(to_pos)
			prev_x[move_id] = from_x
			prev_y[move_id] = from_y
			unit_x[move_id] = to_x
			unit_y[move_id] = to_y
			last_move_tick[move_id] = event_log.ticks[index]
			var from_tile = from_x + from_y * grid_width
			var to_tile = to_x + to_y * grid_width
			var was_empty = false
			if to_tile >= 0 and to_tile < tile_unit_count.size():
				was_empty = tile_unit_count[to_tile] == 0
			if from_tile >= 0 and from_tile < tile_unit_count.size():
				tile_unit_count[from_tile] -= 1
				if tile_unit_count[from_tile] <= 0:
					tile_unit_count[from_tile] = 0
					tile_facing[from_tile] = -1
			if to_tile >= 0 and to_tile < tile_unit_count.size():
				if was_empty and tile_facing[to_tile] == -1:
					tile_facing[to_tile] = BattleConstants.DEFAULT_FACING[unit_side[move_id]]
				if to_x != from_x:
					tile_facing[to_tile] = BattleConstants.Facing.RIGHT if to_x > from_x else BattleConstants.Facing.LEFT
				tile_unit_count[to_tile] += 1
		BattleConstants.EventType.MELEE_ATTACK_RESOLVED:
			var attacker_id = event_log.a[index]
			if attacker_id >= 0 and attacker_id < last_attack_tick.size():
				last_attack_tick[attacker_id] = current_tick
		BattleConstants.EventType.PROJECTILE_FIRED:
			var pid = event_log.a[index]
			var p_type = event_log.b[index]
			var shooter_id = event_log.c[index]
			var target_pos = event_log.d[index]
			var from_pos = BattleConstants.encode_pos(unit_x[shooter_id], unit_y[shooter_id])
			var impact_tick = _compute_impact_tick(event_log.ticks[index], from_pos, target_pos, p_type)
			_add_projectile(pid, p_type, from_pos, target_pos, event_log.ticks[index], impact_tick)
			if shooter_id >= 0 and shooter_id < last_attack_tick.size():
				last_attack_tick[shooter_id] = current_tick
		BattleConstants.EventType.PROJECTILE_IMPACTED:
			var impact_id = event_log.a[index]
			_remove_projectile(impact_id)
		BattleConstants.EventType.UNIT_REMOVED:
			var removed_id = event_log.a[index]
			if unit_alive[removed_id] == 1:
				unit_alive[removed_id] = 0
				units_remaining[unit_side[removed_id]] -= 1
				var removed_tile = unit_x[removed_id] + unit_y[removed_id] * grid_width
				if removed_tile >= 0 and removed_tile < tile_unit_count.size():
					tile_unit_count[removed_tile] -= 1
					if tile_unit_count[removed_tile] <= 0:
						tile_unit_count[removed_tile] = 0
						tile_facing[removed_tile] = -1
		BattleConstants.EventType.SQUAD_DEBUG:
			var squad_id = event_log.a[index]
			if squad_id < 0:
				return
			_ensure_squad_capacity(squad_id + 1)
			var pos = event_log.b[index]
			var packed = event_log.c[index]
			var packed2 = event_log.d[index]
			squad_anchor_x[squad_id] = BattleConstants.decode_x(pos)
			squad_anchor_y[squad_id] = BattleConstants.decode_y(pos)
			squad_facing[squad_id] = (packed >> 16) & 0xFFFF
			squad_slack[squad_id] = packed & 0xFFFF
			squad_anchor_delay[squad_id] = packed2 & 0xFFFF
			squad_choke[squad_id] = (packed2 >> 16) & 1
		BattleConstants.EventType.BATTLE_ENDED:
			end_tick = event_log.b[index]
		_:
			pass

func _compute_impact_tick(fire_tick: int, from_pos: int, to_pos: int, p_type: int) -> int:
	var fx = BattleConstants.decode_x(from_pos)
	var fy = BattleConstants.decode_y(from_pos)
	var tx = BattleConstants.decode_x(to_pos)
	var ty = BattleConstants.decode_y(to_pos)
	var distance = abs(tx - fx) + abs(ty - fy)
	var speed = BattleConstants.PROJECTILE_SPEED[p_type]
	return fire_tick + (speed * distance)

func _add_projectile(pid: int, p_type: int, from_pos: int, to_pos: int, fire_tick: int, impact_tick: int) -> void:
	projectile_index_by_id[pid] = projectile_ids.size()
	projectile_ids.append(pid)
	projectile_type.append(p_type)
	projectile_from.append(from_pos)
	projectile_to.append(to_pos)
	projectile_fire_tick.append(fire_tick)
	projectile_impact_tick.append(impact_tick)

func _remove_projectile(pid: int) -> void:
	if not projectile_index_by_id.has(pid):
		return
	var index = projectile_index_by_id[pid]
	var last_index = projectile_ids.size() - 1
	if index != last_index:
		var swap_id = projectile_ids[last_index]
		projectile_ids[index] = swap_id
		projectile_type[index] = projectile_type[last_index]
		projectile_from[index] = projectile_from[last_index]
		projectile_to[index] = projectile_to[last_index]
		projectile_fire_tick[index] = projectile_fire_tick[last_index]
		projectile_impact_tick[index] = projectile_impact_tick[last_index]
		projectile_index_by_id[swap_id] = index
	projectile_ids.resize(last_index)
	projectile_type.resize(last_index)
	projectile_from.resize(last_index)
	projectile_to.resize(last_index)
	projectile_fire_tick.resize(last_index)
	projectile_impact_tick.resize(last_index)
	projectile_index_by_id.erase(pid)
