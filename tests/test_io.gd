class_name PPTestIO
extends RefCounted

## Round-trips every codec. Anything that can be read back is read back and
## compared, rather than merely checked for "wrote some bytes".


static func run() -> PPTestCase:
	var t: PPTestCase = PPTestCase.new("io")

	_test_default_palettes(t)
	_test_palette_formats(t)
	_test_project_roundtrip(t)
	_test_ase_roundtrip(t)
	_test_ase_blend_mapping(t)
	_test_gif_lzw_roundtrip(t)
	_test_gif_structure(t)
	_test_image_export(t)
	_test_spritesheet(t)

	return t


static func _temp(name: String) -> String:
	return "user://test_%s" % name


## Index of `needle` within `haystack`, or -1. Needed because binary buffers
## cannot be searched as strings: get_string_from_ascii() stops at the first
## null byte, of which a GIF colour table has plenty.
static func _find_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	if needle.is_empty() or haystack.size() < needle.size():
		return -1
	for start: int in range(haystack.size() - needle.size() + 1):
		var matched: bool = true
		for offset: int in range(needle.size()):
			if haystack[start + offset] != needle[offset]:
				matched = false
				break
		if matched:
			return start
	return -1


static func _test_default_palettes(t: PPTestCase) -> void:
	t.equal(PPDefaultPalettes.get_names().size(), 8, "eight palettes are bundled")

	var db32: PPPalette = PPDefaultPalettes.get_palette("DB32")
	t.check(db32 != null, "DB32 loads")
	t.equal(db32.size(), 32, "DB32 has 32 colours")
	t.equal(db32.get_color(0), Color8(0, 0, 0, 255), "DB32 starts with black")

	var pico: PPPalette = PPDefaultPalettes.get_palette("PICO-8")
	t.equal(pico.size(), 16, "PICO-8 has 16 colours")
	t.equal(pico.get_color(8), Color8(255, 0, 77, 255), "PICO-8 red is #FF004D")

	t.equal(PPDefaultPalettes.get_palette("Sweetie 16").size(), 16, "Sweetie 16 has 16 colours")
	t.equal(PPDefaultPalettes.get_palette("Resurrect 64").size(), 64, "Resurrect 64 has 64 colours")
	t.equal(PPDefaultPalettes.get_palette("AAP-64").size(), 64, "AAP-64 has 64 colours")
	t.equal(PPDefaultPalettes.get_palette("Endesga 32").size(), 32, "Endesga 32 has 32 colours")
	t.equal(PPDefaultPalettes.get_palette("Grayscale 16").size(), 16, "Grayscale 16 has 16 colours")
	t.equal(
		PPDefaultPalettes.get_palette("Grayscale 16").get_color(15),
		Color(1.0, 1.0, 1.0, 1.0),
		"Grayscale ends at white"
	)
	t.check(PPDefaultPalettes.get_palette("Nope") == null, "an unknown palette returns null")

	# Palettes must be handed out as copies, or one sprite's edits leak into the next.
	var a: PPPalette = PPDefaultPalettes.get_palette("DB32")
	a.set_color(0, Color.RED)
	var b: PPPalette = PPDefaultPalettes.get_palette("DB32")
	t.equal(b.get_color(0), Color8(0, 0, 0, 255), "each get_palette() call returns a fresh copy")


