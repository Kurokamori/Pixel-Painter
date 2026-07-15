@abstract
class_name PPGifIO
extends RefCounted

## GIF89a encoder for animated exports.
##
## GIF gives us 256 indices, one of which has to be spent on transparency, so
## the real budget is 255 colours across the *whole* animation (a single global
## colour table keeps the file small and avoids per-frame palette flicker).
## Sprites usually fit well under that; when they do not, a median-cut quantiser
## reduces them.
##
## The LZW coder follows the GIF spec's variable-width scheme: codes are packed
## least-significant-bit first, the code width grows as the dictionary fills,
## and the dictionary is reset with a Clear Code once it reaches 4096 entries.

const MAX_COLORS: int = 255
const MIN_DELAY_CS: int = 2


static func supported_extensions() -> PackedStringArray:
	return PackedStringArray(["gif"])


static func save_animation(
	frames: Array[Image], delays_ms: Array[int], path: String, loop: bool = true
) -> Error:
	var bytes: PackedByteArray = encode_animation(frames, delays_ms, loop)
	if bytes.is_empty():
		return ERR_CANT_CREATE

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.close()
	return OK


static func encode_animation(
	frames: Array[Image], delays_ms: Array[int], loop: bool = true
) -> PackedByteArray:
	if frames.is_empty():
		return PackedByteArray()

	var width: int = frames[0].get_width()
	var height: int = frames[0].get_height()
	if width <= 0 or height <= 0 or width > 65535 or height > 65535:
		return PackedByteArray()

	var palette: PackedColorArray = _build_palette(frames)
	var transparent_index: int = palette.size()

	# The colour table must be a power of two and hold the transparent slot too.
	var table_size: int = 2
	while table_size < palette.size() + 1:
		table_size *= 2
	table_size = mini(table_size, 256)

	var color_bits: int = 0
	var probe: int = table_size
	while probe > 1:
		probe >>= 1
		color_bits += 1

	var lookup: Dictionary[int, int] = {}
	for i: int in range(palette.size()):
		lookup[_pack(palette[i])] = i

	var out: PackedByteArray = PackedByteArray()

	out.append_array("GIF89a".to_ascii_buffer())

	# Logical Screen Descriptor.
	_put_u16(out, width)
	_put_u16(out, height)
	# Bit 7: global colour table present. Bits 0-2: table size as 2^(n+1).
	out.append(0x80 | (color_bits - 1))
	out.append(0)  # Background colour index.
	out.append(0)  # Pixel aspect ratio.

	# Global Colour Table, zero-padded out to the table size.
	for i: int in range(table_size):
		if i < palette.size():
			out.append(palette[i].r8)
			out.append(palette[i].g8)
			out.append(palette[i].b8)
		else:
			out.append(0)
			out.append(0)
			out.append(0)

	if loop:
		# NETSCAPE2.0 application extension: loop count 0 means forever.
		out.append_array(
			PackedByteArray([0x21, 0xFF, 0x0B])
		)
		out.append_array("NETSCAPE2.0".to_ascii_buffer())
		out.append_array(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))

	var min_code_size: int = maxi(2, color_bits)

	for frame_index: int in range(frames.size()):
		var frame: Image = frames[frame_index]
		if frame.get_width() != width or frame.get_height() != height:
			continue

		var delay_ms: int = 100
		if frame_index < delays_ms.size():
			delay_ms = delays_ms[frame_index]
		# GIF delays are in hundredths of a second. A zero delay is a special
		# case that browsers silently rewrite to ~100ms, so clamp to 2cs -- the
		# fastest value that is actually honoured.
		var delay_cs: int = maxi(MIN_DELAY_CS, int(round(float(delay_ms) / 10.0)))

		# Graphic Control Extension.
		out.append_array(PackedByteArray([0x21, 0xF9, 0x04]))
		# Disposal 2 (restore to background) + transparent colour flag.
		out.append((2 << 2) | 0x01)
		_put_u16(out, delay_cs)
		out.append(transparent_index)
		out.append(0)

		# Image Descriptor.
		out.append(0x2C)
		_put_u16(out, 0)
		_put_u16(out, 0)
		_put_u16(out, width)
		_put_u16(out, height)
		out.append(0)  # No local colour table, not interlaced.

		var indices: PackedByteArray = _map_pixels(
			frame, palette, lookup, transparent_index
		)
		out.append(min_code_size)
		_append_subblocks(out, _lzw_compress(indices, min_code_size))

	out.append(0x3B)  # Trailer.
	return out


