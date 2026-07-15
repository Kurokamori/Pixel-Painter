@abstract
class_name PPLayerCommands
extends RefCounted

## Undoable layer-structure edits, grouped as inner classes so that the command
## set stays discoverable (PPLayerCommands.AddLayer, .RemoveLayer, ...).
##
## Removed layers are held by reference rather than serialised: the PPLayer and
## its cels stay alive inside the command, so undo is an O(1) re-insert with the
## original pixel data and cel-link topology intact.


class AddLayer:
	extends PPCommand

	var _layer: PPLayer = null
	var _index: int = 0

	static func create(layer: PPLayer, index: int) -> AddLayer:
		var command: AddLayer = AddLayer.new()
		command.label = "Add Layer"
		command._layer = layer
		command._index = index
		return command

	func redo(document: PPDocument) -> void:
		document.sprite.add_layer(_layer, _index)
		document.active_layer = clampi(_index, 0, document.sprite.layer_count() - 1)

	func undo(document: PPDocument) -> void:
		document.sprite.remove_layer(_index)
		document.active_layer = clampi(
			_index - 1, 0, maxi(0, document.sprite.layer_count() - 1)
		)

	func is_structural() -> bool:
		return true


class RemoveLayer:
	extends PPCommand

	var _layer: PPLayer = null
	var _index: int = 0

	static func create(sprite: PPSprite, index: int) -> RemoveLayer:
		# The sprite must always keep at least one layer.
		if sprite.layer_count() <= 1:
			return null
		var command: RemoveLayer = RemoveLayer.new()
		command.label = "Remove Layer"
		command._layer = sprite.get_layer(index)
		command._index = index
		return command

	func redo(document: PPDocument) -> void:
		document.sprite.remove_layer(_index)
		document.active_layer = clampi(
			_index - 1, 0, maxi(0, document.sprite.layer_count() - 1)
		)

	func undo(document: PPDocument) -> void:
		document.sprite.add_layer(_layer, _index)
		document.active_layer = _index

	func is_structural() -> bool:
		return true


class MoveLayer:
	extends PPCommand

	var _from: int = 0
	var _to: int = 0

	static func create(from_index: int, to_index: int) -> MoveLayer:
		if from_index == to_index:
			return null
		var command: MoveLayer = MoveLayer.new()
		command.label = "Reorder Layer"
		command._from = from_index
		command._to = to_index
		return command

	func redo(document: PPDocument) -> void:
		document.sprite.move_layer(_from, _to)
		document.active_layer = _to

	func undo(document: PPDocument) -> void:
		document.sprite.move_layer(_to, _from)
		document.active_layer = _from

	func is_structural() -> bool:
		return true


## Changes one exported property of a layer (visibility, opacity, blend mode,
## name, lock, reference flag). Consecutive changes to the same property of the
## same layer merge, so dragging the opacity slider yields a single undo step.
class SetLayerProperty:
	extends PPCommand

	var _index: int = 0
	var _property: StringName = &""
	var _before: Variant = null
	var _after: Variant = null

	static func create(
		sprite: PPSprite, index: int, property: StringName, value: Variant, label_text: String
	) -> SetLayerProperty:
		var layer: PPLayer = sprite.get_layer(index)
		if layer == null:
			return null
		var current: Variant = layer.get(property)
		if current == value:
			return null
		var command: SetLayerProperty = SetLayerProperty.new()
		command.label = label_text
		command._index = index
		command._property = property
		command._before = current
		command._after = value
		return command

	func redo(document: PPDocument) -> void:
		document.sprite.get_layer(_index).set(_property, _after)

	func undo(document: PPDocument) -> void:
		document.sprite.get_layer(_index).set(_property, _before)

	func is_structural() -> bool:
		return true

	func merge_with(other: PPCommand) -> bool:
		var typed: SetLayerProperty = other as SetLayerProperty
		if typed == null:
			return false
		if typed._index != _index or typed._property != _property:
			return false
		_after = typed._after
		return true


## Merges a layer into the one below it, baking in blend mode and opacity. The
## resulting pixels are precomputed per frame so undo/redo are pure data swaps.
class MergeDown:
	extends PPCommand

	var _upper_index: int = 0
	var _upper_layer: PPLayer = null
	var _lower_before: Array[PPCel] = []
	var _lower_after: Array[PPCel] = []

	static func create(sprite: PPSprite, upper_index: int) -> MergeDown:
		if upper_index <= 0 or upper_index >= sprite.layer_count():
			return null

		var upper: PPLayer = sprite.get_layer(upper_index)
		var lower: PPLayer = sprite.get_layer(upper_index - 1)

		var command: MergeDown = MergeDown.new()
		command.label = "Merge Down"
		command._upper_index = upper_index
		command._upper_layer = upper
		command._lower_before = lower.cels.duplicate()
		command._lower_after = []

		for frame_index: int in range(sprite.frame_count()):
			var lower_cel: PPCel = lower.get_cel(frame_index)
			var upper_cel: PPCel = upper.get_cel(frame_index)

			var merged: PPCel = null
			if lower_cel != null:
				merged = lower_cel.duplicate_cel()
			else:
				merged = PPCel.create(sprite.size)

			if upper_cel != null and upper_cel.image != null:
				var dst: PackedByteArray = merged.image.get_data()
				var src: PackedByteArray = upper_cel.image.get_data()
				var opacity: float = clampf(
					upper.opacity * upper_cel.opacity * (1.0 if upper.visible else 0.0),
					0.0,
					1.0
				)
				PPBlend.blend_buffer(
					dst, src, sprite.size, sprite.get_bounds(), upper.blend_mode, opacity
				)
				merged.set_buffer(dst)

			# The merged result is baked, so it must not inherit the lower cel's
			# own opacity a second time at composite time.
			merged.opacity = 1.0
			command._lower_after.append(merged)

		return command

	func redo(document: PPDocument) -> void:
		var lower: PPLayer = document.sprite.get_layer(_upper_index - 1)
		lower.cels = _lower_after.duplicate()
		document.sprite.remove_layer(_upper_index)
		document.active_layer = _upper_index - 1

	func undo(document: PPDocument) -> void:
		document.sprite.add_layer(_upper_layer, _upper_index)
		var lower: PPLayer = document.sprite.get_layer(_upper_index - 1)
		lower.cels = _lower_before.duplicate()
		document.active_layer = _upper_index

	func is_structural() -> bool:
		return true