static func _test_palette_formats(t: PPTestCase) -> void:
	var source: PPPalette = PPPalette.create(
		"Round Trip",
		PackedColorArray(
			[Color8(255, 0, 0, 255), Color8(0, 255, 0, 255), Color8(18, 52, 86, 255)]
		)
	)
	source.set_color_name(0, "Hot Red")

	for extension: String in ["gpl", "pal", "hex", "png"]:
		var path: String = _temp("palette.%s" % extension)
		t.equal(
			PPPaletteIO.save_palette(source, path), OK, "%s saves" % extension
		)

		var loaded: PPPalette = PPPaletteIO.load_palette(path)
		t.check(loaded != null, "%s loads back" % extension)
		if loaded == null:
			continue

		t.equal(loaded.size(), 3, "%s round-trips the swatch count" % extension)
		t.equal(loaded.get_color(0), Color8(255, 0, 0, 255), "%s round-trips red" % extension)
		t.equal(
			loaded.get_color(2), Color8(18, 52, 86, 255), "%s round-trips an arbitrary colour" % extension
		)

	# .gpl is the only format that carries swatch names.
	var gpl: PPPalette = PPPaletteIO.load_palette(_temp("palette.gpl"))
	t.equal(gpl.get_color_name(0), "Hot Red", "gpl round-trips swatch names")

	# Readers must survive junk rather than crash.
	var junk_path: String = _temp("junk.gpl")
	var junk: FileAccess = FileAccess.open(junk_path, FileAccess.WRITE)
	junk.store_string("this is not a palette\n\n\n")
	junk.close()
	t.check(
		PPPaletteIO.load_palette(junk_path) == null, "a malformed palette returns null, not a crash"
	)

	# A hand-edited .gpl with CRLF, comments and ragged spacing must still parse.
	var messy_path: String = _temp("messy.gpl")
	var messy: FileAccess = FileAccess.open(messy_path, FileAccess.WRITE)
	messy.store_string(
		"GIMP Palette\r\nName: Messy\r\n# a comment\r\n\r\n  255   0   0\tRed\r\n0 0 255\r\n"
	)
	messy.close()
	var parsed: PPPalette = PPPaletteIO.load_palette(messy_path)
	t.check(parsed != null, "a messy but valid gpl parses")
	if parsed != null:
		t.equal(parsed.size(), 2, "messy gpl finds both colours")
		t.equal(parsed.name, "Messy", "messy gpl reads its name")


## Builds a document with every structural feature that must survive a save.
static func _make_rich_document() -> PPDocument:
	var document: PPDocument = PPDocument.create(
		Vector2i(8, 6), PPDefaultPalettes.get_palette("PICO-8")
	)
	var sprite: PPSprite = document.sprite

	sprite.get_layer(0).name = "Base"
	sprite.get_cel(0, 0).image.fill_rect(Rect2i(1, 1, 3, 3), Color8(255, 0, 0, 255))

	var top: PPLayer = PPLayer.create("Shading", 1, sprite.size)
	top.blend_mode = PPTypes.BlendMode.MULTIPLY
	top.opacity = 0.5
	top.visible = false
	top.locked = true
	sprite.add_layer(top, 1)
	top.cels[0].image.fill_rect(Rect2i(2, 2, 4, 3), Color8(0, 0, 255, 128))

	# Three frames, with frames 1 and 2 sharing one linked cel on the base layer.
	sprite.insert_frame(1)
	sprite.insert_frame(2)
	sprite.get_frame(1).duration_ms = 250
	sprite.get_frame(2).duration_ms = 40

	sprite.get_cel(0, 1).image.fill_rect(Rect2i(0, 0, 2, 2), Color8(0, 255, 0, 255))
	sprite.get_layer(0).cels[2] = sprite.get_layer(0).cels[1]

	var tag: PPTag = PPTag.create("walk", 0, 2)
	tag.direction = PPTypes.AnimationDirection.PING_PONG
	tag.repeat = 3
	sprite.tags.append(tag)

	return document


static func _check_rich(t: PPTestCase, loaded: PPDocument, label: String) -> void:
	if loaded == null:
		t.check(false, "%s: document failed to load" % label)
		return

	var sprite: PPSprite = loaded.sprite
	t.equal(sprite.size, Vector2i(8, 6), "%s: canvas size" % label)
	t.equal(sprite.layer_count(), 2, "%s: layer count" % label)
	t.equal(sprite.frame_count(), 3, "%s: frame count" % label)

	t.equal(sprite.get_layer(0).name, "Base", "%s: layer name" % label)
	t.equal(sprite.get_layer(1).name, "Shading", "%s: second layer name" % label)
	t.equal(
		sprite.get_layer(1).blend_mode,
		PPTypes.BlendMode.MULTIPLY,
		"%s: blend mode survives" % label
	)
	t.near(sprite.get_layer(1).opacity, 0.5, "%s: layer opacity survives" % label, 0.01)
	t.check(not sprite.get_layer(1).visible, "%s: hidden flag survives" % label)
	t.check(sprite.get_layer(1).locked, "%s: locked flag survives" % label)

	t.equal(sprite.get_frame(1).duration_ms, 250, "%s: frame duration survives" % label)
	t.equal(sprite.get_frame(2).duration_ms, 40, "%s: second frame duration survives" % label)

	t.pixel(
		sprite.get_cel(0, 0).image, 2, 2, Color8(255, 0, 0, 255), "%s: base pixels" % label
	)
	t.pixel(
		sprite.get_cel(1, 0).image,
		3,
		3,
		Color8(0, 0, 255, 128),
		"%s: upper layer pixels (with alpha)" % label
	)
	t.pixel(
		sprite.get_cel(0, 1).image, 0, 0, Color8(0, 255, 0, 255), "%s: frame 1 pixels" % label
	)

	# The linked cel must come back as one shared instance, not two copies.
	t.check(
		sprite.get_cel(0, 1) == sprite.get_cel(0, 2),
		"%s: linked cels stay linked" % label
	)

	t.equal(sprite.tags.size(), 1, "%s: tag survives" % label)
	if sprite.tags.size() == 1:
		t.equal(sprite.tags[0].name, "walk", "%s: tag name" % label)
		t.equal(sprite.tags[0].from_frame, 0, "%s: tag start" % label)
		t.equal(sprite.tags[0].to_frame, 2, "%s: tag end" % label)
		t.equal(
			sprite.tags[0].direction,
			PPTypes.AnimationDirection.PING_PONG,
			"%s: tag direction" % label
		)

	t.equal(sprite.palette.size(), 16, "%s: palette survives" % label)


