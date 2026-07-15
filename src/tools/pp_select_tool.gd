@abstract
class_name PPSelectTool
extends PPTool

## Shared machinery for the marquee selection tools.
##
## The mask is updated live during the drag so the marching ants track the
## pointer, and the pre-drag mask is carried by the tool so that release can
## still record a correct single undo step (see PPSelectionCommand).

var _document: PPDocument = null
var _settings: PPToolSettings = null
var _canvas: Vector2i = Vector2i.ZERO

var _before: PackedByteArray = PackedByteArray()
var _start: Vector2i = Vector2i.ZERO
var _active: bool = false


## Rasterises the gesture into a fresh full-canvas coverage buffer.
@abstract func _compute_mask(
	context: PPToolContext, from: Vector2i, to: Vector2i, pointer: PPPointer
) -> PackedByteArray


func get_options() -> Array[Option]:
	return [Option.SELECTION_OP]


func is_active() -> bool:
	return _active


func press(context: PPToolContext, pointer: PPPointer) -> void:
	if _active:
		return
	_document = context.document
	_settings = context.settings
	_canvas = _document.sprite.size
	_before = _document.selection.mask.duplicate()
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

	var after: PackedByteArray = _document.selection.mask.duplicate()

	# Roll the live mask back so that pushing the command applies it exactly
	# once -- otherwise the "after" state would be applied twice, which matters
	# for the signal side effects even though the bytes would match.
	_document.selection.set_mask(_before)
	context.push(
		PPSelectionCommand.create(_before, after, get_display_name())
	)
	_document.notify_selection_changed()
	_reset()


func cancel(_context: PPToolContext) -> void:
	if not _active:
		return
	_active = false
	_document.selection.set_mask(_before)
	_document.notify_selection_changed()
	_reset()


func _update(context: PPToolContext, pointer: PPPointer) -> void:
	var gesture: PackedByteArray = _compute_mask(
		context, _start, pointer.get_cell(), pointer
	)

	# Each live update starts from the pre-drag mask, so the operator (add /
	# subtract / intersect) composes against a stable base instead of compounding
	# against the previous frame of the same drag.
	var combined: PPSelection = PPSelection.new(_canvas)
	combined.set_mask(_before)
	combined.apply(gesture, _resolve_op(pointer))

	_document.selection.set_mask(combined.mask)
	_document.notify_selection_changed()

	var bounds: Rect2i = _document.selection.get_bounds()
	if bounds.size.x > 0:
		context.set_status("%d x %d" % [bounds.size.x, bounds.size.y])


## Modifiers override the sticky operator: shift adds, alt subtracts. This is
## the convention every raster editor shares, and muscle memory is worth more
## than consistency with our own dropdown.
func _resolve_op(pointer: PPPointer) -> PPTypes.SelectionOp:
	if pointer.shift and pointer.alt:
		return PPTypes.SelectionOp.INTERSECT
	if pointer.shift:
		return PPTypes.SelectionOp.ADD
	if pointer.alt:
		return PPTypes.SelectionOp.SUBTRACT
	return _settings.selection_op


func _reset() -> void:
	_before = PackedByteArray()
	_document = null


## Fills a cell list into a fresh coverage buffer.
func _mask_from_cells(cells: Array[Vector2i]) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(_canvas.x * _canvas.y)
	mask.fill(0)
	for cell: Vector2i in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= _canvas.x or cell.y >= _canvas.y:
			continue
		mask[cell.y * _canvas.x + cell.x] = 255
	return mask
