class_name PPToolSelectEllipse
extends PPSelectTool

## Elliptical marquee.


func get_id() -> StringName:
	return &"select_ellipse"


func get_display_name() -> String:
	return "Ellipse Select"


func _compute_mask(
	_context: PPToolContext, from: Vector2i, to: Vector2i, _pointer: PPPointer
) -> PackedByteArray:
	return _mask_from_cells(PPRaster.ellipse_filled(from, to))
