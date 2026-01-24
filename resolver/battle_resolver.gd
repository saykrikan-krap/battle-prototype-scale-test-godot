class_name BattleResolver
extends Object

const BattleConstants = preload("res://schema/constants.gd")
const XorShift32 = preload("res://schema/prng.gd")
const EventLog = preload("res://schema/event_log.gd")
const BattleResult = preload("res://schema/battle_result.gd")

const INF_DISTANCE = 1_000_000
const STALL_TICK_LIMIT = 0
const BASE_STEP_COST = 1
const FRIEND_PENALTY = 1
const SLACK_BASE = 2
const SLACK_CHOKE_BONUS = 2
const DETACH_DIST = 8
const REATTACH_DIST = 5
const REBUILD_INTERVAL_TICKS = 8
const MAX_STALE_TICKS = 32
const STALE_GUARD_THRESHOLD = 4
const USE_UNIFORM_COST_BFS = true

static func resolve(input, profile: bool = false) -> Dictionary:
	var start_ms = Time.get_ticks_msec()
	var profile_enabled = profile
	var profile_start_usec = 0
	if profile_enabled:
		profile_start_usec = Time.get_ticks_usec()
	var time_impacts_usec = 0
	var time_field_build_usec = 0
	var time_anchor_usec = 0
	var time_unit_phase_usec = 0
	var time_move_apply_usec = 0
	var time_blocked_usec = 0
	var profile_ticks = 0
	var profile_active_units = 0
	var profile_move_units = 0
	var rng = XorShift32.new(input.seed)
	var event_log = EventLog.new()

	var width = input.grid_width
	var height = input.grid_height
	var tile_count = width * height
	var unit_count = input.unit_count()

	var tile_terrain = input.tile_terrain.duplicate()
	if tile_terrain.size() != tile_count:
		tile_terrain.resize(tile_count)
		for i in range(tile_count):
			tile_terrain[i] = BattleConstants.TerrainType.GRASS
	var uniform_cost = USE_UNIFORM_COST_BFS and _terrain_uniform_cost(tile_terrain)

	event_log.add_event(
		0,
		0,
		BattleConstants.EventType.BATTLE_INIT,
		width,
		height,
		input.time_limit_ticks,
		unit_count
	)
	for tile in range(tile_count):
		event_log.add_event(
			0,
			0,
			BattleConstants.EventType.TERRAIN_SET,
			tile,
			tile_terrain[tile],
			0,
			0
		)

	var alive = PackedInt32Array()
	alive.resize(unit_count)
	for i in range(unit_count):
		alive[i] = 1

	var side = input.unit_sides.duplicate()
	var unit_type = input.unit_types.duplicate()
	var unit_size = input.unit_sizes.duplicate()
	var unit_x = input.unit_x.duplicate()
	var unit_y = input.unit_y.duplicate()
	var next_tick = input.unit_next_tick.duplicate()
	if next_tick.size() < unit_count:
		next_tick.resize(unit_count)
		for i in range(unit_count):
			next_tick[i] = 0
	var unit_squad_id = input.unit_squad_ids.duplicate()
	if unit_squad_id.size() < unit_count:
		unit_squad_id.resize(unit_count)
		for i in range(unit_count):
			unit_squad_id[i] = -1
	var unit_slot_dx = input.unit_slot_dx.duplicate()
	var unit_slot_dy = input.unit_slot_dy.duplicate()
	if unit_slot_dx.size() < unit_count:
		unit_slot_dx.resize(unit_count)
		for i in range(unit_count):
			unit_slot_dx[i] = 0
	if unit_slot_dy.size() < unit_count:
		unit_slot_dy.resize(unit_count)
		for i in range(unit_count):
			unit_slot_dy[i] = 0

	var tile_side = PackedInt32Array()
	tile_side.resize(tile_count)
	var tile_unit_count = PackedInt32Array()
	tile_unit_count.resize(tile_count)
	var tile_total_size = PackedInt32Array()
	tile_total_size.resize(tile_count)
	var tile_units = []
	tile_units.resize(tile_count)
	for i in range(tile_count):
		tile_side[i] = -1
		tile_unit_count[i] = 0
		tile_total_size[i] = 0
		tile_units[i] = []

	for id in range(unit_count):
		var tile = unit_x[id] + unit_y[id] * width
		_add_unit_to_tile(tile, id, side[id], unit_size[id], tile_side, tile_unit_count, tile_total_size, tile_units)
		event_log.add_event(
			0,
			id,
			BattleConstants.EventType.UNIT_SPAWNED,
			id,
			side[id],
			unit_type[id],
			BattleConstants.encode_pos(unit_x[id], unit_y[id])
		)

	var squad_ids = input.squad_ids.duplicate()
	var squad_sides = input.squad_sides.duplicate()
	var squad_formations = input.squad_formations.duplicate()
	var squad_count = squad_ids.size()

	var squad_index_by_id = {}
	for i in range(squad_count):
		squad_index_by_id[squad_ids[i]] = i

	var unit_squad_index = PackedInt32Array()
	unit_squad_index.resize(unit_count)
	for i in range(unit_count):
		var squad_id = unit_squad_id[i]
		if squad_index_by_id.has(squad_id):
			unit_squad_index[i] = squad_index_by_id[squad_id]
		else:
			unit_squad_index[i] = -1

	var squad_units = []
	squad_units.resize(squad_count)
	for i in range(squad_count):
		squad_units[i] = []
	for i in range(unit_count):
		var s_index = unit_squad_index[i]
		if s_index != -1:
			squad_units[s_index].append(i)

	var squad_anchor_x = PackedInt32Array()
	var squad_anchor_y = PackedInt32Array()
	var squad_anchor_next_tick = PackedInt32Array()
	var squad_anchor_delay = PackedInt32Array()
	var squad_facing = PackedInt32Array()
	var squad_slack_base = PackedInt32Array()
	var squad_slack_bonus = PackedInt32Array()
	var squad_choke_active = PackedInt32Array()
	var squad_size_profile = PackedInt32Array()
	var squad_formation_enabled = PackedInt32Array()

	squad_anchor_x.resize(squad_count)
	squad_anchor_y.resize(squad_count)
	squad_anchor_next_tick.resize(squad_count)
	squad_anchor_delay.resize(squad_count)
	squad_facing.resize(squad_count)
	squad_slack_base.resize(squad_count)
	squad_slack_bonus.resize(squad_count)
	squad_choke_active.resize(squad_count)
	squad_size_profile.resize(squad_count)
	squad_formation_enabled.resize(squad_count)

	for s in range(squad_count):
		squad_anchor_x[s] = -1
		squad_anchor_y[s] = -1
		squad_anchor_next_tick[s] = 0
		squad_anchor_delay[s] = 1
		var side_value = squad_sides[s] if s < squad_sides.size() else BattleConstants.Side.RED
		squad_facing[s] = BattleConstants.Dir.EAST if side_value == BattleConstants.Side.RED else BattleConstants.Dir.WEST
		squad_slack_base[s] = SLACK_BASE
		squad_slack_bonus[s] = SLACK_CHOKE_BONUS
		squad_choke_active[s] = 0
		squad_size_profile[s] = 2
		squad_formation_enabled[s] = 1 if (s < squad_formations.size() and squad_formations[s] == BattleConstants.Formation.SQUARE) else 0

	for s in range(squad_count):
		var members: Array = squad_units[s]
		if members.is_empty():
			continue
		var max_size = 0
		for id in members:
			max_size = max(max_size, unit_size[id])
		squad_size_profile[s] = max_size
		squad_anchor_delay[s] = _median_move_delay(members, unit_type)
		var first_id = members[0]
		var facing = squad_facing[s]
		var offset = _rotate_offset(Vector2i(unit_slot_dx[first_id], unit_slot_dy[first_id]), facing)
		squad_anchor_x[s] = unit_x[first_id] - offset.x
		squad_anchor_y[s] = unit_y[first_id] - offset.y

	var unit_attached = PackedInt32Array()
	unit_attached.resize(unit_count)
	var unit_keep_formation_in_melee = PackedInt32Array()
	unit_keep_formation_in_melee.resize(unit_count)
	for i in range(unit_count):
		unit_attached[i] = 1 if unit_squad_index[i] != -1 else 0
		unit_keep_formation_in_melee[i] = 0 if _is_melee_unit(unit_type[i]) else 1

	var unit_no_progress = PackedInt32Array()
	unit_no_progress.resize(unit_count)
	for i in range(unit_count):
		unit_no_progress[i] = 0

	var max_unit_size = _max_unit_size(unit_size)
	var field_cache = []
	field_cache.resize(2)
	for side_value in range(2):
		field_cache[side_value] = []
		field_cache[side_value].resize(max_unit_size + 1)
		for size_value in range(max_unit_size + 1):
			field_cache[side_value][size_value] = FieldCache.new()

	var neighbors = _build_neighbors(width, height)

	var terrain_version = 0
	var occupancy_version = PackedInt32Array()
	occupancy_version.resize(2)
	occupancy_version[0] = 0
	occupancy_version[1] = 0

	var projectiles_by_tick = []
	projectiles_by_tick.resize(input.time_limit_ticks + 1)
	for i in range(projectiles_by_tick.size()):
		projectiles_by_tick[i] = []

	var projectile_type = PackedInt32Array()
	var projectile_target_tile = PackedInt32Array()
	var projectile_shooter_id = PackedInt32Array()
	var projectile_impact_tick = PackedInt32Array()
	var next_projectile_id = 0

	var units_remaining = PackedInt32Array([0, 0])
	for id in range(unit_count):
		units_remaining[side[id]] += 1

	var ticks_elapsed = 0
	var stall_ticks = 0
	var in_flight_projectiles = 0
	var post_battle = false
	var max_tick = input.time_limit_ticks
	var tick = 0

	while tick <= max_tick:
		ticks_elapsed = tick
		if profile_enabled:
			profile_ticks += 1
		var activity = false

		var segment_start = 0
		if profile_enabled:
			segment_start = Time.get_ticks_usec()
		var impacts = []
		if tick < projectiles_by_tick.size():
			impacts = projectiles_by_tick[tick]
		if impacts.size() > 0:
			activity = true
		for pid in impacts:
			var p_type = projectile_type[pid]
			var target_tile = projectile_target_tile[pid]
			event_log.add_event(
				tick,
				0,
				BattleConstants.EventType.PROJECTILE_IMPACTED,
				pid,
				p_type,
				target_tile,
				0
			)
			var shooter_id = projectile_shooter_id[pid]
			if tile_side[target_tile] != -1:
				if p_type == BattleConstants.ProjectileType.ARROW:
					var target_id = _pick_random_unit(tile_units[target_tile], rng)
					if target_id != -1:
						_remove_unit(
							target_id,
							tick,
							0,
							BattleConstants.EventType.UNIT_REMOVED,
							1,
							shooter_id,
							width,
							side,
							unit_size,
							unit_x,
							unit_y,
							alive,
							units_remaining,
							occupancy_version,
							tile_side,
							tile_unit_count,
							tile_total_size,
							tile_units,
							event_log
						)
						activity = true
				else:
					var removed_any = false
					var targets = tile_units[target_tile].duplicate()
					for target_id in targets:
						if alive[target_id] == 1:
							_remove_unit(
								target_id,
								tick,
								0,
								BattleConstants.EventType.UNIT_REMOVED,
								2,
								shooter_id,
								width,
								side,
								unit_size,
								unit_x,
								unit_y,
								alive,
								units_remaining,
								occupancy_version,
								tile_side,
								tile_unit_count,
								tile_total_size,
								tile_units,
								event_log
							)
							removed_any = true
					if removed_any:
						activity = true
			in_flight_projectiles -= 1
			if in_flight_projectiles < 0:
				in_flight_projectiles = 0
		if profile_enabled:
			time_impacts_usec += Time.get_ticks_usec() - segment_start

		if units_remaining[BattleConstants.Side.RED] == 0 or units_remaining[BattleConstants.Side.BLUE] == 0:
			post_battle = true

		if post_battle:
			if in_flight_projectiles <= 0:
				break
			tick += 1
			continue

		var field_needed = []
		field_needed.resize(2)
		for side_value in range(2):
			var needs = PackedInt32Array()
			needs.resize(max_unit_size + 1)
			for size_value in range(max_unit_size + 1):
				needs[size_value] = 0
			field_needed[side_value] = needs

		for id in range(unit_count):
			if alive[id] == 0:
				continue
			if next_tick[id] > tick:
				continue
			var size_value = unit_size[id]
			if size_value <= max_unit_size:
				field_needed[side[id]][size_value] = 1

		for s in range(squad_count):
			if squad_anchor_x[s] < 0 or squad_anchor_y[s] < 0:
				continue
			if tick < squad_anchor_next_tick[s]:
				continue
			var side_value = squad_sides[s] if s < squad_sides.size() else BattleConstants.Side.RED
			var size_value = squad_size_profile[s]
			if size_value <= max_unit_size:
				field_needed[side_value][size_value] = 1

		if profile_enabled:
			segment_start = Time.get_ticks_usec()
		for side_value in range(2):
			for size_value in range(max_unit_size + 1):
				if field_needed[side_value][size_value] == 0:
					continue
				_ensure_distance_field(
					field_cache[side_value][size_value],
					side_value,
					size_value,
					tick,
					width,
					height,
					tile_side,
					tile_terrain,
					neighbors,
					terrain_version,
					occupancy_version,
					uniform_cost
				)
		if profile_enabled:
			time_field_build_usec += Time.get_ticks_usec() - segment_start

		if profile_enabled:
			segment_start = Time.get_ticks_usec()
		var squad_slack = PackedInt32Array()
		squad_slack.resize(squad_count)
		for s in range(squad_count):
			var slack = squad_slack_base[s] + (squad_choke_active[s] * squad_slack_bonus[s])
			squad_slack[s] = slack
			if squad_anchor_x[s] >= 0 and squad_anchor_y[s] >= 0 and tick >= squad_anchor_next_tick[s]:
				var side_value = squad_sides[s] if s < squad_sides.size() else BattleConstants.Side.RED
				var size_profile = squad_size_profile[s]
				var dist_field = field_cache[side_value][size_profile].dist
				var current_tile = squad_anchor_x[s] + squad_anchor_y[s] * width
				var current_dist = dist_field[current_tile]
				var best_tile = current_tile
				var best_dist = current_dist
				var best_dir = squad_facing[s]
				var dir_index = 0
				for dir in BattleConstants.NEIGHBOR_DIRS:
					var nx = squad_anchor_x[s] + dir.x
					var ny = squad_anchor_y[s] + dir.y
					if nx < 0 or nx >= width or ny < 0 or ny >= height:
						dir_index += 1
						continue
					var tile = nx + ny * width
					var dist = dist_field[tile]
					if dist < best_dist:
						best_dist = dist
						best_tile = tile
						best_dir = dir_index
					dir_index += 1
				if best_dist < current_dist and best_tile != current_tile:
					squad_anchor_x[s] = best_tile % width
					squad_anchor_y[s] = best_tile / width
					squad_facing[s] = best_dir
				squad_anchor_next_tick[s] += squad_anchor_delay[s]
			if squad_anchor_x[s] >= 0 and squad_anchor_y[s] >= 0:
				var anchor_pos = BattleConstants.encode_pos(squad_anchor_x[s], squad_anchor_y[s])
				var packed = (squad_facing[s] << 16) | (slack & 0xFFFF)
				var packed2 = (squad_anchor_delay[s] & 0xFFFF) | ((squad_choke_active[s] & 1) << 16)
				event_log.add_event(
					tick,
					squad_ids[s],
					BattleConstants.EventType.SQUAD_DEBUG,
					squad_ids[s],
					anchor_pos,
					packed,
					packed2
				)
		if profile_enabled:
			time_anchor_usec += Time.get_ticks_usec() - segment_start

		if profile_enabled:
			segment_start = Time.get_ticks_usec()
		var unit_rank = PackedInt32Array()
		unit_rank.resize(unit_count)
		for i in range(unit_count):
			var s_index = unit_squad_index[i]
			if s_index == -1:
				unit_rank[i] = 0
				continue
			var offset = _rotate_offset(Vector2i(unit_slot_dx[i], unit_slot_dy[i]), squad_facing[s_index])
			var dir = _dir_vector(squad_facing[s_index])
			var projection = (offset.x * dir.x) + (offset.y * dir.y)
			unit_rank[i] = -projection

		var intent_tile = PackedInt32Array()
		var best_tile = PackedInt32Array()
		var origin_tile = PackedInt32Array()
		var active_move = PackedInt32Array()
		var active_attached = PackedInt32Array()
		var moved_flag = PackedInt32Array()
		intent_tile.resize(unit_count)
		best_tile.resize(unit_count)
		origin_tile.resize(unit_count)
		active_move.resize(unit_count)
		active_attached.resize(unit_count)
		moved_flag.resize(unit_count)
		for i in range(unit_count):
			intent_tile[i] = -1
			best_tile[i] = -1
			origin_tile[i] = -1
			active_move[i] = 0
			active_attached[i] = 0
			moved_flag[i] = 0

		var move_units = []

		for id in range(unit_count):
			if alive[id] == 0:
				continue
			if next_tick[id] > tick:
				continue
			if profile_enabled:
				profile_active_units += 1

			var u_type = unit_type[id]
			var u_side = side[id]
			var ux = unit_x[id]
			var uy = unit_y[id]
			var enemy_side = BattleConstants.enemy_side(u_side)

			var current_tile = ux + uy * width
			var target_tile = _find_adjacent_enemy(current_tile, enemy_side, tile_side, neighbors)
			var engaged = target_tile != -1
			var acted = false
			var formation_active = false
			var desired_x = ux
			var desired_y = uy
			var squad_index = unit_squad_index[id]
			if squad_index != -1 and squad_formation_enabled[squad_index] == 1:
				if squad_anchor_x[squad_index] >= 0 and squad_anchor_y[squad_index] >= 0:
					var offset = _rotate_offset(Vector2i(unit_slot_dx[id], unit_slot_dy[id]), squad_facing[squad_index])
					desired_x = squad_anchor_x[squad_index] + offset.x
					desired_y = squad_anchor_y[squad_index] + offset.y
					var err = abs(ux - desired_x) + abs(uy - desired_y)
					if err > DETACH_DIST:
						unit_attached[id] = 0
					elif unit_attached[id] == 0 and err <= REATTACH_DIST:
						unit_attached[id] = 1
					if unit_attached[id] == 1 and (unit_keep_formation_in_melee[id] == 1 or not engaged):
						formation_active = true

			if _is_melee_unit(u_type) and target_tile != -1:
				var hit_roll = rng.next_range(100)
				var hit_chance = BattleConstants.MELEE_HIT_CHANCE[u_type]
				var hit = hit_roll < hit_chance
				event_log.add_event(
					tick,
					id,
					BattleConstants.EventType.MELEE_ATTACK_RESOLVED,
					id,
					target_tile,
					1 if hit else 0,
					0
				)
				if hit:
					var target_id = _pick_random_unit(tile_units[target_tile], rng)
					if target_id != -1:
						_remove_unit(
							target_id,
							tick,
							id,
							BattleConstants.EventType.UNIT_REMOVED,
							0,
							id,
							width,
							side,
							unit_size,
							unit_x,
							unit_y,
							alive,
							units_remaining,
							occupancy_version,
							tile_side,
							tile_unit_count,
							tile_total_size,
							tile_units,
							event_log
						)
						activity = true
				acted = true
				unit_no_progress[id] = 0
				next_tick[id] = tick + BattleConstants.ATTACK_COST[u_type]
				continue

			if _is_archer(u_type):
				var range = BattleConstants.RANGED_RANGE[u_type]
				var ranged_tile = _find_nearest_enemy_in_range(ux, uy, range, enemy_side, tile_side, width, height)
				if ranged_tile != -1:
					var pid = next_projectile_id
					next_projectile_id += 1
					_schedule_projectile(
						pid,
						BattleConstants.ProjectileType.ARROW,
						ranged_tile,
						id,
						tick,
						width,
						unit_x,
						unit_y,
						projectiles_by_tick,
						projectile_type,
						projectile_target_tile,
						projectile_shooter_id,
						projectile_impact_tick
					)
					var impact_tick = projectile_impact_tick[pid]
					if impact_tick >= 0:
						in_flight_projectiles += 1
						if impact_tick > max_tick:
							max_tick = impact_tick
					event_log.add_event(
						tick,
						id,
						BattleConstants.EventType.PROJECTILE_FIRED,
						pid,
						BattleConstants.ProjectileType.ARROW,
						id,
						BattleConstants.encode_pos(ranged_tile % width, int(ranged_tile / width))
					)
					activity = true
					acted = true
					unit_no_progress[id] = 0
					next_tick[id] = tick + BattleConstants.ATTACK_COST[u_type]
					continue

			if _is_mage(u_type):
				var mage_range = BattleConstants.RANGED_RANGE[u_type]
				var fire_tile = _find_best_fireball_tile(ux, uy, mage_range, enemy_side, tile_side, tile_unit_count, width, height)
				if fire_tile != -1:
					var pid2 = next_projectile_id
					next_projectile_id += 1
					_schedule_projectile(
						pid2,
						BattleConstants.ProjectileType.FIREBALL,
						fire_tile,
						id,
						tick,
						width,
						unit_x,
						unit_y,
						projectiles_by_tick,
						projectile_type,
						projectile_target_tile,
						projectile_shooter_id,
						projectile_impact_tick
					)
					var impact_tick2 = projectile_impact_tick[pid2]
					if impact_tick2 >= 0:
						in_flight_projectiles += 1
						if impact_tick2 > max_tick:
							max_tick = impact_tick2
					event_log.add_event(
						tick,
						id,
						BattleConstants.EventType.PROJECTILE_FIRED,
						pid2,
						BattleConstants.ProjectileType.FIREBALL,
						id,
						BattleConstants.encode_pos(fire_tile % width, int(fire_tile / width))
					)
					activity = true
					acted = true
					unit_no_progress[id] = 0
					next_tick[id] = tick + BattleConstants.ATTACK_COST[u_type]
					continue

			if not acted:
				var dist_field = field_cache[u_side][unit_size[id]].dist
				var slack = squad_slack[squad_index] if formation_active else 0
				var result = _choose_move_with_formation(
					current_tile,
					u_side,
					unit_size[id],
					dist_field,
					tile_side,
					tile_unit_count,
					tile_total_size,
					input.max_units_per_tile,
					input.max_total_size_per_tile,
					width,
					height,
					desired_x,
					desired_y,
					formation_active,
					slack
				)
				var chosen_tile = result["chosen"]
				var best_goal_tile = result["best"]
				if chosen_tile < 0:
					chosen_tile = current_tile
				intent_tile[id] = chosen_tile
				best_tile[id] = best_goal_tile
				origin_tile[id] = current_tile
				active_move[id] = 1
				if formation_active:
					active_attached[id] = 1
				if chosen_tile != current_tile:
					move_units.append(id)

		if profile_enabled:
			time_unit_phase_usec += Time.get_ticks_usec() - segment_start
			profile_move_units += move_units.size()

		if move_units.size() > 0:
			if profile_enabled:
				segment_start = Time.get_ticks_usec()
			var sorter = IntentSorter.new(unit_squad_index, unit_squad_id, unit_rank)
			move_units.sort_custom(Callable(sorter, "less"))
			for id in move_units:
				var target = intent_tile[id]
				if target == -1:
					continue
				if _tile_can_accept(target, side[id], unit_size[id], tile_side, tile_unit_count, tile_total_size, input.max_units_per_tile, input.max_total_size_per_tile):
					var from_tile = origin_tile[id]
					var from_pos = BattleConstants.encode_pos(from_tile % width, int(from_tile / width))
					_remove_unit_from_tile(from_tile, id, unit_size[id], tile_side, tile_unit_count, tile_total_size, tile_units)
					_add_unit_to_tile(target, id, side[id], unit_size[id], tile_side, tile_unit_count, tile_total_size, tile_units)
					var new_x = target % width
					var new_y = target / width
					unit_x[id] = new_x
					unit_y[id] = new_y
					occupancy_version[side[id]] += 1
					moved_flag[id] = 1
					event_log.add_event(
						tick,
						id,
						BattleConstants.EventType.UNIT_MOVED,
						id,
						from_pos,
						BattleConstants.encode_pos(new_x, new_y),
						0
					)
					activity = true
			if profile_enabled:
				time_move_apply_usec += Time.get_ticks_usec() - segment_start

		if active_move.size() > 0:
			for id in range(unit_count):
				if active_move[id] == 0:
					continue
				if moved_flag[id] == 1:
					var moved_tile = unit_x[id] + unit_y[id] * width
					var terrain_type = BattleConstants.TerrainType.GRASS
					if moved_tile >= 0 and moved_tile < tile_terrain.size():
						terrain_type = tile_terrain[moved_tile]
					next_tick[id] = tick + _move_delay(unit_type[id], terrain_type)
				else:
					next_tick[id] = tick + BattleConstants.WAIT_COST[unit_type[id]]

			for id in range(unit_count):
				if active_move[id] == 0:
					continue
				if best_tile[id] == origin_tile[id]:
					unit_no_progress[id] += 1
					if unit_no_progress[id] >= STALE_GUARD_THRESHOLD:
						var size_value = unit_size[id]
						field_cache[side[id]][size_value].force_rebuild = true
				else:
					unit_no_progress[id] = 0

		if profile_enabled:
			segment_start = Time.get_ticks_usec()
		var blocked_count = PackedInt32Array()
		var attached_count = PackedInt32Array()
		blocked_count.resize(squad_count)
		attached_count.resize(squad_count)
		for s in range(squad_count):
			blocked_count[s] = 0
			attached_count[s] = 0
		for id in range(unit_count):
			if active_attached[id] == 0:
				continue
			var s_index = unit_squad_index[id]
			if s_index == -1:
				continue
			attached_count[s_index] += 1
			if moved_flag[id] == 0 and best_tile[id] != origin_tile[id]:
				blocked_count[s_index] += 1
		for s in range(squad_count):
			if attached_count[s] > 0 and blocked_count[s] * 2 >= attached_count[s]:
				squad_choke_active[s] = 1
			else:
				squad_choke_active[s] = 0
		if profile_enabled:
			time_blocked_usec += Time.get_ticks_usec() - segment_start

		if units_remaining[BattleConstants.Side.RED] == 0 or units_remaining[BattleConstants.Side.BLUE] == 0:
			post_battle = true

		if tick >= input.time_limit_ticks:
			post_battle = true

		if post_battle:
			if in_flight_projectiles <= 0:
				break
			tick += 1
			continue

		if activity:
			stall_ticks = 0
		else:
			stall_ticks += 1
			if STALL_TICK_LIMIT > 0 and stall_ticks >= STALL_TICK_LIMIT:
				post_battle = true
				if in_flight_projectiles <= 0:
					break
				tick += 1
				continue

		tick += 1

	var winner = -1
	if units_remaining[BattleConstants.Side.RED] == 0 and units_remaining[BattleConstants.Side.BLUE] == 0:
		winner = -1
	elif units_remaining[BattleConstants.Side.RED] == 0:
		winner = BattleConstants.Side.BLUE
	elif units_remaining[BattleConstants.Side.BLUE] == 0:
		winner = BattleConstants.Side.RED
	else:
		winner = -1

	var result = BattleResult.new()
	result.winner = winner
	result.ticks_elapsed = ticks_elapsed
	result.units_remaining_by_side = units_remaining
	result.resolve_ms = Time.get_ticks_msec() - start_ms
	if result.resolve_ms > 0:
		result.avg_ticks_per_sec = (float(ticks_elapsed) / (float(result.resolve_ms) / 1000.0))

	event_log.add_event(
		ticks_elapsed,
		0,
		BattleConstants.EventType.BATTLE_ENDED,
		winner,
		ticks_elapsed,
		units_remaining[BattleConstants.Side.RED],
		units_remaining[BattleConstants.Side.BLUE]
	)
	result.event_count = event_log.count()
	result.event_hash = event_log.hash_u32()

	if profile_enabled:
		var total_usec = Time.get_ticks_usec() - profile_start_usec
		var total_ms = float(total_usec) / 1000.0
		var tick_div = max(profile_ticks, 1)
		var active_avg = float(profile_active_units) / float(tick_div)
		var move_avg = float(profile_move_units) / float(tick_div)
		print("Profile ticks: %d" % profile_ticks)
		print("Profile active units/tick: %.1f" % active_avg)
		print("Profile move intents/tick: %.1f" % move_avg)
		print("Profile field cadence: interval %d max_stale %d stale_guard %d" % [REBUILD_INTERVAL_TICKS, MAX_STALE_TICKS, STALE_GUARD_THRESHOLD])
		var build_total = 0
		var build_time_total = 0
		for side_value in range(2):
			for size_value in range(max_unit_size + 1):
				var cache: FieldCache = field_cache[side_value][size_value]
				if cache.build_count > 0:
					var avg_ms = float(cache.build_time_usec) / 1000.0 / float(cache.build_count)
					print("Profile field builds: side %d size %d count %d avg %.2f ms" % [side_value, size_value, cache.build_count, avg_ms])
				build_total += cache.build_count
				build_time_total += cache.build_time_usec
		if build_total > 0:
			var avg_total = float(build_time_total) / 1000.0 / float(build_total)
			print("Profile field builds total: %d avg %.2f ms" % [build_total, avg_total])
		if total_usec > 0:
			print("Profile impacts: %.2f ms (%.1f%%)" % [float(time_impacts_usec) / 1000.0, float(time_impacts_usec) * 100.0 / float(total_usec)])
			print("Profile field builds: %.2f ms (%.1f%%)" % [float(time_field_build_usec) / 1000.0, float(time_field_build_usec) * 100.0 / float(total_usec)])
			print("Profile anchors: %.2f ms (%.1f%%)" % [float(time_anchor_usec) / 1000.0, float(time_anchor_usec) * 100.0 / float(total_usec)])
			print("Profile unit phase: %.2f ms (%.1f%%)" % [float(time_unit_phase_usec) / 1000.0, float(time_unit_phase_usec) * 100.0 / float(total_usec)])
			print("Profile move apply: %.2f ms (%.1f%%)" % [float(time_move_apply_usec) / 1000.0, float(time_move_apply_usec) * 100.0 / float(total_usec)])
			print("Profile choke eval: %.2f ms (%.1f%%)" % [float(time_blocked_usec) / 1000.0, float(time_blocked_usec) * 100.0 / float(total_usec)])
		print("Profile total: %.2f ms" % total_ms)

	return {
		"event_log": event_log,
		"result": result,
	}

