class_name BattleView
extends Node2D

const BattleConstants = preload("res://schema/constants.gd")

const TILE_SIZE = 24.0
const VIEW_SCALE = 2.0
const MIN_ZOOM = 0.6
const MAX_ZOOM = 4.0
const ZOOM_STEP = 0.15
const PAN_SPEED = 700.0
const UNIT_SCALE = 0.42
const PROJECTILE_SCALE = 0.2
const OVERLAY_RED = Color(0.85, 0.2, 0.2, 0.18)
const OVERLAY_BLUE = Color(0.2, 0.45, 0.9, 0.18)
const DEPLOY_RED = Color(0.9, 0.25, 0.25, 0.1)
const DEPLOY_BLUE = Color(0.25, 0.5, 0.95, 0.1)
const GHOST_ALPHA = 0.35
const GHOST_INVALID_ALPHA = 0.55

const UNIT_TEXTURE_PATHS = [
	"res://assets/sprites/units/infantry.png",
	"res://assets/sprites/units/heavy_infantry.png",
	"res://assets/sprites/units/elite_infantry.png",
	"res://assets/sprites/units/archer.png",
	"res://assets/sprites/units/cavalry.png",
	"res://assets/sprites/units/heavy_cavalry.png",
	"res://assets/sprites/units/mage.png",
]

const UNIT_FALLBACK_COLORS = [
	Color(0.78, 0.78, 0.82),
	Color(0.46, 0.48, 0.52),
	Color(0.9, 0.78, 0.26),
	Color(0.24, 0.7, 0.3),
	Color(0.25, 0.46, 0.9),
	Color(0.12, 0.25, 0.62),
	Color(0.9, 0.45, 0.15),
]

const SLOT_OFFSETS_RIGHT = [
	Vector2(0.25, -0.25),
	Vector2(0.25, 0.25),
	Vector2(-0.25, -0.25),
	Vector2(-0.25, 0.25),
]

const SLOT_OFFSETS_LEFT = [
	Vector2(-0.25, -0.25),
	Vector2(-0.25, 0.25),
	Vector2(0.25, -0.25),
	Vector2(0.25, 0.25),
]

var grid_width: int = 0
var grid_height: int = 0

var _unit_textures = []
var _projectile_texture: Texture2D
var _unit_meshes = []
var _projectile_meshes = []
var _ghost_meshes = []
var _ghost_units = []
var _ghost_valid: bool = true
var _deploy_red_rect: Rect2i = Rect2i()
var _deploy_blue_rect: Rect2i = Rect2i()
var _show_deploy_zones: bool = false
var _zoom: float = VIEW_SCALE
var _tile_side = PackedInt32Array()
var _hovered_tile = Vector2i(-1, -1)

func _ready() -> void:
	_zoom = VIEW_SCALE
	scale = Vector2(_zoom, _zoom)

