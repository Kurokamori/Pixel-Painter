@abstract
class_name PPAseIO
extends RefCounted

## Aseprite .ase / .aseprite reader and writer.
##
## Implemented against the official ase-file-specs. The format is a 128-byte
## header followed by one block per frame, each block a list of typed chunks:
## layers and tags and the palette are declared in frame 0, and every frame
## carries its cels.
##
## Two details are worth knowing before touching this file:
##
##  * Aseprite's cel pixel data is *zlib*-wrapped deflate. Godot's
##    COMPRESSION_DEFLATE is zlib-wrapped too (its output starts 0x78 0x9C), so
##    the two interoperate directly with no header surgery.
##
##  * A cel chunk's layer index counts *every* layer in the file, including
##    group layers. We have no group layers, so when reading we keep a parallel
##    list with a null in each group's slot and index into that -- dropping the
##    groups from the list outright would silently shift every cel onto the
##    wrong layer.

const MAGIC_FILE: int = 0xA5E0
const MAGIC_FRAME: int = 0xF1FA

const CHUNK_OLD_PALETTE_04: int = 0x0004
const CHUNK_LAYER: int = 0x2004
const CHUNK_CEL: int = 0x2005
const CHUNK_TAGS: int = 0x2018
const CHUNK_PALETTE: int = 0x2019

const CEL_RAW: int = 0
const CEL_LINKED: int = 1
const CEL_COMPRESSED: int = 2

const LAYER_TYPE_GROUP: int = 1

const FLAG_VISIBLE: int = 1
const FLAG_EDITABLE: int = 2
const FLAG_REFERENCE: int = 64


static func supported_extensions() -> PackedStringArray:
	return PackedStringArray(["ase", "aseprite"])


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

static func save(document: PPDocument, path: String) -> Error:
	var bytes: PackedByteArray = encode(document.sprite)
	if bytes.is_empty():
		return ERR_CANT_CREATE

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.close()
	return OK


static func encode(sprite: PPSprite) -> PackedByteArray:
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	out.big_endian = false

	_write_header(out, sprite)

	for frame_index: int in range(sprite.frame_count()):
		_write_frame(out, sprite, frame_index)

	# The header's first field is the total file size, which is only known now.
	var bytes: PackedByteArray = out.data_array
	_patch_u32(bytes, 0, bytes.size())
	return bytes


static func _write_header(out: StreamPeerBuffer, sprite: PPSprite) -> void:
	out.put_u32(0)  # File size, patched once the body is written.
	out.put_u16(MAGIC_FILE)
	out.put_u16(sprite.frame_count())
	out.put_u16(sprite.size.x)
	out.put_u16(sprite.size.y)
	out.put_u16(32)  # Colour depth: we always write RGBA.
	out.put_u32(1)  # Flags: layer opacity is valid.
	out.put_u16(100)  # Deprecated global speed; per-frame durations win.
	out.put_u32(0)
	out.put_u32(0)
	out.put_u8(0)  # Transparent palette index (unused in RGBA mode).
	_put_zeros(out, 3)

	var palette_size: int = 0
	if sprite.palette != null:
		palette_size = sprite.palette.size()
	out.put_u16(palette_size)

	out.put_u8(1)  # Pixel width ratio.
	out.put_u8(1)  # Pixel height ratio.
	out.put_16(0)  # Grid x.
	out.put_16(0)  # Grid y.
	out.put_u16(16)  # Grid width.
	out.put_u16(16)  # Grid height.
	_put_zeros(out, 84)