static func _max_unit_size(unit_size: PackedInt32Array) -> int:
	var max_size = 0
	for value in unit_size:
		if value > max_size:
			max_size = value
	return max_size

static func _terrain_step_cost(terrain_type: int) -> int:
	if terrain_type < 0 or terrain_type >= BattleConstants.TERRAIN_COST.size():
		return BASE_STEP_COST
	return BattleConstants.TERRAIN_COST[terrain_type]

static func _move_delay(unit_type: int, terrain_type: int) -> int:
	var base = BattleConstants.MOVE_COST[unit_type]
	if terrain_type == BattleConstants.TerrainType.TREES and _is_cavalry_unit(unit_type):
		base = BattleConstants.MOVE_COST[BattleConstants.UnitType.INFANTRY]
	return base * _terrain_step_cost(terrain_type)

static func _terrain_uniform_cost(tile_terrain: PackedInt32Array) -> bool:
	for terrain_type in tile_terrain:
		if terrain_type != BattleConstants.TerrainType.GRASS:
			return false
	return true

static func _build_neighbors(width: int, height: int) -> Array:
	var neighbors = []
	neighbors.resize(width * height)
	for y in range(height):
		for x in range(width):
			var list = PackedInt32Array()
			for dir in BattleConstants.NEIGHBOR_DIRS:
				var nx = x + dir.x
				var ny = y + dir.y
				if nx >= 0 and nx < width and ny >= 0 and ny < height:
					list.append(nx + ny * width)
			neighbors[x + y * width] = list
	return neighbors

