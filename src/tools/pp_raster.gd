@abstract
class_name PPRaster
extends RefCounted

## Rasterisation primitives. Everything here works in integer pixel space and
## returns cell lists (for stroke tools to stamp a brush along) or coverage
## buffers (for fills and selections) -- never colours. Keeping colour out of
## these keeps them reusable by the paint tools, the eraser and the selection
## tools alike.


## Bresenham. Includes both endpoints, and is exactly the line a 1px pencil
## draws, so pencil interpolation and the line tool agree by construction.
static func line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []

	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y

	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var error: int = dx + dy

	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var double_error: int = error * 2
		if double_error >= dy:
			if x0 == x1:
				break
			error += dy
			x0 += sx
		if double_error <= dx:
			if y0 == y1:
				break
			error += dx
			y0 += sy

	return points


static func normalize_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var top_left: Vector2i = Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var bottom_right: Vector2i = Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)


## Constrains `b` so the rect a..b is square -- the shift-drag modifier.
static func square_corner(a: Vector2i, b: Vector2i) -> Vector2i:
	var dx: int = b.x - a.x
	var dy: int = b.y - a.y
	var span: int = maxi(absi(dx), absi(dy))
	return Vector2i(
		a.x + span * (1 if dx >= 0 else -1),
		a.y + span * (1 if dy >= 0 else -1)
	)


## Snaps `b` to the nearest of the 8 compass directions from `a`.
static func snap_direction(a: Vector2i, b: Vector2i) -> Vector2i:
	var dx: int = b.x - a.x
	var dy: int = b.y - a.y
	if dx == 0 and dy == 0:
		return b

	var angle: float = atan2(float(dy), float(dx))
	var step: float = PI / 4.0
	var snapped: float = round(angle / step) * step
	var length: float = maxf(absf(float(dx)), absf(float(dy)))

	var ux: float = cos(snapped)
	var uy: float = sin(snapped)
	# Scale so the dominant axis lands exactly on an integer cell, keeping
	# 45-degree lines perfectly diagonal rather than nearly so.
	var scale: float = length / maxf(absf(ux), absf(uy))
	return a + Vector2i(int(round(ux * scale)), int(round(uy * scale)))