static func _test_project_roundtrip(t: PPTestCase) -> void:
	var document: PPDocument = _make_rich_document()
	var path: String = _temp("project.pxp")

	t.equal(PPProjectIO.save(document, path), OK, "pxp saves")
	_check_rich(t, PPProjectIO.load_project(path), "pxp")

	# The encode/decode pair (used by sync) must match the on-disk path.
	var bytes: PackedByteArray = PPProjectIO.encode(document)
	t.check(bytes.size() > 0, "pxp encodes to bytes")
	_check_rich(t, PPProjectIO.decode(bytes), "pxp bytes")

	t.check(PPProjectIO.decode(PackedByteArray([1, 2, 3])) == null, "garbage bytes decode to null")


static func _test_ase_roundtrip(t: PPTestCase) -> void:
	var document: PPDocument = _make_rich_document()
	var path: String = _temp("sprite.ase")

	t.equal(PPAseIO.save(document, path), OK, "ase saves")

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	t.check(bytes.size() > 128, "ase file has a header and a body")
	# Magic number 0xA5E0, little-endian, at offset 4.
	t.equal(bytes[4], 0xE0, "ase magic low byte")
	t.equal(bytes[5], 0xA5, "ase magic high byte")

	_check_rich(t, PPAseIO.load_ase(path), "ase")

	t.check(PPAseIO.decode(PackedByteArray([1, 2, 3])) == null, "a truncated ase decodes to null")


static func _test_ase_blend_mapping(t: PPTestCase) -> void:
	# Aseprite orders its blend ids differently from our enum; a bad mapping here
	# corrupts layer blending on every round-trip, so pin the tricky ones.
	t.equal(PPTypes.to_ase_blend_id(PPTypes.BlendMode.NORMAL), 0, "normal -> 0")
	t.equal(PPTypes.to_ase_blend_id(PPTypes.BlendMode.MULTIPLY), 1, "multiply -> 1")
	t.equal(PPTypes.to_ase_blend_id(PPTypes.BlendMode.SCREEN), 2, "screen -> 2")
	t.equal(PPTypes.to_ase_blend_id(PPTypes.BlendMode.DARKEN), 4, "darken -> 4")
	t.equal(PPTypes.to_ase_blend_id(PPTypes.BlendMode.ADDITION), 16, "addition -> 16")
	t.equal(PPTypes.to_ase_blend_id(PPTypes.BlendMode.DIVIDE), 18, "divide -> 18")

	for mode: int in range(PPTypes.BLEND_MODE_NAMES.size()):
		var ase_id: int = PPTypes.to_ase_blend_id(mode as PPTypes.BlendMode)
		t.equal(
			int(PPTypes.from_ase_blend_id(ase_id)),
			mode,
			"blend id %d round-trips" % ase_id
		)


