extends SceneTree

const SPRITE_SIZE = 32
const CENTER = Vector2i(SPRITE_SIZE / 2, SPRITE_SIZE / 2)

const OUTLINE = Color(0.07, 0.07, 0.08, 1.0)
const SYMBOL_LIGHT = Color(0.95, 0.95, 0.95, 1.0)
const SYMBOL_DARK = Color(0.12, 0.12, 0.14, 1.0)
const TRANSPARENT = Color(0, 0, 0, 0)

const COLOR_INFANTRY = Color(0.78, 0.78, 0.82, 1.0)
const COLOR_HEAVY_INFANTRY = Color(0.46, 0.48, 0.52, 1.0)
const COLOR_ELITE_INFANTRY = Color(0.9, 0.78, 0.26, 1.0)
const COLOR_ARCHER = Color(0.24, 0.7, 0.3, 1.0)
const COLOR_CAVALRY = Color(0.25, 0.46, 0.9, 1.0)
const COLOR_HEAVY_CAVALRY = Color(0.12, 0.25, 0.62, 1.0)
const COLOR_MAGE = Color(0.9, 0.45, 0.15, 1.0)

const OUTPUT_DIR = "res://assets/sprites/units"

func _init() -> void:
	_ensure_output_dir()
	_write_sprite("infantry.png", _make_infantry())
	_write_sprite("heavy_infantry.png", _make_heavy_infantry())
	_write_sprite("elite_infantry.png", _make_elite_infantry())
	_write_sprite("archer.png", _make_archer())
	_write_sprite("cavalry.png", _make_cavalry())
	_write_sprite("heavy_cavalry.png", _make_heavy_cavalry())
	_write_sprite("mage.png", _make_mage())
	print("Generated unit sprites in %s" % OUTPUT_DIR)
	quit()

func _ensure_output_dir() -> void:
	var root = DirAccess.open("res://")
	if root == null:
		push_error("Unable to open res://")
		return
	root.make_dir_recursive("assets/sprites/units")

func _write_sprite(filename: String, image: Image) -> void:
	var path = "%s/%s" % [OUTPUT_DIR, filename]
	var err = image.save_png(path)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])

func _new_canvas() -> Image:
	var image = Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(TRANSPARENT)
	return image

func _make_infantry() -> Image:
	var image = _new_canvas()
	_draw_circle(image, CENTER.x, CENTER.y, 13, OUTLINE)
	_draw_circle(image, CENTER.x, CENTER.y, 12, COLOR_INFANTRY)
	_draw_rect(image, CENTER.x - 2, CENTER.y - 6, 4, 12, SYMBOL_DARK)
	return image

func _make_heavy_infantry() -> Image:
	var image = _new_canvas()
	_draw_rect(image, CENTER.x - 13, CENTER.y - 13, 26, 26, OUTLINE)
	_draw_rect(image, CENTER.x - 12, CENTER.y - 12, 24, 24, COLOR_HEAVY_INFANTRY)
	_draw_rect(image, CENTER.x - 2, CENTER.y - 7, 4, 14, SYMBOL_LIGHT)
	_draw_rect(image, CENTER.x - 7, CENTER.y - 2, 14, 4, SYMBOL_LIGHT)
	return image

func _make_elite_infantry() -> Image:
	var image = _new_canvas()
	_draw_diamond(image, CENTER.x, CENTER.y, 13, OUTLINE)
	_draw_diamond(image, CENTER.x, CENTER.y, 12, COLOR_ELITE_INFANTRY)
	_draw_triangle_up(image, CENTER.x, CENTER.y - 5, 5, SYMBOL_DARK)
	return image

func _make_archer() -> Image:
	var image = _new_canvas()
	_draw_triangle_up(image, CENTER.x, CENTER.y, 13, OUTLINE)
	_draw_triangle_up(image, CENTER.x, CENTER.y, 12, COLOR_ARCHER)
	_draw_circle(image, CENTER.x, CENTER.y + 2, 3, SYMBOL_LIGHT)
	return image

func _make_cavalry() -> Image:
	var image = _new_canvas()
	_draw_circle(image, CENTER.x, CENTER.y, 13, OUTLINE)
	_draw_circle(image, CENTER.x, CENTER.y, 12, COLOR_CAVALRY)
	_draw_triangle_right(image, CENTER.x + 1, CENTER.y, 6, SYMBOL_LIGHT)
	return image