static func _median_move_delay(unit_ids: Array, unit_type: PackedInt32Array) -> int:
	if unit_ids.is_empty():
		return 1
	var delays = []
	for id in unit_ids:
		delays.append(BattleConstants.MOVE_COST[unit_type[id]])
	delays.sort()
	return delays[int(delays.size() / 2)]

static func _dir_vector(dir: int) -> Vector2i:
	match dir:
		BattleConstants.Dir.NORTH:
			return Vector2i(0, -1)
		BattleConstants.Dir.EAST:
			return Vector2i(1, 0)
		BattleConstants.Dir.SOUTH:
			return Vector2i(0, 1)
		BattleConstants.Dir.WEST:
			return Vector2i(-1, 0)
	return Vector2i.ZERO

static func _rotate_offset(offset: Vector2i, facing: int) -> Vector2i:
	match facing:
		BattleConstants.Dir.NORTH:
			return offset
		BattleConstants.Dir.EAST:
			return Vector2i(-offset.y, offset.x)
		BattleConstants.Dir.SOUTH:
			return Vector2i(-offset.x, -offset.y)
		BattleConstants.Dir.WEST:
			return Vector2i(offset.y, -offset.x)
	return offset

static func _is_melee_unit(u_type: int) -> bool:
	return u_type == BattleConstants.UnitType.INFANTRY \
		or u_type == BattleConstants.UnitType.HEAVY_INFANTRY \
		or u_type == BattleConstants.UnitType.ELITE_INFANTRY \
		or u_type == BattleConstants.UnitType.CAVALRY \
		or u_type == BattleConstants.UnitType.HEAVY_CAVALRY

