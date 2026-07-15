class_name PPTestTools
extends RefCounted

## Drives each tool through press/drag/release exactly as the canvas would, and
## checks the pixels that come out the other side.

const RED: Color = Color(1.0, 0.0, 0.0, 1.0)
const BLUE: Color = Color(0.0, 0.0, 1.0, 1.0)
const CLEAR: Color = Color(0.0, 0.0, 0.0, 0.0)


static func run() -> PPTestCase:
	var t: PPTestCase = PPTestCase.new("tools")

	_test_pencil(t)
	_test_pixel_perfect(t)
	_test_brush_size(t)
	_test_eraser(t)
	_test_lock_alpha(t)
	_test_symmetry(t)
	_test_bucket(t)
	_test_eyedropper(t)
	_test_line(t)
	_test_shapes(t)
	_test_selection_tools(t)
	_test_move(t)
	_test_clipboard(t)
	_test_raster(t)

	return t


static func _pointer(x: float, y: float, pressure: float = 1.0) -> PPPointer:
	var pointer: PPPointer = PPPointer.new()
	pointer.position = Vector2(x, y)
	pointer.pressure = pressure
	return pointer


static func _setup(size: int = 16) -> Array:
	var document: PPDocument = PPDocument.create(Vector2i(size, size))
	var settings: PPToolSettings = PPToolSettings.new()
	settings.primary_color = RED
	settings.secondary_color = BLUE
	settings.pixel_perfect = false
	settings.brush_size = 1
	var context: PPToolContext = PPToolContext.create(document, settings)
	return [document, settings, context]


## Runs a tool across a list of cells: press on the first, drag through the
## rest, release on the last.
static func _gesture(
	tool: PPTool, context: PPToolContext, cells: Array[Vector2i], pointer_setup: Callable = Callable()
) -> void:
	for i: int in range(cells.size()):
		var pointer: PPPointer = _pointer(float(cells[i].x), float(cells[i].y))
		if pointer_setup.is_valid():
			pointer_setup.call(pointer)
		if i == 0:
			tool.press(context, pointer)
		else:
			tool.drag(context, pointer)
	var last: PPPointer = _pointer(float(cells[-1].x), float(cells[-1].y))
	if pointer_setup.is_valid():
		pointer_setup.call(last)
	tool.release(context, last)


static func _cel_image(document: PPDocument) -> Image:
	return document.get_active_cel().image


static func _test_pencil(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var context: PPToolContext = parts[2]

	var pencil: PPToolPencil = PPToolPencil.new()
	_gesture(pencil, context, [Vector2i(2, 2), Vector2i(5, 2)] as Array[Vector2i])

	var image: Image = _cel_image(document)
	t.pixel(image, 2, 2, RED, "pencil paints the press cell")
	t.pixel(image, 3, 2, RED, "pencil interpolates between samples")
	t.pixel(image, 4, 2, RED, "pencil interpolates between samples")
	t.pixel(image, 5, 2, RED, "pencil paints the release cell")
	t.pixel(image, 6, 2, CLEAR, "pencil stops at the release cell")

	t.check(document.history.can_undo(), "the stroke produced one undo step")
	document.history.undo()
	t.pixel(_cel_image(document), 3, 2, CLEAR, "undo removes the whole stroke")

	# The right button paints the secondary colour.
	var secondary: PPPointer = _pointer(8.0, 8.0)
	secondary.secondary = true
	pencil.press(context, secondary)
	pencil.release(context, secondary)
	t.pixel(_cel_image(document), 8, 8, BLUE, "right-click paints the secondary colour")


static func _test_pixel_perfect(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	settings.pixel_perfect = true
	var pencil: PPToolPencil = PPToolPencil.new()
	# An L-shaped path: right one, then down one. The corner is redundant.
	_gesture(
		pencil, context, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)] as Array[Vector2i]
	)

	var image: Image = _cel_image(document)
	t.pixel(image, 2, 2, RED, "pixel-perfect keeps the start cell")
	t.pixel(image, 3, 3, RED, "pixel-perfect keeps the end cell")
	t.pixel(image, 3, 2, CLEAR, "pixel-perfect drops the redundant corner cell")

	# With the filter off, the corner survives.
	var parts2: Array = _setup()
	var document2: PPDocument = parts2[0]
	var settings2: PPToolSettings = parts2[1]
	var context2: PPToolContext = parts2[2]
	settings2.pixel_perfect = false

	var pencil2: PPToolPencil = PPToolPencil.new()
	_gesture(
		pencil2, context2, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)] as Array[Vector2i]
	)
	t.pixel(
		_cel_image(document2), 3, 2, RED, "without pixel-perfect the corner cell is kept"
	)


