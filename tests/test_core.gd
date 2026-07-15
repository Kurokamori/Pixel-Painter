class_name PPTestCore
extends RefCounted

## Exercises the document model: painting through the history stack, blend
## modes, compositing, layer/frame structure, linked cels and geometry edits.


static func run() -> PPTestCase:
	var t: PPTestCase = PPTestCase.new("core")

	_test_paint_undo_redo(t)
	_test_blend_modes(t)
	_test_layer_structure(t)
	_test_layer_opacity_and_visibility(t)
	_test_frames_and_links(t)
	_test_merge_down(t)
	_test_selection(t)
	_test_geometry(t)
	_test_palette(t)

	return t


## Writes `color` into a rect of a cel and returns the resulting command,
## mirroring what a painting tool does: snapshot, mutate, hand over the pair.
static func _paint(
	document: PPDocument, layer_index: int, frame_index: int, rect: Rect2i, color: Color
) -> PPCommand:
	var cel: PPCel = document.sprite.get_cel(layer_index, frame_index)
	var before: PackedByteArray = cel.image.get_data()
	cel.image.fill_rect(rect, color)
	var after: PackedByteArray = cel.image.get_data()
	return PPPixelsCommand.create(
		cel, document.sprite.size, before, after, rect, "Paint"
	)


static func _test_paint_undo_redo(t: PPTestCase) -> void:
	var document: PPDocument = PPDocument.create(Vector2i(8, 8))

	var command: PPCommand = _paint(
		document, 0, 0, Rect2i(2, 2, 3, 3), Color(1.0, 0.0, 0.0, 1.0)
	)
	t.check(command != null, "painting produces a command")
	document.history.push_applied(command)
	document.refresh_composite()

	t.pixel(
		document.composite_image, 3, 3, Color(1.0, 0.0, 0.0, 1.0), "painted pixel is red"
	)
	t.pixel(
		document.composite_image, 0, 0, Color(0.0, 0.0, 0.0, 0.0), "outside stays clear"
	)
	t.check(document.history.can_undo(), "history has an undo step")

	document.history.undo()
	t.pixel(
		document.composite_image,
		3,
		3,
		Color(0.0, 0.0, 0.0, 0.0),
		"undo clears the painted pixel"
	)

	document.history.redo()
	t.pixel(
		document.composite_image, 3, 3, Color(1.0, 0.0, 0.0, 1.0), "redo restores it"
	)

	# A stroke that changes nothing must not pollute the undo stack.
	var noop: PPCommand = _paint(
		document, 0, 0, Rect2i(2, 2, 3, 3), Color(1.0, 0.0, 0.0, 1.0)
	)
	t.check(noop == null, "a no-op paint yields no command")

	# Every painting tool records through push_applied(). If that path does not
	# mark the document dirty, painting and quitting loses the work silently.
	var fresh: PPDocument = PPDocument.create(Vector2i(8, 8))
	t.check(not fresh.is_dirty(), "a new document starts clean")
	fresh.history.push_applied(
		_paint(fresh, 0, 0, Rect2i(1, 1, 2, 2), Color(0.0, 1.0, 0.0, 1.0))
	)
	t.check(fresh.is_dirty(), "painting marks the document dirty")

	fresh.mark_saved("user://x.pxp")
	t.check(not fresh.is_dirty(), "saving clears the dirty flag")

	# Structural edits go through push(), which must mark it too.
	fresh.history.push(
		PPLayerCommands.AddLayer.create(
			PPLayer.create("L2", 1, fresh.sprite.size), 1
		)
	)
	t.check(fresh.is_dirty(), "a structural edit marks the document dirty")