## Decodes a GIF LZW stream back into indices. Structural byte checks would not
## catch an off-by-one in the code-width growth; a full round-trip does.
static func _lzw_decode(data: PackedByteArray, min_code_size: int) -> PackedByteArray:
	var clear_code: int = 1 << min_code_size
	var end_code: int = clear_code + 1

	var table: Array[PackedByteArray] = []
	var reset_table: Callable = func() -> void:
		table.clear()
		for i: int in range(clear_code):
			table.append(PackedByteArray([i]))
		table.append(PackedByteArray())
		table.append(PackedByteArray())
	reset_table.call()

	var code_size: int = min_code_size + 1
	var out: PackedByteArray = PackedByteArray()

	var register: int = 0
	var bits: int = 0
	var offset: int = 0
	var previous: PackedByteArray = PackedByteArray()

	while true:
		while bits < code_size and offset < data.size():
			register |= data[offset] << bits
			bits += 8
			offset += 1
		if bits < code_size:
			break

		var code: int = register & ((1 << code_size) - 1)
		register >>= code_size
		bits -= code_size

		if code == clear_code:
			reset_table.call()
			code_size = min_code_size + 1
			previous = PackedByteArray()
			continue
		if code == end_code:
			break

		var entry: PackedByteArray = PackedByteArray()
		if code < table.size():
			entry = table[code].duplicate()
		elif not previous.is_empty():
			entry = previous.duplicate()
			entry.append(previous[0])
		else:
			break

		out.append_array(entry)

		if not previous.is_empty():
			var added: PackedByteArray = previous.duplicate()
			added.append(entry[0])
			table.append(added)
			if table.size() >= (1 << code_size) and code_size < 12:
				code_size += 1

		previous = entry

	return out


static func _test_gif_lzw_roundtrip(t: PPTestCase) -> void:
	# A stream long and varied enough to force the dictionary to grow past the
	# starting code width -- which is exactly where encoders go wrong.
	var indices: PackedByteArray = PackedByteArray()
	for i: int in range(3000):
		indices.append((i * 7 + (i / 13)) % 16)

	var min_code_size: int = 4
	var compressed: PackedByteArray = PPGifIO._lzw_compress(indices, min_code_size)
	t.check(compressed.size() > 0, "lzw produces output")

	var decoded: PackedByteArray = _lzw_decode(compressed, min_code_size)
	t.equal(decoded.size(), indices.size(), "lzw round-trip preserves the pixel count")
	t.check(decoded == indices, "lzw round-trip is byte-exact")

	# A flat run compresses hard; prove it still round-trips.
	var flat: PackedByteArray = PackedByteArray()
	flat.resize(5000)
	flat.fill(3)
	var flat_encoded: PackedByteArray = PPGifIO._lzw_compress(flat, 4)
	t.check(
		_lzw_decode(flat_encoded, 4) == flat, "lzw round-trips a long flat run"
	)
	t.check(
		flat_encoded.size() < 500, "lzw actually compresses a flat run"
	)


static func _test_gif_structure(t: PPTestCase) -> void:
	var frames: Array[Image] = []
	for i: int in range(3):
		var image: Image = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		image.fill_rect(Rect2i(i, 0, 4, 8), Color8(200, 40, 60, 255))
		frames.append(image)

	var delays: Array[int] = [100, 100, 100]
	var bytes: PackedByteArray = PPGifIO.encode_animation(frames, delays, true)

	t.check(bytes.size() > 20, "gif encodes to bytes")
	t.equal(bytes.slice(0, 6).get_string_from_ascii(), "GIF89a", "gif has a GIF89a header")
	t.equal(bytes[bytes.size() - 1], 0x3B, "gif ends with the trailer byte")

	# Logical screen descriptor carries the canvas size, little-endian.
	t.equal(bytes[6] | (bytes[7] << 8), 8, "gif width")
	t.equal(bytes[8] | (bytes[9] << 8), 8, "gif height")
	t.check((bytes[10] & 0x80) != 0, "gif declares a global colour table")

	# The colour table is full of null bytes, so the buffer cannot be searched as
	# an ASCII string -- it would be truncated at the first zero. Search the raw
	# bytes for the application-extension signature instead.
	t.check(
		_find_bytes(bytes, "NETSCAPE2.0".to_ascii_buffer()) >= 0,
		"gif carries the loop extension"
	)

	var without_loop: PackedByteArray = PPGifIO.encode_animation(frames, delays, false)
	t.check(
		_find_bytes(without_loop, "NETSCAPE2.0".to_ascii_buffer()) < 0,
		"a non-looping gif omits the loop extension"
	)

	var path: String = _temp("anim.gif")
	t.equal(PPGifIO.save_animation(frames, delays, path, true), OK, "gif saves to disk")
	t.check(FileAccess.file_exists(path), "gif file exists on disk")


