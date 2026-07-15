@abstract
class_name PPExportIO
extends RefCounted

## Flattened exports: single PNG, per-frame PNGs, sprite sheets (with optional
## JSON metadata), and animated GIF.
##
## Everything here composites through PPCompositeOptions.for_export(), which
## drops hidden layers and reference layers. What you export is what the canvas
## shows, minus the scaffolding.

enum SheetLayout {
	HORIZONTAL,
	VERTICAL,
	GRID,
}


class SheetOptions:
	extends RefCounted

	var layout: SheetLayout = SheetLayout.HORIZONTAL
	## Only consulted for GRID.
	var columns: int = 4
	var padding: int = 0
	## Writes a sibling .json describing each frame's rect and duration.
	var write_metadata: bool = true
	## Nearest-neighbour upscale applied to the finished sheet.
	var scale: int = 1


static func supported_extensions() -> PackedStringArray:
	return PackedStringArray(["png", "gif"])


# --- Single image -----------------------------------------------------------

static func export_png(document: PPDocument, path: String, frame_index: int, scale: int = 1) -> Error:
	var image: Image = PPCompositor.flatten_frame(
		document.sprite, frame_index, PPCompositeOptions.for_export()
	)
	return _scaled(image, scale).save_png(path)


## One PNG per frame: "hero.png" becomes hero_000.png, hero_001.png, ...
static func export_frames(document: PPDocument, path: String, scale: int = 1) -> Error:
	var directory: String = path.get_base_dir()
	var stem: String = path.get_file().get_basename()

	for frame_index: int in range(document.sprite.frame_count()):
		var image: Image = PPCompositor.flatten_frame(
			document.sprite, frame_index, PPCompositeOptions.for_export()
		)
		var frame_path: String = "%s/%s_%03d.png" % [directory, stem, frame_index]
		var error: Error = _scaled(image, scale).save_png(frame_path)
		if error != OK:
			return error

	return OK


# --- Sprite sheet -----------------------------------------------------------

static func export_spritesheet(
	document: PPDocument, path: String, options: SheetOptions
) -> Error:
	var sprite: PPSprite = document.sprite
	var frame_count: int = sprite.frame_count()
	if frame_count == 0:
		return ERR_INVALID_DATA

	var grid: Vector2i = _sheet_grid(frame_count, options)
	var cell: Vector2i = sprite.size + Vector2i(options.padding, options.padding)

	var sheet_size: Vector2i = Vector2i(
		grid.x * cell.x - options.padding,
		grid.y * cell.y - options.padding
	)
	if sheet_size.x <= 0 or sheet_size.y <= 0:
		return ERR_INVALID_DATA

	var sheet: Image = Image.create_empty(
		sheet_size.x, sheet_size.y, false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(0.0, 0.0, 0.0, 0.0))

	var frame_rects: Array = []
	for frame_index: int in range(frame_count):
		var column: int = frame_index % grid.x
		var row: int = frame_index / grid.x
		var at: Vector2i = Vector2i(column * cell.x, row * cell.y)

		var image: Image = PPCompositor.flatten_frame(
			sprite, frame_index, PPCompositeOptions.for_export()
		)
		sheet.blit_rect(image, sprite.get_bounds(), at)

		frame_rects.append(
			{
				"frame": frame_index,
				"x": at.x * options.scale,
				"y": at.y * options.scale,
				"w": sprite.size.x * options.scale,
				"h": sprite.size.y * options.scale,
				"duration": sprite.get_frame(frame_index).duration_ms,
			}
		)

	var error: Error = _scaled(sheet, options.scale).save_png(path)
	if error != OK:
		return error

	if options.write_metadata:
		error = _write_sheet_metadata(document, path, frame_rects, options)

	return error


static func _sheet_grid(frame_count: int, options: SheetOptions) -> Vector2i:
	match options.layout:
		SheetLayout.HORIZONTAL:
			return Vector2i(frame_count, 1)
		SheetLayout.VERTICAL:
			return Vector2i(1, frame_count)
	var columns: int = maxi(1, options.columns)
	var rows: int = int(ceil(float(frame_count) / float(columns)))
	return Vector2i(columns, maxi(1, rows))


