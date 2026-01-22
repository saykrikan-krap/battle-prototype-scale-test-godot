extends Node2D

const BattleConstants = preload("res://schema/constants.gd")
const BattleResolver = preload("res://resolver/battle_resolver.gd")
const BattleReplayer = preload("res://replayer/battle_replayer.gd")
const BattleView = preload("res://replayer/battle_view.gd")
const BattleUI = preload("res://ui/battle_ui.gd")
const ScaleTestV1 = preload("res://scenarios/scale_test_v1.gd")

const DEFAULT_TPS = 20

var _battle_view
var _battle_ui
var _replayer
var _resolver_thread: Thread
var _resolving: bool = false
var _last_result
var _last_event_log
var _current_tps: int = DEFAULT_TPS

func _ready() -> void:
	var args = OS.get_cmdline_args()
	if "--resolve-only" in args:
		_run_headless_resolve()
		return

	_battle_view = BattleView.new()
	add_child(_battle_view)

	_battle_ui = BattleUI.new()
	add_child(_battle_ui)
	_battle_ui.resolve_requested.connect(_start_resolve)
	_battle_ui.play_toggled.connect(_on_play_toggled)
	_battle_ui.step_requested.connect(_on_step_requested)
	_battle_ui.speed_changed.connect(_on_speed_changed)

	_start_resolve()

func _process(delta: float) -> void:
	if _resolving and _resolver_thread != null and not _resolver_thread.is_alive():
		var result = _resolver_thread.wait_to_finish()
		_resolving = false
		_battle_ui.set_resolving(false)
		_on_resolve_complete(result)

	if _replayer != null and not _resolving:
		_replayer.update(delta)
		_battle_view.render(_replayer)

	_update_debug_overlay()

func _start_resolve() -> void:
	if _resolving:
		return
	_resolving = true
	_battle_ui.set_resolving(true)
	_battle_ui.set_playing(false)
	_replayer = null
	_last_event_log = null
	_last_result = null

	_resolver_thread = Thread.new()
	_resolver_thread.start(Callable(self, "_resolve_task"))

func _resolve_task() -> Dictionary:
	var input = ScaleTestV1.build()
	return BattleResolver.resolve(input)

func _on_resolve_complete(result: Dictionary) -> void:
	_last_event_log = result.get("event_log", null)
	_last_result = result.get("result", null)
	if _last_event_log == null:
		return
	_replayer = BattleReplayer.new()
	_replayer.initialize_from_log(_last_event_log)
	_replayer.set_ticks_per_second(_current_tps)
	_replayer.set_playing(true)
	_battle_ui.set_playing(true)

func _on_play_toggled(playing: bool) -> void:
	if _replayer == null:
		return
	_replayer.set_playing(playing)

func _on_step_requested() -> void:
	if _replayer == null:
		return
	_replayer.step_tick()

func _on_speed_changed(tps: int) -> void:
	_current_tps = tps
	if _replayer != null:
		_replayer.set_ticks_per_second(tps)

func _update_debug_overlay() -> void:
	if _battle_ui == null:
		return
	var lines = []
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	if _replayer != null:
		lines.append("Tick: %d" % _replayer.current_tick)
		lines.append("Alive: R %d / B %d" % [_replayer.units_remaining[BattleConstants.Side.RED], _replayer.units_remaining[BattleConstants.Side.BLUE]])
	if _last_event_log != null:
		lines.append("Events: %d" % _last_event_log.count())
	if _last_result != null:
		lines.append("Resolve: %d ms (%.1f tps)" % [_last_result.resolve_ms, _last_result.avg_ticks_per_sec])
		lines.append("Log hash: %08x" % _last_result.event_hash)
		lines.append("Winner: %s" % _winner_name(_last_result.winner))
	if _resolving:
		lines.append("Resolving...")
	_battle_ui.set_debug_text("\n".join(lines))

func _winner_name(winner: int) -> String:
	if winner == BattleConstants.Side.RED:
		return "Red"
	if winner == BattleConstants.Side.BLUE:
		return "Blue"
	return "Draw"

func _run_headless_resolve() -> void:
	var input = ScaleTestV1.build()
	var result = BattleResolver.resolve(input)
	var battle_result = result.get("result", null)
	if battle_result != null:
		print("Resolved ticks: %d" % battle_result.ticks_elapsed)
		print("Winner: %s" % _winner_name(battle_result.winner))
		print("Units remaining: R %d / B %d" % [battle_result.units_remaining_by_side[BattleConstants.Side.RED], battle_result.units_remaining_by_side[BattleConstants.Side.BLUE]])
		print("Resolve ms: %d" % battle_result.resolve_ms)
		print("Avg ticks/sec: %.2f" % battle_result.avg_ticks_per_sec)
		print("Event count: %d" % battle_result.event_count)
		print("Event hash: %08x" % battle_result.event_hash)
	get_tree().quit()
