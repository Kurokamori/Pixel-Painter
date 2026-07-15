@abstract
class_name PPPaintOps
extends RefCounted

## The single place where "coverage + colour + a mode" becomes pixels.
##
## Both the freehand stroke engine (which accumulates coverage incrementally)
## and the shape tools (which rebuild coverage from scratch on every drag frame)
## route through compose_region(). Two implementations of alpha compositing that
## must agree pixel-for-pixel is a bug waiting to happen -- so there is one.

enum Mode {
	PAINT,
	ERASE,
}


## Writes `snapshot` recomposed through `coverage` into `working`, over `rect`.
##
## `selection_mask` may be empty, meaning unmasked. `lock_alpha` recolours only
## already-opaque pixels and never alters their alpha.
static func compose_region(
	working: PackedByteArray,
	snapshot: PackedByteArray,
	coverage: PackedByteArray,
	canvas: Vector2i,
	rect: Rect2i,
	color: Color,
	mode: Mode,
	selection_mask: PackedByteArray,
	lock_alpha: bool
) -> void:
	var clipped: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, canvas))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return

	var has_selection: bool = selection_mask.size() == canvas.x * canvas.y

	for y: int in range(clipped.position.y, clipped.position.y + clipped.size.y):
		var row: int = y * canvas.x
		for x: int in range(clipped.position.x, clipped.position.x + clipped.size.x):
			var pixel: int = row + x
			var i: int = pixel * PPTypes.BPP

			var cover: int = coverage[pixel]
			if has_selection and cover > 0:
				cover = (cover * selection_mask[pixel]) / 255

			if cover == 0:
				_copy_pixel(working, snapshot, i)
				continue

			if mode == Mode.ERASE:
				var erased_alpha: int = (snapshot[i + 3] * (255 - cover)) / 255
				if erased_alpha == 0:
					# Zero the colour too, not just the alpha. Leaving stale RGB
					# under a fully transparent pixel is invisible here but bleeds
					# back out as coloured halos the moment something downstream
					# filters or mipmaps the exported PNG.
					working[i] = 0
					working[i + 1] = 0
					working[i + 2] = 0
					working[i + 3] = 0
					continue
				working[i] = snapshot[i]
				working[i + 1] = snapshot[i + 1]
				working[i + 2] = snapshot[i + 2]
				working[i + 3] = erased_alpha
				continue

			if lock_alpha and snapshot[i + 3] == 0:
				_copy_pixel(working, snapshot, i)
				continue

			var src_a: float = color.a * (float(cover) / 255.0)
			var dst_a: float = float(snapshot[i + 3]) / 255.0
			var out_a: float = src_a + dst_a * (1.0 - src_a)

			if out_a <= 0.0:
				working[i] = 0
				working[i + 1] = 0
				working[i + 2] = 0
				working[i + 3] = 0
				continue

			var inv: float = dst_a * (1.0 - src_a)
			working[i] = _mix(color.r, float(snapshot[i]) / 255.0, src_a, inv, out_a)
			working[i + 1] = _mix(color.g, float(snapshot[i + 1]) / 255.0, src_a, inv, out_a)
			working[i + 2] = _mix(color.b, float(snapshot[i + 2]) / 255.0, src_a, inv, out_a)

			if lock_alpha:
				working[i + 3] = snapshot[i + 3]
			else:
				working[i + 3] = clampi(int(round(out_a * 255.0)), 0, 255)


## Stamps a brush along every cell and returns the resulting coverage buffer.
## Used by the shape tools, which have their whole cell list up front.
static func build_coverage(
	canvas: Vector2i,
	cells: Array[Vector2i],
	brush: PPBrush,
	alpha: int,
	symmetry: PPTypes.SymmetryMode
) -> PackedByteArray:
	var coverage: PackedByteArray = PackedByteArray()
	coverage.resize(canvas.x * canvas.y)
	coverage.fill(0)

	for cell: Vector2i in cells:
		for mirrored: Vector2i in mirror_cell(cell, canvas, symmetry):
			brush.stamp(coverage, canvas, mirrored, alpha)

	return coverage


## Coverage straight from a mask (bucket fill, magic-wand-driven fills), with no
## brush involved: the mask *is* the coverage.
static func coverage_from_mask(mask: PackedByteArray) -> PackedByteArray:
	return mask.duplicate()


static func mirror_cell(
	cell: Vector2i, canvas: Vector2i, symmetry: PPTypes.SymmetryMode
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	var flip_x: int = canvas.x - 1 - cell.x
	var flip_y: int = canvas.y - 1 - cell.y

	match symmetry:
		PPTypes.SymmetryMode.HORIZONTAL:
			if flip_x != cell.x:
				cells.append(Vector2i(flip_x, cell.y))
		PPTypes.SymmetryMode.VERTICAL:
			if flip_y != cell.y:
				cells.append(Vector2i(cell.x, flip_y))
		PPTypes.SymmetryMode.BOTH:
			if flip_x != cell.x:
				cells.append(Vector2i(flip_x, cell.y))
			if flip_y != cell.y:
				cells.append(Vector2i(cell.x, flip_y))
			if flip_x != cell.x or flip_y != cell.y:
				cells.append(Vector2i(flip_x, flip_y))
	return cells


## Bounding box of a cell list once the brush footprint is accounted for.
static func bounds_of(
	cells: Array[Vector2i], brush: PPBrush, canvas: Vector2i, symmetry: PPTypes.SymmetryMode
) -> Rect2i:
	if cells.is_empty():
		return Rect2i()

	var bounds: Rect2i = Rect2i()
	var first: bool = true
	for cell: Vector2i in cells:
		for mirrored: Vector2i in mirror_cell(cell, canvas, symmetry):
			var rect: Rect2i = brush.get_rect(mirrored)
			if first:
				bounds = rect
				first = false
			else:
				bounds = bounds.merge(rect)
	return bounds.intersection(Rect2i(Vector2i.ZERO, canvas))


## Bounding box of every set pixel in a coverage mask.
static func bounds_of_mask(mask: PackedByteArray, canvas: Vector2i) -> Rect2i:
	var min_x: int = canvas.x
	var min_y: int = canvas.y
	var max_x: int = -1
	var max_y: int = -1

	for y: int in range(canvas.y):
		var row: int = y * canvas.x
		for x: int in range(canvas.x):
			if mask[row + x] == 0:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)

	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


static func _copy_pixel(dst: PackedByteArray, src: PackedByteArray, i: int) -> void:
	dst[i] = src[i]
	dst[i + 1] = src[i + 1]
	dst[i + 2] = src[i + 2]
	dst[i + 3] = src[i + 3]


static func _mix(src: float, dst: float, src_a: float, inv: float, out_a: float) -> int:
	var value: float = (src * src_a + dst * inv) / out_a
	return clampi(int(round(value * 255.0)), 0, 255)