static func _test_blend_modes(t: PPTestCase) -> void:
	# Backdrop: opaque mid grey. Source: opaque half-red on the layer above.
	var document: PPDocument = PPDocument.create(Vector2i(4, 4))
	document.sprite.get_cel(0, 0).image.fill(Color(0.5, 0.5, 0.5, 1.0))

	var top: PPLayer = PPLayer.create("Top", 1, document.sprite.size)
	document.sprite.add_layer(top, 1)
	top.cels[0].image.fill(Color(0.5, 0.25, 0.0, 1.0))

	top.blend_mode = PPTypes.BlendMode.MULTIPLY
	document.refresh_composite()
	t.pixel(
		document.composite_image,
		1,
		1,
		Color(0.25, 0.125, 0.0, 1.0),
		"multiply = backdrop * source"
	)

	top.blend_mode = PPTypes.BlendMode.SCREEN
	document.refresh_composite()
	t.pixel(
		document.composite_image,
		1,
		1,
		Color(0.75, 0.625, 0.5, 1.0),
		"screen = b + s - b*s"
	)

	top.blend_mode = PPTypes.BlendMode.ADDITION
	document.refresh_composite()
	t.pixel(
		document.composite_image,
		1,
		1,
		Color(1.0, 0.75, 0.5, 1.0),
		"addition clamps at 1.0"
	)

	top.blend_mode = PPTypes.BlendMode.DIFFERENCE
	document.refresh_composite()
	t.pixel(
		document.composite_image,
		1,
		1,
		Color(0.0, 0.25, 0.5, 1.0),
		"difference = |b - s|"
	)

	# Normal mode over a fully transparent backdrop must not darken the source:
	# a classic premultiply bug shows up right here.
	top.blend_mode = PPTypes.BlendMode.NORMAL
	document.sprite.get_cel(0, 0).image.fill(Color(0.0, 0.0, 0.0, 0.0))
	top.cels[0].image.fill(Color(1.0, 1.0, 1.0, 0.5))
	document.refresh_composite()
	t.pixel(
		document.composite_image,
		1,
		1,
		Color(1.0, 1.0, 1.0, 0.5),
		"50% white over nothing keeps full white RGB"
	)


static func _test_layer_opacity_and_visibility(t: PPTestCase) -> void:
	var document: PPDocument = PPDocument.create(Vector2i(4, 4))
	document.sprite.get_cel(0, 0).image.fill(Color(0.0, 0.0, 0.0, 1.0))

	var top: PPLayer = PPLayer.create("Top", 1, document.sprite.size)
	document.sprite.add_layer(top, 1)
	top.cels[0].image.fill(Color(1.0, 1.0, 1.0, 1.0))
	top.opacity = 0.5

	document.refresh_composite()
	t.pixel(
		document.composite_image,
		1,
		1,
		Color(0.5, 0.5, 0.5, 1.0),
		"50% white layer over black composites to mid grey"
	)

	top.visible = false
	document.refresh_composite()
	t.pixel(
		document.composite_image,
		1,
		1,
		Color(0.0, 0.0, 0.0, 1.0),
		"hidden layer is not composited"
	)


static func _test_layer_structure(t: PPTestCase) -> void:
	var document: PPDocument = PPDocument.create(Vector2i(4, 4))
	t.equal(document.sprite.layer_count(), 1, "new sprite has one layer")

	var added: PPLayer = PPLayer.create("Second", 1, document.sprite.size)
	document.history.push(PPLayerCommands.AddLayer.create(added, 1))
	t.equal(document.sprite.layer_count(), 2, "add layer")
	t.equal(document.sprite.get_layer(1).name, "Second", "added at the top")

	document.history.push(PPLayerCommands.MoveLayer.create(1, 0))
	t.equal(document.sprite.get_layer(0).name, "Second", "move layer down")

	document.history.undo()
	t.equal(document.sprite.get_layer(1).name, "Second", "undo restores order")

	document.history.push(PPLayerCommands.RemoveLayer.create(document.sprite, 1))
	t.equal(document.sprite.layer_count(), 1, "remove layer")

	document.history.undo()
	t.equal(document.sprite.layer_count(), 2, "undo restores the removed layer")
	t.equal(
		document.sprite.get_layer(1).name, "Second", "restored layer keeps its identity"
	)

	# The last layer is load-bearing: removing it must be refused.
	var doomed: PPCommand = PPLayerCommands.RemoveLayer.create(
		PPSprite.create(Vector2i(4, 4)), 0
	)
	t.check(doomed == null, "cannot remove the only layer")


