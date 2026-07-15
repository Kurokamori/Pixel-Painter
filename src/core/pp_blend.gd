@abstract
class_name PPBlend
extends RefCounted

## Pixel blending for every mode in PPTypes.BlendMode.
##
## Blending follows the W3C compositing model (the same one Aseprite uses):
##
##   ar = as + ab * (1 - as)
##   Cr = ((1 - ab) * Cs + ab * B(Cb, Cs)) * as / ar + Cb * ab * (1 - as) / ar
##
## where `b` is the backdrop, `s` is the source, and B() is the mode's colour
## function operating on straight (non-premultiplied) components.
##
## Buffers are raw RGBA8 bytes (PackedByteArray, 4 bytes per pixel) rather than
## Image.get_pixel/set_pixel calls, which are an order of magnitude slower.

const EPSILON: float = 0.0000001


## Blends `src` onto `dst` in place, restricted to `rect` (in pixel coords).
## Both buffers must describe images of the same `size` in FORMAT_RGBA8.
## `opacity` (0..1) scales the source alpha; `mask` (optional) further scales it
## per pixel and is used to honour the active selection.
static func blend_buffer(
	dst: PackedByteArray,
	src: PackedByteArray,
	size: Vector2i,
	rect: Rect2i,
	mode: PPTypes.BlendMode,
	opacity: float,
	mask: PackedByteArray = PackedByteArray()
) -> void:
	var clipped: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, size))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	if opacity <= 0.0:
		return

	var has_mask: bool = mask.size() == size.x * size.y
	var x_end: int = clipped.position.x + clipped.size.x
	var y_end: int = clipped.position.y + clipped.size.y

	for y: int in range(clipped.position.y, y_end):
		var row: int = y * size.x
		for x: int in range(clipped.position.x, x_end):
			var pixel_index: int = row + x
			var i: int = pixel_index * PPTypes.BPP

			var src_a: float = (float(src[i + 3]) / 255.0) * opacity
			if has_mask:
				src_a *= float(mask[pixel_index]) / 255.0
			if src_a <= EPSILON:
				continue

			var dst_a: float = float(dst[i + 3]) / 255.0

			# Fast path: opaque source over anything, in NORMAL mode.
			if mode == PPTypes.BlendMode.NORMAL and src_a >= 1.0 - EPSILON:
				dst[i] = src[i]
				dst[i + 1] = src[i + 1]
				dst[i + 2] = src[i + 2]
				dst[i + 3] = 255
				continue

			var out_a: float = src_a + dst_a * (1.0 - src_a)
			if out_a <= EPSILON:
				dst[i] = 0
				dst[i + 1] = 0
				dst[i + 2] = 0
				dst[i + 3] = 0
				continue

			var backdrop: Vector3 = Vector3(
				float(dst[i]) / 255.0, float(dst[i + 1]) / 255.0, float(dst[i + 2]) / 255.0
			)
			var source: Vector3 = Vector3(
				float(src[i]) / 255.0, float(src[i + 1]) / 255.0, float(src[i + 2]) / 255.0
			)

			var blended: Vector3 = apply_mode(mode, backdrop, source)
			# Mix the raw source with the blended result according to how opaque
			# the backdrop is: with no backdrop there is nothing to blend against.
			var composed: Vector3 = source.lerp(blended, dst_a)

			var out_rgb: Vector3 = (
				(composed * src_a + backdrop * dst_a * (1.0 - src_a)) / out_a
			)

			dst[i] = _to_byte(out_rgb.x)
			dst[i + 1] = _to_byte(out_rgb.y)
			dst[i + 2] = _to_byte(out_rgb.z)
			dst[i + 3] = _to_byte(out_a)


## Replaces a rect of `dst` with `src` verbatim (used for undo restore and for
## tools that must overwrite alpha rather than blend it, such as the eraser).
static func copy_buffer(
	dst: PackedByteArray, src: PackedByteArray, size: Vector2i, rect: Rect2i
) -> void:
	var clipped: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, size))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	var row_bytes: int = clipped.size.x * PPTypes.BPP
	for y: int in range(clipped.position.y, clipped.position.y + clipped.size.y):
		var offset: int = (y * size.x + clipped.position.x) * PPTypes.BPP
		for b: int in range(row_bytes):
			dst[offset + b] = src[offset + b]


