class_name PPToolEllipse
extends PPShapeTool

## Ellipse, outlined or filled. Shift constrains to a circle.


func get_id() -> StringName:
	return &"ellipse"


func get_display_name() -> String:
	return "Ellipse"


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
		return PPRaster.ellipse_filled(corners[0], corners[1])
	return PPRaster.ellipse_outline(corners[0], corners[1])
