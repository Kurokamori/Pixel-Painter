class_name PPToolMove
extends PPTool

## Moves the selected pixels -- or, with no selection, the whole cel.
##
## On press the selected pixels are *lifted*: they are cut out of the cel into a
## floating buffer, leaving a hole behind. The drag then repositions that buffer
## over the hole. This is what makes a move look and behave like moving a piece
## of paper rather than smearing a copy of it, and it means the vacated area is
## genuinely transparent (revealing the layers below) instead of a stale copy.
##
## The selection mask travels with the pixels, so a subsequent move continues
## from where the last one left off.

var _document: PPDocument = null
var _cel: PPCel = null
var _canvas: Vector2i = Vector2i.ZERO

var _snapshot: PackedByteArray = PackedByteArray()
var _base: PackedByteArray = PackedByteArray()
var _working: PackedByteArray = PackedByteArray()

## The lifted pixels (full canvas, only meaningful where _mask > 0).
var _floating: PackedByteArray = PackedByteArray()
var _mask: PackedByteArray = PackedByteArray()
var _mask_before: PackedByteArray = PackedByteArray()
var _had_selection: bool = false

var _origin_bounds: Rect2i = Rect2i()
var _start: Vector2i = Vector2i.ZERO
var _offset: Vector2i = Vector2i.ZERO
var _prev_rect: Rect2i = Rect2i()
var _active: bool = false


func get_id() -> StringName:
	return &"move"


func get_display_name() -> String:
	return "Move"


func is_active() -> bool:
	return _active


func press(context: PPToolContext, pointer: PPPointer) -> void:
	if _active:
		return
	if not context.document.can_paint():
		context.set_status("Layer is locked or hidden")
		return

	_document = context.document
	_cel = _document.get_active_cel()
	_canvas = _document.sprite.size
	_snapshot = _cel.image.get_data()

	_had_selection = not _document.selection.is_empty()
	_mask_before = _document.selection.mask.duplicate()

	if _had_selection:
		_mask = _document.selection.mask.duplicate()
		_origin_bounds = _document.selection.get_bounds()
	else:
		# No selection: the whole cel is the thing being moved.
		_mask = PackedByteArray()
		_mask.resize(_canvas.x * _canvas.y)
		_mask.fill(255)
		_origin_bounds = _document.sprite.get_bounds()

	# Lift: floating keeps the masked pixels, base gets a hole punched in it.
	_floating = _snapshot.duplicate()
	_base = _snapshot.duplicate()
	for pixel: int in range(_canvas.x * _canvas.y):
		if _mask[pixel] == 0:
			continue
		var i: int = pixel * PPTypes.BPP
		# Soft mask edges scale the lifted alpha, and the hole keeps the
		# complementary fraction, so a feathered selection moves without
		# gaining or losing coverage at its border.
		var keep: int = 255 - _mask[pixel]
		_floating[i + 3] = (_snapshot[i + 3] * _mask[pixel]) / 255

		var hole_alpha: int = (_snapshot[i + 3] * keep) / 255
		if hole_alpha == 0:
			# A fully vacated pixel must be fully clear -- colour included -- or
			# the "hole" keeps its old RGB and bleeds under downstream filtering.
			_base[i] = 0
			_base[i + 1] = 0
			_base[i + 2] = 0
		_base[i + 3] = hole_alpha

	_working = _base.duplicate()
	_start = pointer.get_cell()
	_offset = Vector2i.ZERO
	_prev_rect = _origin_bounds
	_active = true

	_render(context)


func drag(context: PPToolContext, pointer: PPPointer) -> void:
	if not _active:
		return
	var next: Vector2i = pointer.get_cell() - _start
	if next == _offset:
		return
	_offset = next
	_render(context)


