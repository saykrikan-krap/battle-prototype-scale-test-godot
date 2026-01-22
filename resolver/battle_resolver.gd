class_name BattleResolver
extends Object

const BattleConstants = preload("res://schema/constants.gd")
const XorShift32 = preload("res://schema/prng.gd")
const EventLog = preload("res://schema/event_log.gd")
const BattleResult = preload("res://schema/battle_result.gd")

const INF_DISTANCE = 1_000_000
const STALL_TICK_LIMIT = 0
const SOFT_COST_EMPTY = 1
const SOFT_COST_FRIENDLY_PER_UNIT = 1

static func resolve(input) -> Dictionary:
	var start_ms = Time.get_ticks_msec()
	var rng = XorShift32.new(input.seed)
	var event_log = EventLog.new()

	var width = input.grid_width
	var height = input.grid_height
	var tile_count = width * height
	var unit_count = input.unit_count()

	event_log.add_event(
		0,
		0,
		BattleConstants.EventType.BATTLE_INIT,
		width,
		height,
		input.time_limit_ticks,
		unit_count
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

	var neighbors = _build_neighbors(width, height)

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
		var activity = false

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

		if units_remaining[BattleConstants.Side.RED] == 0 or units_remaining[BattleConstants.Side.BLUE] == 0:
			post_battle = true

		if post_battle:
			if in_flight_projectiles <= 0:
				break
			tick += 1
			continue

		var dist_red_size2 = _compute_distance_field(
			width,
			height,
			BattleConstants.Side.RED,
			2,
			tile_side,
			tile_unit_count,
			tile_total_size,
			input.max_units_per_tile,
			input.max_total_size_per_tile,
			neighbors
		)
		var dist_red_size3 = _compute_distance_field(
			width,
			height,
			BattleConstants.Side.RED,
			3,
			tile_side,
			tile_unit_count,
			tile_total_size,
			input.max_units_per_tile,
			input.max_total_size_per_tile,
			neighbors
		)
		var dist_blue_size2 = _compute_distance_field(
			width,
			height,
			BattleConstants.Side.BLUE,
			2,
			tile_side,
			tile_unit_count,
			tile_total_size,
			input.max_units_per_tile,
			input.max_total_size_per_tile,
			neighbors
		)
		var dist_blue_size3 = _compute_distance_field(
			width,
			height,
			BattleConstants.Side.BLUE,
			3,
			tile_side,
			tile_unit_count,
			tile_total_size,
			input.max_units_per_tile,
			input.max_total_size_per_tile,
			neighbors
		)

		for id in range(unit_count):
			if alive[id] == 0:
				continue
			if next_tick[id] > tick:
				continue

			var u_type = unit_type[id]
			var u_side = side[id]
			var ux = unit_x[id]
			var uy = unit_y[id]
			var enemy_side = BattleConstants.enemy_side(u_side)

			var current_tile = ux + uy * width
			var target_tile = _find_adjacent_enemy(current_tile, enemy_side, tile_side, neighbors)
			var acted = false

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
							tile_side,
							tile_unit_count,
							tile_total_size,
							tile_units,
							event_log
						)
						activity = true
				acted = true
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
					next_tick[id] = tick + BattleConstants.ATTACK_COST[u_type]
					continue

			if not acted:
				var dist_field = dist_red_size2
				if u_side == BattleConstants.Side.RED:
					dist_field = dist_red_size3 if unit_size[id] == 3 else dist_red_size2
				else:
					dist_field = dist_blue_size3 if unit_size[id] == 3 else dist_blue_size2

				var best_tile = _choose_move_tile(
					current_tile,
					u_side,
					unit_size[id],
					dist_field,
					tile_side,
					tile_unit_count,
					tile_total_size,
					input.max_units_per_tile,
					input.max_total_size_per_tile,
					neighbors
				)
				if best_tile != -1:
					var from_pos = BattleConstants.encode_pos(ux, uy)
					var new_x = best_tile % width
					var new_y = best_tile / width
					_remove_unit_from_tile(current_tile, id, unit_size[id], tile_side, tile_unit_count, tile_total_size, tile_units)
					_add_unit_to_tile(best_tile, id, u_side, unit_size[id], tile_side, tile_unit_count, tile_total_size, tile_units)
					unit_x[id] = new_x
					unit_y[id] = new_y
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
					next_tick[id] = tick + BattleConstants.MOVE_COST[u_type]
				else:
					next_tick[id] = tick + BattleConstants.WAIT_COST[u_type]

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

	return {
		"event_log": event_log,
		"result": result,
	}

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

static func _is_melee_unit(u_type: int) -> bool:
	return u_type == BattleConstants.UnitType.INFANTRY \
		or u_type == BattleConstants.UnitType.HEAVY_INFANTRY \
		or u_type == BattleConstants.UnitType.ELITE_INFANTRY \
		or u_type == BattleConstants.UnitType.CAVALRY \
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

static func _compute_distance_field(
		width: int,
		height: int,
		unit_side: int,
		unit_size: int,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		tile_total_size: PackedInt32Array,
		max_units: int,
		max_total_size: int,
		neighbors: Array
	) -> PackedInt32Array:
	var tile_count = width * height
	var dist = PackedInt32Array()
	dist.resize(tile_count)
	for i in range(tile_count):
		dist[i] = INF_DISTANCE

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
			var side_value = tile_side[neighbor]
			if side_value != -1 and side_value != unit_side:
				continue
			var step_cost = SOFT_COST_EMPTY
			if side_value == unit_side:
				step_cost = SOFT_COST_EMPTY + (tile_unit_count[neighbor] * SOFT_COST_FRIENDLY_PER_UNIT)
			var next_dist = base_dist + step_cost
			if next_dist < dist[neighbor]:
				dist[neighbor] = next_dist
				_heap_push(heap_nodes, heap_dists, neighbor, next_dist)
	return dist

static func _heap_push(nodes: PackedInt32Array, dists: PackedInt32Array, node: int, dist: int) -> void:
	nodes.append(node)
	dists.append(dist)
	var index = nodes.size() - 1
	while index > 0:
		var parent = (index - 1) / 2
		if dists[parent] <= dist:
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
		if right < size and dists[right] < dists[left]:
			smallest = right
		if dists[index] <= dists[smallest]:
			break
		var tmp_node = nodes[index]
		var tmp_dist = dists[index]
		nodes[index] = nodes[smallest]
		dists[index] = dists[smallest]
		nodes[smallest] = tmp_node
		dists[smallest] = tmp_dist
		index = smallest

static func _choose_move_tile(
		current_tile: int,
		unit_side: int,
		unit_size: int,
		dist_field: PackedInt32Array,
		tile_side: PackedInt32Array,
		tile_unit_count: PackedInt32Array,
		tile_total_size: PackedInt32Array,
		max_units: int,
		max_total_size: int,
		neighbors: Array
	) -> int:
	var best_tile = -1
	var best_dist = INF_DISTANCE
	var current_dist = dist_field[current_tile]
	for neighbor in neighbors[current_tile]:
		var dist = dist_field[neighbor]
		if dist < best_dist and dist < current_dist and _tile_can_accept(neighbor, unit_side, unit_size, tile_side, tile_unit_count, tile_total_size, max_units, max_total_size):
			best_dist = dist
			best_tile = neighbor
	return best_tile

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
