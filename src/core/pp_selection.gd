class_name PPSelection
extends RefCounted

## An 8-bit coverage mask over the sprite. 0 = outside, 255 = fully selected.
##
## Coverage is stored per pixel rather than as a boolean so that the magic wand
## and lasso can produce soft edges, and so tools can multiply their alpha by
## the mask directly (see PPBlend.blend_buffer's `mask` argument).
##
## An *empty* selection means "no selection active", which every tool treats as
## "the whole canvas is editable" -- not as "nothing is editable".

signal changed()

var size: Vector2i = Vector2i.ZERO
var mask: PackedByteArray = PackedByteArray()

var _bounds: Rect2i = Rect2i()
var _bounds_dirty: bool = true


func _init(sprite_size: Vector2i = Vector2i.ZERO) -> void:
	resize(sprite_size)


func resize(new_size: Vector2i) -> void:
	size = new_size
	mask = PackedByteArray()
	mask.resize(maxi(0, new_size.x * new_size.y))
	mask.fill(0)
	_bounds_dirty = true
	changed.emit()


func is_empty() -> bool:
	return get_bounds().size == Vector2i.ZERO


func clear() -> void:
	mask.fill(0)
	_bounds = Rect2i()
	_bounds_dirty = false
	changed.emit()


func select_all() -> void:
	mask.fill(255)
	_bounds = Rect2i(Vector2i.ZERO, size)
	_bounds_dirty = false
	changed.emit()


func contains(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return false
	return mask[y * size.x + x] > 0


func coverage_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return 0
	return mask[y * size.x + x]


## The mask to hand to painting operations: an empty selection yields an empty
## array, which PPBlend reads as "unmasked".
func get_paint_mask() -> PackedByteArray:
	if is_empty():
		return PackedByteArray()
	return mask


func get_bounds() -> Rect2i:
	if not _bounds_dirty:
		return _bounds
	_bounds_dirty = false
	_bounds = Rect2i()

	var min_x: int = size.x
	var min_y: int = size.y
	var max_x: int = -1
	var max_y: int = -1
	for y: int in range(size.y):
		var row: int = y * size.x
		for x: int in range(size.x):
			if mask[row + x] == 0:
				continue
			if x < min_x:
				min_x = x
			if x > max_x:
				max_x = x
			if y < min_y:
				min_y = y
			if y > max_y:
				max_y = y
	if max_x >= 0:
		_bounds = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	return _bounds


## Combines `other` (a full-size coverage buffer) into this mask.
func apply(other: PackedByteArray, op: PPTypes.SelectionOp) -> void:
	if other.size() != mask.size():
		return
	match op:
		PPTypes.SelectionOp.REPLACE:
			mask = other.duplicate()
		PPTypes.SelectionOp.ADD:
			for i: int in range(mask.size()):
				mask[i] = maxi(mask[i], other[i])
		PPTypes.SelectionOp.SUBTRACT:
			for i: int in range(mask.size()):
				mask[i] = maxi(0, mask[i] - other[i])
		PPTypes.SelectionOp.INTERSECT:
			for i: int in range(mask.size()):
				mask[i] = mini(mask[i], other[i])
	_bounds_dirty = true
	changed.emit()


func invert() -> void:
	for i: int in range(mask.size()):
		mask[i] = 255 - mask[i]
	_bounds_dirty = true
	changed.emit()


func set_mask(buffer: PackedByteArray) -> void:
	if buffer.size() != size.x * size.y:
		return
	mask = buffer.duplicate()
	_bounds_dirty = true
	changed.emit()


func duplicate_selection() -> PPSelection:
	var copy: PPSelection = PPSelection.new(size)
	copy.mask = mask.duplicate()
	copy._bounds_dirty = true
	return copy


## Builds a blank full-size coverage buffer for a tool to rasterise into before
## handing it back to apply().
func make_scratch() -> PackedByteArray:
	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(size.x * size.y)
	buffer.fill(0)
	return buffer


## Boundary segments between selected and unselected pixels, in pixel space.
## The canvas renders these as the marching-ants outline. Returned as pairs of
## points: [a0, b0, a1, b1, ...].
func build_outline() -> PackedVector2Array:
	var segments: PackedVector2Array = PackedVector2Array()
	if is_empty():
		return segments
	var bounds: Rect2i = get_bounds()
	for y: int in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x: int in range(bounds.position.x, bounds.position.x + bounds.size.x):
			if not contains(x, y):
				continue
			if not contains(x, y - 1):
				segments.append(Vector2(x, y))
				segments.append(Vector2(x + 1, y))
			if not contains(x, y + 1):
				segments.append(Vector2(x, y + 1))
				segments.append(Vector2(x + 1, y + 1))
			if not contains(x - 1, y):
				segments.append(Vector2(x, y))
				segments.append(Vector2(x, y + 1))
			if not contains(x + 1, y):
				segments.append(Vector2(x + 1, y))
				segments.append(Vector2(x + 1, y + 1))
	return segments
