class_name BattleResult
extends Object

var winner: int = -1
var ticks_elapsed: int = 0
var units_remaining_by_side = PackedInt32Array([0, 0])
var resolve_ms: int = 0
var avg_ticks_per_sec: float = 0.0
var event_count: int = 0
var event_hash: int = 0