# --- Palette construction ---------------------------------------------------

## Every distinct opaque colour across every frame, reduced to MAX_COLORS by
## median cut when there are too many.
static func _build_palette(frames: Array[Image]) -> PackedColorArray:
	var counts: Dictionary[int, int] = {}

	for frame: Image in frames:
		var data: PackedByteArray = frame.get_data()
		var pixels: int = frame.get_width() * frame.get_height()
		for i: int in range(pixels):
			var offset: int = i * PPTypes.BPP
			if data[offset + 3] < 128:
				continue
			var key: int = (
				(data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2]
			)
			counts[key] = counts.get(key, 0) + 1

	var unique: Array[int] = []
	for key: int in counts:
		unique.append(key)

	if unique.is_empty():
		return PackedColorArray([Color(0.0, 0.0, 0.0, 1.0)])

	if unique.size() <= MAX_COLORS:
		var exact: PackedColorArray = PackedColorArray()
		for key: int in unique:
			exact.append(_unpack(key))
		return exact

	return _median_cut(unique, counts, MAX_COLORS)


## Classic median cut: repeatedly split the box with the widest colour spread at
## the median of its longest axis, until there are as many boxes as colours
## wanted. Each box then contributes its (population-weighted) average.
static func _median_cut(
	keys: Array[int], counts: Dictionary[int, int], target: int
) -> PackedColorArray:
	var boxes: Array[Array] = [keys]

	while boxes.size() < target:
		var best_index: int = -1
		var best_range: int = -1

		for i: int in range(boxes.size()):
			var box: Array = boxes[i]
			if box.size() < 2:
				continue
			var spread: int = _longest_axis_range(box)
			if spread > best_range:
				best_range = spread
				best_index = i

		if best_index < 0 or best_range <= 0:
			break

		var box: Array = boxes[best_index]
		var axis: int = _longest_axis(box)
		box.sort_custom(
			func(a: int, b: int) -> bool:
				return _channel(a, axis) < _channel(b, axis)
		)

		var middle: int = box.size() / 2
		var lower: Array = box.slice(0, middle)
		var upper: Array = box.slice(middle)
		if lower.is_empty() or upper.is_empty():
			break

		boxes[best_index] = lower
		boxes.append(upper)

	var palette: PackedColorArray = PackedColorArray()
	for box: Array in boxes:
		if box.is_empty():
			continue
		var total: int = 0
		var sum_r: int = 0
		var sum_g: int = 0
		var sum_b: int = 0
		for key: int in box:
			var weight: int = counts.get(key, 1)
			total += weight
			sum_r += _channel(key, 0) * weight
			sum_g += _channel(key, 1) * weight
			sum_b += _channel(key, 2) * weight
		if total == 0:
			continue
		palette.append(
			Color8(sum_r / total, sum_g / total, sum_b / total, 255)
		)

	return palette


static func _longest_axis(box: Array) -> int:
	var best_axis: int = 0
	var best_range: int = -1
	for axis: int in range(3):
		var low: int = 255
		var high: int = 0
		for key: int in box:
			var value: int = _channel(key, axis)
			low = mini(low, value)
			high = maxi(high, value)
		var spread: int = high - low
		if spread > best_range:
			best_range = spread
			best_axis = axis
	return best_axis


static func _longest_axis_range(box: Array) -> int:
	var widest: int = 0
	for axis: int in range(3):
		var low: int = 255
		var high: int = 0
		for key: int in box:
			var value: int = _channel(key, axis)
			low = mini(low, value)
			high = maxi(high, value)
		widest = maxi(widest, high - low)
	return widest


static func _channel(key: int, axis: int) -> int:
	match axis:
		0:
			return (key >> 16) & 0xFF
		1:
			return (key >> 8) & 0xFF
	return key & 0xFF


static func _pack(color: Color) -> int:
	return (color.r8 << 16) | (color.g8 << 8) | color.b8


static func _unpack(key: int) -> Color:
	return Color8((key >> 16) & 0xFF, (key >> 8) & 0xFF, key & 0xFF, 255)