static func _is_cavalry_unit(u_type: int) -> bool:
	return u_type == BattleConstants.UnitType.CAVALRY \
		or u_type == BattleConstants.UnitType.HEAVY_CAVALRY

static func _is_archer(u_type: int) -> bool:
	return u_type == BattleConstants.UnitType.ARCHER

static func _is_mage(u_type: int) -> bool:
	return u_type == BattleConstants.UnitType.MAGE

static func _add_unit_to_tile(
		tile: int,
		unit_id: int,
		unit_side: int,
		unit_size: int,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		tile_total_size: PackedInt32Array,
		tile_units: Array
	) -> void:
	if tile_side[tile] == -1:
		tile_side[tile] = unit_side
	tile_units[tile].append(unit_id)
	tile_unit_count[tile] += 1
	tile_total_size[tile] += unit_size

static func _remove_unit_from_tile(
		tile: int,
		unit_id: int,
		unit_size: int,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		tile_total_size: PackedInt32Array,
		tile_units: Array
	) -> void:
	tile_units[tile].erase(unit_id)
	tile_unit_count[tile] -= 1
	tile_total_size[tile] -= unit_size
	if tile_unit_count[tile] <= 0:
		tile_side[tile] = -1

static func _tile_can_accept(
		tile: int,
		unit_side: int,
		unit_size: int,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		tile_total_size: PackedInt32Array,
		max_units: int,
		max_total_size: int
	) -> bool:
	var side_value = tile_side[tile]
	if side_value == -1 or side_value == unit_side:
		if tile_unit_count[tile] + 1 <= max_units and tile_total_size[tile] + unit_size <= max_total_size:
			return true
	return false

