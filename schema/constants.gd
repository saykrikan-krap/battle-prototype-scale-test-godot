class_name BattleConstants
extends Object

enum Side {
	RED = 0,
	BLUE = 1,
}

enum Facing {
	LEFT = 0,
	RIGHT = 1,
}

enum Dir {
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3,
}

enum UnitType {
	INFANTRY = 0,
	HEAVY_INFANTRY = 1,
	ELITE_INFANTRY = 2,
	ARCHER = 3,
	CAVALRY = 4,
	HEAVY_CAVALRY = 5,
	MAGE = 6,
}

enum TerrainType {
	GRASS = 0,
	TREES = 1,
	WATER = 2,
}

enum EventType {
	BATTLE_INIT = 0,
	UNIT_SPAWNED = 1,
	UNIT_MOVED = 2,
	MELEE_ATTACK_RESOLVED = 3,
	PROJECTILE_FIRED = 4,
	PROJECTILE_IMPACTED = 5,
	UNIT_REMOVED = 6,
	BATTLE_ENDED = 7,
	SQUAD_DEBUG = 8,
	TERRAIN_SET = 9,
}

enum ProjectileType {
	ARROW = 0,
	FIREBALL = 1,
}

enum Formation {
	SQUARE = 0,
}

static var UNIT_SIZE = PackedInt32Array([2, 2, 2, 2, 3, 3, 2])
static var MOVE_COST = PackedInt32Array([6, 7, 6, 6, 4, 5, 6])
static var ATTACK_COST = PackedInt32Array([12, 13, 11, 14, 12, 13, 16])
static var WAIT_COST = PackedInt32Array([1, 1, 1, 1, 1, 1, 1])
static var MELEE_HIT_CHANCE = PackedInt32Array([50, 55, 60, 0, 50, 55, 0])
static var RANGED_RANGE = PackedInt32Array([0, 0, 0, 10, 0, 0, 20])
static var PROJECTILE_SPEED = PackedInt32Array([2, 3])
static var DEFAULT_FACING = PackedInt32Array([Facing.RIGHT, Facing.LEFT])

const MAX_SQUAD_SIZE = 50
static var TERRAIN_COST = PackedInt32Array([1, 2, 1])

const NEIGHBOR_DIRS = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

static func enemy_side(side: int) -> int:
	return Side.BLUE if side == Side.RED else Side.RED

static func encode_pos(x: int, y: int) -> int:
	return (y << 16) | (x & 0xFFFF)

static func decode_x(pos: int) -> int:
	return pos & 0xFFFF

static func decode_y(pos: int) -> int:
	return (pos >> 16) & 0xFFFF

static func tile_index(x: int, y: int, width: int) -> int:
	return x + y * width

static func index_to_x(index: int, width: int) -> int:
	return index % width

static func index_to_y(index: int, width: int) -> int:
	return index / width
