class_name PPPixelsCommand
extends PPCommand

## A pixel edit confined to a rect of one cel.
##
## Only the rect's bytes are kept, zstd-compressed, so a one-pixel dab on a
## 1024x1024 canvas costs a handful of bytes of history instead of 4 MB. The cel
## is referenced by object rather than by (layer, frame) index: indices move when
## the user reorders layers, but the PPCel instance is stable -- and when the cel
## is linked across frames, the object identity is exactly what we want to hit.

var _cel: PPCel = null
var _rect: Rect2i = Rect2i()
var _before: PackedByteArray = PackedByteArray()
var _after: PackedByteArray = PackedByteArray()
var _raw_size: int = 0


## `before` and `after` are full-canvas RGBA8 buffers of the cel. Returns null
## when nothing actually changed, so no-op strokes never reach the undo stack.
static func create(
	cel: PPCel,
	sprite_size: Vector2i,
	before: PackedByteArray,
	after: PackedByteArray,
	hint_rect: Rect2i,
	label_text: String
) -> PPPixelsCommand:
	var changed_rect: Rect2i = _diff_rect(before, after, sprite_size, hint_rect)
	if changed_rect.size.x <= 0 or changed_rect.size.y <= 0:
		return null

	var command: PPPixelsCommand = PPPixelsCommand.new()
	command.label = label_text
	command._cel = cel
	command._rect = changed_rect
	command._raw_size = changed_rect.size.x * changed_rect.size.y * PPTypes.BPP
	command._before = _compress(
		_extract(before, sprite_size, changed_rect)
	)
	command._after = _compress(
		_extract(after, sprite_size, changed_rect)
	)
	return command


func redo(document: PPDocument) -> void:
	_write(document, _after)


func undo(document: PPDocument) -> void:
	_write(document, _before)


func get_dirty_rect(_document: PPDocument) -> Rect2i:
	return _rect


func get_cel() -> PPCel:
	return _cel


func _write(document: PPDocument, compressed: PackedByteArray) -> void:
	if _cel == null or _cel.image == null:
		return
	var bytes: PackedByteArray = compressed.decompress(
		_raw_size, FileAccess.COMPRESSION_ZSTD
	)
	var buffer: PackedByteArray = _cel.image.get_data()
	_inject(buffer, bytes, document.sprite.size, _rect)
	_cel.set_buffer(buffer)


## Narrows `hint_rect` to the pixels that genuinely differ. Tools report a
## generous bounding box (brush radius, shape extents); this trims it so history
## stays small and repaints stay tight.
static func _diff_rect(
	before: PackedByteArray, after: PackedByteArray, size: Vector2i, hint_rect: Rect2i
) -> Rect2i:
	var search: Rect2i = hint_rect.intersection(Rect2i(Vector2i.ZERO, size))
	if search.size.x <= 0 or search.size.y <= 0:
		return Rect2i()

	var min_x: int = search.position.x + search.size.x
	var min_y: int = search.position.y + search.size.y
	var max_x: int = -1
	var max_y: int = -1

	for y: int in range(search.position.y, search.position.y + search.size.y):
		var row: int = y * size.x
		for x: int in range(search.position.x, search.position.x + search.size.x):
			var i: int = (row + x) * PPTypes.BPP
			if (
				before[i] == after[i]
				and before[i + 1] == after[i + 1]
				and before[i + 2] == after[i + 2]
				and before[i + 3] == after[i + 3]
			):
				continue
			if x < min_x:
				min_x = x
			if x > max_x:
				max_x = x
			if y < min_y:
				min_y = y
			if y > max_y:
				max_y = y

	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


static func _extract(
	buffer: PackedByteArray, size: Vector2i, rect: Rect2i
) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(rect.size.x * rect.size.y * PPTypes.BPP)
	var row_bytes: int = rect.size.x * PPTypes.BPP
	var write_at: int = 0
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		var read_at: int = (y * size.x + rect.position.x) * PPTypes.BPP
		for b: int in range(row_bytes):
			out[write_at + b] = buffer[read_at + b]
		write_at += row_bytes
	return out


static func _inject(
	buffer: PackedByteArray, patch: PackedByteArray, size: Vector2i, rect: Rect2i
) -> void:
	var row_bytes: int = rect.size.x * PPTypes.BPP
	var read_at: int = 0
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		var write_at: int = (y * size.x + rect.position.x) * PPTypes.BPP
		for b: int in range(row_bytes):
			buffer[write_at + b] = patch[read_at + b]
		read_at += row_bytes


static func _compress(bytes: PackedByteArray) -> PackedByteArray:
	return bytes.compress(FileAccess.COMPRESSION_ZSTD)
