class_name XorShift32
extends Object

var _state: int

func _init(seed: int) -> void:
	_state = seed & 0xFFFFFFFF
	if _state == 0:
		_state = 0x6D2B79F5

func next_u32() -> int:
	var x = _state
	x = (x ^ ((x << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x ^ ((x >> 17) & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x ^ ((x << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF
	_state = x
	return _state

func next_range(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return int(next_u32() % max_exclusive)
