@abstract
class_name PPCompositor
extends RefCounted

## Flattens (layer, frame) cels into a single RGBA8 image.
##
## Normal-mode layers -- the overwhelming majority -- are composited with
## Image.blend_rect, which is native code. Only layers using an exotic blend
## mode fall back to the per-pixel GDScript path in PPBlend, and even then the
## work is confined to the requested rect.


## Allocates a fresh image of the whole frame.
static func flatten_frame(
	sprite: PPSprite, frame_index: int, options: PPCompositeOptions = null
) -> Image:
	var target: Image = Image.create_empty(
		sprite.size.x, sprite.size.y, false, Image.FORMAT_RGBA8
	)
	target.fill(Color(0.0, 0.0, 0.0, 0.0))
	composite_into(target, sprite, frame_index, sprite.get_bounds(), options)
	return target


## Composites `rect` of `frame_index` into an existing image, which must already
## be sprite-sized RGBA8. The rect is cleared to transparent first, so callers
## can reuse one image across strokes and only pay for the pixels that moved.
static func composite_into(
	target: Image,
	sprite: PPSprite,
	frame_index: int,
	rect: Rect2i,
	options: PPCompositeOptions = null
) -> void:
	var opts: PPCompositeOptions = options
	if opts == null:
		opts = PPCompositeOptions.new()

	var clipped: Rect2i = rect.intersection(sprite.get_bounds())
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return

	_clear_rect(target, clipped)

	# Layers are stored bottom-first, so a straight walk is back-to-front.
	for layer_index: int in range(sprite.layer_count()):
		var layer: PPLayer = sprite.get_layer(layer_index)
		if layer_index == opts.skip_layer_index:
			continue
		if opts.only_visible and not layer.visible:
			continue
		if layer.reference_only and not opts.include_reference:
			continue

		var source: Image = null
		var cel_opacity: float = 1.0
		if layer_index == opts.override_layer_index and opts.override_image != null:
			source = opts.override_image
		else:
			var cel: PPCel = layer.get_cel(frame_index)
			if cel == null or cel.image == null:
				continue
			source = cel.image
			cel_opacity = cel.opacity

		var opacity: float = clampf(layer.opacity * cel_opacity, 0.0, 1.0)
		if opacity <= 0.0:
			continue

		_blend_layer(target, source, sprite.size, clipped, layer.blend_mode, opacity)


static func _blend_layer(
	target: Image,
	source: Image,
	size: Vector2i,
	rect: Rect2i,
	mode: PPTypes.BlendMode,
	opacity: float
) -> void:
	if mode == PPTypes.BlendMode.NORMAL:
		var native_source: Image = source
		if opacity < 1.0:
			native_source = _with_scaled_alpha(source, opacity)
		target.blend_rect(native_source, rect, rect.position)
		return

	var dst_buffer: PackedByteArray = target.get_data()
	var src_buffer: PackedByteArray = source.get_data()
	PPBlend.blend_buffer(dst_buffer, src_buffer, size, rect, mode, opacity)
	_replace_data(target, dst_buffer, size)


## Copy of `source` with every alpha byte scaled by `opacity`. Touching only the
## alpha channel keeps this at a quarter of the work of a full pixel pass.
static func _with_scaled_alpha(source: Image, opacity: float) -> Image:
	var buffer: PackedByteArray = source.get_data()
	var scale: int = clampi(int(round(opacity * 255.0)), 0, 255)
	var index: int = 3
	var length: int = buffer.size()
	while index < length:
		buffer[index] = (buffer[index] * scale) / 255
		index += PPTypes.BPP
	return Image.create_from_data(
		source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8, buffer
	)


static func _replace_data(target: Image, buffer: PackedByteArray, size: Vector2i) -> void:
	var replacement: Image = Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_RGBA8, buffer
	)
	target.copy_from(replacement)


static func _clear_rect(target: Image, rect: Rect2i) -> void:
	target.fill_rect(rect, Color(0.0, 0.0, 0.0, 0.0))


## Flattens every frame in order. Used by the spritesheet/GIF exporters.
static func flatten_all_frames(
	sprite: PPSprite, options: PPCompositeOptions = null
) -> Array[Image]:
	var images: Array[Image] = []
	for frame_index: int in range(sprite.frame_count()):
		images.append(flatten_frame(sprite, frame_index, options))
	return images


## A flattened frame tinted toward `tint` and faded to `alpha`, for onion skins.
static func flatten_onion(
	sprite: PPSprite, frame_index: int, tint: Color, alpha: float
) -> Image:
	var image: Image = flatten_frame(sprite, frame_index)
	var buffer: PackedByteArray = image.get_data()
	var tint_r: float = tint.r
	var tint_g: float = tint.g
	var tint_b: float = tint.b
	var index: int = 0
	var length: int = buffer.size()
	while index < length:
		var a: int = buffer[index + 3]
		if a > 0:
			buffer[index] = clampi(int(buffer[index] * 0.35 + tint_r * 255.0 * 0.65), 0, 255)
			buffer[index + 1] = clampi(int(buffer[index + 1] * 0.35 + tint_g * 255.0 * 0.65), 0, 255)
			buffer[index + 2] = clampi(int(buffer[index + 2] * 0.35 + tint_b * 255.0 * 0.65), 0, 255)
			buffer[index + 3] = clampi(int(a * alpha), 0, 255)
		index += PPTypes.BPP
	return Image.create_from_data(
		sprite.size.x, sprite.size.y, false, Image.FORMAT_RGBA8, buffer
	)
