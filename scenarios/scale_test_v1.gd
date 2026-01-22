class_name ScaleTestV1
extends Object

const BattleConstants = preload("res://schema/constants.gd")
const BattleInput = preload("res://schema/battle_input.gd")

const GRID_WIDTH = 42
const GRID_HEIGHT = 20
const DEPLOY_WIDTH = 15
const DEPLOY_HEIGHT = 20
const RED_ZONE_START = 0
const BLUE_ZONE_START = 27

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

	var next_id = 0
	next_id = _populate_side(input, BattleConstants.Side.RED, RED_ZONE_START, next_id)
	next_id = _populate_side(input, BattleConstants.Side.BLUE, BLUE_ZONE_START, next_id)
	return input

static func _populate_side(input, side: int, zone_start: int, next_id: int) -> int:
	var front_is_high = side == BattleConstants.Side.RED

	var flank_front_cols = []
	var flank_back_cols = []
	if front_is_high:
		flank_front_cols = [zone_start + 12, zone_start + 13, zone_start + 14]
		flank_back_cols = [zone_start + 0, zone_start + 1, zone_start + 2]
	else:
		flank_front_cols = [zone_start + 0, zone_start + 1, zone_start + 2]
		flank_back_cols = [zone_start + 12, zone_start + 13, zone_start + 14]

	var center_cols = []
	for x in range(zone_start + 3, zone_start + 12):
		center_cols.append(x)

	var flank_positions = []
	flank_positions.append_array(_positions_from_columns(_order_columns(flank_front_cols, front_is_high), 3))
	flank_positions.append_array(_positions_from_columns(_order_columns(flank_back_cols, front_is_high), 3))

	var center_positions = _positions_from_columns(_order_columns(center_cols, front_is_high), 4)

	var flank_index = 0
	var center_index = 0

	var result = _add_units(input, side, BattleConstants.UnitType.CAVALRY, 150, flank_positions, flank_index, next_id)
	flank_index = result.pos_index
	next_id = result.next_id

	result = _add_units(input, side, BattleConstants.UnitType.HEAVY_CAVALRY, 150, flank_positions, flank_index, next_id)
	flank_index = result.pos_index
	next_id = result.next_id

	result = _add_units(input, side, BattleConstants.UnitType.HEAVY_INFANTRY, 150, center_positions, center_index, next_id)
	center_index = result.pos_index
	next_id = result.next_id

	result = _add_units(input, side, BattleConstants.UnitType.INFANTRY, 150, center_positions, center_index, next_id)
	center_index = result.pos_index
	next_id = result.next_id

	result = _add_units(input, side, BattleConstants.UnitType.ELITE_INFANTRY, 150, center_positions, center_index, next_id)
	center_index = result.pos_index
	next_id = result.next_id

	result = _add_units(input, side, BattleConstants.UnitType.ARCHER, 200, center_positions, center_index, next_id)
	center_index = result.pos_index
	next_id = result.next_id

	result = _add_units(input, side, BattleConstants.UnitType.MAGE, 50, center_positions, center_index, next_id)
	center_index = result.pos_index
	next_id = result.next_id

	return next_id

static func _order_columns(columns: Array, front_is_high: bool) -> Array:
	var ordered = columns.duplicate()
	ordered.sort()
	if front_is_high:
		ordered.reverse()
	return ordered

static func _positions_from_columns(columns: Array, slots_per_tile: int) -> Array:
	var positions = []
	for x in columns:
		for y in range(DEPLOY_HEIGHT):
			for slot in range(slots_per_tile):
				positions.append(Vector2i(x, y))
	return positions

static func _add_units(
		input,
		side: int,
		unit_type: int,
		count: int,
		positions: Array,
		pos_index: int,
		next_id: int
	) -> Dictionary:
	var unit_size = BattleConstants.UNIT_SIZE[unit_type]
	for i in range(count):
		var pos: Vector2i = positions[pos_index]
		pos_index += 1
		input.unit_ids.append(next_id)
		input.unit_sides.append(side)
		input.unit_types.append(unit_type)
		input.unit_sizes.append(unit_size)
		input.unit_x.append(pos.x)
		input.unit_y.append(pos.y)
		input.unit_next_tick.append(0)
		next_id += 1
	return {
		"pos_index": pos_index,
		"next_id": next_id,
	}