static func _choose_move_with_formation(
		current_tile: int,
		unit_side: int,
		unit_size: int,
		dist_field: PackedInt32Array,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		tile_total_size: PackedInt32Array,
		max_units: int,
		max_total_size: int,
		width: int,
		height: int,
		desired_x: int,
		desired_y: int,
		formation_active: bool,
		slack: int
	) -> Dictionary:
	var candidates = []
	var current_x = current_tile % width
	var current_y = int(current_tile / width)
	var stay_penalty = 0
	if tile_side[current_tile] == unit_side:
		stay_penalty = max(tile_unit_count[current_tile] - 1, 0) * FRIEND_PENALTY
	var stay_cost = dist_field[current_tile] + stay_penalty
	candidates.append({"tile": current_tile, "goal": stay_cost, "order": 0})
	var best_cost = stay_cost
	var best_tile = current_tile
	var best_order = 0

	var order = 1
	for dir in BattleConstants.NEIGHBOR_DIRS:
		var nx = current_x + dir.x
		var ny = current_y + dir.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			order += 1
			continue
		var tile = nx + ny * width
		if not _tile_can_accept(tile, unit_side, unit_size, tile_side, tile_unit_count, tile_total_size, max_units, max_total_size):
			order += 1
			continue
		var dist = dist_field[tile]
		if dist >= INF_DISTANCE:
			order += 1
			continue
		var penalty = 0
		if tile_side[tile] == unit_side:
			penalty = tile_unit_count[tile] * FRIEND_PENALTY
		var goal = dist + penalty
		candidates.append({"tile": tile, "goal": goal, "order": order})
		if goal < best_cost or (goal == best_cost and order < best_order):
			best_cost = goal
			best_tile = tile
			best_order = order
		order += 1

	var limit = best_cost + slack
	var chosen_tile = current_tile
	var chosen_goal = stay_cost
	var chosen_form = INF_DISTANCE
	var chosen_order = 0
	var found = false
	for entry in candidates:
		var goal = entry["goal"]
		if goal > limit:
			continue
		var tile = entry["tile"]
		if formation_active:
			var tx = tile % width
			var ty = int(tile / width)
			var form = abs(tx - desired_x) + abs(ty - desired_y)
			if not found or form < chosen_form or (form == chosen_form and (goal < chosen_goal or (goal == chosen_goal and entry["order"] < chosen_order))):
				chosen_tile = tile
				chosen_goal = goal
				chosen_form = form
				chosen_order = entry["order"]
				found = true
		else:
			if not found or goal < chosen_goal or (goal == chosen_goal and entry["order"] < chosen_order):
				chosen_tile = tile
				chosen_goal = goal
				chosen_order = entry["order"]
				found = true

	return {
		"chosen": chosen_tile,
		"best": best_tile,
	}

