class_name PPToolMagicWand
extends PPSelectTool

## Selects the region of similar colour under the cursor -- the flood fill
## algorithm, but writing a selection mask instead of pixels.


func get_id() -> StringName:
	return &"magic_wand"


func get_display_name() -> String:
	return "Magic Wand"


func get_options() -> Array[Option]:
	return [
		Option.SELECTION_OP,
		Option.TOLERANCE,
		Option.CONTIGUOUS,
		Option.SAMPLE_ALL_LAYERS,
	]


func _compute_mask(
	context: PPToolContext, _from: Vector2i, to: Vector2i, _pointer: PPPointer
) -> PackedByteArray:
	if not context.in_bounds(to):
		var empty: PackedByteArray = PackedByteArray()
		empty.resize(_canvas.x * _canvas.y)
		empty.fill(0)
		return empty

	return PPRaster.flood_fill(
		context.get_sample_buffer(),
		_canvas,
		to,
		context.settings.tolerance,
		context.settings.contiguous
	)
