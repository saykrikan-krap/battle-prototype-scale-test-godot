class_name EventLog
extends Object

var ticks = PackedInt32Array()
var seqs = PackedInt32Array()
var types = PackedInt32Array()
var a = PackedInt32Array()
var b = PackedInt32Array()
var c = PackedInt32Array()
var d = PackedInt32Array()

func add_event(tick: int, seq: int, event_type: int, a_val: int = 0, b_val: int = 0, c_val: int = 0, d_val: int = 0) -> void:
	ticks.append(tick)
	seqs.append(seq)
	types.append(event_type)
	a.append(a_val)
	b.append(b_val)
	c.append(c_val)
	d.append(d_val)

func count() -> int:
	return ticks.size()

func hash_u32() -> int:
	var h: int = 2166136261
	var size = ticks.size()
	for i in size:
		h = (h ^ ticks[i]) * 16777619
		h = (h ^ seqs[i]) * 16777619
		h = (h ^ types[i]) * 16777619
		h = (h ^ a[i]) * 16777619
		h = (h ^ b[i]) * 16777619
		h = (h ^ c[i]) * 16777619
		h = (h ^ d[i]) * 16777619
		h &= 0xFFFFFFFF
	return h
