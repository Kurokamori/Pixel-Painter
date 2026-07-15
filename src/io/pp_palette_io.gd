@abstract
class_name PPPaletteIO
extends RefCounted

## Reads and writes the palette formats pixel artists actually trade in:
## GIMP .gpl, JASC .pal, plain .hex lists, and palette strips as .png.
##
## Every reader is written to survive a hand-edited file -- stray blank lines,
## CRLF endings, comments, inconsistent spacing -- and to return null rather
## than throw when it genuinely cannot make sense of the input.


static func supported_read_extensions() -> PackedStringArray:
	return PackedStringArray(["gpl", "pal", "hex", "png"])


static func supported_write_extensions() -> PackedStringArray:
	return PackedStringArray(["gpl", "pal", "hex", "png"])


static func load_palette(path: String) -> PPPalette:
	var extension: String = path.get_extension().to_lower()
	match extension:
		"gpl":
			return _load_gpl(path)
		"pal":
			return _load_pal(path)
		"hex":
			return _load_hex(path)
		"png":
			return _load_png(path)
	return null


static func save_palette(palette: PPPalette, path: String) -> Error:
	var extension: String = path.get_extension().to_lower()
	match extension:
		"gpl":
			return _save_gpl(palette, path)
		"pal":
			return _save_pal(palette, path)
		"hex":
			return _save_hex(palette, path)
		"png":
			return _save_png(palette, path)
	return ERR_FILE_UNRECOGNIZED


# --- GIMP .gpl --------------------------------------------------------------

static func _load_gpl(path: String) -> PPPalette:
	var text: String = _read_text(path)
	if text.is_empty():
		return null

	var palette: PPPalette = PPPalette.create(path.get_file().get_basename(), PackedColorArray())
	var seen_header: bool = false

	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue

		if not seen_header:
			if line.to_lower().begins_with("gimp palette"):
				seen_header = true
			continue

		if line.begins_with("#"):
			continue
		if line.to_lower().begins_with("name:"):
			palette.name = line.substr(5).strip_edges()
			continue
		if line.to_lower().begins_with("columns:"):
			continue

		# "R G B [name]" with any run of whitespace as the separator.
		var fields: PackedStringArray = _split_whitespace(line)
		if fields.size() < 3:
			continue
		if not (fields[0].is_valid_int() and fields[1].is_valid_int() and fields[2].is_valid_int()):
			continue

		var color: Color = Color8(
			clampi(int(fields[0]), 0, 255),
			clampi(int(fields[1]), 0, 255),
			clampi(int(fields[2]), 0, 255),
			255
		)
		var index: int = palette.add_color(color)

		if fields.size() > 3:
			var swatch_name: String = ""
			for i: int in range(3, fields.size()):
				if not swatch_name.is_empty():
					swatch_name += " "
				swatch_name += fields[i]
			palette.set_color_name(index, swatch_name)

	if not seen_header:
		return null
	return palette


