class_name PPStroke
extends RefCounted

## Accumulates one continuous mark and turns it into a single undo step.
##
## The stroke keeps three buffers over the target cel:
##
##   snapshot  the cel's pixels as they were when the stroke began (immutable)
##   coverage  8-bit "how much of this pixel has the stroke touched" (max-blended)
##   working   snapshot recomposed through coverage -- what the cel now shows
##
## Every dab writes into `coverage`, never straight into pixels. That indirection
## is what makes the hard parts work:
##
##  * overlapping dabs inside one stroke don't compound into a darker core, so a
##    semi-transparent brush paints an even wash instead of blobs at every
##    sample point;
##  * pixel-perfect can *retract* a dab it already laid down, because coverage
##    can be recomputed for a region from the dab list;
##  * the eraser is the same code path with one flag flipped.

## A single stamp of the brush. Kept so a region's coverage can be rebuilt from
## scratch when pixel-perfect retracts a corner.
class Dab:
	extends RefCounted

	var position: Vector2i = Vector2i.ZERO
	var brush: PPBrush = null
	var alpha: int = 255

	static func create(at: Vector2i, dab_brush: PPBrush, dab_alpha: int) -> Dab:
		var dab: Dab = Dab.new()
		dab.position = at
		dab.brush = dab_brush
		dab.alpha = dab_alpha
		return dab

	func get_rect() -> Rect2i:
		return brush.get_rect(position)


enum Mode {
	PAINT,
	ERASE,
}

var mode: Mode = Mode.PAINT
var color: Color = Color.BLACK

var _document: PPDocument = null
var _settings: PPToolSettings = null
var _cel: PPCel = null
var _canvas: Vector2i = Vector2i.ZERO

var _snapshot: PackedByteArray = PackedByteArray()
var _working: PackedByteArray = PackedByteArray()
var _coverage: PackedByteArray = PackedByteArray()
var _selection_mask: PackedByteArray = PackedByteArray()

var _dabs: Array[Dab] = []
var _dirty: Rect2i = Rect2i()
var _has_dirty: bool = false

var _pixel_perfect: PPPixelPerfect = PPPixelPerfect.new()
var _use_pixel_perfect: bool = false
var _last_cell: Vector2i = Vector2i.ZERO
var _has_last_cell: bool = false

## Maps a dab back to the symmetry siblings emitted alongside it, so retracting
## a pixel-perfect corner retracts its mirrors too.
var _sibling_count: int = 1


func begin(
	document: PPDocument,
	settings: PPToolSettings,
	stroke_mode: Mode,
	stroke_color: Color,
	use_pixel_perfect: bool
) -> bool:
	if not document.can_paint():
		return false

	_document = document
	_settings = settings
	_cel = document.get_active_cel()
	_canvas = document.sprite.size
	mode = stroke_mode
	color = stroke_color

	# Pixel-perfect corrects the *path* of a 1px line. With a wide brush there is
	# no staircase to correct -- the dab already covers the corner -- so the
	# filter would only punch holes in the stroke.
	_use_pixel_perfect = use_pixel_perfect and settings.brush_size == 1

	_snapshot = _cel.image.get_data()
	_working = _snapshot.duplicate()
	_coverage = PackedByteArray()
	_coverage.resize(_canvas.x * _canvas.y)
	_coverage.fill(0)
	_selection_mask = document.selection.get_paint_mask()

	_dabs.clear()
	_pixel_perfect.reset()
	_has_last_cell = false
	_has_dirty = false
	_dirty = Rect2i()
	_sibling_count = _count_symmetry_siblings()

	return true


## Adds a pointer sample. Cells between this sample and the previous one are
## interpolated, so a fast flick still lays down a connected line.
func extend(pointer: PPPointer) -> void:
	var cell: Vector2i = pointer.get_cell()

	if not _has_last_cell:
		_emit(cell, pointer)
		_last_cell = cell
		_has_last_cell = true
		return

	if cell == _last_cell:
		return

	var path: Array[Vector2i] = PPRaster.line(_last_cell, cell)
	# line() includes its start point, which we already stamped.
	for i: int in range(1, path.size()):
		_emit(path[i], pointer)
	_last_cell = cell


## Stamps one cell, running it through the pixel-perfect filter first.
func _emit(cell: Vector2i, pointer: PPPointer) -> void:
	if not _use_pixel_perfect:
		_stamp(cell, pointer)
		return

	var retracted: Variant = _pixel_perfect.push(cell)
	_stamp(cell, pointer)

	if retracted != null:
		_retract(retracted as Vector2i)


