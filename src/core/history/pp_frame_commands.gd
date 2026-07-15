@abstract
class_name PPFrameCommands
extends RefCounted

## Undoable frame-structure edits: insert, duplicate, remove, reorder, retime,
## and the cel link/unlink pair.


class InsertFrame:
	extends PPCommand

	var _index: int = 0
	## When set, the new frame's cels are copies of this frame's cels (duplicate)
	## or the very same instances (link). When -1, the frame starts empty.
	var _source_frame: int = -1
	var _linked: bool = false

	var _frame: PPFrame = null
	var _cels: Array[PPCel] = []

	static func create(
		sprite: PPSprite, index: int, source_frame: int, linked: bool, label_text: String
	) -> InsertFrame:
		var command: InsertFrame = InsertFrame.new()
		command.label = label_text
		command._index = clampi(index, 0, sprite.frame_count())
		command._source_frame = source_frame
		command._linked = linked

		if source_frame >= 0:
			command._frame = sprite.get_frame(source_frame).duplicate_frame()
		else:
			command._frame = PPFrame.create()

		# Materialise the new column of cels once, at construction time, so redo
		# always restores byte-identical pixels.
		command._cels = []
		for layer_index: int in range(sprite.layer_count()):
			var layer: PPLayer = sprite.get_layer(layer_index)
			if source_frame < 0:
				command._cels.append(PPCel.create(sprite.size))
				continue
			var source_cel: PPCel = layer.get_cel(source_frame)
			if source_cel == null:
				command._cels.append(PPCel.create(sprite.size))
			elif linked:
				command._cels.append(source_cel)
			else:
				command._cels.append(source_cel.duplicate_cel())
		return command

	func redo(document: PPDocument) -> void:
		var sprite: PPSprite = document.sprite
		sprite.frames.insert(_index, _frame)
		for layer_index: int in range(sprite.layer_count()):
			sprite.get_layer(layer_index).cels.insert(_index, _cels[layer_index])
		sprite._retag_for_insert(_index, 1)
		document.active_frame = _index

	func undo(document: PPDocument) -> void:
		var sprite: PPSprite = document.sprite
		sprite.frames.remove_at(_index)
		for layer_index: int in range(sprite.layer_count()):
			sprite.get_layer(layer_index).cels.remove_at(_index)
		sprite._retag_for_remove(_index)
		document.active_frame = clampi(_index - 1, 0, sprite.frame_count() - 1)

	func is_structural() -> bool:
		return true


class RemoveFrame:
	extends PPCommand

	var _index: int = 0
	var _frame: PPFrame = null
	var _cels: Array[PPCel] = []
	var _tags: Array[PPTag] = []

	static func create(sprite: PPSprite, index: int) -> RemoveFrame:
		if sprite.frame_count() <= 1:
			return null
		if index < 0 or index >= sprite.frame_count():
			return null

		var command: RemoveFrame = RemoveFrame.new()
		command.label = "Remove Frame"
		command._index = index
		command._frame = sprite.get_frame(index)
		command._cels = []
		for layer_index: int in range(sprite.layer_count()):
			command._cels.append(sprite.get_layer(layer_index).get_cel(index))
		# Removing a frame can collapse a tag entirely, so the tag list is
		# snapshotted rather than reconstructed by inverse arithmetic.
		command._tags = []
		for tag: PPTag in sprite.tags:
			command._tags.append(tag.duplicate_tag())
		return command

	func redo(document: PPDocument) -> void:
		var sprite: PPSprite = document.sprite
		sprite.frames.remove_at(_index)
		for layer_index: int in range(sprite.layer_count()):
			sprite.get_layer(layer_index).cels.remove_at(_index)
		sprite._retag_for_remove(_index)
		document.active_frame = clampi(_index - 1, 0, sprite.frame_count() - 1)

	func undo(document: PPDocument) -> void:
		var sprite: PPSprite = document.sprite
		sprite.frames.insert(_index, _frame)
		for layer_index: int in range(sprite.layer_count()):
			sprite.get_layer(layer_index).cels.insert(_index, _cels[layer_index])
		var restored: Array[PPTag] = []
		for tag: PPTag in _tags:
			restored.append(tag.duplicate_tag())
		sprite.tags = restored
		document.active_frame = _index

	func is_structural() -> bool:
		return true


class MoveFrame:
	extends PPCommand

	var _from: int = 0
	var _to: int = 0

	static func create(from_index: int, to_index: int) -> MoveFrame:
		if from_index == to_index:
			return null
		var command: MoveFrame = MoveFrame.new()
		command.label = "Reorder Frame"
		command._from = from_index
		command._to = to_index
		return command

	func redo(document: PPDocument) -> void:
		document.sprite.move_frame(_from, _to)
		document.active_frame = _to

	func undo(document: PPDocument) -> void:
		document.sprite.move_frame(_to, _from)
		document.active_frame = _from

	func is_structural() -> bool:
		return true


class SetFrameDuration:
	extends PPCommand

	var _index: int = 0
	var _before: int = 0
	var _after: int = 0

	static func create(sprite: PPSprite, index: int, duration_ms: int) -> SetFrameDuration:
		var frame: PPFrame = sprite.get_frame(index)
		if frame == null:
			return null
		var clamped: int = maxi(1, duration_ms)
		if frame.duration_ms == clamped:
			return null
		var command: SetFrameDuration = SetFrameDuration.new()
		command.label = "Frame Duration"
		command._index = index
		command._before = frame.duration_ms
		command._after = clamped
		return command

	func redo(document: PPDocument) -> void:
		document.sprite.get_frame(_index).duration_ms = _after

	func undo(document: PPDocument) -> void:
		document.sprite.get_frame(_index).duration_ms = _before

	func is_structural() -> bool:
		return true

	func merge_with(other: PPCommand) -> bool:
		var typed: SetFrameDuration = other as SetFrameDuration
		if typed == null or typed._index != _index:
			return false
		_after = typed._after
		return true


## Replaces a cel with a private copy (unlink) or with a neighbour's instance
## (link). Both directions are covered by swapping the stored cel references.
class SetCel:
	extends PPCommand

	var _layer_index: int = 0
	var _frame_index: int = 0
	var _before: PPCel = null
	var _after: PPCel = null

	static func create_unlink(sprite: PPSprite, layer_index: int, frame_index: int) -> SetCel:
		var layer: PPLayer = sprite.get_layer(layer_index)
		if layer == null or not layer.is_cel_linked(frame_index):
			return null
		var command: SetCel = SetCel.new()
		command.label = "Unlink Cel"
		command._layer_index = layer_index
		command._frame_index = frame_index
		command._before = layer.get_cel(frame_index)
		command._after = command._before.duplicate_cel()
		return command

	## Links `frame_index` to whatever cel instance `source_frame` uses.
	static func create_link(
		sprite: PPSprite, layer_index: int, frame_index: int, source_frame: int
	) -> SetCel:
		var layer: PPLayer = sprite.get_layer(layer_index)
		if layer == null:
			return null
		var source: PPCel = layer.get_cel(source_frame)
		var current: PPCel = layer.get_cel(frame_index)
		if source == null or source == current:
			return null
		var command: SetCel = SetCel.new()
		command.label = "Link Cel"
		command._layer_index = layer_index
		command._frame_index = frame_index
		command._before = current
		command._after = source
		return command

	func redo(document: PPDocument) -> void:
		document.sprite.get_layer(_layer_index).set_cel(_frame_index, _after)

	func undo(document: PPDocument) -> void:
		document.sprite.get_layer(_layer_index).set_cel(_frame_index, _before)

	func is_structural() -> bool:
		return true
