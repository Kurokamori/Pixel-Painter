class_name PPCel
extends Resource

## A single layer's pixels on a single frame.
##
## Cels are always the full sprite size. Aseprite stores bounded cels to save
## space; we trade that memory for far simpler compositing and undo, and compute
## tight bounds only when exporting to .ase.
##
## A *linked* cel is simply the same PPCel instance appearing at more than one
## frame index within a layer -- editing it edits every frame that references it.

@export var image: Image = null
@export_range(0.0, 1.0) var opacity: float = 1.0

## Stable identity used when serialising links between frames.
@export var id: int = 0

static var _next_id: int = 1


static func create(size: Vector2i) -> PPCel:
	var cel: PPCel = PPCel.new()
	cel.image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	cel.image.fill(Color(0.0, 0.0, 0.0, 0.0))
	cel.id = _take_id()
	return cel


static func from_image(source: Image) -> PPCel:
	var cel: PPCel = PPCel.new()
	cel.image = _as_rgba8(source)
	cel.id = _take_id()
	return cel


static func _take_id() -> int:
	var value: int = _next_id
	_next_id += 1
	return value


## Ensures freshly deserialised cels never collide with runtime-generated ids.
static func reserve_id(used: int) -> void:
	if used >= _next_id:
		_next_id = used + 1


static func _as_rgba8(source: Image) -> Image:
	var copy: Image = Image.new()
	copy.copy_from(source)
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	return copy


## A deep copy with a *new* identity -- used when unlinking a cel.
func duplicate_cel() -> PPCel:
	var copy: PPCel = PPCel.new()
	copy.image = _as_rgba8(image)
	copy.opacity = opacity
	copy.id = _take_id()
	return copy


func get_size() -> Vector2i:
	if image == null:
		return Vector2i.ZERO
	return Vector2i(image.get_width(), image.get_height())


func get_buffer() -> PackedByteArray:
	return image.get_data()


func set_buffer(buffer: PackedByteArray) -> void:
	var size: Vector2i = get_size()
	image = Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_RGBA8, buffer
	)


## Tight bounding box of non-transparent pixels, or an empty rect if the cel is
## fully transparent. Used by the .ase exporter and by "trim" operations.
func get_used_rect() -> Rect2i:
	if image == null:
		return Rect2i()
	return image.get_used_rect()


func is_empty() -> bool:
	return get_used_rect().size == Vector2i.ZERO


func resize_canvas(new_size: Vector2i, offset: Vector2i) -> void:
	var resized: Image = Image.create_empty(
		new_size.x, new_size.y, false, Image.FORMAT_RGBA8
	)
	resized.fill(Color(0.0, 0.0, 0.0, 0.0))
	var old_size: Vector2i = get_size()
	var source_rect: Rect2i = Rect2i(Vector2i.ZERO, old_size)
	resized.blit_rect(image, source_rect, offset)
	image = resized