func _stamp(cell: Vector2i, pointer: PPPointer) -> void:
	var size: int = _settings.size_for_pressure(pointer.pressure)
	var alpha: int = _settings.alpha_for_pressure(pointer.pressure)
	var brush: PPBrush = PPBrush.get_brush(_settings.brush_shape, size)

	for mirrored: Vector2i in _mirror(cell):
		var dab: Dab = Dab.create(mirrored, brush, alpha)
		_dabs.append(dab)
		brush.stamp(_coverage, _canvas, mirrored, alpha)
		_apply_region(dab.get_rect())


## Removes the last-emitted dab (and its symmetry siblings) after pixel-perfect
## decides the cell was a redundant corner.
func _retract(cell: Vector2i) -> void:
	var removed: Array[Dab] = []
	# The retracted cell and its mirrors are the most recent dabs, so walk back
	# from the end rather than scanning the whole stroke.
	var index: int = _dabs.size() - 1
	while index >= 0 and removed.size() < _sibling_count:
		var dab: Dab = _dabs[index]
		if _is_mirror_of(dab.position, cell):
			removed.append(dab)
			_dabs.remove_at(index)
		index -= 1

	for dab: Dab in removed:
		var rect: Rect2i = dab.get_rect()
		_rebuild_coverage(rect)
		_apply_region(rect)


## Recomputes coverage inside `rect` from the surviving dab list.
##
## A cheap "subtract this dab" would be wrong: the stroke may have crossed itself,
## and other dabs -- possibly from far earlier in the stroke -- can legitimately
## cover the same pixels. So the region is cleared and every dab whose footprint
## touches it is re-stamped. Testing footprints is an integer rect check, so this
## stays fast even for a long, self-crossing stroke.
func _rebuild_coverage(rect: Rect2i) -> void:
	var clipped: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, _canvas))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return

	for y: int in range(clipped.position.y, clipped.position.y + clipped.size.y):
		var row: int = y * _canvas.x
		for x: int in range(clipped.position.x, clipped.position.x + clipped.size.x):
			_coverage[row + x] = 0

	for dab: Dab in _dabs:
		if dab.get_rect().intersects(clipped):
			dab.brush.stamp(_coverage, _canvas, dab.position, dab.alpha)


## Recomposes `working` from `snapshot` through `coverage` over one rect, then
## pushes the result to the cel and repaints just that rect.
func _apply_region(rect: Rect2i) -> void:
	var clipped: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, _canvas))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return

	var paint_mode: PPPaintOps.Mode = (
		PPPaintOps.Mode.ERASE if mode == Mode.ERASE else PPPaintOps.Mode.PAINT
	)
	PPPaintOps.compose_region(
		_working,
		_snapshot,
		_coverage,
		_canvas,
		clipped,
		color,
		paint_mode,
		_selection_mask,
		_settings.lock_alpha
	)

	_cel.image = Image.create_from_data(
		_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8, _working
	)
	_grow_dirty(clipped)
	_document.refresh_composite(clipped)


func _grow_dirty(rect: Rect2i) -> void:
	if not _has_dirty:
		_dirty = rect
		_has_dirty = true
		return
	_dirty = _dirty.merge(rect)


## Mirror positions for the active symmetry mode, including the original.
func _mirror(cell: Vector2i) -> Array[Vector2i]:
	return PPPaintOps.mirror_cell(cell, _canvas, _settings.symmetry)


func _is_mirror_of(candidate: Vector2i, cell: Vector2i) -> bool:
	for mirrored: Vector2i in _mirror(cell):
		if mirrored == candidate:
			return true
	return false


func _count_symmetry_siblings() -> int:
	match _settings.symmetry:
		PPTypes.SymmetryMode.HORIZONTAL, PPTypes.SymmetryMode.VERTICAL:
			return 2
		PPTypes.SymmetryMode.BOTH:
			return 4
	return 1


## Ends the stroke and hands back the undo step. The cel already shows the
## result, so callers use PPHistory.push_applied(), not push().
func end() -> PPCommand:
	if not _has_dirty:
		return null
	var label: String = "Erase" if mode == Mode.ERASE else "Paint"
	return PPPixelsCommand.create(
		_cel, _canvas, _snapshot, _working, _dirty, label
	)


## Abandons the stroke, restoring the cel to its pre-stroke pixels.
func cancel() -> void:
	if not _has_dirty:
		return
	_cel.set_buffer(_snapshot)
	_document.refresh_composite(_dirty)