func _input(event) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(_zoom + ZOOM_STEP, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(_zoom - ZOOM_STEP, event.position)

func _process(delta: float) -> void:
	_update_hovered_tile()
	var direction = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if direction != Vector2.ZERO:
		var pan_scale = 1.0
		if _zoom < 1.0:
			pan_scale = 1.0 / _zoom
		position -= direction.normalized() * (PAN_SPEED * delta * pan_scale)

func _update_hovered_tile() -> void:
	if grid_width <= 0 or grid_height <= 0:
		if _hovered_tile.x != -1:
			_hovered_tile = Vector2i(-1, -1)
			queue_redraw()
		return
	var local = get_local_mouse_position()
	var tile_x = int(floor(local.x / TILE_SIZE))
	var tile_y = int(floor(local.y / TILE_SIZE))
	var next_tile = Vector2i(-1, -1)
	if local.x >= 0.0 and local.y >= 0.0 and tile_x < grid_width and tile_y < grid_height:
		next_tile = Vector2i(tile_x, tile_y)
	if next_tile != _hovered_tile:
		_hovered_tile = next_tile
		queue_redraw()

func get_hovered_tile() -> Vector2i:
	return _hovered_tile

func set_ghost_units(units: Array, valid: bool) -> void:
	_ghost_units = units
	_ghost_valid = valid
	_update_ghost_meshes()

func set_deployment_zones(red_rect: Rect2i, blue_rect: Rect2i, visible: bool) -> void:
	_deploy_red_rect = red_rect
	_deploy_blue_rect = blue_rect
	_show_deploy_zones = visible
	queue_redraw()

func _apply_zoom(target_zoom: float, mouse_pos: Vector2) -> void:
	var clamped = clamp(target_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(clamped, _zoom):
		return
	var local = (mouse_pos - position) / _zoom
	_zoom = clamped
	scale = Vector2(_zoom, _zoom)
	position = mouse_pos - local * _zoom

func setup(width: int, height: int) -> void:
	if width == grid_width and height == grid_height and _unit_meshes.size() > 0:
		return
	grid_width = width
	grid_height = height
	_ensure_meshes()
	queue_redraw()

func _draw() -> void:
	if grid_width <= 0 or grid_height <= 0:
		return
	var total_width = grid_width * TILE_SIZE
	var total_height = grid_height * TILE_SIZE
	draw_rect(Rect2(0, 0, total_width, total_height), Color(0.08, 0.09, 0.12))

	if _show_deploy_zones:
		_draw_deploy_zone(_deploy_red_rect, DEPLOY_RED)
		_draw_deploy_zone(_deploy_blue_rect, DEPLOY_BLUE)

	if _tile_side.size() == grid_width * grid_height:
		for y in range(grid_height):
			for x in range(grid_width):
				var tile = x + y * grid_width
				var side = _tile_side[tile]
				if side == BattleConstants.Side.RED:
					draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), OVERLAY_RED)
				elif side == BattleConstants.Side.BLUE:
					draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), OVERLAY_BLUE)

	var line_color = Color(0.18, 0.2, 0.25)
	for x in range(grid_width + 1):
		var px = x * TILE_SIZE
		draw_line(Vector2(px, 0), Vector2(px, total_height), line_color)
	for y in range(grid_height + 1):
		var py = y * TILE_SIZE
		draw_line(Vector2(0, py), Vector2(total_width, py), line_color)
	if _hovered_tile.x >= 0:
		draw_rect(
			Rect2(_hovered_tile.x * TILE_SIZE, _hovered_tile.y * TILE_SIZE, TILE_SIZE, TILE_SIZE),
			Color(1, 1, 1, 0.9),
			false,
			2.0
		)

func _draw_deploy_zone(zone: Rect2i, color: Color) -> void:
	if zone.size.x <= 0 or zone.size.y <= 0:
		return
	draw_rect(
		Rect2(
			zone.position.x * TILE_SIZE,
			zone.position.y * TILE_SIZE,
			zone.size.x * TILE_SIZE,
			zone.size.y * TILE_SIZE
		),
		color
	)

func render(replayer) -> void:
	if replayer == null:
		return
	setup(replayer.grid_width, replayer.grid_height)
	if replayer.unit_alive.size() == 0:
		_clear_unit_meshes()
		_clear_projectile_meshes()
		_clear_tile_overlay()
		return

	_update_tile_overlay(replayer)
	_update_unit_meshes(replayer)
	_update_projectile_meshes(replayer)

func _ensure_meshes() -> void:
	if _unit_textures.size() == 0:
		_unit_textures.resize(UNIT_TEXTURE_PATHS.size())
		for i in range(UNIT_TEXTURE_PATHS.size()):
			_unit_textures[i] = _load_texture(UNIT_TEXTURE_PATHS[i], UNIT_FALLBACK_COLORS[i])

	if _projectile_texture == null:
		_projectile_texture = _make_color_texture(Color.WHITE)

	if _unit_meshes.size() == 0:
		for texture in _unit_textures:
			var instance = _make_multimesh_instance(texture, Color.WHITE)
			_unit_meshes.append(instance)
			add_child(instance)

	if _ghost_meshes.size() == 0:
		for texture in _unit_textures:
			var instance = _make_multimesh_instance(texture, Color.WHITE)
			instance.z_index = 2
			_ghost_meshes.append(instance)
			add_child(instance)

	if _projectile_meshes.size() == 0:
		var arrow = _make_multimesh_instance(_projectile_texture, Color(0.95, 0.9, 0.7))
		var fireball = _make_multimesh_instance(_projectile_texture, Color(0.95, 0.3, 0.1))
		_projectile_meshes.append(arrow)
		_projectile_meshes.append(fireball)
		add_child(arrow)
		add_child(fireball)

func _load_texture(path: String, fallback_color: Color) -> Texture2D:
	var image = Image.new()
	var err = image.load(path)
	if err != OK:
		push_warning("Failed to load sprite %s (error %d)" % [path, err])
		return _make_color_texture(fallback_color)
	return ImageTexture.create_from_image(image)

func _make_color_texture(color: Color) -> Texture2D:
	var image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func _make_multimesh_instance(texture: Texture2D, color: Color) -> MultiMeshInstance2D:
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	multimesh.mesh = quad
	multimesh.instance_count = 0

	var instance = MultiMeshInstance2D.new()
	instance.multimesh = multimesh
	instance.texture = texture
	instance.modulate = color
	return instance

