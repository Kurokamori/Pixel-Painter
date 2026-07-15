class_name PPToolSelectRect
extends PPSelectTool

## Rectangular marquee. Shift-drag from the press point constrains to a square
## only when the selection operator is not already bound to shift, so the
## modifier that adds to a selection stays the modifier that adds to a selection.


func get_id() -> StringName:
	return &"select_rect"


func get_display_name() -> String:
	return "Rectangle Select"


func _compute_mask(
	_context: PPToolContext, from: Vector2i, to: Vector2i, _pointer: PPPointer
) -> PackedByteArray:
	return _mask_from_cells(PPRaster.rect_filled(from, to))
