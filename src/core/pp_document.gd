class_name PPDocument
extends RefCounted

## An open sprite plus everything the editor tracks alongside it: the active
## layer/frame, the selection, the undo stack, and a cached composite of the
## current frame.
##
## The composite is kept as one Image + one ImageTexture that are *updated in
## place* rather than recreated. A stroke therefore repaints only its dirty rect
## and uploads only that rect to the GPU, which is what keeps a 4096x4096 canvas
## responsive under a stylus.

signal canvas_changed(rect: Rect2i)
signal structure_changed()
signal selection_changed()
signal active_cel_changed()
signal dirty_changed(is_dirty: bool)

var sprite: PPSprite = null
var selection: PPSelection = null
var history: PPHistory = null

## Empty until the document has been saved or opened from disk.
var path: String = ""

var composite_image: Image = null
var composite_texture: ImageTexture = null

var _active_layer: int = 0
var _active_frame: int = 0
var _dirty: bool = false


var active_layer: int:
	get:
		return _active_layer
	set(value):
		var clamped: int = clampi(value, 0, maxi(0, sprite.layer_count() - 1))
		if clamped == _active_layer:
			return
		_active_layer = clamped
		active_cel_changed.emit()

var active_frame: int:
	get:
		return _active_frame
	set(value):
		var clamped: int = clampi(value, 0, maxi(0, sprite.frame_count() - 1))
		if clamped == _active_frame:
			return
		_active_frame = clamped
		refresh_composite()
		active_cel_changed.emit()


static func create(size: Vector2i, palette: PPPalette = null) -> PPDocument:
	return from_sprite(PPSprite.create(size, palette))


static func from_sprite(source: PPSprite) -> PPDocument:
	var document: PPDocument = PPDocument.new()
	document.sprite = source
	document.selection = PPSelection.new(source.size)
	document.history = PPHistory.new(document)
	document._rebuild_composite_surface()
	document.refresh_composite()
	return document


func get_title() -> String:
	if path.is_empty():
		return "Untitled"
	return path.get_file()


func is_dirty() -> bool:
	return _dirty


func set_dirty(value: bool) -> void:
	if _dirty == value:
		return
	_dirty = value
	dirty_changed.emit(_dirty)


func mark_saved(saved_path: String) -> void:
	path = saved_path
	set_dirty(false)


func get_active_layer() -> PPLayer:
	return sprite.get_layer(_active_layer)


func get_active_cel() -> PPCel:
	return sprite.get_cel(_active_layer, _active_frame)


## True when the active cel may be painted on. Locked or hidden layers are
## refused so the user cannot silently paint into something they cannot see.
func can_paint() -> bool:
	var layer: PPLayer = get_active_layer()
	if layer == null or layer.locked or not layer.visible:
		return false
	return get_active_cel() != null


# --- Composite cache --------------------------------------------------------

## Recomposites `rect` (default: the whole canvas) and pushes it to the GPU.
func refresh_composite(rect: Rect2i = Rect2i()) -> void:
	if composite_image == null:
		_rebuild_composite_surface()

	var target: Rect2i = rect
	if target.size.x <= 0 or target.size.y <= 0:
		target = sprite.get_bounds()
	target = target.intersection(sprite.get_bounds())
	if target.size.x <= 0 or target.size.y <= 0:
		return

	PPCompositor.composite_into(composite_image, sprite, _active_frame, target)
	composite_texture.update(composite_image)
	canvas_changed.emit(target)


## Recomposites with a layer's pixels temporarily replaced by `preview` -- the
## live preview for line/shape/gradient tools, which must not touch the cel.
func refresh_composite_with_preview(
	layer_index: int, preview: Image, rect: Rect2i
) -> void:
	if composite_image == null:
		_rebuild_composite_surface()

	var target: Rect2i = rect.intersection(sprite.get_bounds())
	if target.size.x <= 0 or target.size.y <= 0:
		return

	var options: PPCompositeOptions = PPCompositeOptions.new()
	options.override_layer_index = layer_index
	options.override_image = preview

	PPCompositor.composite_into(
		composite_image, sprite, _active_frame, target, options
	)
	composite_texture.update(composite_image)
	canvas_changed.emit(target)


## Recomposites with a layer skipped -- used while the move tool floats a lifted
## selection above the canvas.
func refresh_composite_skipping(layer_index: int, rect: Rect2i) -> void:
	if composite_image == null:
		_rebuild_composite_surface()

	var target: Rect2i = rect.intersection(sprite.get_bounds())
	if target.size.x <= 0 or target.size.y <= 0:
		return

	var options: PPCompositeOptions = PPCompositeOptions.new()
	options.skip_layer_index = layer_index

	PPCompositor.composite_into(
		composite_image, sprite, _active_frame, target, options
	)
	composite_texture.update(composite_image)
	canvas_changed.emit(target)


func on_canvas_size_changed() -> void:
	selection.resize(sprite.size)
	_rebuild_composite_surface()
	refresh_composite()
	structure_changed.emit()


## Called by PPHistory after any command is applied, undone or redone.
func notify_command_applied(command: PPCommand) -> void:
	set_dirty(true)

	_active_layer = clampi(_active_layer, 0, maxi(0, sprite.layer_count() - 1))
	_active_frame = clampi(_active_frame, 0, maxi(0, sprite.frame_count() - 1))

	if command.is_structural():
		refresh_composite()
		structure_changed.emit()
		active_cel_changed.emit()
	else:
		refresh_composite(command.get_dirty_rect(self))


func notify_selection_changed() -> void:
	selection_changed.emit()


func _rebuild_composite_surface() -> void:
	composite_image = Image.create_empty(
		sprite.size.x, sprite.size.y, false, Image.FORMAT_RGBA8
	)
	composite_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	composite_texture = ImageTexture.create_from_image(composite_image)
