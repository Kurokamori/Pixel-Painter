@abstract
class_name PPSpriteCommands
extends RefCounted

## Whole-sprite geometry edits: canvas resize, scale, crop, flip and rotate.
##
## These all share one shape -- every cel's image is replaced and the sprite's
## size may change -- so they share one command class, `TransformSprite`, built
## from a per-cel transform. Each unique cel is transformed exactly once, which
## keeps linked cels linked afterwards.


class TransformSprite:
	extends PPCommand

	var _before_size: Vector2i = Vector2i.ZERO
	var _after_size: Vector2i = Vector2i.ZERO
	## Parallel arrays: _cels[i]'s pixels before and after, zstd-compressed.
	var _cels: Array[PPCel] = []
	var _before: Array[PackedByteArray] = []
	var _after: Array[PackedByteArray] = []
	var _before_raw: PackedInt32Array = PackedInt32Array()
	var _after_raw: PackedInt32Array = PackedInt32Array()

	## `transform` takes an Image and returns a new Image of `new_size`.
	static func create(
		sprite: PPSprite, new_size: Vector2i, transform: Callable, label_text: String
	) -> TransformSprite:
		var command: TransformSprite = TransformSprite.new()
		command.label = label_text
		command._before_size = sprite.size
		command._after_size = new_size

		var seen: Dictionary[PPCel, bool] = {}
		for layer: PPLayer in sprite.layers:
			for cel: PPCel in layer.cels:
				if cel == null or cel.image == null or seen.has(cel):
					continue
				seen[cel] = true

				var before_bytes: PackedByteArray = cel.image.get_data()
				var after_image: Image = transform.call(cel.image) as Image
				var after_bytes: PackedByteArray = after_image.get_data()

				command._cels.append(cel)
				command._before_raw.append(before_bytes.size())
				command._after_raw.append(after_bytes.size())
				command._before.append(before_bytes.compress(FileAccess.COMPRESSION_ZSTD))
				command._after.append(after_bytes.compress(FileAccess.COMPRESSION_ZSTD))

		if command._cels.is_empty() and new_size == sprite.size:
			return null
		return command

	func redo(document: PPDocument) -> void:
		_restore(document, _after, _after_raw, _after_size)

	func undo(document: PPDocument) -> void:
		_restore(document, _before, _before_raw, _before_size)

	func is_structural() -> bool:
		return true

	func _restore(
		document: PPDocument,
		blobs: Array[PackedByteArray],
		raw_sizes: PackedInt32Array,
		size: Vector2i
	) -> void:
		document.sprite.size = size
		for i: int in range(_cels.size()):
			var bytes: PackedByteArray = blobs[i].decompress(
				raw_sizes[i], FileAccess.COMPRESSION_ZSTD
			)
			_cels[i].image = Image.create_from_data(
				size.x, size.y, false, Image.FORMAT_RGBA8, bytes
			)
		document.on_canvas_size_changed()


# --- Factories --------------------------------------------------------------

## Grows or shrinks the canvas without touching pixel scale. `offset` is where
## the old canvas lands inside the new one (negative values crop).
static func resize_canvas(
	sprite: PPSprite, new_size: Vector2i, offset: Vector2i
) -> PPCommand:
	var old_size: Vector2i = sprite.size
	var transform: Callable = func(source: Image) -> Image:
		var result: Image = Image.create_empty(
			new_size.x, new_size.y, false, Image.FORMAT_RGBA8
		)
		result.fill(Color(0.0, 0.0, 0.0, 0.0))
		result.blit_rect(source, Rect2i(Vector2i.ZERO, old_size), offset)
		return result
	return TransformSprite.create(sprite, new_size, transform, "Resize Canvas")


## Rescales the artwork itself. Nearest-neighbour keeps pixel art crisp; it is
## the only interpolation that makes sense here, so it is not an option.
static func scale_sprite(sprite: PPSprite, new_size: Vector2i) -> PPCommand:
	var transform: Callable = func(source: Image) -> Image:
		var result: Image = Image.new()
		result.copy_from(source)
		result.resize(new_size.x, new_size.y, Image.INTERPOLATE_NEAREST)
		return result
	return TransformSprite.create(sprite, new_size, transform, "Scale Sprite")


static func crop(sprite: PPSprite, rect: Rect2i) -> PPCommand:
	var clipped: Rect2i = rect.intersection(sprite.get_bounds())
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return null
	var transform: Callable = func(source: Image) -> Image:
		var result: Image = Image.create_empty(
			clipped.size.x, clipped.size.y, false, Image.FORMAT_RGBA8
		)
		result.fill(Color(0.0, 0.0, 0.0, 0.0))
		result.blit_rect(source, clipped, Vector2i.ZERO)
		return result
	return TransformSprite.create(sprite, clipped.size, transform, "Crop")


static func flip(sprite: PPSprite, horizontal: bool) -> PPCommand:
	var transform: Callable = func(source: Image) -> Image:
		var result: Image = Image.new()
		result.copy_from(source)
		if horizontal:
			result.flip_x()
		else:
			result.flip_y()
		return result
	return TransformSprite.create(
		sprite, sprite.size, transform, "Flip Horizontal" if horizontal else "Flip Vertical"
	)


## Rotates by a multiple of 90 degrees. 90 and 270 swap the canvas dimensions.
static func rotate(sprite: PPSprite, degrees: int) -> PPCommand:
	var steps: int = posmod(degrees / 90, 4)
	if steps == 0:
		return null
	var new_size: Vector2i = sprite.size
	if steps == 1 or steps == 3:
		new_size = Vector2i(sprite.size.y, sprite.size.x)

	var transform: Callable = func(source: Image) -> Image:
		return _rotate_image(source, steps)
	return TransformSprite.create(sprite, new_size, transform, "Rotate %d°" % (steps * 90))


static func _rotate_image(source: Image, steps: int) -> Image:
	var width: int = source.get_width()
	var height: int = source.get_height()
	var out_width: int = width
	var out_height: int = height
	if steps == 1 or steps == 3:
		out_width = height
		out_height = width

	var src: PackedByteArray = source.get_data()
	var dst: PackedByteArray = PackedByteArray()
	dst.resize(out_width * out_height * PPTypes.BPP)

	for y: int in range(height):
		for x: int in range(width):
			var target_x: int = 0
			var target_y: int = 0
			match steps:
				1:
					target_x = out_width - 1 - y
					target_y = x
				2:
					target_x = width - 1 - x
					target_y = height - 1 - y
				3:
					target_x = y
					target_y = out_height - 1 - x
			var from_index: int = (y * width + x) * PPTypes.BPP
			var to_index: int = (target_y * out_width + target_x) * PPTypes.BPP
			for b: int in range(PPTypes.BPP):
				dst[to_index + b] = src[from_index + b]

	return Image.create_from_data(
		out_width, out_height, false, Image.FORMAT_RGBA8, dst
	)
