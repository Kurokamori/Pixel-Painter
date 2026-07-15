class_name PPToolLasso
extends PPSelectTool

## Freehand lasso. The traced path is closed automatically and filled with an
## even-odd scanline rule, so releasing anywhere yields a closed region.

var _path: Array[Vector2i] = []


func get_id() -> StringName:
	return &"lasso"


func get_display_name() -> String:
	return "Lasso Select"


func press(context: PPToolContext, pointer: PPPointer) -> void:
	_path = [pointer.get_cell()]
	super.press(context, pointer)


func drag(context: PPToolContext, pointer: PPPointer) -> void:
	if not is_active():
		return
	var cell: Vector2i = pointer.get_cell()
	if _path.is_empty() or _path[-1] != cell:
		_path.append(cell)
	super.drag(context, pointer)


func _compute_mask(
	_context: PPToolContext, _from: Vector2i, _to: Vector2i, _pointer: PPPointer
) -> PackedByteArray:
	if _path.size() < 3:
		return _mask_from_cells(_path)
	return PPRaster.polygon_fill(_path, _canvas)


## The in-progress path, for the canvas to draw as a rubber band.
func get_path() -> Array[Vector2i]:
	return _path