static func _test_frames_and_links(t: PPTestCase) -> void:
	var document: PPDocument = PPDocument.create(Vector2i(4, 4))
	document.sprite.get_cel(0, 0).image.fill(Color(1.0, 0.0, 0.0, 1.0))

	# Duplicate frame 0 as an independent copy.
	document.history.push(
		PPFrameCommands.InsertFrame.create(document.sprite, 1, 0, false, "Duplicate Frame")
	)
	t.equal(document.sprite.frame_count(), 2, "frame inserted")

	var cel_a: PPCel = document.sprite.get_cel(0, 0)
	var cel_b: PPCel = document.sprite.get_cel(0, 1)
	t.check(cel_a != cel_b, "duplicated frame gets its own cel")
	t.pixel(cel_b.image, 1, 1, Color(1.0, 0.0, 0.0, 1.0), "duplicate copies pixels")

	cel_b.image.fill(Color(0.0, 1.0, 0.0, 1.0))
	t.pixel(cel_a.image, 1, 1, Color(1.0, 0.0, 0.0, 1.0), "editing the copy leaves frame 0 alone")

	# Now a *linked* frame: the cel instance must be shared.
	document.history.push(
		PPFrameCommands.InsertFrame.create(document.sprite, 2, 1, true, "Link Frame")
	)
	t.equal(document.sprite.frame_count(), 3, "linked frame inserted")
	t.check(
		document.sprite.get_cel(0, 1) == document.sprite.get_cel(0, 2),
		"linked frames share one cel instance"
	)
	t.check(document.sprite.get_layer(0).is_cel_linked(1), "cel reports as linked")

	document.sprite.get_cel(0, 2).image.fill(Color(0.0, 0.0, 1.0, 1.0))
	t.pixel(
		document.sprite.get_cel(0, 1).image,
		1,
		1,
		Color(0.0, 0.0, 1.0, 1.0),
		"painting a linked cel updates every frame that shares it"
	)

	# Unlinking must break that sharing.
	document.history.push(
		PPFrameCommands.SetCel.create_unlink(document.sprite, 0, 2)
	)
	t.check(
		document.sprite.get_cel(0, 1) != document.sprite.get_cel(0, 2),
		"unlink gives the frame its own cel"
	)

	document.history.push(PPFrameCommands.RemoveFrame.create(document.sprite, 2))
	t.equal(document.sprite.frame_count(), 2, "frame removed")
	document.history.undo()
	t.equal(document.sprite.frame_count(), 3, "undo restores the frame")


static func _test_merge_down(t: PPTestCase) -> void:
	var document: PPDocument = PPDocument.create(Vector2i(4, 4))
	document.sprite.get_cel(0, 0).image.fill(Color(1.0, 0.0, 0.0, 1.0))

	var top: PPLayer = PPLayer.create("Top", 1, document.sprite.size)
	document.sprite.add_layer(top, 1)
	# Half-opaque white covering only the left half.
	top.cels[0].image.fill_rect(Rect2i(0, 0, 2, 4), Color(1.0, 1.0, 1.0, 0.5))

	document.history.push(PPLayerCommands.MergeDown.create(document.sprite, 1))
	t.equal(document.sprite.layer_count(), 1, "merge down removes the upper layer")

	var merged: Image = document.sprite.get_cel(0, 0).image
	t.pixel(merged, 0, 0, Color(1.0, 0.5, 0.5, 1.0), "merged pixel blends the two layers")
	t.pixel(merged, 3, 0, Color(1.0, 0.0, 0.0, 1.0), "untouched pixel keeps the base colour")

	document.history.undo()
	t.equal(document.sprite.layer_count(), 2, "undo restores the merged layer")
	t.pixel(
		document.sprite.get_cel(0, 0).image,
		0,
		0,
		Color(1.0, 0.0, 0.0, 1.0),
		"undo restores the lower layer's original pixels"
	)