static func _write_frame(
	out: StreamPeerBuffer, sprite: PPSprite, frame_index: int
) -> void:
	var chunks: Array[PackedByteArray] = []

	# Layers, palette and tags are declared once, on the first frame.
	if frame_index == 0:
		for layer: PPLayer in sprite.layers:
			chunks.append(_encode_layer_chunk(layer))
		if sprite.palette != null and sprite.palette.size() > 0:
			chunks.append(_encode_palette_chunk(sprite.palette))
		if not sprite.tags.is_empty():
			chunks.append(_encode_tags_chunk(sprite.tags))

	for layer_index: int in range(sprite.layer_count()):
		var chunk: PackedByteArray = _encode_cel_chunk(sprite, layer_index, frame_index)
		if not chunk.is_empty():
			chunks.append(chunk)

	var body: PackedByteArray = PackedByteArray()
	for chunk: PackedByteArray in chunks:
		body.append_array(chunk)

	out.put_u32(16 + body.size())
	out.put_u16(MAGIC_FRAME)
	# The 16-bit "old" chunk count saturates; readers then use the 32-bit field.
	out.put_u16(mini(chunks.size(), 0xFFFF))
	out.put_u16(sprite.get_frame(frame_index).duration_ms)
	_put_zeros(out, 2)
	out.put_u32(chunks.size())
	out.put_data(body)


static func _encode_layer_chunk(layer: PPLayer) -> PackedByteArray:
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.big_endian = false

	var flags: int = 0
	if layer.visible:
		flags |= FLAG_VISIBLE
	if not layer.locked:
		flags |= FLAG_EDITABLE
	if layer.reference_only:
		flags |= FLAG_REFERENCE

	body.put_u16(flags)
	body.put_u16(0)  # Layer type: normal image layer.
	body.put_u16(0)  # Child level: we have no groups, so everything is root.
	body.put_u16(0)  # Default width, ignored by Aseprite.
	body.put_u16(0)  # Default height, ignored by Aseprite.
	body.put_u16(PPTypes.to_ase_blend_id(layer.blend_mode))
	body.put_u8(clampi(int(round(layer.opacity * 255.0)), 0, 255))
	_put_zeros(body, 3)
	_put_string(body, layer.name)

	return _wrap_chunk(CHUNK_LAYER, body.data_array)


static func _encode_palette_chunk(palette: PPPalette) -> PackedByteArray:
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.big_endian = false

	body.put_u32(palette.size())
	body.put_u32(0)
	body.put_u32(maxi(0, palette.size() - 1))
	_put_zeros(body, 8)

	for i: int in range(palette.size()):
		var color: Color = palette.get_color(i)
		var swatch_name: String = palette.get_color_name(i)
		body.put_u16(1 if not swatch_name.is_empty() else 0)
		body.put_u8(color.r8)
		body.put_u8(color.g8)
		body.put_u8(color.b8)
		body.put_u8(color.a8)
		if not swatch_name.is_empty():
			_put_string(body, swatch_name)

	return _wrap_chunk(CHUNK_PALETTE, body.data_array)


static func _encode_tags_chunk(tags: Array[PPTag]) -> PackedByteArray:
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.big_endian = false

	body.put_u16(tags.size())
	_put_zeros(body, 8)

	for tag: PPTag in tags:
		body.put_u16(tag.from_frame)
		body.put_u16(tag.to_frame)
		body.put_u8(int(tag.direction))
		body.put_u16(tag.repeat)
		_put_zeros(body, 6)
		body.put_u8(tag.color.r8)
		body.put_u8(tag.color.g8)
		body.put_u8(tag.color.b8)
		body.put_u8(0)
		_put_string(body, tag.name)

	return _wrap_chunk(CHUNK_TAGS, body.data_array)


