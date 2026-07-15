@abstract
class_name PPShapeTool
extends PPTool

## Shared machinery for line, rectangle, ellipse and any other drag-out shape.
##
## Shapes preview *non-destructively*: while dragging, the shape is composed
## into a scratch buffer and handed to the compositor as a stand-in for the
## layer's cel. The cel itself is not touched until the pointer is released, so
## an abandoned drag leaves no pixels and no undo entry behind.
##
## Only the rect the shape actually occupies is recomposed each frame -- the
## previous frame's rect is restored from the snapshot first -- so dragging a
## long diagonal across a large canvas stays cheap.

var _document: PPDocument = null
var _settings: PPToolSettings = null
var _cel: PPCel = null
var _canvas: Vector2i = Vector2i.ZERO

var _snapshot: PackedByteArray = PackedByteArray()
var _working: PackedByteArray = PackedByteArray()
var _selection_mask: PackedByteArray = PackedByteArray()

var _start: Vector2i = Vector2i.ZERO
var _color: Color = Color.BLACK
var _erase: bool = false
var _active: bool = false

var _prev_rect: Rect2i = Rect2i()
var _total_rect: Rect2i = Rect2i()
var _has_total: bool = false


## The cells this shape covers for a given drag. Implemented per shape.
@abstract func _compute_cells(
	context: PPToolContext, from: Vector2i, to: Vector2i, pointer: PPPointer
) -> Array[Vector2i]


func get_options() -> Array[Option]:
	return [Option.BRUSH, Option.OPACITY, Option.LOCK_ALPHA, Option.SYMMETRY]


func _shows_brush_cursor() -> bool:
	return true


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

	_start = pointer.get_cell()
	_color = context.color_for(pointer)
	_erase = pointer.inverted
	_active = true

	_prev_rect = Rect2i()
	_total_rect = Rect2i()
	_has_total = false

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

	# Commit the previewed buffer to the cel for real.
	_cel.image = Image.create_from_data(
		_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8, _working
	)

	var rect: Rect2i = _total_rect if _has_total else _document.sprite.get_bounds()
	context.push_applied(
		PPPixelsCommand.create(
			_cel, _canvas, _snapshot, _working, rect, get_display_name()
		)
	)
	_document.refresh_composite(rect)
	_reset()


func cancel(_context: PPToolContext) -> void:
	if not _active:
		return
	_active = false
	# The cel was never written, so restoring the view is enough.
	var rect: Rect2i = _total_rect if _has_total else _document.sprite.get_bounds()
	_document.refresh_composite(rect)
	_reset()


func _update(context: PPToolContext, pointer: PPPointer) -> void:
	var end: Vector2i = pointer.get_cell()
	var cells: Array[Vector2i] = _compute_cells(context, _start, end, pointer)

	var brush: PPBrush = PPBrush.get_brush(
		_settings.brush_shape, _settings.size_for_pressure(1.0)
	)
	var alpha: int = _settings.alpha_for_pressure(1.0)

	# Undo the previous frame's preview before drawing this one.
	if _prev_rect.size.x > 0 and _prev_rect.size.y > 0:
		PPBlend.copy_buffer(_working, _snapshot, _canvas, _prev_rect)

	var rect: Rect2i = PPPaintOps.bounds_of(cells, brush, _canvas, _settings.symmetry)
	if rect.size.x > 0 and rect.size.y > 0:
		var coverage: PackedByteArray = PPPaintOps.build_coverage(
			_canvas, cells, brush, alpha, _settings.symmetry
		)
		PPPaintOps.compose_region(
			_working,
			_snapshot,
			coverage,
			_canvas,
			rect,
			_color,
			PPPaintOps.Mode.ERASE if _erase else PPPaintOps.Mode.PAINT,
			_selection_mask,
			_settings.lock_alpha
		)

	var repaint: Rect2i = _union(_prev_rect, rect)
	_prev_rect = rect
	if rect.size.x > 0 and rect.size.y > 0:
		_total_rect = _union(_total_rect, rect) if _has_total else rect
		_has_total = true

	var preview: Image = Image.create_from_data(
		_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8, _working
	)
	if repaint.size.x > 0 and repaint.size.y > 0:
		_document.refresh_composite_with_preview(
			_document.active_layer, preview, repaint
		)

	context.set_status(_describe(_start, end))


func _describe(from: Vector2i, to: Vector2i) -> String:
	var rect: Rect2i = PPRaster.normalize_rect(from, to)
	return "%d x %d" % [rect.size.x, rect.size.y]


## `shape_from_center` reinterprets the press point as the shape's centre and
## the drag point as a corner, mirroring the offset back through the centre.
func _resolve_corners(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not _settings.shape_from_center:
		return [from, to]
	var offset: Vector2i = to - from
	return [from - offset, from + offset]


static func _union(a: Rect2i, b: Rect2i) -> Rect2i:
	if a.size.x <= 0 or a.size.y <= 0:
		return b
	if b.size.x <= 0 or b.size.y <= 0:
		return a
	return a.merge(b)


func _reset() -> void:
	_snapshot = PackedByteArray()
	_working = PackedByteArray()
	_selection_mask = PackedByteArray()
	_cel = null
	_document = null
