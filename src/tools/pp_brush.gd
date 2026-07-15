class_name PPBrush
extends RefCounted

## A brush "dab": the stamp laid down at a single point of a stroke.
##
## Held as an 8-bit coverage grid plus the offset from the dab's centre to the
## grid's top-left corner. Coverage is hard-edged (0 or 255) because anti-
## aliased edges are precisely what pixel art does not want; soft brushes are a
## different medium, and faking them here would produce muddy, unsnappable
## colour that no palette can absorb.
##
## Masks are cached per (shape, size): a stroke re-stamps the same dab hundreds
## of times, and regenerating it each dab shows up immediately in stylus latency.

var shape: PPTypes.BrushShape = PPTypes.BrushShape.CIRCLE
var size: int = 1

## Grid dimensions and the top-left offset relative to the dab centre.
var extent: Vector2i = Vector2i.ONE
var origin: Vector2i = Vector2i.ZERO
var coverage: PackedByteArray = PackedByteArray()

static var _cache: Dictionary[int, PPBrush] = {}


static func get_brush(brush_shape: PPTypes.BrushShape, brush_size: int) -> PPBrush:
	var clamped: int = clampi(brush_size, 1, 64)
	var key: int = int(brush_shape) * 1000 + clamped
	if _cache.has(key):
		return _cache[key]

	var brush: PPBrush = PPBrush.new()
	brush.shape = brush_shape
	brush.size = clamped
	brush._build()
	_cache[key] = brush
	return brush


## A custom dab lifted from an image (the "brush from selection" feature).
static func from_image(source: Image) -> PPBrush:
	var brush: PPBrush = PPBrush.new()
	brush.size = maxi(source.get_width(), source.get_height())
	brush.extent = Vector2i(source.get_width(), source.get_height())
	brush.origin = -Vector2i(brush.extent.x / 2, brush.extent.y / 2)
	brush.coverage = PackedByteArray()
	brush.coverage.resize(brush.extent.x * brush.extent.y)
	for y: int in range(brush.extent.y):
		for x: int in range(brush.extent.x):
			brush.coverage[y * brush.extent.x + x] = source.get_pixel(x, y).a8
	return brush


func _build() -> void:
	extent = Vector2i(size, size)
	# For even sizes there is no true centre pixel; biasing the anchor up-left
	# matches Aseprite and keeps a 2px brush from drifting under the cursor.
	origin = Vector2i(-((size - 1) / 2), -((size - 1) / 2))

	coverage = PackedByteArray()
	coverage.resize(size * size)
	coverage.fill(0)

	if size == 1:
		coverage[0] = 255
		return

	var center: float = float(size - 1) * 0.5
	var radius: float = float(size) * 0.5

	for y: int in range(size):
		for x: int in range(size):
			var dx: float = float(x) - center
			var dy: float = float(y) - center
			var inside: bool = false
			match shape:
				PPTypes.BrushShape.SQUARE:
					inside = true
				PPTypes.BrushShape.CIRCLE:
					# The 0.25 bias fattens the disc just enough that small odd
					# sizes come out as the plus/round shapes pixel artists expect
					# instead of losing their cardinal tips.
					inside = (dx * dx + dy * dy) <= (radius * radius - radius * 0.25)
				PPTypes.BrushShape.DIAMOND:
					inside = (absf(dx) + absf(dy)) <= radius - 0.5
			if inside:
				coverage[y * size + x] = 255


## Stamps this dab into `target` (a full-canvas 8-bit coverage buffer) centred on
## `at`, keeping the maximum of the existing and new coverage so that repeated
## overlapping dabs within one stroke do not compound into a darker core.
func stamp(target: PackedByteArray, canvas: Vector2i, at: Vector2i, alpha: int = 255) -> void:
	var base: Vector2i = at + origin
	for y: int in range(extent.y):
		var py: int = base.y + y
		if py < 0 or py >= canvas.y:
			continue
		for x: int in range(extent.x):
			var px: int = base.x + x
			if px < 0 or px >= canvas.x:
				continue
			var value: int = coverage[y * extent.x + x]
			if value == 0:
				continue
			var scaled: int = (value * alpha) / 255
			var index: int = py * canvas.x + px
			if scaled > target[index]:
				target[index] = scaled


## Clears this dab's footprint from a coverage buffer. Used when pixel-perfect
## retracts a corner point that has already been stamped.
func erase_stamp(target: PackedByteArray, canvas: Vector2i, at: Vector2i) -> void:
	var base: Vector2i = at + origin
	for y: int in range(extent.y):
		var py: int = base.y + y
		if py < 0 or py >= canvas.y:
			continue
		for x: int in range(extent.x):
			var px: int = base.x + x
			if px < 0 or px >= canvas.x:
				continue
			if coverage[y * extent.x + x] == 0:
				continue
			target[py * canvas.x + px] = 0


## Canvas-space bounding box of this dab centred on `at`.
func get_rect(at: Vector2i) -> Rect2i:
	return Rect2i(at + origin, extent)
