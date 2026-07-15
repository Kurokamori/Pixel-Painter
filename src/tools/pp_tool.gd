@abstract
class_name PPTool
extends RefCounted

## Base class for every tool.
##
## The canvas feeds a tool three events -- press, drag, release -- already
## normalised into PPPointer, so a tool is identical under a mouse, a Wacom pen
## and an Apple Pencil. Anything a tool needs beyond the pointer comes from its
## PPToolContext.

## Which tool-option controls the options bar should show for this tool.
enum Option {
	BRUSH,
	PIXEL_PERFECT,
	OPACITY,
	LOCK_ALPHA,
	TOLERANCE,
	CONTIGUOUS,
	SAMPLE_ALL_LAYERS,
	SHAPE_FILL,
	SHAPE_FROM_CENTER,
	SELECTION_OP,
	SYMMETRY,
	PRESSURE,
}


@abstract func get_id() -> StringName

@abstract func get_display_name() -> String


## Which option controls this tool exposes. The options bar is built from this,
## so a tool never shows a knob it does not honour.
func get_options() -> Array[Option]:
	return []


func press(_context: PPToolContext, _pointer: PPPointer) -> void:
	pass


func drag(_context: PPToolContext, _pointer: PPPointer) -> void:
	pass


func release(_context: PPToolContext, _pointer: PPPointer) -> void:
	pass


## Abandons an in-progress gesture (Escape, or a second finger landing).
func cancel(_context: PPToolContext) -> void:
	pass


## True while the tool is mid-gesture, so the canvas knows not to start another.
func is_active() -> bool:
	return false


## Cells to outline under the cursor as a brush preview. Empty means "no preview".
func get_cursor_cells(context: PPToolContext, pointer: PPPointer) -> Array[Vector2i]:
	if not _shows_brush_cursor():
		return []
	var brush: PPBrush = PPBrush.get_brush(
		context.settings.brush_shape, context.settings.brush_size
	)
	var cells: Array[Vector2i] = []
	var origin: Vector2i = pointer.get_cell() + brush.origin
	for y: int in range(brush.extent.y):
		for x: int in range(brush.extent.x):
			if brush.coverage[y * brush.extent.x + x] > 0:
				cells.append(origin + Vector2i(x, y))
	return cells


func _shows_brush_cursor() -> bool:
	return false
