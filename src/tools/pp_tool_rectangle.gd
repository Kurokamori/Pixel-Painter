class_name PPToolRectangle
extends PPShapeTool

## Rectangle, outlined or filled. Shift constrains to a square; the "from
## centre" option grows it out of the press point.


func get_id() -> StringName:
	return &"rectangle"


func get_display_name() -> String:
	return "Rectangle"


func get_options() -> Array[Option]:
	return [
		Option.BRUSH,
		Option.OPACITY,
		Option.SHAPE_FILL,
		Option.SHAPE_FROM_CENTER,
		Option.LOCK_ALPHA,
		Option.SYMMETRY,
	]


func _compute_cells(
	context: PPToolContext, from: Vector2i, to: Vector2i, pointer: PPPointer
) -> Array[Vector2i]:
	var end: Vector2i = to
	if pointer.shift:
		end = PPRaster.square_corner(from, to)

	var corners: Array[Vector2i] = _resolve_corners(from, end)
	if context.settings.shape_filled:
		return PPRaster.rect_filled(corners[0], corners[1])
	return PPRaster.rect_outline(corners[0], corners[1])