static func _find_adjacent_enemy(
		tile: int,
		enemy_side: int,
		tile_side: PackedInt32Array,
		neighbors: Array
	) -> int:
	for neighbor in neighbors[tile]:
		if tile_side[neighbor] == enemy_side:
			return neighbor
	return -1

static func _find_nearest_enemy_in_range(
		x: int,
		y: int,
		range: int,
		enemy_side: int,
		tile_side: PackedInt32Array,
		width: int,
		height: int
	) -> int:
	var best_tile = -1
	var best_dist = INF_DISTANCE
	for dy in range(-range, range + 1):
		var ny = y + dy
		if ny < 0 or ny >= height:
			continue
		var max_dx = range - abs(dy)
		for dx in range(-max_dx, max_dx + 1):
			if dx == 0 and dy == 0:
				continue
			var nx = x + dx
			if nx < 0 or nx >= width:
				continue
			var tile = nx + ny * width
			if tile_side[tile] == enemy_side:
				var dist = abs(dx) + abs(dy)
				if dist < best_dist or (dist == best_dist and tile < best_tile):
					best_tile = tile
					best_dist = dist
	return best_tile

static func _find_best_fireball_tile(
		x: int,
		y: int,
		range: int,
		enemy_side: int,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		width: int,
		height: int
	) -> int:
	var best_tile = -1
	var best_count = -1
	for dy in range(-range, range + 1):
		var ny = y + dy
		if ny < 0 or ny >= height:
			continue
		var max_dx = range - abs(dy)
		for dx in range(-max_dx, max_dx + 1):
			if dx == 0 and dy == 0:
				continue
			var nx = x + dx
			if nx < 0 or nx >= width:
				continue
			var tile = nx + ny * width
			if tile_side[tile] == enemy_side:
				var count = tile_unit_count[tile]
				if count > best_count or (count == best_count and tile < best_tile):
					best_tile = tile
					best_count = count
	return best_tile