static func apply_mode(
	mode: PPTypes.BlendMode, backdrop: Vector3, source: Vector3
) -> Vector3:
	match mode:
		PPTypes.BlendMode.NORMAL:
			return source
		PPTypes.BlendMode.DARKEN:
			return Vector3(
				minf(backdrop.x, source.x),
				minf(backdrop.y, source.y),
				minf(backdrop.z, source.z)
			)
		PPTypes.BlendMode.MULTIPLY:
			return backdrop * source
		PPTypes.BlendMode.COLOR_BURN:
			return Vector3(
				_color_burn(backdrop.x, source.x),
				_color_burn(backdrop.y, source.y),
				_color_burn(backdrop.z, source.z)
			)
		PPTypes.BlendMode.LIGHTEN:
			return Vector3(
				maxf(backdrop.x, source.x),
				maxf(backdrop.y, source.y),
				maxf(backdrop.z, source.z)
			)
		PPTypes.BlendMode.SCREEN:
			return backdrop + source - backdrop * source
		PPTypes.BlendMode.COLOR_DODGE:
			return Vector3(
				_color_dodge(backdrop.x, source.x),
				_color_dodge(backdrop.y, source.y),
				_color_dodge(backdrop.z, source.z)
			)
		PPTypes.BlendMode.ADDITION:
			return _saturate(backdrop + source)
		PPTypes.BlendMode.OVERLAY:
			return Vector3(
				_hard_light(source.x, backdrop.x),
				_hard_light(source.y, backdrop.y),
				_hard_light(source.z, backdrop.z)
			)
		PPTypes.BlendMode.SOFT_LIGHT:
			return Vector3(
				_soft_light(backdrop.x, source.x),
				_soft_light(backdrop.y, source.y),
				_soft_light(backdrop.z, source.z)
			)
		PPTypes.BlendMode.HARD_LIGHT:
			return Vector3(
				_hard_light(backdrop.x, source.x),
				_hard_light(backdrop.y, source.y),
				_hard_light(backdrop.z, source.z)
			)
		PPTypes.BlendMode.DIFFERENCE:
			return Vector3(
				absf(backdrop.x - source.x),
				absf(backdrop.y - source.y),
				absf(backdrop.z - source.z)
			)
		PPTypes.BlendMode.EXCLUSION:
			return backdrop + source - 2.0 * backdrop * source
		PPTypes.BlendMode.SUBTRACT:
			return _saturate(backdrop - source)
		PPTypes.BlendMode.DIVIDE:
			return Vector3(
				_divide(backdrop.x, source.x),
				_divide(backdrop.y, source.y),
				_divide(backdrop.z, source.z)
			)
		PPTypes.BlendMode.HUE:
			return _set_luminosity(_set_saturation(source, _saturation(backdrop)), _luminosity(backdrop))
		PPTypes.BlendMode.SATURATION:
			return _set_luminosity(_set_saturation(backdrop, _saturation(source)), _luminosity(backdrop))
		PPTypes.BlendMode.COLOR:
			return _set_luminosity(source, _luminosity(backdrop))
		PPTypes.BlendMode.LUMINOSITY:
			return _set_luminosity(backdrop, _luminosity(source))
	return source


static func _to_byte(value: float) -> int:
	return clampi(int(round(value * 255.0)), 0, 255)


static func _saturate(v: Vector3) -> Vector3:
	return Vector3(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))


static func _color_burn(cb: float, cs: float) -> float:
	if cb >= 1.0:
		return 1.0
	if cs <= 0.0:
		return 0.0
	return 1.0 - minf(1.0, (1.0 - cb) / cs)


static func _color_dodge(cb: float, cs: float) -> float:
	if cb <= 0.0:
		return 0.0
	if cs >= 1.0:
		return 1.0
	return minf(1.0, cb / (1.0 - cs))


static func _hard_light(cb: float, cs: float) -> float:
	if cs <= 0.5:
		return cb * (2.0 * cs)
	return _screen_channel(cb, 2.0 * cs - 1.0)


static func _screen_channel(cb: float, cs: float) -> float:
	return cb + cs - cb * cs


static func _soft_light(cb: float, cs: float) -> float:
	var d: float = 0.0
	if cb <= 0.25:
		d = ((16.0 * cb - 12.0) * cb + 4.0) * cb
	else:
		d = sqrt(cb)
	if cs <= 0.5:
		return cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb)
	return cb + (2.0 * cs - 1.0) * (d - cb)


static func _divide(cb: float, cs: float) -> float:
	if cb <= 0.0:
		return 0.0
	if cs <= 0.0:
		return 1.0
	return minf(1.0, cb / cs)


# --- Non-separable modes (HUE / SATURATION / COLOR / LUMINOSITY) ---

static func _luminosity(c: Vector3) -> float:
	return 0.3 * c.x + 0.59 * c.y + 0.11 * c.z


static func _clip_color(c: Vector3) -> Vector3:
	var lum: float = _luminosity(c)
	var lowest: float = minf(c.x, minf(c.y, c.z))
	var highest: float = maxf(c.x, maxf(c.y, c.z))
	var result: Vector3 = c
	if lowest < 0.0:
		var denom_low: float = lum - lowest
		if absf(denom_low) > EPSILON:
			result = Vector3(
				lum + (result.x - lum) * lum / denom_low,
				lum + (result.y - lum) * lum / denom_low,
				lum + (result.z - lum) * lum / denom_low
			)
		else:
			result = Vector3(lum, lum, lum)
	if highest > 1.0:
		var denom_high: float = highest - lum
		if absf(denom_high) > EPSILON:
			result = Vector3(
				lum + (result.x - lum) * (1.0 - lum) / denom_high,
				lum + (result.y - lum) * (1.0 - lum) / denom_high,
				lum + (result.z - lum) * (1.0 - lum) / denom_high
			)
		else:
			result = Vector3(lum, lum, lum)
	return result


static func _set_luminosity(c: Vector3, lum: float) -> Vector3:
	var delta: float = lum - _luminosity(c)
	return _clip_color(c + Vector3(delta, delta, delta))


static func _saturation(c: Vector3) -> float:
	return maxf(c.x, maxf(c.y, c.z)) - minf(c.x, minf(c.y, c.z))


static func _set_saturation(c: Vector3, sat: float) -> Vector3:
	# Sort the three channels by value, rescale the mid/max pair, zero the min.
	var components: Array[float] = [c.x, c.y, c.z]
	var min_index: int = 0
	var max_index: int = 0
	for i: int in range(1, 3):
		if components[i] < components[min_index]:
			min_index = i
		if components[i] > components[max_index]:
			max_index = i
	if min_index == max_index:
		return Vector3.ZERO
	var mid_index: int = 3 - min_index - max_index

	var result: Array[float] = [0.0, 0.0, 0.0]
	var span: float = components[max_index] - components[min_index]
	if span > EPSILON:
		result[mid_index] = (components[mid_index] - components[min_index]) * sat / span
		result[max_index] = sat
	result[min_index] = 0.0
	return Vector3(result[0], result[1], result[2])