## Returns an empty array for a cel with nothing in it -- Aseprite simply omits
## empty cels rather than storing a zero-area one.
static func _encode_cel_chunk(
	sprite: PPSprite, layer_index: int, frame_index: int
) -> PackedByteArray:
	var layer: PPLayer = sprite.get_layer(layer_index)
	var cel: PPCel = layer.get_cel(frame_index)
	if cel == null or cel.image == null:
		return PackedByteArray()

	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.big_endian = false

	# If this exact cel instance already appeared in an earlier frame of this
	# layer, emit a link to that frame instead of the pixels again. That is what
	# preserves linked cels across a round-trip.
	var link_frame: int = _find_link_source(layer, cel, frame_index)

	var used: Rect2i = cel.get_used_rect()
	if link_frame < 0 and (used.size.x <= 0 or used.size.y <= 0):
		return PackedByteArray()

	body.put_u16(layer_index)

	if link_frame >= 0:
		body.put_16(0)
		body.put_16(0)
		body.put_u8(clampi(int(round(cel.opacity * 255.0)), 0, 255))
		body.put_u16(CEL_LINKED)
		body.put_16(0)  # Z-index.
		_put_zeros(body, 5)
		body.put_u16(link_frame)
		return _wrap_chunk(CHUNK_CEL, body.data_array)

	body.put_16(used.position.x)
	body.put_16(used.position.y)
	body.put_u8(clampi(int(round(cel.opacity * 255.0)), 0, 255))
	body.put_u16(CEL_COMPRESSED)
	body.put_16(0)  # Z-index.
	_put_zeros(body, 5)
	body.put_u16(used.size.x)
	body.put_u16(used.size.y)

	# Cels are stored trimmed to their used rect, so crop before compressing.
	var cropped: Image = Image.create_empty(
		used.size.x, used.size.y, false, Image.FORMAT_RGBA8
	)
	cropped.blit_rect(cel.image, used, Vector2i.ZERO)
	body.put_data(cropped.get_data().compress(FileAccess.COMPRESSION_DEFLATE))

	return _wrap_chunk(CHUNK_CEL, body.data_array)


## The earliest frame in this layer that references the same PPCel instance, or
## -1 when this frame is that earliest one.
static func _find_link_source(layer: PPLayer, cel: PPCel, frame_index: int) -> int:
	for i: int in range(frame_index):
		if layer.get_cel(i) == cel:
			return i
	return -1


static func _wrap_chunk(type: int, body: PackedByteArray) -> PackedByteArray:
	var chunk: StreamPeerBuffer = StreamPeerBuffer.new()
	chunk.big_endian = false
	chunk.put_u32(body.size() + 6)
	chunk.put_u16(type)
	chunk.put_data(body)
	return chunk.data_array


static func _put_string(out: StreamPeerBuffer, text: String) -> void:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	out.put_u16(bytes.size())
	out.put_data(bytes)


static func _put_zeros(out: StreamPeerBuffer, count: int) -> void:
	for i: int in range(count):
		out.put_u8(0)


static func _patch_u32(bytes: PackedByteArray, offset: int, value: int) -> void:
	bytes[offset] = value & 0xFF
	bytes[offset + 1] = (value >> 8) & 0xFF
	bytes[offset + 2] = (value >> 16) & 0xFF
	bytes[offset + 3] = (value >> 24) & 0xFF


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

static func load_ase(path: String) -> PPDocument:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	var sprite: PPSprite = decode(bytes)
	if sprite == null:
		return null

	var document: PPDocument = PPDocument.from_sprite(sprite)
	document.mark_saved(path)
	return document


