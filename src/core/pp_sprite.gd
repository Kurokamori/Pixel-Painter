class_name PPSprite
extends Resource

## The whole artwork: a grid of cels addressed by (layer, frame), plus the
## palette and animation tags.
##
## Layer order is bottom-first: layers[0] is the backmost layer, which matches
## how the compositor walks them and how Aseprite stores them on disk. The
## layers panel presents this reversed so the topmost layer appears at the top.

@export var size: Vector2i = Vector2i(64, 64)
@export var layers: Array[PPLayer] = []
@export var frames: Array[PPFrame] = []
@export var tags: Array[PPTag] = []
@export var palette: PPPalette = null


static func create(sprite_size: Vector2i, palette_source: PPPalette = null) -> PPSprite:
	var sprite: PPSprite = PPSprite.new()
	sprite.size = sprite_size
	sprite.frames = [PPFrame.create()]
	sprite.layers = [PPLayer.create("Layer 1", 1, sprite_size)]
	if palette_source != null:
		sprite.palette = palette_source.duplicate_palette()
	else:
		sprite.palette = PPPalette.create("Palette", PackedColorArray())
	return sprite


func frame_count() -> int:
	return frames.size()


func layer_count() -> int:
	return layers.size()


func get_layer(index: int) -> PPLayer:
	if index < 0 or index >= layers.size():
		return null
	return layers[index]


func get_frame(index: int) -> PPFrame:
	if index < 0 or index >= frames.size():
		return null
	return frames[index]


func get_cel(layer_index: int, frame_index: int) -> PPCel:
	var layer: PPLayer = get_layer(layer_index)
	if layer == null:
		return null
	return layer.get_cel(frame_index)


func get_bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, size)


func total_duration_ms() -> int:
	var total: int = 0
	for frame: PPFrame in frames:
		total += frame.duration_ms
	return total


# --- Structural edits -------------------------------------------------------
# These are raw mutations. Anything the user triggers goes through a command in
# PPHistory so that it is undoable; callers outside the command layer should not
# invoke these directly.

func add_layer(layer: PPLayer, at_index: int = -1) -> int:
	var target: int = at_index
	if target < 0 or target > layers.size():
		target = layers.size()
	# A layer joining the sprite must have a cel slot for every existing frame.
	while layer.cels.size() < frames.size():
		layer.cels.append(PPCel.create(size))
	while layer.cels.size() > frames.size():
		layer.cels.remove_at(layer.cels.size() - 1)
	layers.insert(target, layer)
	return target


func remove_layer(index: int) -> PPLayer:
	if index < 0 or index >= layers.size():
		return null
	var layer: PPLayer = layers[index]
	layers.remove_at(index)
	return layer


func move_layer(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= layers.size():
		return
	var target: int = clampi(to_index, 0, layers.size() - 1)
	if target == from_index:
		return
	var layer: PPLayer = layers[from_index]
	layers.remove_at(from_index)
	layers.insert(target, layer)


func insert_frame(at_index: int, frame: PPFrame = null) -> int:
	var target: int = clampi(at_index, 0, frames.size())
	var new_frame: PPFrame = frame
	if new_frame == null:
		new_frame = PPFrame.create()
	frames.insert(target, new_frame)
	for layer: PPLayer in layers:
		layer.insert_frame(target, size)
	_retag_for_insert(target, 1)
	return target


func remove_frame(index: int) -> void:
	# A sprite must always keep at least one frame.
	if frames.size() <= 1 or index < 0 or index >= frames.size():
		return
	frames.remove_at(index)
	for layer: PPLayer in layers:
		layer.remove_frame(index)
	_retag_for_remove(index)


func move_frame(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= frames.size():
		return
	var target: int = clampi(to_index, 0, frames.size() - 1)
	if target == from_index:
		return

	var frame: PPFrame = frames[from_index]
	frames.remove_at(from_index)
	frames.insert(target, frame)
	for layer: PPLayer in layers:
		var cel: PPCel = layer.cels[from_index]
		layer.cels.remove_at(from_index)
		layer.cels.insert(target, cel)


func resize_canvas(new_size: Vector2i, offset: Vector2i) -> void:
	size = new_size
	for layer: PPLayer in layers:
		layer.resize_canvas(new_size, offset)


func tags_at(frame_index: int) -> Array[PPTag]:
	var found: Array[PPTag] = []
	for tag: PPTag in tags:
		if tag.contains(frame_index):
			found.append(tag)
	return found


func duplicate_sprite() -> PPSprite:
	var copy: PPSprite = PPSprite.new()
	copy.size = size
	copy.frames = []
	for frame: PPFrame in frames:
		copy.frames.append(frame.duplicate_frame())
	copy.layers = []
	for layer: PPLayer in layers:
		var layer_copy: PPLayer = layer.duplicate_layer()
		layer_copy.name = layer.name
		copy.layers.append(layer_copy)
	copy.tags = []
	for tag: PPTag in tags:
		copy.tags.append(tag.duplicate_tag())
	if palette != null:
		copy.palette = palette.duplicate_palette()
	return copy


func _retag_for_insert(at: int, count: int) -> void:
	var kept: Array[PPTag] = []
	for tag: PPTag in tags:
		if tag.shift_for_insert(at, count):
			kept.append(tag)
	tags = kept


func _retag_for_remove(at: int) -> void:
	var kept: Array[PPTag] = []
	for tag: PPTag in tags:
		if tag.shift_for_remove(at):
			kept.append(tag)
	tags = kept
