@abstract
class_name PPEditOps
extends RefCounted

## Menu- and shortcut-driven edits that are not gestures: selection commands,
## clipboard, nudge, and per-cel transforms.
##
## The clipboard is process-wide (a static) rather than the OS clipboard: it
## carries a mask alongside the pixels, so pasting a lasso'd shape pastes that
## shape and not its bounding box. Cross-application copy/paste goes through
## PNG export instead.

static var _clip_image: Image = null
static var _clip_mask: PackedByteArray = PackedByteArray()
static var _clip_size: Vector2i = Vector2i.ZERO


static func has_clipboard() -> bool:
	return _clip_image != null


# --- Selection --------------------------------------------------------------

static func select_all(document: PPDocument) -> void:
	var full: PackedByteArray = PackedByteArray()
	full.resize(document.sprite.size.x * document.sprite.size.y)
	full.fill(255)
	document.history.push(
		PPSelectionCommand.create(document.selection.mask.duplicate(), full, "Select All")
	)
	document.notify_selection_changed()


static func select_none(document: PPDocument) -> void:
	if document.selection.is_empty():
		return
	var empty: PackedByteArray = PackedByteArray()
	empty.resize(document.sprite.size.x * document.sprite.size.y)
	empty.fill(0)
	document.history.push(
		PPSelectionCommand.create(document.selection.mask.duplicate(), empty, "Deselect")
	)
	document.notify_selection_changed()


static func invert_selection(document: PPDocument) -> void:
	var before: PackedByteArray = document.selection.mask.duplicate()
	var inverted: PackedByteArray = before.duplicate()
	for i: int in range(inverted.size()):
		inverted[i] = 255 - inverted[i]
	document.history.push(
		PPSelectionCommand.create(before, inverted, "Invert Selection")
	)
	document.notify_selection_changed()


# --- Clipboard --------------------------------------------------------------

## Copies the selected pixels of the active cel (or the whole cel when nothing
## is selected) into the internal clipboard.
static func copy(document: PPDocument) -> bool:
	var cel: PPCel = document.get_active_cel()
	if cel == null or cel.image == null:
		return false

	var canvas: Vector2i = document.sprite.size
	var mask: PackedByteArray = document.selection.mask.duplicate()
	if document.selection.is_empty():
		mask.fill(255)

	var bounds: Rect2i = PPPaintOps.bounds_of_mask(mask, canvas)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false

	var source: PackedByteArray = cel.image.get_data()
	var clip: PackedByteArray = PackedByteArray()
	clip.resize(bounds.size.x * bounds.size.y * PPTypes.BPP)
	clip.fill(0)

	var clip_mask: PackedByteArray = PackedByteArray()
	clip_mask.resize(bounds.size.x * bounds.size.y)
	clip_mask.fill(0)

	for y: int in range(bounds.size.y):
		for x: int in range(bounds.size.x):
			var src_pixel: int = (bounds.position.y + y) * canvas.x + bounds.position.x + x
			var dst_pixel: int = y * bounds.size.x + x
			var coverage: int = mask[src_pixel]
			clip_mask[dst_pixel] = coverage
			if coverage == 0:
				continue
			var si: int = src_pixel * PPTypes.BPP
			var di: int = dst_pixel * PPTypes.BPP
			clip[di] = source[si]
			clip[di + 1] = source[si + 1]
			clip[di + 2] = source[si + 2]
			clip[di + 3] = (source[si + 3] * coverage) / 255

	_clip_image = Image.create_from_data(
		bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8, clip
	)
	_clip_mask = clip_mask
	_clip_size = bounds.size
	return true


static func cut(document: PPDocument) -> bool:
	if not copy(document):
		return false
	document.history.begin_group("Cut")
	delete_selection(document)
	document.history.end_group()
	return true


## Pastes the clipboard into the active cel, anchored at `at`. The pasted region
## becomes the new selection, so it can be moved immediately.
static func paste(document: PPDocument, at: Vector2i = Vector2i.ZERO) -> bool:
	if _clip_image == null or not document.can_paint():
		return false

	var cel: PPCel = document.get_active_cel()
	var canvas: Vector2i = document.sprite.size
	var snapshot: PackedByteArray = cel.image.get_data()
	var working: PackedByteArray = snapshot.duplicate()
	var clip: PackedByteArray = _clip_image.get_data()

	var new_mask: PackedByteArray = PackedByteArray()
	new_mask.resize(canvas.x * canvas.y)
	new_mask.fill(0)

	for y: int in range(_clip_size.y):
		var ty: int = at.y + y
		if ty < 0 or ty >= canvas.y:
			continue
		for x: int in range(_clip_size.x):
			var tx: int = at.x + x
			if tx < 0 or tx >= canvas.x:
				continue

			var src_pixel: int = y * _clip_size.x + x
			if _clip_mask[src_pixel] == 0:
				continue

			var dst_pixel: int = ty * canvas.x + tx
			new_mask[dst_pixel] = _clip_mask[src_pixel]

			var si: int = src_pixel * PPTypes.BPP
			var di: int = dst_pixel * PPTypes.BPP

			var src_a: float = float(clip[si + 3]) / 255.0
			var dst_a: float = float(working[di + 3]) / 255.0
			var out_a: float = src_a + dst_a * (1.0 - src_a)
			if out_a <= 0.0:
				working[di] = 0
				working[di + 1] = 0
				working[di + 2] = 0
				working[di + 3] = 0
				continue

			var inv: float = dst_a * (1.0 - src_a)
			for c: int in range(3):
				var src: float = float(clip[si + c]) / 255.0
				var dst: float = float(working[di + c]) / 255.0
				working[di + c] = clampi(
					int(round(((src * src_a + dst * inv) / out_a) * 255.0)), 0, 255
				)
			working[di + 3] = clampi(int(round(out_a * 255.0)), 0, 255)

	var rect: Rect2i = Rect2i(at, _clip_size).intersection(document.sprite.get_bounds())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false

	var before_mask: PackedByteArray = document.selection.mask.duplicate()
	cel.image = Image.create_from_data(
		canvas.x, canvas.y, false, Image.FORMAT_RGBA8, working
	)

	document.history.begin_group("Paste")
	document.history.push_applied(
		PPPixelsCommand.create(cel, canvas, snapshot, working, rect, "Paste")
	)
	document.history.push(
		PPSelectionCommand.create(before_mask, new_mask, "Paste Selection")
	)
	document.history.end_group()

	document.refresh_composite(rect)
	document.notify_selection_changed()
	return true