static func decode(bytes: PackedByteArray) -> PPSprite:
	if bytes.size() < 128:
		return null

	var input: StreamPeerBuffer = StreamPeerBuffer.new()
	input.big_endian = false
	input.data_array = bytes

	input.get_u32()  # File size; the buffer length is authoritative.
	if input.get_u16() != MAGIC_FILE:
		return null

	var frame_count: int = input.get_u16()
	var width: int = input.get_u16()
	var height: int = input.get_u16()
	var depth: int = input.get_u16()
	input.get_u32()  # Flags.
	input.get_u16()  # Deprecated speed.
	input.get_u32()
	input.get_u32()
	var transparent_index: int = input.get_u8()
	input.seek(input.get_position() + 3)
	input.get_u16()  # Colour count.
	# Pixel ratio (2) + grid (8) + reserved (84). Getting this wrong by even a
	# byte lands us mid-way into the first frame header and the whole parse
	# unravels, so it is pinned to a named constant.
	input.seek(input.get_position() + PPTypes.ASE_HEADER_TAIL)

	if width <= 0 or height <= 0 or frame_count <= 0:
		return null
	if width > PPTypes.MAX_SPRITE_SIZE or height > PPTypes.MAX_SPRITE_SIZE:
		return null
	if depth != 32 and depth != 16 and depth != 8:
		return null

	var size: Vector2i = Vector2i(width, height)
	var sprite: PPSprite = PPSprite.new()
	sprite.size = size
	sprite.frames = []
	sprite.layers = []
	sprite.tags = []
	sprite.palette = PPPalette.create("Palette", PackedColorArray())

	# Indexed and grayscale files resolve their pixels through the palette, so
	# it must be populated before any cel is decoded. Aseprite always writes the
	# palette in frame 0 ahead of the cels, so a single forward pass is enough.
	var state: AseReadState = AseReadState.new()
	state.sprite = sprite
	state.depth = depth
	state.transparent_index = transparent_index
	state.size = size

	for frame_index: int in range(frame_count):
		if not _read_frame(input, state, frame_index):
			break

	if sprite.frames.is_empty():
		return null

	# Layers that never got a cel on some frame need an empty one: the rest of
	# the app assumes every layer has exactly one cel slot per frame.
	for layer: PPLayer in sprite.layers:
		while layer.cels.size() < sprite.frames.size():
			layer.cels.append(PPCel.create(size))

	if sprite.layers.is_empty():
		sprite.layers.append(PPLayer.create("Layer 1", sprite.frames.size(), size))

	return sprite


class AseReadState:
	extends RefCounted

	var sprite: PPSprite = null
	var depth: int = 32
	var transparent_index: int = 0
	var size: Vector2i = Vector2i.ZERO

	## Every layer in file order, with a null placeholder wherever the file had a
	## group layer. Cel chunks index into this, not into sprite.layers.
	var file_layers: Array = []


static func _read_frame(
	input: StreamPeerBuffer, state: AseReadState, frame_index: int
) -> bool:
	if input.get_position() + 16 > input.data_array.size():
		return false

	var frame_start: int = input.get_position()
	var frame_bytes: int = input.get_u32()
	if input.get_u16() != MAGIC_FRAME:
		return false

	var old_chunks: int = input.get_u16()
	var duration: int = input.get_u16()
	input.seek(input.get_position() + 2)
	var new_chunks: int = input.get_u32()

	var chunk_count: int = new_chunks if new_chunks > 0 else old_chunks

	state.sprite.frames.append(PPFrame.create(maxi(1, duration)))

	# Every layer gains an empty cel slot for this frame up front; cel chunks
	# then fill in the ones that actually have pixels.
	for layer: PPLayer in state.sprite.layers:
		while layer.cels.size() <= frame_index:
			layer.cels.append(PPCel.create(state.size))

	for i: int in range(chunk_count):
		if input.get_position() + 6 > input.data_array.size():
			return false

		var chunk_start: int = input.get_position()
		var chunk_size: int = input.get_u32()
		var chunk_type: int = input.get_u16()

		if chunk_size < 6:
			return false

		_read_chunk(input, state, chunk_type, frame_index, chunk_start + chunk_size)
		input.seek(chunk_start + chunk_size)

	if frame_bytes >= 16:
		input.seek(frame_start + frame_bytes)
	return true


static func _read_chunk(
	input: StreamPeerBuffer,
	state: AseReadState,
	chunk_type: int,
	frame_index: int,
	chunk_end: int
) -> void:
	match chunk_type:
		CHUNK_LAYER:
			_read_layer_chunk(input, state, frame_index)
		CHUNK_CEL:
			_read_cel_chunk(input, state, frame_index, chunk_end)
		CHUNK_PALETTE:
			_read_palette_chunk(input, state)
		CHUNK_OLD_PALETTE_04:
			_read_old_palette_chunk(input, state)
		CHUNK_TAGS:
			_read_tags_chunk(input, state)