static func _test_selection(t: PPTestCase) -> void:
	var selection: PPSelection = PPSelection.new(Vector2i(8, 8))
	t.check(selection.is_empty(), "a fresh selection is empty")

	var scratch: PackedByteArray = selection.make_scratch()
	for y: int in range(2, 6):
		for x: int in range(2, 6):
			scratch[y * 8 + x] = 255
	selection.apply(scratch, PPTypes.SelectionOp.REPLACE)

	t.check(not selection.is_empty(), "selection is now populated")
	t.equal(selection.get_bounds(), Rect2i(2, 2, 4, 4), "bounds track the selected rect")
	t.check(selection.contains(3, 3), "inside is selected")
	t.check(not selection.contains(1, 1), "outside is not selected")

	var subtract: PackedByteArray = selection.make_scratch()
	for y: int in range(4, 8):
		for x: int in range(4, 8):
			subtract[y * 8 + x] = 255
	selection.apply(subtract, PPTypes.SelectionOp.SUBTRACT)
	t.check(not selection.contains(5, 5), "subtracted region is deselected")
	t.check(selection.contains(2, 2), "untouched region survives subtraction")

	selection.clear()
	t.check(selection.is_empty(), "clear empties the selection")

	# An empty selection must mean "paint anywhere", not "paint nowhere".
	t.equal(
		selection.get_paint_mask().size(), 0, "an empty selection yields an unmasked paint mask"
	)


static func _test_geometry(t: PPTestCase) -> void:
	var document: PPDocument = PPDocument.create(Vector2i(4, 2))
	document.sprite.get_cel(0, 0).image.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 1.0))

	document.history.push(PPSpriteCommands.flip(document.sprite, true))
	t.pixel(
		document.sprite.get_cel(0, 0).image,
		3,
		0,
		Color(1.0, 0.0, 0.0, 1.0),
		"horizontal flip moves the pixel to the far edge"
	)
	document.history.undo()
	t.pixel(
		document.sprite.get_cel(0, 0).image,
		0,
		0,
		Color(1.0, 0.0, 0.0, 1.0),
		"undo restores the flip"
	)

	document.history.push(PPSpriteCommands.rotate(document.sprite, 90))
	t.equal(document.sprite.size, Vector2i(2, 4), "90° rotation swaps the canvas dimensions")
	t.pixel(
		document.sprite.get_cel(0, 0).image,
		1,
		0,
		Color(1.0, 0.0, 0.0, 1.0),
		"90° rotation moves (0,0) to the top-right"
	)
	document.history.undo()
	t.equal(document.sprite.size, Vector2i(4, 2), "undo restores the canvas size")

	document.history.push(
		PPSpriteCommands.resize_canvas(document.sprite, Vector2i(8, 8), Vector2i(2, 2))
	)
	t.equal(document.sprite.size, Vector2i(8, 8), "canvas resized")
	t.pixel(
		document.sprite.get_cel(0, 0).image,
		2,
		2,
		Color(1.0, 0.0, 0.0, 1.0),
		"resize offsets the old content"
	)
	t.equal(document.selection.size, Vector2i(8, 8), "selection follows the canvas size")

	document.history.push(PPSpriteCommands.scale_sprite(document.sprite, Vector2i(16, 16)))
	t.equal(document.sprite.size, Vector2i(16, 16), "sprite scaled")
	t.pixel(
		document.sprite.get_cel(0, 0).image,
		5,
		5,
		Color(1.0, 0.0, 0.0, 1.0),
		"nearest-neighbour scaling doubles the pixel"
	)


static func _test_palette(t: PPTestCase) -> void:
	var document: PPDocument = PPDocument.create(Vector2i(4, 4))
	var replacement: PPPalette = PPPalette.create(
		"Test",
		PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	)

	document.history.push(
		PPPaletteCommand.create(document.sprite.palette, replacement, "Load Palette")
	)
	t.equal(document.sprite.palette.size(), 3, "palette loaded")
	t.equal(document.sprite.palette.find_color(Color.GREEN), 1, "exact colour lookup")
	t.equal(
		document.sprite.palette.find_nearest(Color(0.9, 0.1, 0.1)),
		0,
		"nearest colour lookup snaps to red"
	)

	document.history.undo()
	t.equal(document.sprite.palette.size(), 0, "undo restores the empty palette")