static func _test_image_export(t: PPTestCase) -> void:
	var document: PPDocument = _make_rich_document()
	var path: String = _temp("frame.png")

	t.equal(PPExportIO.export_png(document, path, 0), OK, "png exports")

	var loaded: Image = Image.load_from_file(path)
	t.check(loaded != null, "exported png loads back")
	t.equal(Vector2i(loaded.get_width(), loaded.get_height()), Vector2i(8, 6), "png size")
	# The upper layer is hidden, so the export must show only the base layer's red.
	t.pixel(loaded, 2, 2, Color8(255, 0, 0, 255), "png export composites visible layers")

	# A 3x upscale must be a clean nearest-neighbour multiple.
	var scaled_path: String = _temp("frame3x.png")
	t.equal(PPExportIO.export_png(document, scaled_path, 0, 3), OK, "scaled png exports")
	var scaled: Image = Image.load_from_file(scaled_path)
	t.equal(Vector2i(scaled.get_width(), scaled.get_height()), Vector2i(24, 18), "3x png size")
	t.pixel(scaled, 6, 6, Color8(255, 0, 0, 255), "3x upscale keeps hard pixel edges")

	# Round-trip a flat image back in as a document.
	var imported: PPDocument = PPExportIO.import_image(path)
	t.check(imported != null, "png imports as a document")
	if imported != null:
		t.equal(imported.sprite.size, Vector2i(8, 6), "imported png size")
		t.equal(imported.sprite.layer_count(), 1, "imported png has one layer")


static func _test_spritesheet(t: PPTestCase) -> void:
	var document: PPDocument = _make_rich_document()
	var path: String = _temp("sheet.png")

	var options: PPExportIO.SheetOptions = PPExportIO.SheetOptions.new()
	options.layout = PPExportIO.SheetLayout.HORIZONTAL
	options.write_metadata = true

	t.equal(PPExportIO.export_spritesheet(document, path, options), OK, "spritesheet exports")

	var sheet: Image = Image.load_from_file(path)
	t.check(sheet != null, "spritesheet loads back")
	# 3 frames of 8x6 laid out horizontally.
	t.equal(
		Vector2i(sheet.get_width(), sheet.get_height()),
		Vector2i(24, 6),
		"horizontal sheet is frames-wide"
	)

	var json_path: String = path.get_basename() + ".json"
	t.check(FileAccess.file_exists(json_path), "spritesheet writes its metadata")
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	t.check(meta is Dictionary, "spritesheet metadata is valid json")
	if meta is Dictionary:
		var frames: Array = (meta as Dictionary).get("frames", [])
		t.equal(frames.size(), 3, "metadata lists every frame")
		t.equal(int((frames[1] as Dictionary).get("x", -1)), 8, "metadata frame offsets are right")
		t.equal(
			int((frames[1] as Dictionary).get("duration", -1)),
			250,
			"metadata carries frame durations"
		)

	# A grid layout wraps.
	var grid_options: PPExportIO.SheetOptions = PPExportIO.SheetOptions.new()
	grid_options.layout = PPExportIO.SheetLayout.GRID
	grid_options.columns = 2
	grid_options.write_metadata = false
	var grid_path: String = _temp("grid.png")
	t.equal(
		PPExportIO.export_spritesheet(document, grid_path, grid_options), OK, "grid sheet exports"
	)
	var grid: Image = Image.load_from_file(grid_path)
	t.equal(
		Vector2i(grid.get_width(), grid.get_height()),
		Vector2i(16, 12),
		"grid sheet wraps to 2 columns x 2 rows"
	)

	# And slicing a sheet back into frames must recover them.
	var reimported: PPDocument = PPExportIO.import_spritesheet(path, Vector2i(8, 6))
	t.check(reimported != null, "spritesheet reimports")
	if reimported != null:
		t.equal(reimported.sprite.frame_count(), 3, "reimported sheet recovers every frame")
		t.equal(reimported.sprite.size, Vector2i(8, 6), "reimported frames are cell-sized")
