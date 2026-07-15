class_name PPToolEraser
extends PPTool

## Freehand erase. Identical to the pencil but drives the stroke in ERASE mode,
## which scales the cel's existing alpha down by coverage rather than blending a
## colour in.

var _stroke: PPStroke = null


func get_id() -> StringName:
	return &"eraser"


func get_display_name() -> String:
	return "Eraser"


func get_options() -> Array[Option]:
	return [
		Option.BRUSH,
		Option.OPACITY,
		Option.PIXEL_PERFECT,
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

	var stroke: PPStroke = PPStroke.new()
	if not stroke.begin(
		context.document,
		context.settings,
		PPStroke.Mode.ERASE,
		Color.BLACK,
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