static func delete_selection(document: PPDocument) -> bool:
	if not document.can_paint():
		return false

	var cel: PPCel = document.get_active_cel()
	var canvas: Vector2i = document.sprite.size
	var mask: PackedByteArray = document.selection.mask.duplicate()
	if document.selection.is_empty():
		mask.fill(255)

	var rect: Rect2i = PPPaintOps.bounds_of_mask(mask, canvas)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false

	var snapshot: PackedByteArray = cel.image.get_data()
	var working: PackedByteArray = snapshot.duplicate()

	PPPaintOps.compose_region(
		working,
		snapshot,
		mask,
		canvas,
		rect,
		Color.BLACK,
		PPPaintOps.Mode.ERASE,
		PackedByteArray(),
		false
	)

	cel.image = Image.create_from_data(
		canvas.x, canvas.y, false, Image.FORMAT_RGBA8, working
	)
	document.history.push_applied(
		PPPixelsCommand.create(cel, canvas, snapshot, working, rect, "Delete")
	)
	document.refresh_composite(rect)
	return true


# --- Nudge ------------------------------------------------------------------

## Arrow-key nudge: shifts the selected pixels (or the whole cel) by `delta`.
static func nudge(document: PPDocument, delta: Vector2i) -> bool:
	if not document.can_paint() or delta == Vector2i.ZERO:
		return false

	var cel: PPCel = document.get_active_cel()
	var canvas: Vector2i = document.sprite.size
	var had_selection: bool = not document.selection.is_empty()

	var mask: PackedByteArray = document.selection.mask.duplicate()
	if not had_selection:
		mask.fill(255)

	var snapshot: PackedByteArray = cel.image.get_data()
	var working: PackedByteArray = snapshot.duplicate()

	# Punch the hole, then stamp the lifted pixels back at the offset.
	for pixel: int in range(canvas.x * canvas.y):
		if mask[pixel] == 0:
			continue
		var i: int = pixel * PPTypes.BPP
		var hole_alpha: int = (snapshot[i + 3] * (255 - mask[pixel])) / 255
		if hole_alpha == 0:
			working[i] = 0
			working[i + 1] = 0
			working[i + 2] = 0
		working[i + 3] = hole_alpha

	for y: int in range(canvas.y):
		var source_y: int = y - delta.y
		if source_y < 0 or source_y >= canvas.y:
			continue
		for x: int in range(canvas.x):
			var source_x: int = x - delta.x
			if source_x < 0 or source_x >= canvas.x:
				continue
			var source_pixel: int = source_y * canvas.x + source_x
			if mask[source_pixel] == 0:
				continue

			var si: int = source_pixel * PPTypes.BPP
			var di: int = (y * canvas.x + x) * PPTypes.BPP
			var src_a: float = (
				(float(snapshot[si + 3]) / 255.0) * (float(mask[source_pixel]) / 255.0)
			)
			if src_a <= 0.0:
				continue
			var dst_a: float = float(working[di + 3]) / 255.0
			var out_a: float = src_a + dst_a * (1.0 - src_a)
			if out_a <= 0.0:
				continue

			var inv: float = dst_a * (1.0 - src_a)
			for c: int in range(3):
				var src: float = float(snapshot[si + c]) / 255.0
				var dst: float = float(working[di + c]) / 255.0
				working[di + c] = clampi(
					int(round(((src * src_a + dst * inv) / out_a) * 255.0)), 0, 255
				)
			working[di + 3] = clampi(int(round(out_a * 255.0)), 0, 255)

	cel.image = Image.create_from_data(
		canvas.x, canvas.y, false, Image.FORMAT_RGBA8, working
	)

	document.history.begin_group("Nudge")
	document.history.push_applied(
		PPPixelsCommand.create(
			cel, canvas, snapshot, working, document.sprite.get_bounds(), "Nudge"
		)
	)
	if had_selection:
		document.history.push(
			PPSelectionCommand.create(
				document.selection.mask.duplicate(),
				PPToolMove._shift_mask_static(
					document.selection.mask.duplicate(), canvas, delta
				),
				"Nudge Selection"
			)
		)
	document.history.end_group()

	document.refresh_composite()
	document.notify_selection_changed()
	return true