func release(context: PPToolContext, _pointer: PPPointer) -> void:
	if not _active:
		return
	_active = false

	_cel.image = Image.create_from_data(
		_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8, _working
	)

	var affected: Rect2i = _origin_bounds.merge(_shifted_bounds())

	_document.history.begin_group("Move")
	context.push_applied(
		PPPixelsCommand.create(
			_cel, _canvas, _snapshot, _working, affected, "Move"
		)
	)
	if _had_selection and _offset != Vector2i.ZERO:
		context.push(
			PPSelectionCommand.create(
				_mask_before, _shift_mask(_mask, _offset), "Move Selection"
			)
		)
	_document.history.end_group()

	_document.refresh_composite(affected)
	_reset()


func cancel(_context: PPToolContext) -> void:
	if not _active:
		return
	_active = false
	_cel.set_buffer(_snapshot)
	_document.selection.set_mask(_mask_before)
	_document.refresh_composite(_origin_bounds.merge(_shifted_bounds()))
	_document.notify_selection_changed()
	_reset()


func _render(_context: PPToolContext) -> void:
	_working = _base.duplicate()

	var target: Rect2i = _shifted_bounds()
	for y: int in range(target.position.y, target.position.y + target.size.y):
		for x: int in range(target.position.x, target.position.x + target.size.x):
			if x < 0 or y < 0 or x >= _canvas.x or y >= _canvas.y:
				continue
			var source: Vector2i = Vector2i(x, y) - _offset
			if (
				source.x < 0
				or source.y < 0
				or source.x >= _canvas.x
				or source.y >= _canvas.y
			):
				continue

			var source_pixel: int = source.y * _canvas.x + source.x
			if _mask[source_pixel] == 0:
				continue

			var si: int = source_pixel * PPTypes.BPP
			var di: int = (y * _canvas.x + x) * PPTypes.BPP

			var src_a: float = float(_floating[si + 3]) / 255.0
			if src_a <= 0.0:
				continue
			var dst_a: float = float(_working[di + 3]) / 255.0
			var out_a: float = src_a + dst_a * (1.0 - src_a)
			if out_a <= 0.0:
				continue

			var inv: float = dst_a * (1.0 - src_a)
			for c: int in range(3):
				var src: float = float(_floating[si + c]) / 255.0
				var dst: float = float(_working[di + c]) / 255.0
				_working[di + c] = clampi(
					int(round(((src * src_a + dst * inv) / out_a) * 255.0)), 0, 255
				)
			_working[di + 3] = clampi(int(round(out_a * 255.0)), 0, 255)

	var repaint: Rect2i = _prev_rect.merge(target).merge(_origin_bounds)
	_prev_rect = target

	var preview: Image = Image.create_from_data(
		_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8, _working
	)
	_document.refresh_composite_with_preview(
		_document.active_layer, preview, repaint
	)

	if _had_selection:
		_document.selection.set_mask(_shift_mask(_mask, _offset))
		_document.notify_selection_changed()


func _shifted_bounds() -> Rect2i:
	return Rect2i(_origin_bounds.position + _offset, _origin_bounds.size)


static func _shift_mask_static(
	mask: PackedByteArray, canvas: Vector2i, offset: Vector2i
) -> PackedByteArray:
	var shifted: PackedByteArray = PackedByteArray()
	shifted.resize(mask.size())
	shifted.fill(0)
	for y: int in range(canvas.y):
		var source_y: int = y - offset.y
		if source_y < 0 or source_y >= canvas.y:
			continue
		for x: int in range(canvas.x):
			var source_x: int = x - offset.x
			if source_x < 0 or source_x >= canvas.x:
				continue
			shifted[y * canvas.x + x] = mask[source_y * canvas.x + source_x]
	return shifted


func _shift_mask(mask: PackedByteArray, offset: Vector2i) -> PackedByteArray:
	return _shift_mask_static(mask, _canvas, offset)


func _reset() -> void:
	_snapshot = PackedByteArray()
	_base = PackedByteArray()
	_working = PackedByteArray()
	_floating = PackedByteArray()
	_mask = PackedByteArray()
	_mask_before = PackedByteArray()
	_cel = null
	_document = null