static func rect_outline(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var rect: Rect2i = normalize_rect(a, b)
	var points: Array[Vector2i] = []
	var x_end: int = rect.position.x + rect.size.x - 1
	var y_end: int = rect.position.y + rect.size.y - 1

	for x: int in range(rect.position.x, x_end + 1):
		points.append(Vector2i(x, rect.position.y))
		if y_end != rect.position.y:
			points.append(Vector2i(x, y_end))
	for y: int in range(rect.position.y + 1, y_end):
		points.append(Vector2i(rect.position.x, y))
		if x_end != rect.position.x:
			points.append(Vector2i(x_end, y))

	return points


static func rect_filled(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var rect: Rect2i = normalize_rect(a, b)
	var points: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			points.append(Vector2i(x, y))
	return points


## Cells whose centre lies inside the ellipse inscribed in the a..b box.
##
## Solving the ellipse equation per cell (rather than running a midpoint tracer)
## keeps even- and odd-sized ellipses symmetric, which the classic integer
## algorithms famously do not.
static func ellipse_filled(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var rect: Rect2i = normalize_rect(a, b)
	var points: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if _in_ellipse(x, y, rect):
				points.append(Vector2i(x, y))
	return points


## The contour of the filled ellipse: inside cells with at least one 4-connected
## neighbour outside. Always closed and always 1px thick.
static func ellipse_outline(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var rect: Rect2i = normalize_rect(a, b)
	var points: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if not _in_ellipse(x, y, rect):
				continue
			if (
				not _in_ellipse(x - 1, y, rect)
				or not _in_ellipse(x + 1, y, rect)
				or not _in_ellipse(x, y - 1, rect)
				or not _in_ellipse(x, y + 1, rect)
			):
				points.append(Vector2i(x, y))
	return points


static func _in_ellipse(x: int, y: int, rect: Rect2i) -> bool:
	if not rect.has_point(Vector2i(x, y)):
		return false
	var rx: float = float(rect.size.x) * 0.5
	var ry: float = float(rect.size.y) * 0.5
	if rx <= 0.0 or ry <= 0.0:
		return false
	# Cell centres sit at +0.5, so measure from the box's true centre.
	var cx: float = float(rect.position.x) + rx
	var cy: float = float(rect.position.y) + ry
	var nx: float = (float(x) + 0.5 - cx) / rx
	var ny: float = (float(y) + 0.5 - cy) / ry
	return (nx * nx + ny * ny) <= 1.0


# --- Fills ------------------------------------------------------------------

## Scanline flood fill over an RGBA8 buffer. Returns a full-canvas coverage mask
## of the region matching the seed pixel within `tolerance` (0-255).
##
## `contiguous` false turns this into a global "replace this colour everywhere"
## select, which is what the bucket's global mode and the magic wand both need.
static func flood_fill(
	source: PackedByteArray,
	canvas: Vector2i,
	seed: Vector2i,
	tolerance: int,
	contiguous: bool,
	diagonal: bool = false
) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(canvas.x * canvas.y)
	mask.fill(0)

	if seed.x < 0 or seed.y < 0 or seed.x >= canvas.x or seed.y >= canvas.y:
		return mask

	var seed_index: int = (seed.y * canvas.x + seed.x) * PPTypes.BPP
	var target_r: int = source[seed_index]
	var target_g: int = source[seed_index + 1]
	var target_b: int = source[seed_index + 2]
	var target_a: int = source[seed_index + 3]

	if not contiguous:
		for i: int in range(canvas.x * canvas.y):
			var p: int = i * PPTypes.BPP
			if _matches(
				source, p, target_r, target_g, target_b, target_a, tolerance
			):
				mask[i] = 255
		return mask

	# Span-based flood: push whole horizontal runs rather than single pixels, so
	# large flat regions cost one stack entry per row instead of one per pixel.
	var stack: Array[Vector2i] = [seed]
	while not stack.is_empty():
		var point: Vector2i = stack.pop_back()
		var y: int = point.y
		if y < 0 or y >= canvas.y:
			continue

		var x: int = point.x
		if x < 0 or x >= canvas.x:
			continue
		if mask[y * canvas.x + x] != 0:
			continue
		if not _matches_at(source, canvas, x, y, target_r, target_g, target_b, target_a, tolerance):
			continue

		var left: int = x
		while (
			left - 1 >= 0
			and mask[y * canvas.x + left - 1] == 0
			and _matches_at(
				source, canvas, left - 1, y, target_r, target_g, target_b, target_a, tolerance
			)
		):
			left -= 1

		var right: int = x
		while (
			right + 1 < canvas.x
			and mask[y * canvas.x + right + 1] == 0
			and _matches_at(
				source, canvas, right + 1, y, target_r, target_g, target_b, target_a, tolerance
			)
		):
			right += 1

		for fill_x: int in range(left, right + 1):
			mask[y * canvas.x + fill_x] = 255

		# Seed the rows above and below across the whole span we just filled.
		var scan_from: int = left - (1 if diagonal else 0)
		var scan_to: int = right + (1 if diagonal else 0)
		for next_x: int in range(maxi(0, scan_from), mini(canvas.x - 1, scan_to) + 1):
			if y - 1 >= 0 and mask[(y - 1) * canvas.x + next_x] == 0:
				stack.append(Vector2i(next_x, y - 1))
			if y + 1 < canvas.y and mask[(y + 1) * canvas.x + next_x] == 0:
				stack.append(Vector2i(next_x, y + 1))

	return mask


static func _matches_at(
	source: PackedByteArray,
	canvas: Vector2i,
	x: int,
	y: int,
	r: int,
	g: int,
	b: int,
	a: int,
	tolerance: int
) -> bool:
	return _matches(
		source, (y * canvas.x + x) * PPTypes.BPP, r, g, b, a, tolerance
	)


static func _matches(
	source: PackedByteArray, index: int, r: int, g: int, b: int, a: int, tolerance: int
) -> bool:
	# Two fully transparent pixels match regardless of their RGB, which would
	# otherwise be garbage left behind by whatever last painted there.
	var source_a: int = source[index + 3]
	if source_a == 0 and a == 0:
		return true
	if tolerance == 0:
		return (
			source[index] == r
			and source[index + 1] == g
			and source[index + 2] == b
			and source_a == a
		)
	return (
		absi(source[index] - r) <= tolerance
		and absi(source[index + 1] - g) <= tolerance
		and absi(source[index + 2] - b) <= tolerance
		and absi(source_a - a) <= tolerance
	)


## Even-odd scanline fill of a closed polygon. Backs the lasso select.
static func polygon_fill(polygon: Array[Vector2i], canvas: Vector2i) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(canvas.x * canvas.y)
	mask.fill(0)
	if polygon.size() < 3:
		return mask

	var min_y: int = canvas.y
	var max_y: int = 0
	for point: Vector2i in polygon:
		min_y = mini(min_y, point.y)
		max_y = maxi(max_y, point.y)
	min_y = maxi(0, min_y)
	max_y = mini(canvas.y - 1, max_y)

	for y: int in range(min_y, max_y + 1):
		var crossings: Array[float] = []
		var scan_y: float = float(y) + 0.5

		for i: int in range(polygon.size()):
			var a: Vector2i = polygon[i]
			var b: Vector2i = polygon[(i + 1) % polygon.size()]
			var ay: float = float(a.y)
			var by: float = float(b.y)
			if (ay <= scan_y and by > scan_y) or (by <= scan_y and ay > scan_y):
				var t: float = (scan_y - ay) / (by - ay)
				crossings.append(float(a.x) + t * float(b.x - a.x))

		crossings.sort()
		var i: int = 0
		while i + 1 < crossings.size():
			var x_start: int = int(ceil(crossings[i] - 0.5))
			var x_end: int = int(floor(crossings[i + 1] - 0.5))
			for x: int in range(maxi(0, x_start), mini(canvas.x - 1, x_end) + 1):
				mask[y * canvas.x + x] = 255
			i += 2

	# The scanline rule can miss the polygon's own boundary cells on shallow
	# edges; stamping the outline guarantees the lasso encloses what the user
	# actually traced.
	for i: int in range(polygon.size()):
		var a: Vector2i = polygon[i]
		var b: Vector2i = polygon[(i + 1) % polygon.size()]
		for point: Vector2i in line(a, b):
			if point.x >= 0 and point.y >= 0 and point.x < canvas.x and point.y < canvas.y:
				mask[point.y * canvas.x + point.x] = 255

	return mask
