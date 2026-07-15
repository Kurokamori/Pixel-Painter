class_name PPToolBucket
extends PPTool

## Flood fill.
##
## Contiguous mode fills the connected region under the cursor; global mode
## replaces every pixel of that colour on the layer. Tolerance widens what counts
## as "the same colour", and "sample all layers" makes the fill respect what the
## user can actually see rather than just the active cel -- which is what you
## want when line art lives on its own layer above the fill layer.


func get_id() -> StringName:
	return &"bucket"


func get_display_name() -> String:
	return "Fill"


func get_options() -> Array[Option]:
	return [
		Option.OPACITY,
		Option.TOLERANCE,
		Option.CONTIGUOUS,
		Option.SAMPLE_ALL_LAYERS,
		Option.LOCK_ALPHA,
	]


func press(context: PPToolContext, pointer: PPPointer) -> void:
	var cell: Vector2i = pointer.get_cell()
	if not context.in_bounds(cell):
		return
	if not context.document.can_paint():
		context.set_status("Layer is locked or hidden")
		return

	var document: PPDocument = context.document
	var settings: PPToolSettings = context.settings
	var canvas: Vector2i = document.sprite.size
	var cel: PPCel = document.get_active_cel()

	# Sampling and writing are deliberately different buffers: the region is
	# decided from what the user sees, but the paint always lands on the active
	# cel. Filling straight into the flattened frame would silently bake every
	# layer together.
	var sample: PackedByteArray = context.get_sample_buffer()
	var coverage: PackedByteArray = PPRaster.flood_fill(
		sample, canvas, cell, settings.tolerance, settings.contiguous
	)

	var rect: Rect2i = PPPaintOps.bounds_of_mask(coverage, canvas)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return

	var alpha: int = settings.alpha_for_pressure(1.0)
	if alpha < 255:
		for i: int in range(coverage.size()):
			if coverage[i] > 0:
				coverage[i] = (coverage[i] * alpha) / 255

	var snapshot: PackedByteArray = cel.image.get_data()
	var working: PackedByteArray = snapshot.duplicate()

	PPPaintOps.compose_region(
		working,
		snapshot,
		coverage,
		canvas,
		rect,
		context.color_for(pointer),
		PPPaintOps.Mode.ERASE if pointer.inverted else PPPaintOps.Mode.PAINT,
		document.selection.get_paint_mask(),
		settings.lock_alpha
	)

	cel.image = Image.create_from_data(
		canvas.x, canvas.y, false, Image.FORMAT_RGBA8, working
	)
	context.push_applied(
		PPPixelsCommand.create(cel, canvas, snapshot, working, rect, "Fill")
	)
	document.refresh_composite(rect)