func _clear_unit_meshes() -> void:
	_ensure_meshes()
	for mesh in _unit_meshes:
		mesh.multimesh.instance_count = 0

func _clear_projectile_meshes() -> void:
	_ensure_meshes()
	for mesh in _projectile_meshes:
		mesh.multimesh.instance_count = 0

func _clear_tile_overlay() -> void:
	if grid_width <= 0 or grid_height <= 0:
		return
	var tile_count = grid_width * grid_height
	if _tile_side.size() != tile_count:
		_tile_side.resize(tile_count)
	for i in range(tile_count):
		_tile_side[i] = -1
	queue_redraw()

func _update_unit_meshes(replayer) -> void:
	var unit_count = replayer.unit_alive.size()
	var type_counts = PackedInt32Array()
	type_counts.resize(_unit_meshes.size())
	for i in range(_unit_meshes.size()):
		type_counts[i] = 0

	for id in range(unit_count):
		if replayer.unit_alive[id] == 1:
			type_counts[replayer.unit_type[id]] += 1

	for t in range(_unit_meshes.size()):
		_unit_meshes[t].multimesh.instance_count = type_counts[t]

	var type_offsets = PackedInt32Array()
	type_offsets.resize(_unit_meshes.size())
	for t in range(_unit_meshes.size()):
		type_offsets[t] = 0

	var tile_slots = PackedInt32Array()
	tile_slots.resize(grid_width * grid_height)
	for i in range(tile_slots.size()):
		tile_slots[i] = 0

	var alpha = replayer.tick_alpha()
	var unit_pixel_size = TILE_SIZE * UNIT_SCALE
	var half_unit = Vector2(unit_pixel_size * 0.5, unit_pixel_size * 0.5)

	for id in range(unit_count):
		if replayer.unit_alive[id] == 0:
			continue
		var ux = replayer.unit_x[id]
		var uy = replayer.unit_y[id]
		var tile = ux + uy * grid_width
		var slot = tile_slots[tile]
		tile_slots[tile] = slot + 1
		var facing = BattleConstants.DEFAULT_FACING[replayer.unit_side[id]]
		if replayer.tile_facing.size() == grid_width * grid_height:
			var tile_facing = replayer.tile_facing[tile]
			if tile_facing != -1:
				facing = tile_facing
		var offset = _slot_offset(slot, facing)

		var to_pos = _tile_center(ux, uy) + offset
		var draw_pos = to_pos
		if replayer.last_move_tick[id] == replayer.current_tick:
			var from_pos = _tile_center(replayer.prev_x[id], replayer.prev_y[id]) + offset
			draw_pos = from_pos.lerp(to_pos, alpha)

		var t = replayer.unit_type[id]
		var idx = type_offsets[t]
		type_offsets[t] = idx + 1
		var color = Color(1, 1, 1, 1)
		if replayer.last_attack_tick.size() == unit_count:
			var last_attack = replayer.last_attack_tick[id]
			if last_attack >= 0 and last_attack == replayer.current_tick:
				color = Color(1.0, 0.35, 0.2, 1.0)

		var transform = Transform2D.IDENTITY
		transform = transform.scaled(Vector2(unit_pixel_size, unit_pixel_size))
		transform.origin = draw_pos - half_unit
		_unit_meshes[t].multimesh.set_instance_transform_2d(idx, transform)
		_unit_meshes[t].multimesh.set_instance_color(idx, color)

func _update_ghost_meshes() -> void:
	_ensure_meshes()
	var type_counts = PackedInt32Array()
	type_counts.resize(_ghost_meshes.size())
	for i in range(_ghost_meshes.size()):
		type_counts[i] = 0

	for entry in _ghost_units:
		var unit_type = int(entry["type"])
		if unit_type >= 0 and unit_type < type_counts.size():
			type_counts[unit_type] += 1

	for t in range(_ghost_meshes.size()):
		_ghost_meshes[t].multimesh.instance_count = type_counts[t]

	var type_offsets = PackedInt32Array()
	type_offsets.resize(_ghost_meshes.size())
	for t in range(_ghost_meshes.size()):
		type_offsets[t] = 0

	var unit_pixel_size = TILE_SIZE * UNIT_SCALE
	var half_unit = Vector2(unit_pixel_size * 0.5, unit_pixel_size * 0.5)
	var tint = Color(1, 1, 1, GHOST_ALPHA)
	if not _ghost_valid:
		tint = Color(1.0, 0.2, 0.2, GHOST_INVALID_ALPHA)

	for entry in _ghost_units:
		var unit_type = int(entry["type"])
		if unit_type < 0 or unit_type >= _ghost_meshes.size():
			continue
		var ux = int(entry["x"])
		var uy = int(entry["y"])
		var slot = int(entry["slot"])
		var side = int(entry["side"])
		var facing = BattleConstants.DEFAULT_FACING[side]
		var offset = _slot_offset(slot, facing)
		var draw_pos = _tile_center(ux, uy) + offset

		var idx = type_offsets[unit_type]
		type_offsets[unit_type] = idx + 1

		var transform = Transform2D.IDENTITY
		transform = transform.scaled(Vector2(unit_pixel_size, unit_pixel_size))
		transform.origin = draw_pos - half_unit
		_ghost_meshes[unit_type].multimesh.set_instance_transform_2d(idx, transform)
		_ghost_meshes[unit_type].multimesh.set_instance_color(idx, tint)

