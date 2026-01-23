class_name BattleInput
extends Object

var grid_width: int
var grid_height: int
var max_units_per_tile: int
var max_total_size_per_tile: int
var seed: int
var time_limit_ticks: int

var unit_ids = PackedInt32Array()
var unit_sides = PackedInt32Array()
var unit_types = PackedInt32Array()
var unit_sizes = PackedInt32Array()
var unit_x = PackedInt32Array()
var unit_y = PackedInt32Array()
var unit_next_tick = PackedInt32Array()
var unit_squad_ids = PackedInt32Array()
var unit_slot_dx = PackedInt32Array()
var unit_slot_dy = PackedInt32Array()

var tile_terrain = PackedInt32Array()

var squad_ids = PackedInt32Array()
var squad_sides = PackedInt32Array()
var squad_formations = PackedInt32Array()

func unit_count() -> int:
	return unit_ids.size()