static func _ensure_distance_field(
		cache: FieldCache,
		unit_side: int,
		unit_size: int,
		tick: int,
		width: int,
		height: int,
		tile_side: PackedInt32Array,
		tile_terrain: PackedInt32Array,
		neighbors: Array,
		terrain_version: int,
		occupancy_version: PackedInt32Array,
		use_uniform_cost: bool
	) -> void:
	var enemy_side = BattleConstants.enemy_side(unit_side)
	var dirty = false
	if not cache.initialized:
		dirty = true
	if cache.built_terrain_version != terrain_version:
		dirty = true
	if cache.built_enemy_occupancy_version != occupancy_version[enemy_side]:
		dirty = true
	if cache.force_rebuild:
		dirty = true

	var should_rebuild = false
	if not cache.initialized:
		should_rebuild = true
	elif tick - cache.last_build_tick >= MAX_STALE_TICKS:
		should_rebuild = true
	elif dirty and tick - cache.last_build_tick >= REBUILD_INTERVAL_TICKS:
		should_rebuild = true

	if not should_rebuild:
		return

	var start_usec = Time.get_ticks_usec()
	_build_distance_field(cache.dist, width, height, unit_side, unit_size, tile_side, tile_terrain, neighbors, use_uniform_cost)
	var elapsed = Time.get_ticks_usec() - start_usec

	cache.initialized = true
	cache.last_build_tick = tick
	cache.built_terrain_version = terrain_version
	cache.built_enemy_occupancy_version = occupancy_version[enemy_side]
	cache.force_rebuild = false
	cache.build_count += 1
	cache.build_time_usec += elapsed

static func _build_distance_field(
		dist: PackedInt32Array,
		width: int,
		height: int,
		unit_side: int,
		unit_size: int,
		tile_side: PackedInt32Array,
		tile_terrain: PackedInt32Array,
		neighbors: Array,
		use_uniform_cost: bool
	) -> void:
	var tile_count = width * height
	if dist.size() != tile_count:
		dist.resize(tile_count)
	dist.fill(INF_DISTANCE)
	if use_uniform_cost:
		_build_distance_field_bfs(dist, width, height, unit_side, tile_side, neighbors)
	else:
		_build_distance_field_dijkstra(dist, width, height, unit_side, tile_side, tile_terrain, neighbors)

static func _build_distance_field_bfs(
		dist: PackedInt32Array,
		width: int,
		height: int,
		unit_side: int,
		tile_side: PackedInt32Array,
		neighbors: Array
	) -> void:
	var tile_count = width * height
	var queue = PackedInt32Array()
	queue.resize(tile_count)
	var head = 0
	var tail = 0
	for tile in range(tile_count):
		if tile_side[tile] != -1 and tile_side[tile] != unit_side:
			dist[tile] = 0
			queue[tail] = tile
			tail += 1

	while head < tail:
		var tile = queue[head]
		head += 1
		var base_dist = dist[tile]
		var next_dist = base_dist + BASE_STEP_COST
		for neighbor in neighbors[tile]:
			if next_dist < dist[neighbor]:
				dist[neighbor] = next_dist
				queue[tail] = neighbor
				tail += 1

static func _build_distance_field_dijkstra(
		dist: PackedInt32Array,
		width: int,
		height: int,
		unit_side: int,
		tile_side: PackedInt32Array,
		tile_terrain: PackedInt32Array,
		neighbors: Array
	) -> void:
	var tile_count = width * height
	var heap_nodes = PackedInt32Array()
	var heap_dists = PackedInt32Array()
	for tile in range(tile_count):
		if tile_side[tile] != -1 and tile_side[tile] != unit_side:
			dist[tile] = 0
			_heap_push(heap_nodes, heap_dists, tile, 0)

	while heap_nodes.size() > 0:
		var current = _heap_pop(heap_nodes, heap_dists)
		var tile = current.x
		var base_dist = current.y
		if base_dist != dist[tile]:
			continue
		for neighbor in neighbors[tile]:
			var step_cost = _terrain_step_cost(tile_terrain[neighbor])
			var next_dist = base_dist + step_cost
			if next_dist < dist[neighbor]:
				dist[neighbor] = next_dist
				_heap_push(heap_nodes, heap_dists, neighbor, next_dist)