func _update_projectile_meshes(replayer) -> void:
	var count = replayer.projectile_ids.size()
	if count == 0:
		_projectile_meshes[0].multimesh.instance_count = 0
		_projectile_meshes[1].multimesh.instance_count = 0
		return

	var arrow_count = 0
	var fireball_count = 0
	for i in range(count):
		if replayer.projectile_type[i] == BattleConstants.ProjectileType.ARROW:
			arrow_count += 1
		else:
			fireball_count += 1

	_projectile_meshes[0].multimesh.instance_count = arrow_count
	_projectile_meshes[1].multimesh.instance_count = fireball_count

	var arrow_index = 0
	var fireball_index = 0
	var time = float(replayer.current_tick) + replayer.tick_alpha()
	var projectile_pixel_size = TILE_SIZE * PROJECTILE_SCALE
	var half_projectile = Vector2(projectile_pixel_size * 0.5, projectile_pixel_size * 0.5)

	for i in range(count):
		var p_type = replayer.projectile_type[i]
		var from_pos = replayer.projectile_from[i]
		var to_pos = replayer.projectile_to[i]
		var fire_tick = replayer.projectile_fire_tick[i]
		var impact_tick = replayer.projectile_impact_tick[i]
		var total = float(impact_tick - fire_tick)
		var t = 1.0
		if total > 0.0:
			t = clamp((time - float(fire_tick)) / total, 0.0, 1.0)

		var from_world = _tile_center(
			BattleConstants.decode_x(from_pos),
			BattleConstants.decode_y(from_pos)
		)
		var to_world = _tile_center(
			BattleConstants.decode_x(to_pos),
			BattleConstants.decode_y(to_pos)
		)
		var draw_pos = from_world.lerp(to_world, t)

		var transform = Transform2D.IDENTITY
		transform = transform.scaled(Vector2(projectile_pixel_size, projectile_pixel_size))
		transform.origin = draw_pos - half_projectile

		if p_type == BattleConstants.ProjectileType.ARROW:
			_projectile_meshes[0].multimesh.set_instance_transform_2d(arrow_index, transform)
			_projectile_meshes[0].multimesh.set_instance_color(arrow_index, Color(1, 1, 1, 1))
			arrow_index += 1
		else:
			_projectile_meshes[1].multimesh.set_instance_transform_2d(fireball_index, transform)
			_projectile_meshes[1].multimesh.set_instance_color(fireball_index, Color(1, 1, 1, 1))
			fireball_index += 1

func _update_tile_overlay(replayer) -> void:
	var tile_count = grid_width * grid_height
	if _tile_side.size() != tile_count:
		_tile_side.resize(tile_count)
	for i in range(tile_count):
		_tile_side[i] = -1
	var unit_count = replayer.unit_alive.size()
	for id in range(unit_count):
		if replayer.unit_alive[id] == 0:
			continue
		var tile = replayer.unit_x[id] + replayer.unit_y[id] * grid_width
		_tile_side[tile] = replayer.unit_side[id]
	queue_redraw()

func _tile_center(x: int, y: int) -> Vector2:
	return Vector2((float(x) + 0.5) * TILE_SIZE, (float(y) + 0.5) * TILE_SIZE)

func _slot_offset(slot: int, facing: int) -> Vector2:
	var clamped = slot
	if clamped < 0:
		clamped = 0
	var offsets = SLOT_OFFSETS_LEFT if facing == BattleConstants.Facing.LEFT else SLOT_OFFSETS_RIGHT
	if clamped >= offsets.size():
		clamped = offsets.size() - 1
	return offsets[clamped] * TILE_SIZE