static func _test_brush_size(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	settings.brush_size = 3
	settings.brush_shape = PPTypes.BrushShape.SQUARE
	settings.pressure_target = PPTypes.PressureTarget.NONE

	var pencil: PPToolPencil = PPToolPencil.new()
	var pointer: PPPointer = _pointer(8.0, 8.0)
	pencil.press(context, pointer)
	pencil.release(context, pointer)

	var image: Image = _cel_image(document)
	t.pixel(image, 8, 8, RED, "3px square brush covers its centre")
	t.pixel(image, 7, 7, RED, "3px square brush covers its corner")
	t.pixel(image, 9, 9, RED, "3px square brush covers its opposite corner")
	t.pixel(image, 6, 6, CLEAR, "3px square brush does not overreach")


static func _test_eraser(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var context: PPToolContext = parts[2]

	_cel_image(document).fill(RED)
	document.refresh_composite()

	var eraser: PPToolEraser = PPToolEraser.new()
	_gesture(eraser, context, [Vector2i(4, 4), Vector2i(6, 4)] as Array[Vector2i])

	var image: Image = _cel_image(document)
	t.pixel(image, 4, 4, CLEAR, "eraser clears the press cell")
	t.pixel(image, 5, 4, CLEAR, "eraser clears along the path")
	t.pixel(image, 4, 5, RED, "eraser leaves neighbouring pixels alone")

	document.history.undo()
	t.pixel(_cel_image(document), 4, 4, RED, "undo restores erased pixels")


static func _test_lock_alpha(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	# A single opaque blue pixel on an otherwise empty cel.
	_cel_image(document).set_pixel(5, 5, BLUE)
	settings.lock_alpha = true

	var pencil: PPToolPencil = PPToolPencil.new()
	_gesture(pencil, context, [Vector2i(4, 5), Vector2i(6, 5)] as Array[Vector2i])

	var image: Image = _cel_image(document)
	t.pixel(image, 5, 5, RED, "lock alpha recolours the opaque pixel")
	t.pixel(image, 4, 5, CLEAR, "lock alpha refuses to paint into transparency")
	t.pixel(image, 6, 5, CLEAR, "lock alpha refuses to paint into transparency")


static func _test_symmetry(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	settings.symmetry = PPTypes.SymmetryMode.HORIZONTAL

	var pencil: PPToolPencil = PPToolPencil.new()
	var pointer: PPPointer = _pointer(2.0, 7.0)
	pencil.press(context, pointer)
	pencil.release(context, pointer)

	var image: Image = _cel_image(document)
	t.pixel(image, 2, 7, RED, "symmetry paints the original cell")
	t.pixel(image, 13, 7, RED, "horizontal symmetry mirrors across the canvas centre")


static func _test_bucket(t: PPTestCase) -> void:
	var parts: Array = _setup(8)
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	# A blue wall down the middle splits the canvas into two regions.
	var image: Image = _cel_image(document)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	for y: int in range(8):
		image.set_pixel(4, y, BLUE)
	document.refresh_composite()

	var bucket: PPToolBucket = PPToolBucket.new()
	var pointer: PPPointer = _pointer(1.0, 1.0)
	bucket.press(context, pointer)

	var filled: Image = _cel_image(document)
	t.pixel(filled, 0, 0, RED, "contiguous fill floods the left region")
	t.pixel(filled, 3, 7, RED, "contiguous fill reaches the far corner of the region")
	t.pixel(filled, 4, 0, BLUE, "contiguous fill respects the wall")
	t.pixel(filled, 5, 0, Color(1.0, 1.0, 1.0, 1.0), "contiguous fill does not cross the wall")

	document.history.undo()

	# Global mode ignores connectivity and replaces the colour everywhere.
	settings.contiguous = false
	var bucket2: PPToolBucket = PPToolBucket.new()
	bucket2.press(context, _pointer(1.0, 1.0))

	var global_filled: Image = _cel_image(document)
	t.pixel(global_filled, 0, 0, RED, "global fill recolours the left region")
	t.pixel(global_filled, 5, 0, RED, "global fill also recolours the disconnected region")
	t.pixel(global_filled, 4, 0, BLUE, "global fill leaves other colours alone")


static func _test_eyedropper(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	_cel_image(document).set_pixel(3, 3, BLUE)

	var dropper: PPToolEyedropper = PPToolEyedropper.new()
	dropper.press(context, _pointer(3.0, 3.0))
	t.equal(settings.primary_color, BLUE, "eyedropper picks into the primary slot")

	var right: PPPointer = _pointer(9.0, 9.0)
	right.secondary = true
	dropper.press(context, right)
	t.equal(
		settings.secondary_color, CLEAR, "right-click eyedropper picks into the secondary slot"
	)


static func _test_line(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var context: PPToolContext = parts[2]

	var line: PPToolLine = PPToolLine.new()
	line.press(context, _pointer(2.0, 2.0))
	line.drag(context, _pointer(6.0, 2.0))

	# Mid-drag the cel must still be untouched -- the preview is non-destructive.
	t.pixel(
		_cel_image(document), 4, 2, CLEAR, "line preview does not write to the cel"
	)

	line.release(context, _pointer(6.0, 2.0))
	var image: Image = _cel_image(document)
	t.pixel(image, 2, 2, RED, "line commits its start")
	t.pixel(image, 4, 2, RED, "line commits its middle")
	t.pixel(image, 6, 2, RED, "line commits its end")

	# A cancelled drag must leave nothing behind.
	var line2: PPToolLine = PPToolLine.new()
	line2.press(context, _pointer(2.0, 9.0))
	line2.drag(context, _pointer(7.0, 9.0))
	line2.cancel(context)
	t.pixel(_cel_image(document), 5, 9, CLEAR, "a cancelled line leaves no pixels")


static func _test_shapes(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	var rect: PPToolRectangle = PPToolRectangle.new()
	_gesture(rect, context, [Vector2i(2, 2), Vector2i(6, 6)] as Array[Vector2i])

	var image: Image = _cel_image(document)
	t.pixel(image, 2, 2, RED, "rectangle outline draws its corner")
	t.pixel(image, 4, 2, RED, "rectangle outline draws its top edge")
	t.pixel(image, 2, 4, RED, "rectangle outline draws its left edge")
	t.pixel(image, 4, 4, CLEAR, "rectangle outline leaves its interior empty")

	document.history.undo()

	settings.shape_filled = true
	var rect2: PPToolRectangle = PPToolRectangle.new()
	_gesture(rect2, context, [Vector2i(2, 2), Vector2i(6, 6)] as Array[Vector2i])
	t.pixel(_cel_image(document), 4, 4, RED, "filled rectangle fills its interior")

	document.history.undo()

	# An ellipse should be empty at the corners of its bounding box and filled at
	# its centre -- the cheapest way to prove it is not secretly a rectangle.
	var ellipse: PPToolEllipse = PPToolEllipse.new()
	_gesture(ellipse, context, [Vector2i(2, 2), Vector2i(8, 8)] as Array[Vector2i])
	var ellipse_image: Image = _cel_image(document)
	t.pixel(ellipse_image, 5, 5, RED, "filled ellipse covers its centre")
	t.pixel(ellipse_image, 2, 2, CLEAR, "filled ellipse does not reach its bounding corner")


static func _test_selection_tools(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var settings: PPToolSettings = parts[1]
	var context: PPToolContext = parts[2]

	var marquee: PPToolSelectRect = PPToolSelectRect.new()
	_gesture(marquee, context, [Vector2i(2, 2), Vector2i(5, 5)] as Array[Vector2i])

	t.equal(
		document.selection.get_bounds(), Rect2i(2, 2, 4, 4), "rect select bounds the drag"
	)
	t.check(document.selection.contains(3, 3), "rect select includes the interior")

	# Painting must now be confined to the selection.
	var pencil: PPToolPencil = PPToolPencil.new()
	_gesture(pencil, context, [Vector2i(0, 3), Vector2i(8, 3)] as Array[Vector2i])

	var image: Image = _cel_image(document)
	t.pixel(image, 3, 3, RED, "painting inside the selection lands")
	t.pixel(image, 0, 3, CLEAR, "painting outside the selection is masked away")
	t.pixel(image, 8, 3, CLEAR, "painting outside the selection is masked away")

	document.history.undo()

	# Undoing the selection itself must restore the previous mask.
	document.history.undo()
	t.check(document.selection.is_empty(), "undo clears the selection")

	# Magic wand over a flat region.
	document.history.redo()
	PPEditOps.select_none(document)

	_cel_image(document).fill(Color(1.0, 1.0, 1.0, 1.0))
	_cel_image(document).fill_rect(Rect2i(4, 4, 3, 3), BLUE)
	document.refresh_composite()

	settings.tolerance = 0
	var wand: PPToolMagicWand = PPToolMagicWand.new()
	_gesture(wand, context, [Vector2i(5, 5)] as Array[Vector2i])
	t.equal(
		document.selection.get_bounds(),
		Rect2i(4, 4, 3, 3),
		"magic wand selects the flat colour region"
	)


static func _test_move(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var context: PPToolContext = parts[2]

	_cel_image(document).fill_rect(Rect2i(2, 2, 2, 2), RED)
	document.refresh_composite()

	# Select the square, then drag it three cells right.
	var marquee: PPToolSelectRect = PPToolSelectRect.new()
	_gesture(marquee, context, [Vector2i(2, 2), Vector2i(3, 3)] as Array[Vector2i])

	var move: PPToolMove = PPToolMove.new()
	_gesture(move, context, [Vector2i(2, 2), Vector2i(5, 2)] as Array[Vector2i])

	var image: Image = _cel_image(document)
	t.pixel(image, 5, 2, RED, "move relocates the selected pixels")
	t.pixel(image, 6, 3, RED, "move relocates the whole selected block")
	t.pixel(image, 2, 2, CLEAR, "move leaves a genuine hole behind, not a copy")
	t.check(
		document.selection.contains(5, 2), "the selection travels with the pixels"
	)

	document.history.undo()
	var restored: Image = _cel_image(document)
	t.pixel(restored, 2, 2, RED, "undo puts the moved pixels back")
	t.pixel(restored, 5, 2, CLEAR, "undo clears where they were moved to")


static func _test_clipboard(t: PPTestCase) -> void:
	var parts: Array = _setup()
	var document: PPDocument = parts[0]
	var context: PPToolContext = parts[2]

	_cel_image(document).fill_rect(Rect2i(1, 1, 2, 2), RED)
	document.refresh_composite()

	var marquee: PPToolSelectRect = PPToolSelectRect.new()
	_gesture(marquee, context, [Vector2i(1, 1), Vector2i(2, 2)] as Array[Vector2i])

	t.check(PPEditOps.copy(document), "copy succeeds")
	t.check(PPEditOps.paste(document, Vector2i(8, 8)), "paste succeeds")

	var image: Image = _cel_image(document)
	t.pixel(image, 8, 8, RED, "paste lands at the requested anchor")
	t.pixel(image, 9, 9, RED, "paste copies the whole block")
	t.pixel(image, 1, 1, RED, "paste leaves the original alone")

	# Cut must remove the source pixels.
	PPEditOps.select_none(document)
	var marquee2: PPToolSelectRect = PPToolSelectRect.new()
	_gesture(marquee2, context, [Vector2i(1, 1), Vector2i(2, 2)] as Array[Vector2i])
	t.check(PPEditOps.cut(document), "cut succeeds")
	t.pixel(_cel_image(document), 1, 1, CLEAR, "cut removes the source pixels")

	document.history.undo()
	t.pixel(_cel_image(document), 1, 1, RED, "undo restores the cut pixels")


static func _test_raster(t: PPTestCase) -> void:
	var line: Array[Vector2i] = PPRaster.line(Vector2i(0, 0), Vector2i(3, 0))
	t.equal(line.size(), 4, "a 4-cell horizontal line has 4 cells")
	t.equal(line[0], Vector2i(0, 0), "line includes its start")
	t.equal(line[3], Vector2i(3, 0), "line includes its end")

	var diagonal: Array[Vector2i] = PPRaster.line(Vector2i(0, 0), Vector2i(3, 3))
	t.equal(diagonal.size(), 4, "a diagonal line is one cell per step")
	t.equal(diagonal[2], Vector2i(2, 2), "a 45-degree line stays on the diagonal")

	var single: Array[Vector2i] = PPRaster.line(Vector2i(5, 5), Vector2i(5, 5))
	t.equal(single.size(), 1, "a zero-length line is a single cell")

	# Shift-snapping a near-diagonal must land on an exact diagonal.
	var snapped: Vector2i = PPRaster.snap_direction(Vector2i(0, 0), Vector2i(10, 9))
	t.equal(snapped, Vector2i(10, 10), "snap_direction snaps a near-diagonal to 45 degrees")

	var square: Vector2i = PPRaster.square_corner(Vector2i(0, 0), Vector2i(10, 4))
	t.equal(square, Vector2i(10, 10), "square_corner extends the shorter axis")

	var outline: Array[Vector2i] = PPRaster.rect_outline(Vector2i(0, 0), Vector2i(2, 2))
	t.equal(outline.size(), 8, "a 3x3 rectangle outline is 8 cells")