## Maps every pixel to a palette index. `lookup` memoises exact hits *and*
## quantised near-misses, so a large frame costs one nearest-colour search per
## distinct colour rather than one per pixel.
static func _map_pixels(
	frame: Image,
	palette: PackedColorArray,
	lookup: Dictionary[int, int],
	transparent_index: int
) -> PackedByteArray:
	var data: PackedByteArray = frame.get_data()
	var pixels: int = frame.get_width() * frame.get_height()

	var indices: PackedByteArray = PackedByteArray()
	indices.resize(pixels)

	for i: int in range(pixels):
		var offset: int = i * PPTypes.BPP
		if data[offset + 3] < 128:
			indices[i] = transparent_index
			continue

		var key: int = (
			(data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2]
		)
		if lookup.has(key):
			indices[i] = lookup[key]
			continue

		var nearest: int = _nearest(palette, data[offset], data[offset + 1], data[offset + 2])
		lookup[key] = nearest
		indices[i] = nearest

	return indices


static func _nearest(palette: PackedColorArray, r: int, g: int, b: int) -> int:
	var best: int = 0
	var best_distance: int = 1 << 30
	for i: int in range(palette.size()):
		var dr: int = palette[i].r8 - r
		var dg: int = palette[i].g8 - g
		var db: int = palette[i].b8 - b
		var distance: int = dr * dr + dg * dg + db * db
		if distance < best_distance:
			best_distance = distance
			best = i
			if distance == 0:
				break
	return best


# --- LZW --------------------------------------------------------------------

## Packs variable-width codes least-significant-bit first.
##
## This is an object rather than a closure on purpose: GDScript lambdas capture
## locals *by value*, so a closure writing to a captured buffer and bit counter
## would quietly discard everything it wrote.
class BitWriter:
	extends RefCounted

	var bytes: PackedByteArray = PackedByteArray()
	var _register: int = 0
	var _bits: int = 0

	func write(code: int, width: int) -> void:
		_register |= code << _bits
		_bits += width
		while _bits >= 8:
			bytes.append(_register & 0xFF)
			_register >>= 8
			_bits -= 8

	func flush() -> void:
		if _bits > 0:
			bytes.append(_register & 0xFF)
			_register = 0
			_bits = 0


## GIF-flavoured LZW. Returns the raw code stream; the caller wraps it in
## sub-blocks.
static func _lzw_compress(indices: PackedByteArray, min_code_size: int) -> PackedByteArray:
	var writer: BitWriter = BitWriter.new()

	var clear_code: int = 1 << min_code_size
	var end_code: int = clear_code + 1
	var next_code: int = end_code + 1
	var code_size: int = min_code_size + 1

	if indices.is_empty():
		writer.write(clear_code, code_size)
		writer.write(end_code, code_size)
		writer.flush()
		return writer.bytes

	var table: Dictionary[int, int] = {}
	writer.write(clear_code, code_size)

	var prefix: int = indices[0]

	for i: int in range(1, indices.size()):
		var k: int = indices[i]
		var key: int = (prefix << 8) | k

		if table.has(key):
			prefix = table[key]
			continue

		writer.write(prefix, code_size)

		if next_code == 4096:
			# Dictionary full: tell the decoder to reset, and start over.
			writer.write(clear_code, code_size)
			table.clear()
			next_code = end_code + 1
			code_size = min_code_size + 1
		else:
			# Widen *before* assigning, so the decoder -- which widens on the
			# same entry count -- stays in step with us.
			if next_code >= (1 << code_size) and code_size < 12:
				code_size += 1
			table[key] = next_code
			next_code += 1

		prefix = k

	writer.write(prefix, code_size)
	writer.write(end_code, code_size)
	writer.flush()

	return writer.bytes


## GIF image data is carried in length-prefixed sub-blocks of at most 255 bytes,
## terminated by a zero-length block.
static func _append_subblocks(out: PackedByteArray, data: PackedByteArray) -> void:
	var offset: int = 0
	while offset < data.size():
		var chunk: int = mini(255, data.size() - offset)
		out.append(chunk)
		out.append_array(data.slice(offset, offset + chunk))
		offset += chunk
	out.append(0)


static func _put_u16(out: PackedByteArray, value: int) -> void:
	out.append(value & 0xFF)
	out.append((value >> 8) & 0xFF)