static func _read_layer_chunk(
	input: StreamPeerBuffer, state: AseReadState, frame_index: int
) -> void:
	var flags: int = input.get_u16()
	var layer_type: int = input.get_u16()
	input.get_u16()  # Child level.
	input.get_u16()  # Default width.
	input.get_u16()  # Default height.
	var blend_id: int = input.get_u16()
	var opacity: int = input.get_u8()
	input.seek(input.get_position() + 3)
	var name: String = _get_string(input)

	# Groups (and tilemap layers) carry no pixels. Keep a placeholder so the cel
	# chunks' layer indices stay aligned, but do not add them to the sprite.
	if layer_type == LAYER_TYPE_GROUP:
		state.file_layers.append(null)
		return

	var layer: PPLayer = PPLayer.new()
	layer.name = name
	layer.visible = (flags & FLAG_VISIBLE) != 0
	layer.locked = (flags & FLAG_EDITABLE) == 0
	layer.reference_only = (flags & FLAG_REFERENCE) != 0
	layer.opacity = clampf(float(opacity) / 255.0, 0.0, 1.0)
	layer.blend_mode = PPTypes.from_ase_blend_id(blend_id)
	layer.cels = []

	# Layers are declared on frame 0, but be defensive: give the layer a cel for
	# every frame already seen.
	for i: int in range(frame_index + 1):
		layer.cels.append(PPCel.create(state.size))

	state.sprite.layers.append(layer)
	state.file_layers.append(layer)