static func _save_gpl(palette: PPPalette, path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_line("GIMP Palette")
	file.store_line("Name: %s" % palette.name)
	file.store_line("Columns: 0")
	file.store_line("#")

	for i: int in range(palette.size()):
		var color: Color = palette.get_color(i)
		var swatch_name: String = palette.get_color_name(i)
		if swatch_name.is_empty():
			swatch_name = "Untitled"
		file.store_line(
			"%3d %3d %3d\t%s" % [color.r8, color.g8, color.b8, swatch_name]
		)

	file.close()
	return OK


# --- JASC .pal --------------------------------------------------------------

static func _load_pal(path: String) -> PPPalette:
	var text: String = _read_text(path)
	if text.is_empty():
		return null

	var lines: PackedStringArray = PackedStringArray()
	for raw_line: String in text.split("\n"):
		lines.append(raw_line.strip_edges())

	if lines.size() < 3 or not lines[0].to_upper().begins_with("JASC-PAL"):
		return null

	var palette: PPPalette = PPPalette.create(path.get_file().get_basename(), PackedColorArray())

	# Line 1 is the version ("0100") and line 2 the count; the count is advisory,
	# so parse every row that looks like a colour rather than trusting it.
	for i: int in range(3, lines.size()):
		var fields: PackedStringArray = _split_whitespace(lines[i])
		if fields.size() < 3:
			continue
		if not (fields[0].is_valid_int() and fields[1].is_valid_int() and fields[2].is_valid_int()):
			continue
		palette.add_color(
			Color8(
				clampi(int(fields[0]), 0, 255),
				clampi(int(fields[1]), 0, 255),
				clampi(int(fields[2]), 0, 255),
				255
			)
		)

	return palette


static func _save_pal(palette: PPPalette, path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_line("JASC-PAL")
	file.store_line("0100")
	file.store_line(str(palette.size()))
	for i: int in range(palette.size()):
		var color: Color = palette.get_color(i)
		file.store_line("%d %d %d" % [color.r8, color.g8, color.b8])

	file.close()
	return OK


# --- Plain .hex -------------------------------------------------------------

static func _load_hex(path: String) -> PPPalette:
	var text: String = _read_text(path)
	if text.is_empty():
		return null

	var palette: PPPalette = PPPalette.create(path.get_file().get_basename(), PackedColorArray())
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges().lstrip("#")
		if line.is_empty():
			continue
		var color: Color = _parse_hex(line)
		if color.a < 0.0:
			continue
		palette.add_color(color)

	if palette.size() == 0:
		return null
	return palette


static func _save_hex(palette: PPPalette, path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	for i: int in range(palette.size()):
		var color: Color = palette.get_color(i)
		if color.a8 >= 255:
			file.store_line("%02X%02X%02X" % [color.r8, color.g8, color.b8])
		else:
			file.store_line(
				"%02X%02X%02X%02X" % [color.r8, color.g8, color.b8, color.a8]
			)

	file.close()
	return OK


## Parses "RRGGBB" or "RRGGBBAA". Returns a Color with a == -1.0 on failure,
## which callers check -- a real colour can never have negative alpha.
static func _parse_hex(text: String) -> Color:
	var clean: String = text.strip_edges().lstrip("#")
	if clean.length() != 6 and clean.length() != 8:
		return Color(0.0, 0.0, 0.0, -1.0)
	if not clean.is_valid_hex_number(false):
		return Color(0.0, 0.0, 0.0, -1.0)

	var r: int = clean.substr(0, 2).hex_to_int()
	var g: int = clean.substr(2, 2).hex_to_int()
	var b: int = clean.substr(4, 2).hex_to_int()
	var a: int = 255
	if clean.length() == 8:
		a = clean.substr(6, 2).hex_to_int()
	return Color8(r, g, b, a)


## Public helper so the default-palette tables can share the parser.
static func parse_hex(text: String) -> Color:
	return _parse_hex(text)


# --- Palette strips as .png -------------------------------------------------

static func _load_png(path: String) -> PPPalette:
	var image: Image = Image.load_from_file(path)
	if image == null:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var palette: PPPalette = PPPalette.create(path.get_file().get_basename(), PackedColorArray())
	var seen: Dictionary[int, bool] = {}

	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.a8 == 0:
				continue
			var key: int = (
				(color.r8 << 24) | (color.g8 << 16) | (color.b8 << 8) | color.a8
			)
			if seen.has(key):
				continue
			seen[key] = true
			palette.add_color(color)

	if palette.size() == 0:
		return null
	return palette


static func _save_png(palette: PPPalette, path: String) -> Error:
	if palette.size() == 0:
		return ERR_INVALID_DATA

	var image: Image = Image.create_empty(
		palette.size(), 1, false, Image.FORMAT_RGBA8
	)
	for i: int in range(palette.size()):
		image.set_pixel(i, 0, palette.get_color(i))
	return image.save_png(path)


# --- Shared helpers ---------------------------------------------------------

static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	# Normalise CRLF and lone CR so the line splitters see plain \n.
	return text.replace("\r\n", "\n").replace("\r", "\n")


static func _split_whitespace(line: String) -> PackedStringArray:
	var fields: PackedStringArray = PackedStringArray()
	for token: String in line.replace("\t", " ").split(" ", false):
		var trimmed: String = token.strip_edges()
		if not trimmed.is_empty():
			fields.append(trimmed)
	return fields
