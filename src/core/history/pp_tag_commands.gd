@abstract
class_name PPTagCommands
extends RefCounted

## Undoable edits to the animation tag list. The list is snapshotted whole: tags
## are tiny and few, and a snapshot sidesteps the index bookkeeping that add /
## remove / retime would otherwise each need to invert.


class SetTags:
	extends PPCommand

	var _before: Array[PPTag] = []
	var _after: Array[PPTag] = []

	static func create(
		sprite: PPSprite, new_tags: Array[PPTag], label_text: String
	) -> SetTags:
		var command: SetTags = SetTags.new()
		command.label = label_text
		command._before = _snapshot(sprite.tags)
		command._after = _snapshot(new_tags)
		return command

	static func _snapshot(tags: Array[PPTag]) -> Array[PPTag]:
		var copy: Array[PPTag] = []
		for tag: PPTag in tags:
			copy.append(tag.duplicate_tag())
		return copy

	func redo(document: PPDocument) -> void:
		document.sprite.tags = _snapshot(_after)

	func undo(document: PPDocument) -> void:
		document.sprite.tags = _snapshot(_before)

	func is_structural() -> bool:
		return true