static func _heap_push(nodes: PackedInt32Array, dists: PackedInt32Array, node: int, dist: int) -> void:
	nodes.append(node)
	dists.append(dist)
	var index = nodes.size() - 1
	while index > 0:
		var parent = (index - 1) / 2
		if _heap_less(dists[parent], nodes[parent], dist, node):
			break
		nodes[index] = nodes[parent]
		dists[index] = dists[parent]
		nodes[parent] = node
		dists[parent] = dist
		index = parent

static func _heap_pop(nodes: PackedInt32Array, dists: PackedInt32Array) -> Vector2i:
	var node = nodes[0]
	var dist = dists[0]
	var last_index = nodes.size() - 1
	if last_index == 0:
		nodes.resize(0)
		dists.resize(0)
		return Vector2i(node, dist)
	nodes[0] = nodes[last_index]
	dists[0] = dists[last_index]
	nodes.resize(last_index)
	dists.resize(last_index)
	_heap_sift_down(nodes, dists, 0)
	return Vector2i(node, dist)

static func _heap_sift_down(nodes: PackedInt32Array, dists: PackedInt32Array, index: int) -> void:
	var size = nodes.size()
	while index < size:
		var left = (index * 2) + 1
		if left >= size:
			break
		var right = left + 1
		var smallest = left
		if right < size and _heap_less(dists[right], nodes[right], dists[left], nodes[left]):
			smallest = right
		if _heap_less(dists[index], nodes[index], dists[smallest], nodes[smallest]):
			break
		var tmp_node = nodes[index]
		var tmp_dist = dists[index]
		nodes[index] = nodes[smallest]
		dists[index] = dists[smallest]
		nodes[smallest] = tmp_node
		dists[smallest] = tmp_dist
		index = smallest

static func _heap_less(dist_a: int, node_a: int, dist_b: int, node_b: int) -> bool:
	if dist_a == dist_b:
		return node_a <= node_b
	return dist_a < dist_b

static func _schedule_projectile(
		pid: int,
		p_type: int,
		target_tile: int,
		shooter_id: int,
		tick: int,
		width: int,
		unit_x: PackedInt32Array,
		unit_y: PackedInt32Array,
		projectiles_by_tick: Array,
		projectile_type: PackedInt32Array,
		projectile_target_tile: PackedInt32Array,
		projectile_shooter_id: PackedInt32Array,
		projectile_impact_tick: PackedInt32Array
	) -> int:
	var sx = unit_x[shooter_id]
	var sy = unit_y[shooter_id]
	var tx = target_tile % width
	var ty = target_tile / width
	var distance = abs(tx - sx) + abs(ty - sy)
	var speed = BattleConstants.PROJECTILE_SPEED[p_type]
	var impact_tick = tick + (speed * distance)
	projectile_type.append(p_type)
	projectile_target_tile.append(target_tile)
	projectile_shooter_id.append(shooter_id)
	projectile_impact_tick.append(impact_tick)
	if impact_tick >= 0:
		if impact_tick >= projectiles_by_tick.size():
			var old_size = projectiles_by_tick.size()
			projectiles_by_tick.resize(impact_tick + 1)
			for i in range(old_size, projectiles_by_tick.size()):
				projectiles_by_tick[i] = []
		projectiles_by_tick[impact_tick].append(pid)
	return impact_tick

static func _pick_random_unit(tile_list: Array, rng) -> int:
	if tile_list.is_empty():
		return -1
	var index = rng.next_range(tile_list.size())
	return tile_list[index]

static func _remove_unit(
		unit_id: int,
		tick: int,
		seq: int,
		event_type: int,
		reason: int,
		source_id: int,
		width: int,
		side: PackedInt32Array,
		unit_size: PackedInt32Array,
		unit_x: PackedInt32Array,
		unit_y: PackedInt32Array,
		alive: PackedInt32Array,
		units_remaining: PackedInt32Array,
		occupancy_version: PackedInt32Array,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		tile_total_size: PackedInt32Array,
		tile_units: Array,
		event_log
	) -> void:
	if alive[unit_id] == 0:
		return
	alive[unit_id] = 0
	units_remaining[side[unit_id]] -= 1
	occupancy_version[side[unit_id]] += 1
	var tile_index = unit_x[unit_id] + unit_y[unit_id] * width
	_remove_unit_from_tile(tile_index, unit_id, unit_size[unit_id], tile_side, tile_unit_count, tile_total_size, tile_units)
	event_log.add_event(
		tick,
		seq,
		event_type,
		unit_id,
		reason,
		source_id,
		BattleConstants.encode_pos(unit_x[unit_id], unit_y[unit_id])
	)

class IntentSorter:
	var unit_squad_index: PackedInt32Array
	var unit_squad_id: PackedInt32Array
	var unit_rank: PackedInt32Array

	func _init(unit_squad_index_in: PackedInt32Array, unit_squad_id_in: PackedInt32Array, unit_rank_in: PackedInt32Array) -> void:
		unit_squad_index = unit_squad_index_in
		unit_squad_id = unit_squad_id_in
		unit_rank = unit_rank_in

	func less(a: int, b: int) -> bool:
		var squad_a = unit_squad_index[a]
		var squad_b = unit_squad_index[b]
		var has_a = squad_a != -1
		var has_b = squad_b != -1
		if has_a != has_b:
			return has_a
		if has_a:
			var id_a = unit_squad_id[a]
			var id_b = unit_squad_id[b]
			if id_a != id_b:
				return id_a < id_b
			var rank_a = unit_rank[a]
			var rank_b = unit_rank[b]
			if rank_a != rank_b:
				return rank_a < rank_b
		return a < b

class FieldCache:
	var dist = PackedInt32Array()
	var initialized: bool = false
	var last_build_tick: int = -MAX_STALE_TICKS
	var built_terrain_version: int = -1
	var built_enemy_occupancy_version: int = -1
	var force_rebuild: bool = false
	var build_count: int = 0
	var build_time_usec: int = 0
