class_name PPToolGradient
extends PPTool

## Linear gradient from the primary to the secondary colour, drawn by dragging
## out the gradient axis.
##
## Ordered (Bayer) dithering is the default rather than a smooth ramp: a smooth
## gradient in a 32-colour sprite produces dozens of off-palette in-between
## shades, which is exactly what pixel art is trying to avoid. Dithering keeps
## the output to the two chosen colours and lets the eye do the mixing.

## 4x4 ordered dither matrix, normalised to 0..15.
const BAYER_4X4: Array[int] = [
	0, 8, 2, 10,
	12, 4, 14, 6,
	3, 11, 1, 9,
	15, 7, 13, 5,
]

var dithered: bool = true

var _document: PPDocument = null
var _settings: PPToolSettings = null
var _cel: PPCel = null
var _canvas: Vector2i = Vector2i.ZERO

var _snapshot: PackedByteArray = PackedByteArray()
var _working: PackedByteArray = PackedByteArray()
var _selection_mask: PackedByteArray = PackedByteArray()

var _start: Vector2i = Vector2i.ZERO
var _active: bool = false
var _rect: Rect2i = Rect2i()


func get_id() -> StringName:
	return &"gradient"


func get_display_name() -> String:
	return "Gradient"


func get_options() -> Array[Option]:
	return [Option.OPACITY, Option.LOCK_ALPHA]


func is_active() -> bool:
	return _active


func press(context: PPToolContext, pointer: PPPointer) -> void:
	if _active:
		return
	if not context.document.can_paint():
		context.set_status("Layer is locked or hidden")
		return

	_document = context.document
	_settings = context.settings
	_cel = _document.get_active_cel()
	_canvas = _document.sprite.size

	_snapshot = _cel.image.get_data()
	_working = _snapshot.duplicate()
	_selection_mask = _document.selection.get_paint_mask()

	# A gradient fills the selection, or the whole canvas when there is none.
	_rect = _document.selection.get_bounds()
	if _rect.size.x <= 0 or _rect.size.y <= 0:
		_rect = _document.sprite.get_bounds()

	_start = pointer.get_cell()
	_active = true
	_update(context, pointer)


func drag(context: PPToolContext, pointer: PPPointer) -> void:
	if not _active:
		return
	_update(context, pointer)


func release(context: PPToolContext, pointer: PPPointer) -> void:
	if not _active:
		return
	_update(context, pointer)
	_active = false

	_cel.image = Image.create_from_data(
		_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8, _working
	)
	context.push_applied(
		PPPixelsCommand.create(
			_cel, _canvas, _snapshot, _working, _rect, "Gradient"
		)
	)
	_document.refresh_composite(_rect)
	_reset()


func cancel(_context: PPToolContext) -> void:
	if not _active:
		return
	_active = false
	_document.refresh_composite(_rect)
	_reset()


func _update(context: PPToolContext, pointer: PPPointer) -> void:
	var end: Vector2i = pointer.get_cell()
	if pointer.shift:
		end = PPRaster.snap_direction(_start, end)

	var axis: Vector2 = Vector2(end - _start)
	var length_squared: float = axis.length_squared()

	var from_color: Color = _settings.primary_color
	var to_color: Color = _settings.secondary_color
	var opacity: float = _settings.opacity
	var lock_alpha: bool = _settings.lock_alpha
	var has_selection: bool = _selection_mask.size() == _canvas.x * _canvas.y

	for y: int in range(_rect.position.y, _rect.position.y + _rect.size.y):
		for x: int in range(_rect.position.x, _rect.position.x + _rect.size.x):
			var pixel: int = y * _canvas.x + x
			var i: int = pixel * PPTypes.BPP

			var mask: float = 1.0
			if has_selection:
				mask = float(_selection_mask[pixel]) / 255.0
			if mask <= 0.0:
				_copy(i)
				continue
			if lock_alpha and _snapshot[i + 3] == 0:
				_copy(i)
				continue

			# Project the pixel onto the gradient axis. A zero-length drag makes
			# every pixel t=0, i.e. a flat fill of the primary colour.
			var t: float = 0.0
			if length_squared > 0.0:
				var offset: Vector2 = Vector2(Vector2i(x, y) - _start)
				t = clampf(offset.dot(axis) / length_squared, 0.0, 1.0)

			var color: Color = Color.BLACK
			if dithered:
				var threshold: float = (
					float(BAYER_4X4[(y % 4) * 4 + (x % 4)]) + 0.5
				) / 16.0
				color = to_color if t > threshold else from_color
			else:
				color = from_color.lerp(to_color, t)

			var src_a: float = color.a * opacity * mask
			var dst_a: float = float(_snapshot[i + 3]) / 255.0
			var out_a: float = src_a + dst_a * (1.0 - src_a)
			if out_a <= 0.0:
				_working[i] = 0
				_working[i + 1] = 0
				_working[i + 2] = 0
				_working[i + 3] = 0
				continue

			var inv: float = dst_a * (1.0 - src_a)
			_working[i] = _mix(color.r, float(_snapshot[i]) / 255.0, src_a, inv, out_a)
			_working[i + 1] = _mix(color.g, float(_snapshot[i + 1]) / 255.0, src_a, inv, out_a)
			_working[i + 2] = _mix(color.b, float(_snapshot[i + 2]) / 255.0, src_a, inv, out_a)
			if lock_alpha:
				_working[i + 3] = _snapshot[i + 3]
			else:
				_working[i + 3] = clampi(int(round(out_a * 255.0)), 0, 255)

	var preview: Image = Image.create_from_data(
		_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8, _working
	)
	_document.refresh_composite_with_preview(_document.active_layer, preview, _rect)
	context.set_status("Gradient  %d px" % int(axis.length()))


func _copy(i: int) -> void:
	_working[i] = _snapshot[i]
	_working[i + 1] = _snapshot[i + 1]
	_working[i + 2] = _snapshot[i + 2]
	_working[i + 3] = _snapshot[i + 3]


static func _mix(src: float, dst: float, src_a: float, inv: float, out_a: float) -> int:
	var value: float = (src * src_a + dst * inv) / out_a
	return clampi(int(round(value * 255.0)), 0, 255)


func _reset() -> void:
	_snapshot = PackedByteArray()
	_working = PackedByteArray()
	_selection_mask = PackedByteArray()
	_cel = null
	_document = null