static func _write_sheet_metadata(
	document: PPDocument, path: String, frame_rects: Array, options: SheetOptions
) -> Error:
	var tags: Array = []
	for tag: PPTag in document.sprite.tags:
		tags.append(
			{
				"name": tag.name,
				"from": tag.from_frame,
				"to": tag.to_frame,
				"direction": int(tag.direction),
			}
		)

	var metadata: Dictionary = {
		"image": path.get_file(),
		"size": {
			"w": document.sprite.size.x * options.scale,
			"h": document.sprite.size.y * options.scale,
		},
		"frames": frame_rects,
		"tags": tags,
	}

	var json_path: String = path.get_basename() + ".json"
	var file: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(metadata, "  "))
	file.close()
	return OK


# --- GIF --------------------------------------------------------------------

static func export_gif(document: PPDocument, path: String, scale: int = 1) -> Error:
	var frames: Array[Image] = []
	var delays: Array[int] = []

	for frame_index: int in range(document.sprite.frame_count()):
		var image: Image = PPCompositor.flatten_frame(
			document.sprite, frame_index, PPCompositeOptions.for_export()
		)
		frames.append(_scaled(image, scale))
		delays.append(document.sprite.get_frame(frame_index).duration_ms)

	return PPGifIO.save_animation(frames, delays, path, true)


# --- Import -----------------------------------------------------------------

## Opens a flat image as a new one-layer, one-frame document.
static func import_image(path: String) -> PPDocument:
	var image: Image = Image.load_from_file(path)
	if image == null:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var size: Vector2i = Vector2i(image.get_width(), image.get_height())
	if size.x <= 0 or size.y <= 0:
		return null
	if size.x > PPTypes.MAX_SPRITE_SIZE or size.y > PPTypes.MAX_SPRITE_SIZE:
		return null

	var sprite: PPSprite = PPSprite.create(size, PPDefaultPalettes.get_default())
	sprite.get_layer(0).name = path.get_file().get_basename()
	sprite.get_layer(0).cels[0] = PPCel.from_image(image)

	var document: PPDocument = PPDocument.from_sprite(sprite)
	document.mark_saved("")
	return document


## Slices a sprite sheet into frames of `cell` size, left-to-right, top-to-bottom.
static func import_spritesheet(path: String, cell: Vector2i) -> PPDocument:
	var image: Image = Image.load_from_file(path)
	if image == null or cell.x <= 0 or cell.y <= 0:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var columns: int = image.get_width() / cell.x
	var rows: int = image.get_height() / cell.y
	var count: int = columns * rows
	if count <= 0:
		return null

	var sprite: PPSprite = PPSprite.create(cell, PPDefaultPalettes.get_default())
	sprite.frames = []
	var layer: PPLayer = sprite.get_layer(0)
	layer.name = path.get_file().get_basename()
	layer.cels = []

	for index: int in range(count):
		var column: int = index % columns
		var row: int = index / columns
		var source: Rect2i = Rect2i(
			Vector2i(column * cell.x, row * cell.y), cell
		)

		var frame_image: Image = Image.create_empty(
			cell.x, cell.y, false, Image.FORMAT_RGBA8
		)
		frame_image.fill(Color(0.0, 0.0, 0.0, 0.0))
		frame_image.blit_rect(image, source, Vector2i.ZERO)

		sprite.frames.append(PPFrame.create())
		layer.cels.append(PPCel.from_image(frame_image))

	return PPDocument.from_sprite(sprite)


static func _scaled(image: Image, scale: int) -> Image:
	if scale <= 1:
		return image
	var result: Image = Image.new()
	result.copy_from(image)
	# Nearest-neighbour is the only correct choice: any smoothing would invent
	# colours that are not in the artwork.
	result.resize(
		image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST
	)
	return result
