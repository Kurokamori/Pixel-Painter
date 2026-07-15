class_name PPToolEyedropper
extends PPTool

## Picks the colour under the cursor into the primary slot (secondary on a
## right-click). Dragging keeps sampling, so you can scrub for the shade you
## want and watch the swatch follow.


func get_id() -> StringName:
	return &"eyedropper"


func get_display_name() -> String:
	return "Eyedropper"


func get_options() -> Array[Option]:
	return [Option.SAMPLE_ALL_LAYERS]


func press(context: PPToolContext, pointer: PPPointer) -> void:
	_sample(context, pointer)


func drag(context: PPToolContext, pointer: PPPointer) -> void:
	_sample(context, pointer)


func _sample(context: PPToolContext, pointer: PPPointer) -> void:
	var cell: Vector2i = pointer.get_cell()
	if not context.in_bounds(cell):
		return

	var canvas: Vector2i = context.document.sprite.size
	var buffer: PackedByteArray = context.get_sample_buffer()
	var i: int = (cell.y * canvas.x + cell.x) * PPTypes.BPP

	var picked: Color = Color8(
		buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 3]
	)

	if pointer.secondary:
		context.settings.set_secondary(picked)
	else:
		context.settings.set_primary(picked)

	context.set_status(
		"#%s  a %d" % [picked.to_html(false).to_upper(), picked.a8]
	)