static func _read_cel_chunk(
	input: StreamPeerBuffer, state: AseReadState, frame_index: int, chunk_end: int
) -> void:
	var layer_index: int = input.get_u16()
	var x: int = input.get_16()
	var y: int = input.get_16()
	var opacity: int = input.get_u8()
	var cel_type: int = input.get_u16()
	input.get_16()  # Z-index (Aseprite 1.3+); older files have zero here.
	input.seek(input.get_position() + 5)

	if layer_index < 0 or layer_index >= state.file_layers.size():
		return
	var layer: PPLayer = state.file_layers[layer_index] as PPLayer
	if layer == null:
		return

	while layer.cels.size() <= frame_index:
		layer.cels.append(PPCel.create(state.size))

	if cel_type == CEL_LINKED:
		var source_frame: int = input.get_u16()
		if source_frame >= 0 and source_frame < layer.cels.size():
			# Sharing the instance *is* the link.
			layer.cels[frame_index] = layer.cels[source_frame]
		return

	if cel_type != CEL_RAW and cel_type != CEL_COMPRESSED:
		return

	var cel_width: int = input.get_u16()
	var cel_height: int = input.get_u16()
	if cel_width <= 0 or cel_height <= 0:
		return

	var bytes_per_pixel: int = _bytes_per_pixel(state.depth)
	var expected: int = cel_width * cel_height * bytes_per_pixel

	var raw: PackedByteArray = PackedByteArray()
	if cel_type == CEL_RAW:
		raw = input.get_data(expected)[1]
	else:
		var remaining: int = chunk_end - input.get_position()
		if remaining <= 0:
			return
		var compressed: PackedByteArray = input.get_data(remaining)[1]
		raw = compressed.decompress(expected, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() != expected:
			raw = compressed.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() < expected:
		return

	var cel: PPCel = PPCel.create(state.size)
	var canvas: PackedByteArray = cel.image.get_data()

	for py: int in range(cel_height):
		var ty: int = y + py
		if ty < 0 or ty >= state.size.y:
			continue
		for px: int in range(cel_width):
			var tx: int = x + px
			if tx < 0 or tx >= state.size.x:
				continue

			var color: Color = _decode_pixel(
				raw, (py * cel_width + px) * bytes_per_pixel, state
			)
			var di: int = (ty * state.size.x + tx) * PPTypes.BPP
			canvas[di] = color.r8
			canvas[di + 1] = color.g8
			canvas[di + 2] = color.b8
			canvas[di + 3] = color.a8

	cel.set_buffer(canvas)
	cel.opacity = clampf(float(opacity) / 255.0, 0.0, 1.0)
	layer.cels[frame_index] = cel


static func _bytes_per_pixel(depth: int) -> int:
	match depth:
		32:
			return 4
		16:
			return 2
	return 1


static func _decode_pixel(
	raw: PackedByteArray, index: int, state: AseReadState
) -> Color:
	match state.depth:
		32:
			return Color8(raw[index], raw[index + 1], raw[index + 2], raw[index + 3])
		16:
			# Grayscale: one value byte plus one alpha byte.
			var value: int = raw[index]
			return Color8(value, value, value, raw[index + 1])
	# Indexed: the palette entry, with the transparent index meaning "no pixel".
	var palette_index: int = raw[index]
	if palette_index == state.transparent_index:
		return Color(0.0, 0.0, 0.0, 0.0)
	if palette_index >= state.sprite.palette.size():
		return Color(0.0, 0.0, 0.0, 0.0)
	return state.sprite.palette.get_color(palette_index)


static func _read_palette_chunk(input: StreamPeerBuffer, state: AseReadState) -> void:
	var new_size: int = input.get_u32()
	var first: int = input.get_u32()
	var last: int = input.get_u32()
	input.seek(input.get_position() + 8)

	var palette: PPPalette = state.sprite.palette
	while palette.colors.size() < new_size:
		palette.colors.append(Color(0.0, 0.0, 0.0, 0.0))

	for i: int in range(first, last + 1):
		if i < 0 or i >= palette.colors.size():
			break
		var flags: int = input.get_u16()
		var r: int = input.get_u8()
		var g: int = input.get_u8()
		var b: int = input.get_u8()
		var a: int = input.get_u8()
		palette.colors[i] = Color8(r, g, b, a)
		if (flags & 1) != 0:
			palette.set_color_name(i, _get_string(input))


static func _read_old_palette_chunk(
	input: StreamPeerBuffer, state: AseReadState
) -> void:
	var packets: int = input.get_u16()
	var palette: PPPalette = state.sprite.palette
	var index: int = 0

	for p: int in range(packets):
		index += input.get_u8()
		var count: int = input.get_u8()
		if count == 0:
			count = 256
		for i: int in range(count):
			var r: int = input.get_u8()
			var g: int = input.get_u8()
			var b: int = input.get_u8()
			while palette.colors.size() <= index:
				palette.colors.append(Color(0.0, 0.0, 0.0, 1.0))
			palette.colors[index] = Color8(r, g, b, 255)
			index += 1


static func _read_tags_chunk(input: StreamPeerBuffer, state: AseReadState) -> void:
	var count: int = input.get_u16()
	input.seek(input.get_position() + 8)

	for i: int in range(count):
		var tag: PPTag = PPTag.new()
		tag.from_frame = input.get_u16()
		tag.to_frame = input.get_u16()
		var direction: int = input.get_u8()
		tag.direction = _safe_direction(direction)
		tag.repeat = input.get_u16()
		input.seek(input.get_position() + 6)
		var r: int = input.get_u8()
		var g: int = input.get_u8()
		var b: int = input.get_u8()
		input.get_u8()  # Extra byte, always zero.
		tag.name = _get_string(input)
		tag.color = Color8(r, g, b, 255)

		if tag.to_frame >= tag.from_frame:
			state.sprite.tags.append(tag)


static func _safe_direction(value: int) -> PPTypes.AnimationDirection:
	if value < 0 or value > 3:
		return PPTypes.AnimationDirection.FORWARD
	return value as PPTypes.AnimationDirection


static func _get_string(input: StreamPeerBuffer) -> String:
	var length: int = input.get_u16()
	if length <= 0:
		return ""
	var result: Array = input.get_data(length)
	if result[0] != OK:
		return ""
	var bytes: PackedByteArray = result[1]
	return bytes.get_string_from_utf8()