func _make_heavy_cavalry() -> Image:
	var image = _new_canvas()
	_draw_rect(image, CENTER.x - 13, CENTER.y - 13, 26, 26, OUTLINE)
	_draw_rect(image, CENTER.x - 12, CENTER.y - 12, 24, 24, COLOR_HEAVY_CAVALRY)
	_draw_line(image, CENTER.x - 7, CENTER.y - 7, CENTER.x + 7, CENTER.y + 7, SYMBOL_LIGHT, 3)
	return image

func _make_mage() -> Image:
	var image = _new_canvas()
	_draw_circle(image, CENTER.x, CENTER.y, 13, OUTLINE)
	_draw_circle(image, CENTER.x, CENTER.y, 12, COLOR_MAGE)
	_draw_line(image, CENTER.x - 6, CENTER.y, CENTER.x + 6, CENTER.y, SYMBOL_LIGHT, 3)
	_draw_line(image, CENTER.x, CENTER.y - 6, CENTER.x, CENTER.y + 6, SYMBOL_LIGHT, 3)
	_draw_line(image, CENTER.x - 5, CENTER.y - 5, CENTER.x + 5, CENTER.y + 5, SYMBOL_LIGHT, 2)
	_draw_line(image, CENTER.x - 5, CENTER.y + 5, CENTER.x + 5, CENTER.y - 5, SYMBOL_LIGHT, 2)
	return image

func _draw_rect(image: Image, x0: int, y0: int, w: int, h: int, color: Color) -> void:
	var x1 = x0 + w
	var y1 = y0 + h
	for y in range(y0, y1):
		if y < 0 or y >= SPRITE_SIZE:
			continue
		for x in range(x0, x1):
			if x < 0 or x >= SPRITE_SIZE:
				continue
			image.set_pixel(x, y, color)

func _draw_circle(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var r2 = radius * radius
	for y in range(cy - radius, cy + radius + 1):
		if y < 0 or y >= SPRITE_SIZE:
			continue
		for x in range(cx - radius, cx + radius + 1):
			if x < 0 or x >= SPRITE_SIZE:
				continue
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= r2:
				image.set_pixel(x, y, color)

func _draw_diamond(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for y in range(cy - radius, cy + radius + 1):
		if y < 0 or y >= SPRITE_SIZE:
			continue
		var dy = abs(y - cy)
		var span = radius - dy
		for x in range(cx - span, cx + span + 1):
			if x < 0 or x >= SPRITE_SIZE:
				continue
			image.set_pixel(x, y, color)

func _draw_triangle_up(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var top = cy - radius
	var bottom = cy + radius
	var height = bottom - top
	for y in range(top, bottom + 1):
		if y < 0 or y >= SPRITE_SIZE:
			continue
		var t = 0.0
		if height > 0:
			t = float(y - top) / float(height)
		var half_span = int(round(t * radius))
		for x in range(cx - half_span, cx + half_span + 1):
			if x < 0 or x >= SPRITE_SIZE:
				continue
			image.set_pixel(x, y, color)

func _draw_triangle_right(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var left = cx - radius
	var right = cx + radius
	var width = right - left
	for x in range(left, right + 1):
		if x < 0 or x >= SPRITE_SIZE:
			continue
		var t = 0.0
		if width > 0:
			t = float(x - left) / float(width)
		var half_span = int(round(t * radius))
		for y in range(cy - half_span, cy + half_span + 1):
			if y < 0 or y >= SPRITE_SIZE:
				continue
			image.set_pixel(x, y, color)

func _draw_line(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color, thickness: int) -> void:
	var dx = x1 - x0
	var dy = y1 - y0
	var steps = max(abs(dx), abs(dy))
	if steps <= 0:
		_draw_rect(image, x0, y0, 1, 1, color)
		return
	var half = int(floor(float(thickness) * 0.5))
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var x = x0 + int(round(float(dx) * t))
		var y = y0 + int(round(float(dy) * t))
		_draw_rect(image, x - half, y - half, thickness, thickness, color)
