class_name PPLayer
extends Resource

## One layer of the sprite. Holds exactly one cel slot per frame; a slot may be
## null (an empty cel) and two slots may reference the same PPCel (a linked cel).

@export var name: String = "Layer"
@export var visible: bool = true
@export var locked: bool = false
@export_range(0.0, 1.0) var opacity: float = 1.0
@export var blend_mode: PPTypes.BlendMode = PPTypes.BlendMode.NORMAL

## When true the layer is drawn but excluded from flattened exports -- the usual
## home for reference sketches and construction guides.
@export var reference_only: bool = false

@export var cels: Array[PPCel] = []


static func create(layer_name: String, frame_count: int, size: Vector2i) -> PPLayer:
	var layer: PPLayer = PPLayer.new()
	layer.name = layer_name
	layer.cels = []
	for i: int in range(frame_count):
		layer.cels.append(PPCel.create(size))
	return layer


func get_cel(frame_index: int) -> PPCel:
	if frame_index < 0 or frame_index >= cels.size():
		return null
	return cels[frame_index]


func set_cel(frame_index: int, cel: PPCel) -> void:
	if frame_index < 0 or frame_index >= cels.size():
		return
	cels[frame_index] = cel


## True when this frame's cel instance is shared with any other frame.
func is_cel_linked(frame_index: int) -> bool:
	var cel: PPCel = get_cel(frame_index)
	if cel == null:
		return false
	var seen: int = 0
	for other: PPCel in cels:
		if other == cel:
			seen += 1
			if seen > 1:
				return true
	return false


## Gives this frame its own private copy of a shared cel. No-op when unlinked.
func unlink_cel(frame_index: int) -> void:
	if not is_cel_linked(frame_index):
		return
	cels[frame_index] = cels[frame_index].duplicate_cel()


func insert_frame(frame_index: int, size: Vector2i) -> void:
	cels.insert(clampi(frame_index, 0, cels.size()), PPCel.create(size))


func remove_frame(frame_index: int) -> void:
	if frame_index < 0 or frame_index >= cels.size():
		return
	cels.remove_at(frame_index)


func duplicate_layer() -> PPLayer:
	var copy: PPLayer = PPLayer.new()
	copy.name = name + " copy"
	copy.visible = visible
	copy.locked = locked
	copy.opacity = opacity
	copy.blend_mode = blend_mode
	copy.reference_only = reference_only
	copy.cels = []

	# Preserve the layer's internal link topology: cels that were linked to each
	# other in the source must stay linked to each other in the copy.
	var remap: Dictionary[PPCel, PPCel] = {}
	for cel: PPCel in cels:
		if cel == null:
			copy.cels.append(null)
			continue
		if not remap.has(cel):
			remap[cel] = cel.duplicate_cel()
		copy.cels.append(remap[cel])
	return copy


func resize_canvas(new_size: Vector2i, offset: Vector2i) -> void:
	var done: Dictionary[PPCel, bool] = {}
	for cel: PPCel in cels:
		if cel == null or done.has(cel):
			continue
		done[cel] = true
		cel.resize_canvas(new_size, offset)
