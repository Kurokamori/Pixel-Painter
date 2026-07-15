class_name PPToolPencil
extends PPTool

## Freehand paint. The workhorse: everything interesting lives in PPStroke.

var _stroke: PPStroke = null


func get_id() -> StringName:
	return &"pencil"


func get_display_name() -> String:
	return "Pencil"


func get_options() -> Array[Option]:
	return [
		Option.BRUSH,
		Option.OPACITY,
		Option.PIXEL_PERFECT,
		Option.LOCK_ALPHA,
		Option.PRESSURE,
		Option.SYMMETRY,
	]


func _shows_brush_cursor() -> bool:
	return true


func is_active() -> bool:
	return _stroke != null


func press(context: PPToolContext, pointer: PPPointer) -> void:
	if _stroke != null:
		return

	# A flipped stylus erases, matching the physical affordance the hardware is
	# advertising -- users expect the eraser end to erase whatever tool is armed.
	var mode: PPStroke.Mode = (
		PPStroke.Mode.ERASE if pointer.inverted else PPStroke.Mode.PAINT
	)

	var stroke: PPStroke = PPStroke.new()
	if not stroke.begin(
		context.document,
		context.settings,
		mode,
		context.color_for(pointer),
		context.settings.pixel_perfect
	):
		context.set_status("Layer is locked or hidden")
		return

	_stroke = stroke
	_stroke.extend(pointer)


func drag(_context: PPToolContext, pointer: PPPointer) -> void:
	if _stroke == null:
		return
	_stroke.extend(pointer)


func release(context: PPToolContext, _pointer: PPPointer) -> void:
	if _stroke == null:
		return
	context.push_applied(_stroke.end())
	_stroke = null


func cancel(_context: PPToolContext) -> void:
	if _stroke == null:
		return
	_stroke.cancel()
	_stroke = null
