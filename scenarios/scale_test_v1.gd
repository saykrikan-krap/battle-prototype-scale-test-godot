class_name ScaleTestV1
extends Object

const BattleConstants = preload("res://schema/constants.gd")
const BattleInput = preload("res://schema/battle_input.gd")

const GRID_WIDTH = 80
const GRID_HEIGHT = 40
const DEPLOY_WIDTH = 15
const DEPLOY_HEIGHT = 28
const RED_ZONE_START = 0
const BLUE_ZONE_START = GRID_WIDTH - DEPLOY_WIDTH

const MAX_UNITS_PER_TILE = 4
const MAX_TOTAL_SIZE_PER_TILE = 10
const TIME_LIMIT_TICKS = 5000

const DEFAULT_SEED = 12345

static func build(seed: int = DEFAULT_SEED):
	var input = BattleInput.new()
	input.grid_width = GRID_WIDTH
	input.grid_height = GRID_HEIGHT
	input.max_units_per_tile = MAX_UNITS_PER_TILE
	input.max_total_size_per_tile = MAX_TOTAL_SIZE_PER_TILE
	input.seed = seed
	input.time_limit_ticks = TIME_LIMIT_TICKS

	var next_unit_id = 0
	var next_squad_id = 0
	var result = _populate_side(input, BattleConstants.Side.RED, RED_ZONE_START, next_unit_id, next_squad_id)
	next_unit_id = result.next_unit_id
	next_squad_id = result.next_squad_id
	result = _populate_side(input, BattleConstants.Side.BLUE, BLUE_ZONE_START, next_unit_id, next_squad_id)
	return input

static func _populate_side(input, side: int, zone_start: int, next_unit_id: int, next_squad_id: int) -> Dictionary:
	var front_is_high = side == BattleConstants.Side.RED
	var zone_x_start = zone_start
	var zone_x_end = zone_start + DEPLOY_WIDTH - 1
	var zone_y_start = int((GRID_HEIGHT - DEPLOY_HEIGHT) / 2)
	var zone_y_end = zone_y_start + DEPLOY_HEIGHT - 1

	var squads = []
	var roster = [
		{"type": BattleConstants.UnitType.CAVALRY, "count": 150},
		{"type": BattleConstants.UnitType.HEAVY_CAVALRY, "count": 150},
		{"type": BattleConstants.UnitType.HEAVY_INFANTRY, "count": 150},
		{"type": BattleConstants.UnitType.INFANTRY, "count": 150},
		{"type": BattleConstants.UnitType.ELITE_INFANTRY, "count": 150},
		{"type": BattleConstants.UnitType.ARCHER, "count": 200},
		{"type": BattleConstants.UnitType.MAGE, "count": 50},
	]

	for entry in roster:
		var result = _add_squad_type(
			input,
			squads,
			side,
			entry["type"],
			entry["count"],
			next_unit_id,
			next_squad_id
		)
		next_unit_id = result.next_unit_id
		next_squad_id = result.next_squad_id

	_place_squads(
		input,
		squads,
		zone_x_start,
		zone_x_end,
		zone_y_start,
		zone_y_end,
		front_is_high
	)

	return {
		"next_unit_id": next_unit_id,
		"next_squad_id": next_squad_id,
	}

static func _add_squad_type(
		input,
		squads: Array,
		side: int,
		unit_type: int,
		count: int,
		next_unit_id: int,
		next_squad_id: int
	) -> Dictionary:
	var remaining = count
	var unit_size = BattleConstants.UNIT_SIZE[unit_type]

	while remaining > 0:
		var squad_size = min(BattleConstants.MAX_SQUAD_SIZE, remaining)
		var squad_id = next_squad_id
		next_squad_id += 1

		input.squad_ids.append(squad_id)
		input.squad_sides.append(side)
		input.squad_formations.append(BattleConstants.Formation.SQUARE)

		var squad_units = []
		for i in range(squad_size):
			var unit_id = next_unit_id
			next_unit_id += 1
			input.unit_ids.append(unit_id)
			input.unit_sides.append(side)
			input.unit_types.append(unit_type)
			input.unit_sizes.append(unit_size)
			input.unit_x.append(-1)
			input.unit_y.append(-1)
			input.unit_next_tick.append(0)
			input.unit_squad_ids.append(squad_id)
			squad_units.append(unit_id)

		squads.append({
			"id": squad_id,
			"units": squad_units,
		})
		remaining -= squad_size

	return {
		"next_unit_id": next_unit_id,
		"next_squad_id": next_squad_id,
	}

static func _place_squads(
		input,
		squads: Array,
		zone_x_start: int,
		zone_x_end: int,
		zone_y_start: int,
		zone_y_end: int,
		front_is_high: bool
	) -> void:
	var prepared = []
	var block_width = 0
	var block_height = 0
	for squad in squads:
		var unit_ids: Array = squad["units"]
		var tile_units = _pack_units_into_tiles(
			unit_ids,
			input.unit_sizes,
			input.max_units_per_tile,
			input.max_total_size_per_tile
		)
		var formation = _square_tile_positions(tile_units.size())
		prepared.append({
			"id": squad["id"],
			"tile_units": tile_units,
			"positions": formation["positions"],
			"width": formation["width"],
			"height": formation["height"],
			"tile_count": tile_units.size(),
		})
		block_width = max(block_width, int(formation["width"]))
		block_height = max(block_height, int(formation["height"]))

	if block_width <= 0 or block_height <= 0:
		push_error("Invalid squad block size.")
		return

	# Place squads into fixed blocks to guarantee no overlap at setup.
	var blocks_x = int(DEPLOY_WIDTH / block_width)
	var blocks_y = int(DEPLOY_HEIGHT / block_height)
	if blocks_x * blocks_y < prepared.size():
		push_error("Insufficient squad blocks for placement.")
		return

	for i in range(input.unit_x.size()):
		input.unit_x[i] = -1
		input.unit_y[i] = -1

	var block_origins = []
	for row in range(blocks_y):
		var y = zone_y_start + row * block_height
		if front_is_high:
			for col in range(blocks_x):
				var x = zone_x_start + (blocks_x - 1 - col) * block_width
				block_origins.append(Vector2i(x, y))
		else:
			for col in range(blocks_x):
				var x = zone_x_start + col * block_width
				block_origins.append(Vector2i(x, y))

	for i in range(prepared.size()):
		var squad = prepared[i]
		var block = block_origins[i]
		var positions: Array = squad["positions"]
		var tile_units: Array = squad["tile_units"]
		for j in range(positions.size()):
			var local = positions[j] as Vector2i
			var world_x = block.x + local.x
			if front_is_high:
				world_x = block.x + (block_width - 1 - local.x)
			var world_y = block.y + local.y
			for unit_id in tile_units[j]:
				input.unit_x[unit_id] = world_x
				input.unit_y[unit_id] = world_y

static func _pack_units_into_tiles(
		unit_ids: Array,
		unit_sizes: PackedInt32Array,
		max_units: int,
		max_total_size: int
	) -> Array:
	var tiles = []
	var current_units = []
	var current_count = 0
	var current_size = 0

	for unit_id in unit_ids:
		var size = unit_sizes[unit_id]
		if current_units.is_empty() or current_count + 1 > max_units or current_size + size > max_total_size:
			if not current_units.is_empty():
				tiles.append(current_units)
			current_units = []
			current_count = 0
			current_size = 0
		current_units.append(unit_id)
		current_count += 1
		current_size += size

	if not current_units.is_empty():
		tiles.append(current_units)

	return tiles

static func _square_tile_positions(tile_count: int) -> Dictionary:
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
