@abstract
class_name PPProjectIO
extends RefCounted

## The native project format, `.pxp`.
##
## A .pxp is a zip archive:
##
##   manifest.json     the whole document structure
##   cels/<id>.png     one PNG per *unique* cel
##
## Storing cels as PNGs rather than a raw blob means the archive is inspectable
## with any zip tool, compresses properly, and survives a manifest change without
## a migration. Cels are keyed by id and referenced from the layer table, so two
## frames pointing at the same id round-trip as a genuine linked cel rather than
## silently becoming two copies.

const FORMAT_ID: String = "pixel-painter-project"
const FORMAT_VERSION: int = 1
const EXTENSION: String = "pxp"


static func save(document: PPDocument, path: String) -> Error:
	var bytes: PackedByteArray = encode(document)
	if bytes.is_empty():
		return ERR_CANT_CREATE

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.close()
	return OK


static func load_project(path: String) -> PPDocument:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	var document: PPDocument = decode(bytes)
	if document != null:
		document.mark_saved(path)
	return document


## Serialises to an in-memory archive. The sync layer moves these bytes over the
## wire directly, so encoding must not depend on a filesystem destination.
static func encode(document: PPDocument) -> PackedByteArray:
	# ZIPPacker only writes to a path, so build in a scratch file under user://
	# and read it back. user:// is writable on every platform we ship to,
	# including a sandboxed iOS app, which res:// and the OS temp dir are not.
	var scratch: String = "user://.pxp_encode_%d.tmp" % Time.get_ticks_usec()

	var packer: ZIPPacker = ZIPPacker.new()
	if packer.open(scratch) != OK:
		return PackedByteArray()

	var sprite: PPSprite = document.sprite
	var unique_cels: Array[PPCel] = _collect_unique_cels(sprite)

	packer.start_file("manifest.json")
	packer.write_file(
		JSON.stringify(_build_manifest(sprite), "  ").to_utf8_buffer()
	)
	packer.close_file()

	for cel: PPCel in unique_cels:
		packer.start_file("cels/%d.png" % cel.id)
		packer.write_file(cel.image.save_png_to_buffer())
		packer.close_file()

	packer.close()

	var file: FileAccess = FileAccess.open(scratch, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	return bytes


static func decode(bytes: PackedByteArray) -> PPDocument:
	var scratch: String = "user://.pxp_decode_%d.tmp" % Time.get_ticks_usec()
	var out: FileAccess = FileAccess.open(scratch, FileAccess.WRITE)
	if out == null:
		return null
	out.store_buffer(bytes)
	out.close()

	var reader: ZIPReader = ZIPReader.new()
	if reader.open(scratch) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
		return null

	var document: PPDocument = null
	var manifest_bytes: PackedByteArray = reader.read_file("manifest.json")
	if not manifest_bytes.is_empty():
		var parsed: Variant = JSON.parse_string(
			manifest_bytes.get_string_from_utf8()
		)
		if parsed is Dictionary:
			document = _build_document(parsed as Dictionary, reader)

	reader.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	return document


# --- Manifest ---------------------------------------------------------------

static func _build_manifest(sprite: PPSprite) -> Dictionary:
	var frames: Array = []
	for frame: PPFrame in sprite.frames:
		frames.append({"duration": frame.duration_ms})

	var layers: Array = []
	for layer: PPLayer in sprite.layers:
		var cel_refs: Array = []
		for cel: PPCel in layer.cels:
			if cel == null:
				cel_refs.append(null)
			else:
				cel_refs.append({"id": cel.id, "opacity": cel.opacity})
		layers.append(
			{
				"name": layer.name,
				"visible": layer.visible,
				"locked": layer.locked,
				"opacity": layer.opacity,
				"blend_mode": int(layer.blend_mode),
				"reference_only": layer.reference_only,
				"cels": cel_refs,
			}
		)

	var tags: Array = []
	for tag: PPTag in sprite.tags:
		tags.append(
			{
				"name": tag.name,
				"from": tag.from_frame,
				"to": tag.to_frame,
				"direction": int(tag.direction),
				"color": tag.color.to_html(true),
				"repeat": tag.repeat,
			}
		)

	var palette_colors: Array = []
	var palette_names: Dictionary = {}
	var palette_name: String = "Palette"
	if sprite.palette != null:
		palette_name = sprite.palette.name
		for color: Color in sprite.palette.colors:
			palette_colors.append(color.to_html(true))
		for key: int in sprite.palette.color_names:
			palette_names[str(key)] = sprite.palette.color_names[key]

	return {
		"format": FORMAT_ID,
		"version": FORMAT_VERSION,
		"size": [sprite.size.x, sprite.size.y],
		"frames": frames,
		"layers": layers,
		"tags": tags,
		"palette": {
			"name": palette_name,
			"colors": palette_colors,
			"names": palette_names,
		},
	}


static func _build_document(manifest: Dictionary, reader: ZIPReader) -> PPDocument:
	if String(manifest.get("format", "")) != FORMAT_ID:
		return null

	var size_field: Array = manifest.get("size", [64, 64])
	if size_field.size() < 2:
		return null
	var size: Vector2i = Vector2i(int(size_field[0]), int(size_field[1]))
	if size.x < PPTypes.MIN_SPRITE_SIZE or size.y < PPTypes.MIN_SPRITE_SIZE:
		return null
	if size.x > PPTypes.MAX_SPRITE_SIZE or size.y > PPTypes.MAX_SPRITE_SIZE:
		return null

	var sprite: PPSprite = PPSprite.new()
	sprite.size = size

	sprite.frames = []
	for entry: Variant in manifest.get("frames", []):
		var frame_data: Dictionary = entry as Dictionary
		sprite.frames.append(
			PPFrame.create(int(frame_data.get("duration", PPTypes.DEFAULT_FRAME_DURATION_MS)))
		)
	if sprite.frames.is_empty():
		sprite.frames.append(PPFrame.create())

	# One PPCel instance per id, so two frames referencing the same id come back
	# as the same object -- which is exactly what "linked" means in this model.
	var cels_by_id: Dictionary[int, PPCel] = {}

	sprite.layers = []
	for entry: Variant in manifest.get("layers", []):
		var layer_data: Dictionary = entry as Dictionary
		var layer: PPLayer = PPLayer.new()
		layer.name = String(layer_data.get("name", "Layer"))
		layer.visible = bool(layer_data.get("visible", true))
		layer.locked = bool(layer_data.get("locked", false))
		layer.opacity = clampf(float(layer_data.get("opacity", 1.0)), 0.0, 1.0)
		layer.blend_mode = _safe_blend_mode(int(layer_data.get("blend_mode", 0)))
		layer.reference_only = bool(layer_data.get("reference_only", false))

		layer.cels = []
		var cel_refs: Array = layer_data.get("cels", [])
		for frame_index: int in range(sprite.frames.size()):
			if frame_index >= cel_refs.size() or cel_refs[frame_index] == null:
				layer.cels.append(PPCel.create(size))
				continue

			var ref: Dictionary = cel_refs[frame_index] as Dictionary
			var id: int = int(ref.get("id", 0))

			if not cels_by_id.has(id):
				var cel: PPCel = _read_cel(reader, id, size)
				cel.id = id
				cel.opacity = clampf(float(ref.get("opacity", 1.0)), 0.0, 1.0)
				PPCel.reserve_id(id)
				cels_by_id[id] = cel

			layer.cels.append(cels_by_id[id])

		sprite.layers.append(layer)

	if sprite.layers.is_empty():
		sprite.layers.append(PPLayer.create("Layer 1", sprite.frames.size(), size))

	sprite.tags = []
	for entry: Variant in manifest.get("tags", []):
		var tag_data: Dictionary = entry as Dictionary
		var tag: PPTag = PPTag.new()
		tag.name = String(tag_data.get("name", "Tag"))
		tag.from_frame = clampi(int(tag_data.get("from", 0)), 0, sprite.frames.size() - 1)
		tag.to_frame = clampi(int(tag_data.get("to", 0)), 0, sprite.frames.size() - 1)
		tag.direction = _safe_direction(int(tag_data.get("direction", 0)))
		tag.color = Color.from_string(String(tag_data.get("color", "#59b8ff")), Color.SKY_BLUE)
		tag.repeat = int(tag_data.get("repeat", 0))
		if tag.to_frame >= tag.from_frame:
			sprite.tags.append(tag)

	var palette_data: Dictionary = manifest.get("palette", {}) as Dictionary
	var palette: PPPalette = PPPalette.create(
		String(palette_data.get("name", "Palette")), PackedColorArray()
	)
	for hex: Variant in palette_data.get("colors", []):
		palette.colors.append(Color.from_string(String(hex), Color.WHITE))
	var names: Dictionary = palette_data.get("names", {}) as Dictionary
	for key: Variant in names:
		palette.set_color_name(int(String(key)), String(names[key]))
	sprite.palette = palette

	return PPDocument.from_sprite(sprite)


static func _read_cel(reader: ZIPReader, id: int, size: Vector2i) -> PPCel:
	var png: PackedByteArray = reader.read_file("cels/%d.png" % id)
	if png.is_empty():
		return PPCel.create(size)

	var image: Image = Image.new()
	if image.load_png_from_buffer(png) != OK:
		return PPCel.create(size)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	# A cel from a tampered or mismatched archive must not be allowed to make the
	# sprite ragged: force it to the canvas size.
	if image.get_width() != size.x or image.get_height() != size.y:
		var fitted: Image = Image.create_empty(
			size.x, size.y, false, Image.FORMAT_RGBA8
		)
		fitted.fill(Color(0.0, 0.0, 0.0, 0.0))
		fitted.blit_rect(
			image,
			Rect2i(0, 0, mini(image.get_width(), size.x), mini(image.get_height(), size.y)),
			Vector2i.ZERO
		)
		image = fitted

	return PPCel.from_image(image)


static func _collect_unique_cels(sprite: PPSprite) -> Array[PPCel]:
	var unique: Array[PPCel] = []
	var seen: Dictionary[PPCel, bool] = {}
	for layer: PPLayer in sprite.layers:
		for cel: PPCel in layer.cels:
			if cel == null or seen.has(cel):
				continue
			seen[cel] = true
			unique.append(cel)
	return unique


static func _safe_blend_mode(value: int) -> PPTypes.BlendMode:
	if value < 0 or value >= PPTypes.BLEND_MODE_NAMES.size():
		return PPTypes.BlendMode.NORMAL
	return value as PPTypes.BlendMode


static func _safe_direction(value: int) -> PPTypes.AnimationDirection:
	if value < 0 or value > 3:
		return PPTypes.AnimationDirection.FORWARD
	return value as PPTypes.AnimationDirection
