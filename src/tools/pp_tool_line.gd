class_name PPToolLine
extends PPShapeTool

## Straight line. Shift snaps to the 8 compass directions.


func get_id() -> StringName:
	return &"line"


func get_display_name() -> String:
	return "Line"


func get_options() -> Array[Option]:
	return [Option.BRUSH, Option.OPACITY, Option.LOCK_ALPHA, Option.SYMMETRY]


func _compute_cells(
	_context: PPToolContext, from: Vector2i, to: Vector2i, pointer: PPPointer
) -> Array[Vector2i]:
	var end: Vector2i = to
	if pointer.shift:
		end = PPRaster.snap_direction(from, to)
	return PPRaster.line(from, end)


func _describe(from: Vector2i, to: Vector2i) -> String:
	var delta: Vector2i = to - from
	var length: float = Vector2(delta).length()
	var angle: float = rad_to_deg(atan2(float(-delta.y), float(delta.x)))
	return "%.1f px  %.0f°" % [length, angle]
